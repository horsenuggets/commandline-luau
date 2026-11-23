--[[

TerminalTest.spec

Tests for Terminal, covering setting precedence from the app and environment, painted
text helpers, timestamped printing, and line buffering for streamed output.

--]]

const Style = require("../Source/Commandline/Terminal/Style")
const Terminal = require("../Source/Commandline/Terminal")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

type Harness = {
    Advance: (seconds: number) -> (),
    Errors: { string },
    Output: { string },
    Terminal: Terminal.Terminal,
}

const function harness(config: Terminal.Config?): Harness
    local elapsed = 0
    const output = {}
    const errors = {}
    const options: Terminal.Config = table.clone(config or {})
    options.Clock = {
        Elapsed = function()
            return elapsed
        end,
        LocalOffsetMinutes = function()
            return -360
        end,
        UnixMillis = function()
            return 1795460709042
        end,
    }
    options.Env = options.Env or {}
    options.Write = function(text)
        table.insert(output, text)
    end
    options.WriteError = function(text)
        table.insert(errors, text)
    end
    return {
        Advance = function(seconds)
            elapsed += seconds
        end,
        Errors = errors,
        Output = output,
        Terminal = Terminal.new(options),
    }
end

return function()
    describe("Terminal.new", function()
        it("should combine the app setting and environment override in every combination", function()
            -- False stands in for an unset value, since nil cannot sit inside an array.
            for _, appValue in { "stopwatch", "utc", false } do
                for _, envValue in { "local", "", false } do
                    const appSetting = if appValue then appValue else nil
                    const envSetting = if envValue then envValue else nil
                    const terminal =
                        harness({ Env = { COMMANDLINE_TIMESTAMPS = envSetting }, Timestamps = appSetting }).Terminal
                    const expected = if envSetting and envSetting ~= ""
                        then "Local"
                        elseif appSetting == "stopwatch" then "Stopwatch"
                        elseif appSetting == "utc" then "Utc"
                        else "Disabled"
                    expect(terminal.Timestamps.Mode).to.equal(expected)
                end
            end
        end)

        it("should fail loudly on an invalid environment override", function()
            expect(function()
                harness({ Env = { COMMANDLINE_TIMESTAMPS = "sometimes" } })
            end).to.throw()
        end)

        it("should turn color off when NO_COLOR is set unless the app forces it", function()
            const cases = {
                { nil, nil, true },
                { "", nil, true },
                { "1", nil, false },
                { "1", true, true },
                { nil, false, false },
            }
            for _, case in cases do
                const terminal = harness({ Color = case[2], Env = { NO_COLOR = case[1] } }).Terminal
                expect(terminal.Color).to.equal(case[3])
            end
        end)

        it("should find the home folder from the environment", function()
            const terminal = harness({ Env = { HOME = "/Users/user", USERPROFILE = "C:\\Users\\user" } }).Terminal
            expect(terminal.Home ~= nil).to.equal(true)
        end)

        it("should reject unknown options", function()
            expect(function()
                Terminal.new({ Timestamp = "utc" } :: any)
            end).to.throw()
        end)
    end)

    describe("Terminal helpers", function()
        it("should style paths by kind and normalize them", function()
            const terminal = harness({ Color = false, Home = "C:\\Users\\user" }).Terminal
            expect(terminal:Path("C:\\Users\\user\\My Games\\Place.rbxl")).to.equal("~/My·Games/Place.rbxl")
            expect(terminal:Path("C:\\Users\\user\\.ae", { Directory = true })).to.equal("~/.ae/")
            expect(terminal:Path("/home/demo/x", { Home = "/home/demo" })).to.equal("~/x")
            expect(terminal:Path("C:\\Users\\user\\x", { Home = "" })).to.equal("C:/Users/user/x")

            const colored = harness({ Color = true, Home = "/Users/user" }).Terminal
            const roblox = colored:Path("/tmp/Place.rbxl")
            const plain = colored:Path("/tmp/notes.txt")
            expect(roblox).to.equal(Style.paintPath(colored.Theme.RobloxPath, "/tmp/Place.rbxl", true))
            expect(plain).to.equal(Style.paintPath(colored.Theme.Path, "/tmp/notes.txt", true))
        end)

        it("should paint each helper with its own theme entry", function()
            const terminal = harness({ Color = true }).Terminal
            const helpers = {
                Address = terminal.Address,
                Error = terminal.Error,
                Heading = terminal.Heading,
                Identifier = terminal.Identifier,
                Success = terminal.Success,
                Url = terminal.Url,
                Warning = terminal.Warning,
            }
            for key, helper in helpers do
                expect(helper(terminal, "text")).to.equal(Style.paint((terminal.Theme :: any)[key], "text", true))
            end
            expect(terminal:Count(15)).to.equal(Style.paint(terminal.Theme.Count, "15", true))
        end)

        it("should apply theme overrides", function()
            const terminal = harness({ Color = true, Theme = { Success = { Color = "magenta" } } }).Terminal
            expect(terminal:Success("Done.")).to.equal("\u{1b}[35mDone.\u{1b}[39m")
        end)

        it("should format numbered steps", function()
            const terminal = harness({ Color = false }).Terminal
            expect(terminal:Step(1, 5, "Starting...")).to.equal("[1/5] Starting...")
            const colored = harness({ Color = true }).Terminal
            expect(Style.strip(colored:Step(3, 5, "Building..."))).to.equal("[3/5] Building...")
            expect(
                string.find(colored:Step(3, 5, "x"), Style.paint(colored.Theme.StepCurrent, "3", true), 1, true) ~= nil
            ).to.equal(true)
        end)
    end)

    describe("Terminal:Print", function()
        it("should print plain lines when timestamps are disabled", function()
            const h = harness()
            h.Terminal:Print("One.\nTwo.")
            expect(table.concat(h.Output)).to.equal("One.\nTwo.\n")
        end)

        it("should prefix every line with the stopwatch", function()
            const h = harness({ Color = false, Timestamps = "stopwatch" })
            h.Advance(1.234)
            h.Terminal:Print("Started.\r\nReady.")
            h.Terminal:PrintError("Failed.")
            expect(table.concat(h.Output)).to.equal("[00:01.234] Started.\n[00:01.234] Ready.\n")
            expect(table.concat(h.Errors)).to.equal("[00:01.234] Failed.\n")
        end)

        it("should leave blank lines blank", function()
            const h = harness({ Color = false, Timestamps = "utc" })
            h.Terminal:Print()
            h.Terminal:Print("A.\n\nB.")
            expect(table.concat(h.Output)).to.equal("\n[19:05:09.042] A.\n\n[19:05:09.042] B.\n")
        end)

        it("should wrap long lines at words, aligned after the timestamp", function()
            const h = harness({ Color = false, Columns = 40, Timestamps = "stopwatch" })
            h.Advance(1.5)
            h.Terminal:Print("Visit http://localhost:52876/ in your browser.")
            expect(table.concat(h.Output)).to.equal(
                "[00:01.500] Visit\n            http://localhost:52876/ in\n            your browser.\n"
            )
        end)

        it("should only wrap custom sinks when given a width", function()
            const h = harness({ Color = false })
            expect(h.Terminal:Columns()).to.equal(0)
            h.Terminal:Print(string.rep("word ", 100))
            expect(#h.Output).to.equal(1)
            expect(string.find(h.Output[1], "\n", 1, true)).to.equal(#h.Output[1])
        end)

        it("should color the faint lead separately from the counting digits", function()
            const h = harness({ Color = true, Timestamps = "stopwatch" })
            h.Advance(12.345)
            const theme = h.Terminal.Theme
            expect(h.Terminal:Prefix()).to.equal(
                `{Style.paint(theme.TimestampBracket, "[", true)}{Style.paint(theme.TimestampFaint, "00:", true)}{Style.paint(
                    theme.TimestampText,
                    "12.345",
                    true
                )}{Style.paint(theme.TimestampBracket, "]", true)} `
            )
        end)
    end)

    describe("Terminal:Stream", function()
        it("should buffer partial lines until they finish", function()
            const h = harness({ Color = false, Timestamps = "stopwatch" })
            const stream = h.Terminal:Stream()
            stream.Write("Rojo+ server ")
            expect(#h.Output).to.equal(0)
            h.Advance(0.5)
            stream.Write("listening.\nVisit")
            expect(table.concat(h.Output)).to.equal("[00:00.500] Rojo+ server listening.\n")
            h.Advance(0.25)
            stream.Write(" the page.\n")
            stream.Write("Trailing")
            stream.Flush()
            stream.Flush()
            expect(table.concat(h.Output)).to.equal(
                "[00:00.500] Rojo+ server listening.\n[00:00.750] Visit the page.\n[00:00.750] Trailing\n"
            )
        end)

        it("should write error streams to standard error", function()
            const h = harness({ Color = false })
            const stream = h.Terminal:Stream("Error")
            stream.Write("Problem.\n")
            expect(table.concat(h.Errors)).to.equal("Problem.\n")
            expect(#h.Output).to.equal(0)
        end)

        it("should produce the same lines however the chunks are split", function()
            const text = "One.\nTwo.\r\nThree.\n"
            const expected = "One.\nTwo.\nThree.\n"
            for size = 1, #text do
                const h = harness({ Color = false })
                const stream = h.Terminal:Stream()
                for start = 1, #text, size do
                    stream.Write(string.sub(text, start, start + size - 1))
                end
                stream.Flush()
                expect(table.concat(h.Output)).to.equal(expected)
            end
        end)
    end)

    describe("Terminal.default", function()
        it("should return the terminal set as the default", function()
            const previous = Terminal.default()
            const replacement = harness().Terminal
            Terminal.setDefault(replacement)
            expect(Terminal.default()).to.equal(replacement)
            Terminal.setDefault(previous)
            expect(Terminal.default()).to.equal(previous)
        end)
    end)
end

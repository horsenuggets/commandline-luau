--[[

TerminalTest.spec

Tests for Terminal, covering setting precedence from the app and environment, painted
text helpers, timestamped printing, and line buffering for streamed output.

--]]

const DateTime = require("@lune/datetime")
const Style = require("../Source/Commandline/Terminal/Style")
const Terminal = require("../Source/Commandline/Terminal")
const fs = require("@lune/fs")
const process = require("@lune/process")
const stdio = require("@lune/stdio")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

type Harness = {
    Advance: (seconds: number) -> (),
    Errors: { string },
    Output: { string },
    Terminal: Terminal.Terminal
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
        end
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
        Terminal = Terminal.new(options)
    }
end

return function()
    describe("Terminal.localOffsetMinutes", function()
        it("should agree with the local offset at the actual instant", function()
            const now = DateTime.now()
            const offset = now:formatLocalTime("%z")
            const sign, hours, minutes = string.match(offset, "^([+-])(%d%d)(%d%d)$")
            assert(sign and hours and minutes)
            const expected = ((tonumber(hours) :: number) * 60 + (tonumber(minutes) :: number))
                * (if sign == "-" then -1 else 1)
            expect(Terminal.localOffsetMinutes(now.unixTimestampMillis)).to.equal(expected)
        end)

        if process.os ~= "windows" then
            it("should not interpret UTC wall-clock components in a DST gap or repeated hour", function()
                const root = `Build/TerminalTimeTest-{os.time()}-{math.random(1, 1e9)}`
                fs.writeDir(root)
                const script = `{root}/Child.luau`
                fs.writeFile(
                    script,
                    [[
                    const DateTime = require("@lune/datetime")
                    const Terminal = require("../../Source/Commandline/Terminal")
                    for _, case in {
                        { "2026-03-08T02:30:00Z", -300 },
                        { "2026-03-08T04:30:00Z", -300 },
                        { "2026-03-08T06:59:00Z", -300 },
                        { "2026-03-08T07:00:00Z", -240 },
                        { "2026-11-01T01:30:00Z", -240 },
                        { "2026-11-01T04:30:00Z", -240 },
                        { "2026-11-01T05:59:00Z", -240 },
                        { "2026-11-01T06:00:00Z", -300 },
                    } do
                        const instant = DateTime.fromIsoDate(case[1])
                        assert(Terminal.localOffsetMinutes(instant.unixTimestampMillis) == case[2], case[1])
                    end
                ]]
                )
                const ok, result = pcall(process.exec, "lune", { "run", script }, { env = { TZ = "America/New_York" } })
                fs.removeDir(root)
                assert(ok, tostring(result))
                expect(result.stderr).to.equal("")
                expect(result.ok).to.equal(true)
            end)
        end
    end)

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
                { nil, false, false }
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

    describe("Terminal capabilities", function()
        it("should render colored timestamps through the actual native capability API", function()
            const terminal = Terminal.new({ Color = true, Columns = 0, Env = {}, Timestamps = "stopwatch" })
            expect(type(terminal:Prefix())).to.equal("string")
            expect(terminal:Capabilities().ForegroundOpacity).to.equal(
                (stdio :: any).terminalCapabilities().ForegroundOpacity
            )
        end)

        it("should detect lazily once and apply the result to every opacity-bearing role", function()
            for _, supported in { false, true } do
                local calls = 0
                const terminal = harness({
                    Color = true,
                    DetectCapabilities = function()
                        calls += 1
                        return { ForegroundOpacity = supported }
                    end,
                    Timestamps = "stopwatch"
                }).Terminal
                terminal:Heading("Heading.")
                expect(calls).to.equal(0)
                for key, spec in terminal.Theme :: any do
                    const resolved = Style.resolve(spec, supported, "#5A5A5A")
                    expect(terminal:Paint(key, "text")).to.equal(Style.paint(resolved, "text", true))
                end
                for _ = 1, 3 do
                    const prefix = terminal:Prefix()
                    expect(string.find(prefix, "38:6::168:168:168:128", 1, true) ~= nil).to.equal(supported)
                    expect(string.find(prefix, "38;2;90;90;90", 1, true) ~= nil).to.equal(not supported)
                    expect(string.find(prefix, "\u{1b}[2m", 1, true)).to.equal(nil)
                end
                expect(calls).to.equal(1)
            end
        end)

        it("should never probe disabled colors or fully opaque output", function()
            const function unexpectedProbe(): Terminal.Capabilities
                error("This output must not probe the terminal.")
            end
            for _, config in
                {
                    { Color = false },
                    { Env = { NO_COLOR = "1" } }
                }
            do
                config.DetectCapabilities = unexpectedProbe
                const terminal = harness(config).Terminal
                expect(terminal:Paint("TimestampFaint", "0")).to.equal("0")
            end
            const terminal = harness({
                Color = true,
                DetectCapabilities = unexpectedProbe,
                Theme = { TimestampFaint = { Color = "#A8A8A8", Opacity = 1 } }
            }).Terminal
            expect(terminal:Paint("TimestampFaint", "0")).to.equal("\u{1b}[38;2;168;168;168m0\u{1b}[39m")
            terminal:Heading("Heading.")
        end)

        it("should use solid gray for custom sinks without native detection", function()
            for _, sink in { "Write", "WriteError" } do
                const options: Terminal.Config = { Color = true }
                (options :: any)[sink] = function() end
                const terminal = Terminal.new(options)
                expect(terminal:Paint("TimestampFaint", "0")).to.equal("\u{1b}[38;2;90;90;90m0\u{1b}[39m")
                expect(terminal._foregroundOpacity).to.equal(false)
            end
        end)

        it("should let buffered renderers inherit the parent capability decision", function()
            for _, supported in { false, true } do
                const parent = harness({
                    Color = true,
                    DetectCapabilities = function()
                        return { ForegroundOpacity = supported }
                    end
                }).Terminal
                const child = harness({
                    Color = true,
                    DetectCapabilities = function()
                        return parent:Capabilities()
                    end
                }).Terminal
                expect(child:Paint("TimestampFaint", "0")).to.equal(parent:Paint("TimestampFaint", "0"))
                const capabilities = parent:Capabilities()
                capabilities.ForegroundOpacity = not supported
                expect(parent:Capabilities().ForegroundOpacity).to.equal(supported)
            end
            const disabled = harness({
                Color = false,
                DetectCapabilities = function()
                    error("Disabled colors must not query terminal capabilities.")
                end
            }).Terminal
            expect(disabled:Capabilities().ForegroundOpacity).to.equal(false)
        end)

        it("should resolve custom opacity for paths, helpers, and nested styles", function()
            for _, supported in { false, true } do
                const terminal = harness({
                    Color = true,
                    DetectCapabilities = function()
                        return { ForegroundOpacity = supported }
                    end,
                    Theme = {
                        Path = { Color = "#A8A8A8", Opacity = 0.25 },
                        RobloxPath = { Bold = true, Color = "#A8A8A8", Opacity = 0.25 },
                        Warning = { Color = "#A8A8A8", Opacity = 0.25 }
                    }
                }).Terminal
                const expected = if supported then "38:6::168:168:168:64" else "38;2;90;90;90"
                for _, value in
                    {
                        terminal:Path("a b.txt"),
                        terminal:Path("a b.rbxl"),
                        terminal:RobloxPath("Workspace.My Model"),
                        terminal:Warning(terminal:RobloxPath("Workspace.My Model"))
                    }
                do
                    expect(string.find(value, expected, 1, true) ~= nil).to.equal(true)
                    expect(string.find(value, "38:6", 1, true) ~= nil).to.equal(supported)
                end
            end
        end)

        it("should resolve legacy dim without emitting ANSI faint or requiring a Faint override color", function()
            const terminal = harness({
                Color = true,
                Theme = { Faint = { Bold = true }, Path = { Color = "gray", Dim = true } }
            }).Terminal
            expect(terminal:Path("a b")).to.equal("\u{1b}[38;2;90;90;90ma\u{1b}[22;38;2;90;90;90m·b\u{1b}[39m")
        end)
    end)

    describe("Terminal prompts", function()
        it("should accept every named theme foreground at the real native parser", function()
            -- Native palette validation precedes the required confirm message. This
            -- sentinel exercises real color parsing without opening an input prompt.
            const invalidOk, invalidProblem = pcall((stdio :: any).prompt, "confirm", nil, true, {
                Accent = "unknown",
                Color = false,
                Error = "",
                Muted = "",
                Success = "",
                Text = "",
                Warning = ""
            })
            expect(invalidOk).to.equal(false)
            expect(string.find(tostring(invalidProblem), 'Prompt color field "Accent"', 1, true)).to.be.ok()
            for _, role in { "Error", "HelpArgument", "Muted", "RobloxPath", "Success", "Warning" } do
                for _, name in
                    {
                        "black",
                        "blackBright",
                        "blue",
                        "blueBright",
                        "cyan",
                        "cyanBright",
                        "gray",
                        "green",
                        "greenBright",
                        "magenta",
                        "magentaBright",
                        "red",
                        "redBright",
                        "white",
                        "whiteBright",
                        "yellow",
                        "yellowBright"
                    }
                do
                    for _, color in { false, true } do
                        const terminal = harness({ Color = color, Theme = { [role] = { Color = name } } }).Terminal
                        const ok, problem = pcall(function()
                            terminal:Prompt("confirm", nil, true)
                        end)
                        expect(ok).to.equal(false)
                        expect(string.find(tostring(problem), "Argument #2 missing or nil", 1, true)).to.be.ok()
                    end
                end
            end
        end)

        it("should pass each prompt kind, its default, and the current RGB theme to the native boundary", function()
            const cases: { [string]: { Default: Terminal.PromptDefault?, Result: Terminal.PromptResult } } = {
                confirm = { Default = true, Result = false },
                multiselect = { Default = { "First", "Second" }, Result = { 1, 2 } },
                password = { Result = "secret" },
                select = { Default = { "First", "Second" }, Result = 2 },
                text = { Default = "initial", Result = "answer" }
            }
            for _, color in { false, true } do
                const terminal = harness({
                    Color = color,
                    Prompt = function(kind, text, defaultValue, colors)
                        const case = cases[kind]
                        expect(text).to.equal("Question?")
                        expect(defaultValue).to.equal(case.Default)
                        expect(colors.Accent).to.equal("#010203")
                        expect(colors.Color).to.equal(color)
                        expect(colors.Error).to.equal("#040506")
                        expect(colors.Muted).to.equal("#070809")
                        expect(colors.Success).to.equal("#0A0B0C")
                        expect(colors.Text).to.equal("#0D0E0F")
                        expect(colors.Warning).to.equal("#101112")
                        return case.Result
                    end,
                    Theme = {
                        Error = { Color = "#040506" },
                        HelpArgument = { Color = "#0D0E0F" },
                        Muted = { Color = "#070809" },
                        RobloxPath = { Color = "#010203" },
                        Success = { Color = "#0A0B0C" },
                        Warning = { Color = "#101112" }
                    }
                }).Terminal
                for kind, case in cases do
                    expect(terminal:Prompt(kind, "Question?", case.Default)).to.equal(case.Result)
                end
            end
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
                Warning = terminal.Warning
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

        it("should calculate the local offset for the timestamp's sampled instant", function()
            const h = harness({ Color = false, Timestamps = "local" })
            const instant = DateTime.fromIsoDate("2026-03-08T06:59:59Z").unixTimestampMillis
            h.Terminal._clock.UnixMillis = function()
                return instant
            end
            h.Terminal._clock.LocalOffsetMinutes = function(unixMillis)
                expect(unixMillis).to.equal(instant)
                return -300
            end
            expect(h.Terminal:Prefix()).to.equal("[01:59:59.000] ")
        end)

        it("should restore message styles after each timestamp prefix", function()
            const h = harness({ Color = true, Timestamps = "stopwatch" })
            h.Terminal:Print(h.Terminal:Warning("One\nTwo"))
            const output = table.concat(h.Output)
            for _, word in { "One", "Two" } do
                const position = assert(string.find(output, word, 1, true))
                expect(Style.sgrState("", string.sub(output, 1, position - 1))).to.equal("\u{1b}[38;2;224;175;104m")
            end
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

        it("should opt out of wrapping per print without changing later output or streams", function()
            for _, color in { false, true } do
                for _, timestamps in { false, true } do
                    const h = harness({
                        Color = color,
                        Columns = 18,
                        Timestamps = if timestamps then "stopwatch" else nil
                    })
                    const text = h.Terminal:Warning("One two three four five.\n\nSix seven eight nine.")
                    h.Terminal:Print(text, { Wrap = false })
                    h.Terminal:PrintError(text, { Wrap = false })
                    const prefix = if timestamps then "[00:00.000] " else ""
                    const expected = `{prefix}One two three four five.\n\n{prefix}Six seven eight nine.\n`
                    expect(Style.strip(table.concat(h.Output))).to.equal(expected)
                    expect(table.concat(h.Errors)).to.equal(table.concat(h.Output))
                    expect(h.Terminal:Columns()).to.equal(18)

                    table.clear(h.Output)
                    h.Terminal:Print("One two three four five.", { Wrap = true })
                    const wrapped = table.concat(h.Output)
                    expect(wrapped == `{prefix}One two three four five.\n`).to.equal(false)
                    table.clear(h.Output)
                    h.Terminal:Print("One two three four five.")
                    expect(table.concat(h.Output)).to.equal(wrapped)
                    table.clear(h.Output)
                    const stream = h.Terminal:Stream()
                    stream.Write("One two three four five.\n")
                    stream.Flush()
                    expect(table.concat(h.Output)).to.equal(wrapped)
                end
            end
        end)

        it("should suppress timestamps per write without changing styles, wrapping, or later output", function()
            for _, color in { false, true } do
                for _, timestamps in { "disabled", "stopwatch", "local" } do
                    for _, wrap in { false, true } do
                        const h = harness({ Color = color, Columns = 18, Timestamps = timestamps })
                        const plain = harness({ Color = color, Columns = 18 })
                        const setting = h.Terminal.Timestamps
                        const clock = h.Terminal._clock
                        const unreadClock = {
                            Elapsed = function()
                                error("Suppressed timestamps must not read elapsed time.")
                            end,
                            LocalOffsetMinutes = function()
                                error("Suppressed timestamps must not read the local offset.")
                            end,
                            UnixMillis = function()
                                error("Suppressed timestamps must not read wall-clock time.")
                            end
                        }
                        h.Terminal._clock = unreadClock
                        const text = h.Terminal:Warning("One two three four five.\n\nSix seven eight nine.")
                        h.Terminal:Print(text, { Timestamps = false, Wrap = wrap })
                        h.Terminal:PrintError(text, { Timestamps = false, Wrap = wrap })
                        plain.Terminal:Print(text, { Wrap = wrap })
                        expect(table.concat(h.Output)).to.equal(table.concat(plain.Output))
                        expect(table.concat(h.Errors)).to.equal(table.concat(plain.Output))
                        expect(Style.strip(table.concat(h.Output))).to.equal(
                            if wrap
                                then "One two three four\nfive.\n\nSix seven eight\nnine.\n"
                                else "One two three four five.\n\nSix seven eight nine.\n"
                        )
                        expect(h.Terminal.Timestamps).to.equal(setting)
                        expect(h.Terminal._clock).to.equal(unreadClock)
                        expect(h.Terminal:Columns()).to.equal(18)
                        h.Terminal._clock = clock
                        h.Advance(1.5)
                        table.clear(h.Output)
                        table.clear(h.Errors)
                        const prefix = h.Terminal:Prefix()
                        for _, options in { {}, { Timestamps = true } } do
                            h.Terminal:Print("OK.", options)
                            h.Terminal:PrintError("No.", options)
                        end
                        const stream = h.Terminal:Stream()
                        stream.Write("OK.\n")
                        stream.Flush()
                        const expected = `{prefix}OK.\n`
                        expect(Style.strip(table.concat(h.Output))).to.equal(Style.strip(string.rep(expected, 3)))
                        expect(Style.strip(table.concat(h.Errors))).to.equal(
                            Style.strip(string.rep(`{prefix}No.\n`, 2))
                        )
                        expect(Style.strip(prefix)).to.equal(
                            if timestamps == "disabled"
                                then ""
                                elseif timestamps == "stopwatch" then "[00:01.500] "
                                else "[13:05:09.042] "
                        )
                    end
                end
            end
        end)

        it("should reject invalid print options", function()
            const terminal = harness().Terminal
            expect(function()
                terminal:Print("Text.", { Wrap = "no" } :: any)
            end).to.throw()
            expect(function()
                terminal:PrintError("Text.", { Unknown = true } :: any)
            end).to.throw()
            for _, value in { "false", 0, {} } do
                expect(function()
                    terminal:Print("Text.", { Timestamps = value } :: any)
                end).to.throw()
                expect(function()
                    terminal:PrintError("Text.", { Timestamps = value } :: any)
                end).to.throw()
            end
        end)

        it("should wrap explicit-alpha timestamps using only their visible width", function()
            for _, color in { true, false } do
                const h = harness({
                    Color = color,
                    Columns = 25,
                    DetectCapabilities = function()
                        return { ForegroundOpacity = true }
                    end,
                    Theme = {
                        TimestampBracket = { Color = "#a8a8a8", Opacity = 0.25 },
                        TimestampFaint = { Color = "#a8a8a8", Opacity = 0.25 }
                    },
                    Timestamps = "stopwatch"
                })
                h.Advance(0.001)
                h.Terminal:Print("One two three four.")
                const output = table.concat(h.Output)
                expect(Style.strip(output)).to.equal("[00:00.001] One two three\n            four.\n")
                expect(string.find(output, "38:6::168:168:168:64", 1, true) ~= nil).to.equal(color)
            end
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
            const bracket = Style.resolve(theme.TimestampBracket, false, "#5A5A5A")
            const faint = Style.resolve(theme.TimestampFaint, false, "#5A5A5A")
            expect(h.Terminal:Prefix()).to.equal(
                `{Style.paint(bracket, "[", true)}{Style.paint(faint, "00:", true)}{Style.paint(
                    theme.TimestampText,
                    "12.345",
                    true
                )}{Style.paint(bracket, "]", true)} `
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

        it("should retain child SGR state across writes without coloring prefixes", function()
            const h = harness({ Color = true, Timestamps = "stopwatch" })
            const stream = h.Terminal:Stream()
            const color = "\u{1b}[38:6::168:168:168:128m"
            stream.Write(`\u{1b}[1m{color}One\n`)
            stream.Write("Two\n\u{1b}[22;39mThree\n")
            stream.Flush()
            const output = table.concat(h.Output)
            for _, word in { "One", "Two" } do
                const position = assert(string.find(output, word, 1, true))
                expect(Style.sgrState("", string.sub(output, 1, position - 1))).to.equal(`\u{1b}[1m{color}`)
            end
            const third = assert(string.find(output, "Three", 1, true))
            expect(Style.sgrState("", string.sub(output, 1, third - 1))).to.equal("")
            expect(Style.strip(output)).to.equal("[00:00.000] One\n[00:00.000] Two\n[00:00.000] Three\n")
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

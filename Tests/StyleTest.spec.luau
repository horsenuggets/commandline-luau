--[[

StyleTest.spec

Tests for Style, covering color codes, theme overrides and validation, escape sequences
for every attribute combination, and path painting with center dots.

--]]

const Style = require("../Source/Commandline/Terminal/Style")
const Text = require("../Source/Commandline/Terminal/Text")
const fs = require("@lune/fs")
const luau = require("@lune/luau")
const t = require("@packages/t")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const ESCAPE = "\u{1b}["

return function()
    describe("Style.colorCode", function()
        it("should map named colors to their SGR codes", function()
            expect(Style.colorCode("cyanBright")).to.equal("96")
            expect(Style.colorCode("gray")).to.equal("90")
            expect(Style.colorCode("red")).to.equal("31")
        end)

        it("should map hex colors to 24-bit codes", function()
            expect(Style.colorCode("#96cc22")).to.equal("38;2;150;204;34")
        end)

        it("should encode explicit opacity as an RGBA foreground", function()
            for _, case in { { 0, 0 }, { 0.25, 64 }, { 0.5, 128 }, { 1, 255 } } do
                expect(Style.colorCode("#a8a8a8", case[1])).to.equal(`38:6::168:168:168:{case[2]}`)
            end
            expect(Style.colorCode("gray", 0.25)).to.equal(nil)
        end)

        it("should reject unknown colors", function()
            expect(Style.colorCode("teal")).to.equal(nil)
            expect(Style.colorCode("#12345")).to.equal(nil)
        end)
    end)

    describe("Style.theme", function()
        it("should return the defaults without overrides", function()
            const theme = Style.theme()
            for key, spec in Style.DefaultTheme :: any do
                expect((theme :: any)[key]).to.equal(spec)
            end
        end)

        it("should replace only the overridden entries", function()
            const theme = Style.theme({ Success = { Color = "#00ff00", Underline = true } })
            expect(theme.Success.Color).to.equal("#00ff00")
            expect(theme.Success.Underline).to.equal(true)
            expect(theme.Success.Bold).to.equal(nil)
            expect(theme.Heading).to.equal(Style.DefaultTheme.Heading)
        end)

        it("should reject unknown keys, unknown colors, and unknown attributes", function()
            expect(function()
                Style.theme({ Sucess = { Bold = true } })
            end).to.throw()
            expect(function()
                Style.theme({ Success = { Color = "teal" } })
            end).to.throw()
            expect(function()
                Style.theme({ Success = { Blink = true } :: any })
            end).to.throw()
        end)

        it("should validate opacity without accepting invalid channels or palette guesses", function()
            for _, opacity in { -0.1, 1.1, math.huge, -math.huge, 0 / 0 } do
                expect(Style.validate({ Color = "#a8a8a8", Opacity = opacity })).to.equal(false)
                if opacity == opacity then
                    expect(Style.colorCode("#a8a8a8", opacity)).to.equal(nil)
                else
                    expect(function()
                        Style.colorCode("#a8a8a8", opacity)
                    end).to.throw()
                end
                expect(function()
                    Style.codes({ Color = "#a8a8a8", Opacity = opacity })
                end).to.throw()
            end
            for _, spec in
                {
                    { Opacity = 0.25 },
                    { Color = "gray", Opacity = 0.25 },
                    { Color = "#12345", Opacity = 0.25 },
                    { Color = "#a8a8a8", Opacity = "0.25" } :: any
                }
            do
                expect(Style.validate(spec)).to.equal(false)
            end
            const theme = Style.theme({ TimestampFaint = { Color = "#a8a8a8", Opacity = 0.25 } })
            expect(theme.TimestampFaint.Opacity).to.equal(0.25)
            expect(theme.TimestampFaint.Dim).to.equal(nil)
        end)

        it("should freeze the theme so it cannot drift after creation", function()
            const theme = Style.theme({ Count = { Bold = false } })
            expect(table.isfrozen(theme)).to.equal(true)
            expect(table.isfrozen(theme.Count)).to.equal(true)
        end)

        it("should give every default entry a valid spec", function()
            for key, spec in Style.DefaultTheme :: any do
                const ok, problem = Style.validate(spec)
                expect(ok).to.equal(true)
                expect(problem).to.equal(nil)
                expect(type(key)).to.equal("string")
            end
        end)

        it("should request explicit opacity for timestamp brackets and leading zeros", function()
            const theme = Style.DefaultTheme
            for _, spec in { theme.TimestampBracket, theme.TimestampFaint } do
                expect(spec.Color).to.equal(theme.TimestampText.Color)
                expect(spec.Opacity).to.equal(0.5)
                expect(spec.Dim).to.equal(nil)
                expect(Style.paint(spec, "0", true)).to.equal(`{ESCAPE}38:6::168:168:168:128m0{ESCAPE}39m`)
                expect(Style.paint(spec, "0", false)).to.equal("0")
            end
            expect(theme.TimestampText.Opacity).to.equal(nil)
        end)

        it("should share one muted gray across secondary text", function()
            const theme = Style.DefaultTheme :: any
            for _, key in
                {
                    "Address",
                    "Identifier",
                    "Muted",
                    "Path",
                    "StepBracket",
                    "StepTotal",
                    "TimestampBracket",
                    "TimestampFaint",
                    "Url"
                }
            do
                expect(theme[key].Color).to.equal(theme.TimestampText.Color)
            end
        end)

        it("should use the approved RGB palette for every colored role without ANSI faint", function()
            const palette = {
                Address = "#A8A8A8",
                Count = "#E0AF68",
                Error = "#F7768E",
                Faint = "#5A5A5A",
                Heading = "#7AA2F7",
                HelpArgument = "#C0CAF5",
                HelpCommand = "#7AA2F7",
                HelpDescription = "#A8A8A8",
                HelpHeading = "#E0AF68",
                HelpVersion = "#9ECE6A",
                Identifier = "#A8A8A8",
                Muted = "#A8A8A8",
                Path = "#A8A8A8",
                RobloxPath = "#7DCFFF",
                StepBracket = "#A8A8A8",
                StepCurrent = "#E0AF68",
                StepTotal = "#A8A8A8",
                Success = "#9ECE6A",
                TimestampBracket = "#A8A8A8",
                TimestampFaint = "#A8A8A8",
                TimestampText = "#A8A8A8",
                Url = "#A8A8A8",
                Warning = "#E0AF68"
            }
            for key, spec in Style.DefaultTheme :: any do
                expect(spec.Color).to.equal((palette :: any)[key])
                expect(spec.Dim).to.equal(nil)
                expect(spec.Opacity == 0.5).to.equal(key == "TimestampBracket" or key == "TimestampFaint")
                if spec.Color then
                    expect(string.match(Style.colorCode(spec.Color) :: string, "^38;2;") ~= nil).to.equal(true)
                end
            end
        end)
    end)

    describe("Style.resolve", function()
        it("should resolve every opacity and support combination without changing the input", function()
            for _, supported in { false, true } do
                for _, opacity in { 0, 0.25, 0.5, 1 } do
                    const spec = table.freeze({ Bold = true, Color = "#A8A8A8", Opacity = opacity })
                    const resolved = Style.resolve(spec, supported, "#5A5A5A")
                    const repeated = Style.resolve(spec, supported, "#5A5A5A")
                    expect(resolved.Color).to.equal(if supported or opacity == 1 then "#A8A8A8" else "#5A5A5A")
                    expect(resolved.Opacity).to.equal(if supported and opacity ~= 1 then opacity else nil)
                    expect(resolved.Bold).to.equal(true)
                    expect(resolved.Dim).to.equal(nil)
                    expect(Style.codes(resolved)).to.equal(Style.codes(repeated))
                    expect(spec.Opacity).to.equal(opacity)
                end
            end
        end)

        it("should replace legacy dim with confirmed opacity or solid gray", function()
            for _, supported in { false, true } do
                for _, color in { "#A8A8A8", "gray", false } do
                    const spec = { Bold = true, Color = if color then color else nil, Dim = true }
                    const resolved = Style.resolve(spec, supported, "#5A5A5A")
                    expect(resolved.Dim).to.equal(nil)
                    expect(resolved.Bold).to.equal(true)
                    expect(resolved.Opacity).to.equal(if supported and color == "#A8A8A8" then 0.5 else nil)
                    expect(resolved.Color).to.equal(if supported and color == "#A8A8A8" then color else "#5A5A5A")
                    expect(spec.Dim).to.equal(true)
                end
            end
        end)

        it("should leave opaque and ordinary styles untouched", function()
            for _, spec in { {}, { Bold = true }, { Color = "green", Dim = false } } do
                expect(Style.resolve(spec, false, "#5A5A5A")).to.equal(spec)
            end
        end)
    end)

    describe("Style.codes", function()
        it("should open and close exactly the attributes in every combination", function()
            const attributes = { "Bold", "Dim", "Italic", "Underline", "Color" }
            for mask = 0, 2 ^ #attributes - 1 do
                const spec = {}
                for index, attribute in attributes do
                    if bit32.extract(mask, index - 1) == 1 then
                        spec[attribute] = if attribute == "Color" then "green" else true
                    end
                end
                const opening, closing = Style.codes(spec)
                if mask == 0 then
                    expect(opening).to.equal("")
                    expect(closing).to.equal("")
                    continue
                end
                const hasIntensity = spec.Bold or spec.Dim
                expect(string.find(opening, "1", 1, true) ~= nil).to.equal(spec.Bold == true)
                expect(string.find(closing, "22", 1, true) ~= nil).to.equal(hasIntensity == true)
                expect(string.find(closing, "23", 1, true) ~= nil).to.equal(spec.Italic == true)
                expect(string.find(closing, "24", 1, true) ~= nil).to.equal(spec.Underline == true)
                expect(string.find(opening, "32", 1, true) ~= nil).to.equal(spec.Color ~= nil)
                expect(string.find(closing, "39", 1, true) ~= nil).to.equal(spec.Color ~= nil)
                -- Never emit a full reset, since that would clear styles around the text.
                expect(string.find(closing, `{ESCAPE}0m`, 1, true)).to.equal(nil)
            end
        end)
    end)

    describe("Style.paint", function()
        it("should wrap text in the spec's codes", function()
            expect(Style.paint({ Bold = true, Color = "greenBright" }, "Done.", true)).to.equal(
                `{ESCAPE}1;92mDone.{ESCAPE}22;39m`
            )
        end)

        it("should reset alpha after text and preserve outer opacity around nested colors", function()
            const spec = { Color = "#a8a8a8", Opacity = 0.25 }
            const opening = `{ESCAPE}38:6::168:168:168:64m`
            const inner = Style.paint({ Color = "green" }, "inner", true)
            expect(Style.paint(spec, "x", true)).to.equal(`{opening}x{ESCAPE}39m`)
            expect(Style.paint(spec, "x", false)).to.equal("x")
            expect(Style.paint(spec, "", true)).to.equal("")
            expect(Style.paint(spec, `a {inner} b`, true)).to.equal(
                `{opening}a {ESCAPE}32minner{ESCAPE}39m{opening} b{ESCAPE}39m`
            )
            expect(Style.paint({ Color = "green" }, Style.paint(spec, "x", true), true)).to.equal(
                `{ESCAPE}32m{opening}x{ESCAPE}39m{ESCAPE}32m{ESCAPE}39m`
            )
        end)

        it("should return plain text when color is off or the text is empty", function()
            expect(Style.paint({ Bold = true }, "Done.", false)).to.equal("Done.")
            expect(Style.paint({ Bold = true }, "", true)).to.equal("")
            expect(Style.paint({}, "Done.", true)).to.equal("Done.")
        end)

        it("should not interpret SGR bytes inside a control-string payload", function()
            const payload = `\u{1b}Ppayload {ESCAPE}39m\u{1b}\\`
            expect(Style.paint({ Color = "yellow" }, `{payload}text`, true)).to.equal(
                `{ESCAPE}33m{payload}text{ESCAPE}39m`
            )
        end)

        it("should keep its own style after text painted inside it ends", function()
            const inner = Style.paint({ Color = "gray" }, "~/repo/", true)
            const outer = Style.paint({ Color = "yellow" }, `Cannot read {inner} today.`, true)
            expect(outer).to.equal(`{ESCAPE}33mCannot read {ESCAPE}90m~/repo/{ESCAPE}39m{ESCAPE}33m today.{ESCAPE}39m`)
        end)

        it("should keep a nested path's dot in the path's color", function()
            const path = Style.paintPath({ Bold = true, Color = "cyanBright" }, "My Place.rbxl", true)
            const outer = Style.paint({ Color = "yellow" }, `Open {path}.`, true)
            expect(outer).to.equal(
                `{ESCAPE}33mOpen {ESCAPE}1;96mMy{ESCAPE}22;96m·{ESCAPE}1mPlace.rbxl{ESCAPE}22;39m{ESCAPE}33m.{ESCAPE}39m`
            )
        end)
    end)

    describe("Style.isClosing", function()
        it("should only accept codes that turn attributes off", function()
            for _, parameters in { "", "0", "22", "22;39", "23;24;49" } do
                expect(Style.isClosing(parameters)).to.equal(true)
            end
            for _, parameters in
                { "1", "22;96", "38;2;1;2;3", "38:6::168:168:168:64", "22;38:6::168:168:168:64", "39;1" }
            do
                expect(Style.isClosing(parameters)).to.equal(false)
            end
        end)
    end)

    describe("Style.paintPath", function()
        it("should show spaces as center dots in every color and weight combination", function()
            for _, color in { true, false } do
                for _, bold in { true, false } do
                    const painted = Style.paintPath({ Bold = bold, Color = "cyanBright" }, "My Place.rbxl", color)
                    expect(Style.strip(painted)).to.equal("My·Place.rbxl")
                end
            end
        end)

        it("should never make the dot bold", function()
            const painted = Style.paintPath({ Bold = true, Color = "cyanBright" }, "a b", true)
            expect(painted).to.equal(`{ESCAPE}1;96ma{ESCAPE}22;96m·{ESCAPE}1mb{ESCAPE}22;39m`)
        end)

        it("should preserve path alpha on the unbold dot even inside an opaque color", function()
            const path = Style.paintPath({ Bold = true, Color = "#a8a8a8", Opacity = 0.25 }, "a b", true)
            const expected =
                `{ESCAPE}1;38:6::168:168:168:64ma{ESCAPE}22;38:6::168:168:168:64m·{ESCAPE}1mb{ESCAPE}22;39m`
            expect(path).to.equal(expected)
            expect(Style.paint({ Color = "yellow" }, path, true)).to.equal(
                `{ESCAPE}33m{expected}{ESCAPE}33m{ESCAPE}39m`
            )
            expect(Style.paintPath({ Color = "#a8a8a8", Opacity = 0.25 }, "a b", false)).to.equal("a·b")
        end)

        it("should suppress inherited bold for colored and colorless path dots", function()
            for _, pathStyle in { {}, { Bold = true }, { Color = "cyanBright" }, { Bold = true, Color = "cyanBright" } } do
                const path = Style.paintPath(pathStyle, "a b", true)
                const painted = Style.paint({ Bold = true, Color = "blueBright" }, path, true)
                const dot = assert(string.find(painted, "·", 1, true))
                const before = Style.sgrState("", string.sub(painted, 1, dot - 1))
                expect(string.find(before, `{ESCAPE}1m`, 1, true)).to.equal(nil)
                const after = Style.sgrState("", string.sub(painted, 1, (assert(string.find(painted, "b", 1, true)))))
                expect(string.find(after, `{ESCAPE}1m`, 1, true) ~= nil).to.equal(true)
            end
        end)

        it("should keep dim text dim around the dot", function()
            const painted = Style.paintPath({ Bold = true, Dim = true }, "a b", true)
            expect(painted).to.equal(`{ESCAPE}1;2ma{ESCAPE}22;2m·{ESCAPE}1mb{ESCAPE}22m`)
        end)
    end)

    describe("Style.sgrState", function()
        it("should canonicalize previous styles without tokenizing plain text", function()
            const source = fs.readFile("Source/Commandline/Terminal/Style.luau")
            for _, text in { "", "Plain ASCII [31m", "Café 界 e\u{301}", string.rep("x", 8192) } do
                for _, case in
                    {
                        { "", "" },
                        { "unstyled", "" },
                        { `{ESCAPE}31;1m{ESCAPE}32m`, `{ESCAPE}1m{ESCAPE}32m` },
                        { `{ESCAPE}1;31m{ESCAPE}0m`, "" },
                        { `{ESCAPE}48;2;1;2;3;38:2::4:5:6m`, `{ESCAPE}38:2::4:5:6m{ESCAPE}48;2;1;2;3m` }
                    }
                do
                    const previous, expected = case[1], case[2]
                    const dependencies: { [string]: any } = {
                        ["./Text"] = {
                            tokens = function(input: string)
                                -- Guard the boundary rather than relying on elapsed time or call counts.
                                expect(input).to.equal(previous)
                                return Text.tokens(input)
                            end
                        },
                        ["@packages/t"] = t
                    }
                    const style = luau.load(source, {
                        environment = {
                            require = function(path)
                                return assert(dependencies[path], `Unexpected dependency "{path}".`)
                            end
                        }
                    })()
                    expect(style.sgrState(previous, text)).to.equal(expected)
                    expect(Style.sgrState(previous, text)).to.equal(expected)
                end
            end
        end)

        it("should not treat C1 controls or Unicode lookalikes as ANSI escapes", function()
            for _, text in { "\u{9b}31m", string.char(0x9b) .. "31m", "␛[31m", "[0m", "\u{1b0}31m" } do
                expect(Style.sgrState("", text)).to.equal("")
                expect(Style.sgrState(`{ESCAPE}1;32m`, text)).to.equal(`{ESCAPE}1m{ESCAPE}32m`)
            end
        end)

        it("should still parse escapes after long plain prefixes and reset active styles", function()
            const prefix = string.rep("x", 8192)
            expect(Style.sgrState(`{ESCAPE}1;31m`, `{prefix}{ESCAPE}32m`)).to.equal(`{ESCAPE}1m{ESCAPE}32m`)
            expect(Style.sgrState(`{ESCAPE}1;31m`, `{prefix}{ESCAPE}m`)).to.equal("")
            expect(Style.sgrState(`{ESCAPE}1m`, `\u{1b}]title {ESCAPE}0m\u{7}plain`)).to.equal(`{ESCAPE}1m`)
        end)

        it("should preserve escapes completed across the previous and text boundary", function()
            for _, case in
                {
                    { "\u{1b}", "[31m", `{ESCAPE}31m` },
                    { `{ESCAPE}3`, "1m", `{ESCAPE}31m` },
                    { `{ESCAPE}1m{ESCAPE}`, "0m", "" },
                    { `{ESCAPE}38:2::1:`, "2:3m", `{ESCAPE}38:2::1:2:3m` },
                    { `{ESCAPE}1m{ESCAPE}3`, "plain", `{ESCAPE}1m` }
                }
            do
                expect(Style.sgrState(case[1], case[2])).to.equal(case[3])
            end
        end)

        it("should retain only active attributes and complete extended colors", function()
            const rgba = `{ESCAPE}38:6::168:168:168:128m`
            expect(Style.sgrState("", `{ESCAPE}1;2;3m{rgba}`)).to.equal(`{ESCAPE}1m{ESCAPE}2m{ESCAPE}3m{rgba}`)
            expect(Style.sgrState(`{ESCAPE}1;2;3;31m`, `{ESCAPE}22;39m`)).to.equal(`{ESCAPE}3m`)
            expect(Style.sgrState(`{ESCAPE}1;31m`, `{ESCAPE}0m`)).to.equal("")
            expect(Style.sgrState("", `{ESCAPE}38;2;1;2;3m`)).to.equal(`{ESCAPE}38;2;1;2;3m`)
            local state = ""
            for _ = 1, 100 do
                state = Style.sgrState(state, `{ESCAPE}33mtext`)
            end
            expect(state).to.equal(`{ESCAPE}33m`)
        end)
    end)

    describe("Style.strip", function()
        it("should remove every escape sequence", function()
            expect(Style.strip(`{ESCAPE}1;38;2;1;2;3mx{ESCAPE}22;39m`)).to.equal("x")
            expect(Style.strip(`{ESCAPE}1;38:6::168:168:168:64mx{ESCAPE}22;39m`)).to.equal("x")
        end)
    end)
end

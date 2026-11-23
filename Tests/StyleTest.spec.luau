--[[

StyleTest.spec

Tests for Style, covering color codes, theme overrides and validation, escape sequences
for every attribute combination, and path painting with center dots.

--]]

const Style = require("../Source/Commandline/Terminal/Style")

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

        it("should show counting timestamp digits brighter than their faint lead", function()
            const function brightness(color: string): number
                const red, green, blue = string.match(color, "^#(%x%x)(%x%x)(%x%x)$")
                assert(red and green and blue, `Expected a hex color, got "{color}".`)
                return (tonumber(red, 16) :: number) + (tonumber(green, 16) :: number) + (tonumber(blue, 16) :: number)
            end
            const theme = Style.DefaultTheme
            expect(theme.TimestampBracket.Color).to.equal(theme.TimestampFaint.Color)
            expect(theme.TimestampFaint.Dim).to.equal(nil)
            expect(brightness(theme.TimestampText.Color :: string) > brightness(theme.TimestampFaint.Color :: string)).to.equal(
                true
            )
        end)

        it("should share one muted gray across secondary text", function()
            const theme = Style.DefaultTheme :: any
            for _, key in { "Address", "Identifier", "Path", "StepBracket", "StepTotal", "Url" } do
                expect(theme[key].Color).to.equal(theme.TimestampText.Color)
            end
        end)

        it("should never rely on dim text in the default theme", function()
            for _, spec in Style.DefaultTheme :: any do
                expect(spec.Dim).to.equal(nil)
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

        it("should return plain text when color is off or the text is empty", function()
            expect(Style.paint({ Bold = true }, "Done.", false)).to.equal("Done.")
            expect(Style.paint({ Bold = true }, "", true)).to.equal("")
            expect(Style.paint({}, "Done.", true)).to.equal("Done.")
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
            for _, parameters in { "1", "22;96", "38;2;1;2;3", "39;1" } do
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

        it("should keep dim text dim around the dot", function()
            const painted = Style.paintPath({ Bold = true, Dim = true }, "a b", true)
            expect(painted).to.equal(`{ESCAPE}1;2ma{ESCAPE}22;2m·{ESCAPE}1mb{ESCAPE}22m`)
        end)
    end)

    describe("Style.strip", function()
        it("should remove every escape sequence", function()
            expect(Style.strip(`{ESCAPE}1;38;2;1;2;3mx{ESCAPE}22;39m`)).to.equal("x")
        end)
    end)
end

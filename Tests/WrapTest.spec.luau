--[[

WrapTest.spec

Tests for Wrap, covering word boundaries, hanging indents, styled text, multi-byte
characters, and words wider than a whole line.

--]]

const Style = require("../Source/Commandline/Terminal/Style")
const Wrap = require("../Source/Commandline/Terminal/Wrap")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const ESCAPE = "\u{1b}["

return function()
    describe("Wrap.width", function()
        it("should count columns without escape sequences", function()
            expect(Wrap.width(`{ESCAPE}1;96mMy·Place{ESCAPE}22;39m`)).to.equal(8)
            expect(Wrap.width("")).to.equal(0)
        end)
    end)

    describe("Wrap.line", function()
        it("should leave lines that fit unchanged", function()
            expect(Wrap.line("One two three.", 14)).to.equal("One two three.")
        end)

        it("should break between words and drop the spaces at the break", function()
            expect(Wrap.line("is not a readable Git checkout.", 12)).to.equal("is not a\nreadable Git\ncheckout.")
        end)

        it("should indent continuation lines to line up after a timestamp", function()
            expect(Wrap.line("[00:01.234] Visit the page for more.", 26, "            ")).to.equal(
                "[00:01.234] Visit the page\n            for more."
            )
        end)

        it("should split only words wider than a whole line", function()
            expect(Wrap.line("Go /a/very/long/path now", 8)).to.equal("Go\n/a/very/\nlong/pat\nh now")
        end)

        it("should keep styles intact and count only visible columns", function()
            const path = Style.paintPath({ Bold = true, Color = "cyanBright" }, "My Place.rbxl", true)
            const text = Style.paint({ Color = "yellow" }, `Opening {path} in Studio now.`, true)
            const wrapped = Wrap.line(text, 22)
            expect(Style.strip(wrapped)).to.equal("Opening My·Place.rbxl\nin Studio now.")
            expect(string.gsub(wrapped, "\n", "")).to.equal((string.gsub(text, " in Studio", "in Studio")))
        end)

        it("should never exceed the width or lose words, whatever the width", function()
            const text = "Cannot check whether ae is up to date because ~/projects/game/ is not readable."
            for columns = 1, #text + 2 do
                const wrapped = Wrap.line(text, columns, if columns > 4 then "  " else nil)
                for line in string.gmatch(`{wrapped}\n`, "([^\n]*)\n") do
                    expect(Wrap.width(line) <= math.max(columns, 1)).to.equal(true)
                end
                const words = string.gsub(string.gsub(wrapped, "%s+", ""), "\n", "")
                expect(words).to.equal((string.gsub(text, "%s+", "")))
            end
        end)

        it("should leave text alone when the indent leaves no room", function()
            expect(Wrap.line("Some long text here.", 4, "    ")).to.equal("Some long text here.")
        end)

        it("should return the same result for the same input", function()
            const text = "[00:00.001] [1/5] Refreshing and watching local package mirrors..."
            expect(Wrap.line(text, 30, "            ")).to.equal(Wrap.line(text, 30, "            "))
        end)
    end)
end

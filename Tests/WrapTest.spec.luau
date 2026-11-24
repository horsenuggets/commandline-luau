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
            expect(Wrap.width(`{ESCAPE}38:6::168:168:168:64mMy·Place{ESCAPE}39m`)).to.equal(8)
            expect(Wrap.width("")).to.equal(0)
        end)
    end)

    describe("Terminal display columns", function()
        it("should measure wide glyphs, combining marks, and emoji clusters", function()
            for _, case in
                {
                    { "\u{754c}\u{754c}\u{754c}", 6 },
                    { "e\u{301}e\u{301}", 2 },
                    { "\u{1f469}\u{200d}\u{1f4bb}", 2 },
                    { "\u{1f1fa}\u{1f1f8}", 2 },
                    { "\u{1f44d}\u{1f3fd}", 2 },
                    { "1\u{fe0f}\u{20e3}", 2 },
                    { "\u{2764}\u{fe0e}", 1 },
                    { "\u{2764}\u{fe0f}", 2 },
                    { "\u{1100}\u{1161}", 2 },
                }
            do
                expect(Wrap.width(case[1] :: string)).to.equal(case[2])
            end
        end)

        it("should wrap between intact wide glyphs and emoji clusters", function()
            const wide = "\u{754c}"
            const emoji = "\u{1f469}\u{200d}\u{1f4bb}"
            expect(Wrap.line(string.rep(wide, 3), 4)).to.equal(`{wide}{wide}\n{wide}`)
            expect(Wrap.line(string.rep(emoji, 3), 4)).to.equal(`{emoji}{emoji}\n{emoji}`)
            expect(Wrap.line("e\u{301}e\u{301}", 2)).to.equal("e\u{301}e\u{301}")
        end)

        it("should keep control strings and hyperlink URLs intact at zero width", function()
            const opening = "\u{1b}]8;;https://example.com/a-long-link\u{1b}\\"
            const closing = "\u{1b}]8;;\u{1b}\\"
            const text = `Open {opening}docs{closing} now.`
            const wrapped = Wrap.line(text, 9)
            expect(Style.strip(wrapped)).to.equal("Open docs\nnow.")
            expect(string.find(wrapped, opening, 1, true) ~= nil).to.equal(true)
            expect(string.find(wrapped, closing, 1, true) ~= nil).to.equal(true)
            for _, escape in
                {
                    "\u{1b}]0;A title with spaces\u{7}",
                    "\u{1b}Ppayload with spaces\u{1b}\\",
                    "\u{1b}_payload with spaces\u{1b}\\",
                    "\u{1b}[2K",
                }
            do
                expect(Wrap.width(`a{escape}b`)).to.equal(2)
                expect(Style.strip(`a{escape}b`)).to.equal("ab")
                expect(string.find(Wrap.line(`One {escape}two`, 3), escape, 1, true) ~= nil).to.equal(true)
            end
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

        it("should preserve complete RGBA escapes when moving and splitting words", function()
            const opening = `{ESCAPE}38:6::168:168:168:64m`
            const closing = `{ESCAPE}39m`
            expect(Wrap.line(`One {opening}two{closing}`, 3)).to.equal(`One{opening}\ntwo{closing}`)
            expect(Wrap.line(`{opening}abcdef{closing}`, 2)).to.equal(`{opening}ab\ncd\nef{closing}`)
            for columns = 1, 12 do
                const wrapped = Wrap.line(`One {opening}two three{closing}`, columns)
                for _, line in string.split(wrapped, "\n") do
                    expect(Wrap.width(line) <= columns).to.equal(true)
                end
                expect(string.gsub(Style.strip(wrapped), "%s", "")).to.equal("Onetwothree")
                expect(string.find(wrapped, opening, 1, true) ~= nil).to.equal(true)
            end
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

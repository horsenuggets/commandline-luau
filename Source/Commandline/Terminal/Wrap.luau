--[[

Wrap

Word-wraps one line of styled terminal text to a column width. Escape sequences take no
columns, words move whole to the next line, and only a word wider than the whole line is
split. Continuation lines start with an indent, so wrapped text stays aligned after a
timestamp. Contains no I/O.

--]]

const Text = require("./Text")
const t = require("@packages/t")

const Wrap = {}

-- Returns the number of columns text takes once escape sequences are removed.
function Wrap.width(text: string): number
    assert(t.string(text))
    return Text.width(text)
end

--[[
    Returns the line wrapped to the given width, with every continuation line starting
    with the indent. The indent's columns count against the width. Widths too narrow to
    fit any text after the indent leave the line unchanged.
]]
function Wrap.line(text: string, columns: number, indent: string?): string
    assert(t.string(text))
    assert(t.integer(columns))
    assert(t.optional(t.string)(indent))

    const continuation = indent or ""
    const available = columns - Wrap.width(continuation)
    if available < 1 or Wrap.width(text) <= columns then
        return text
    end

    const indentWidth = Wrap.width(continuation)
    const lines = {}
    local current = ""
    local currentWidth = 0
    -- A word and the spaces before it are held back until the word ends, so a break can
    -- drop those spaces instead of leaving them at the end of a line. Escape sequences
    -- between words travel with the spaces, so a style opening a word moves with it.
    local spaces = ""
    local spacesWidth = 0
    local word = ""
    local wordWidth = 0

    const function breakLine()
        table.insert(lines, current)
        current = continuation
        currentWidth = indentWidth
    end

    const function placeWord()
        if wordWidth == 0 then
            return
        end
        if currentWidth > indentWidth and currentWidth + spacesWidth + wordWidth > columns then
            -- Keep style changes from the dropped spaces, since they may open the word.
            for _, token in Text.tokens(spaces) do
                if token.Escape or token.Text ~= " " then
                    current ..= token.Text
                end
            end
            breakLine()
        else
            current ..= spaces
            currentWidth += spacesWidth
        end
        spaces = ""
        spacesWidth = 0
        -- Only a word wider than a whole line is split, at the column edge.
        for _, token in Text.tokens(word) do
            if token.Width > 0 and currentWidth + token.Width > columns then
                breakLine()
            end
            current ..= token.Text
            currentWidth += token.Width
        end
        word = ""
        wordWidth = 0
    end

    for _, token in Text.tokens(text) do
        if token.Text == " " then
            if wordWidth > 0 then
                placeWord()
            end
            spaces ..= " "
            spacesWidth += 1
        elseif token.Width == 0 and wordWidth == 0 then
            spaces ..= token.Text
        else
            word ..= token.Text
            wordWidth += token.Width
        end
    end
    placeWord()
    current ..= spaces
    table.insert(lines, current)
    return table.concat(lines, "\n")
end

return Wrap

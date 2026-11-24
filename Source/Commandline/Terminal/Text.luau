--[[

Text

Tokenizes terminal text without splitting escape sequences or display clusters. Measures
wide characters, combining marks, and common emoji sequences in terminal columns. Uses
Lune's Unicode properties for marks and emoji rather than maintaining duplicate tables.

--]]

const regex = require("@lune/regex")
const t = require("@packages/t")

const EMOJI = regex.new([[^\p{Emoji}$]])
const EMOJI_PRESENTATION = regex.new([[^\p{Emoji_Presentation}$]])
const PICTOGRAPHIC = regex.new([[^\p{Extended_Pictographic}$]])
const ZERO_WIDTH = regex.new([[^[\p{Mark}\p{Default_Ignorable_Code_Point}\p{Emoji_Modifier}]$]])

export type Token = { Escape: boolean?, Text: string, Width: number }

const Text = {}

-- CSI ends at its final byte. OSC permits BEL or ST, while the other control strings
-- use ST. An incomplete escape stays intact rather than becoming visible URL fragments.
const function escapeEnd(text: string, start: number): number
    const kind = string.byte(text, start + 1)
    if kind == 0x5b then
        for index = start + 2, #text do
            const byte = string.byte(text, index)
            if byte >= 0x40 and byte <= 0x7e then
                return index
            end
        end
        return #text
    elseif kind == 0x5d or kind == 0x50 or kind == 0x58 or kind == 0x5e or kind == 0x5f then
        for index = start + 2, #text do
            const byte = string.byte(text, index)
            if (kind == 0x5d and byte == 7) or (byte == 0x5c and string.byte(text, index - 1) == 0x1b) then
                return index
            end
        end
        return #text
    end
    local index = start + 1
    while index < #text do
        const byte = string.byte(text, index)
        if byte < 0x20 or byte > 0x2f then
            break
        end
        index += 1
    end
    return math.min(index, #text)
end

-- East Asian wide/fullwidth blocks use two columns; ambiguous-width text uses one.
const function isWide(codepoint: number): boolean
    return (codepoint >= 0x1100 and codepoint <= 0x115f)
        or codepoint == 0x2329
        or codepoint == 0x232a
        or (codepoint >= 0x2e80 and codepoint <= 0xa4cf and codepoint ~= 0x303f)
        or (codepoint >= 0xac00 and codepoint <= 0xd7a3)
        or (codepoint >= 0xf900 and codepoint <= 0xfaff)
        or (codepoint >= 0xfe10 and codepoint <= 0xfe19)
        or (codepoint >= 0xfe30 and codepoint <= 0xfe6f)
        or (codepoint >= 0xff01 and codepoint <= 0xff60)
        or (codepoint >= 0xffe0 and codepoint <= 0xffe6)
        or (codepoint >= 0x1b000 and codepoint <= 0x1b2ff)
        or (codepoint >= 0x1f200 and codepoint <= 0x1f251)
        or (codepoint >= 0x20000 and codepoint <= 0x3fffd)
end

function Text.tokens(text: string): { Token }
    assert(t.string(text))
    const result: { Token } = {}
    local index = 1
    local base: number? = nil
    local emoji = false
    local join = false
    local regional = false
    while index <= #text do
        if string.byte(text, index) == 0x1b then
            const finish = escapeEnd(text, index)
            table.insert(result, { Escape = true, Text = string.sub(text, index, finish), Width = 0 })
            index = finish + 1
            continue
        end
        const character = string.match(text, `^{utf8.charpattern}`, index) or string.sub(text, index, index)
        const valid, value = pcall(utf8.codepoint, character)
        const codepoint = if valid then value :: number else string.byte(character)
        local width = 1
        if valid and codepoint == 0x200d then
            width = 0
            join = emoji
        elseif valid and codepoint == 0xfe0f and base and emoji then
            width = 0
            result[base].Width = 2
        elseif valid and codepoint == 0xfe0e and base and emoji then
            width = 0
            result[base].Width = 1
        elseif
            valid
            and codepoint >= 0x80
            and (ZERO_WIDTH:isMatch(character) or (codepoint >= 0x1160 and codepoint <= 0x11ff))
        then
            width = 0
        elseif codepoint < 0x20 or (codepoint >= 0x7f and codepoint < 0xa0) then
            width = 0
        elseif valid and join and base and PICTOGRAPHIC:isMatch(character) then
            width = 0
            result[base].Width = 2
            join = false
        elseif valid and codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff and regional then
            width = 0
            regional = false
        else
            width = if valid
                    and codepoint >= 0x80
                    and (isWide(codepoint) or EMOJI_PRESENTATION:isMatch(character))
                then 2
                else 1
            base = #result + 1
            emoji = valid
                and (
                    (codepoint >= 0x80 and EMOJI:isMatch(character))
                    or (codepoint >= 0x30 and codepoint <= 0x39)
                    or codepoint == 0x23
                    or codepoint == 0x2a
                )
            regional = valid and codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff
            join = false
        end
        -- Combining keycaps have emoji presentation even without a variation selector.
        if valid and codepoint == 0x20e3 and base and emoji then
            result[base].Width = 2
        end
        table.insert(result, { Text = character, Width = width })
        index += #character
    end
    return result
end

function Text.strip(text: string): string
    assert(t.string(text))
    const visible = {}
    for _, token in Text.tokens(text) do
        if not token.Escape then
            table.insert(visible, token.Text)
        end
    end
    return table.concat(visible)
end

function Text.width(text: string): number
    assert(t.string(text))
    local width = 0
    for _, token in Text.tokens(text) do
        width += token.Width
    end
    return width
end

return Text

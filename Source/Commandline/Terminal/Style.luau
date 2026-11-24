--[[

Style

Turns semantic style specs into ANSI escape sequences. A theme maps each kind of terminal
text (paths, counts, headings, timestamps, and so on) to a spec, and any spec can be
overridden. Contains no I/O, so callers decide whether color is enabled.

--]]

const Text = require("./Text")
const t = require("@packages/t")

const CLOSING_PARAMETERS = {
    ["0"] = true,
    ["22"] = true,
    ["23"] = true,
    ["24"] = true,
    ["39"] = true,
    ["49"] = true
}
const ESCAPE = "\u{1b}["
const NAMED_COLORS = {
    black = 30,
    blackBright = 90,
    blue = 34,
    blueBright = 94,
    cyan = 36,
    cyanBright = 96,
    gray = 90,
    green = 32,
    greenBright = 92,
    magenta = 35,
    magentaBright = 95,
    red = 31,
    redBright = 91,
    white = 37,
    whiteBright = 97,
    yellow = 33,
    yellowBright = 93
}
const PATH_SEPARATOR_DOT = "·"
const SGR_RESETS = {
    [22] = 1,
    [23] = 3,
    [24] = 4,
    [25] = 5,
    [27] = 7,
    [28] = 8,
    [29] = 9,
    [39] = 30,
    [49] = 40,
    [54] = 51,
    [55] = 53,
    [59] = 58
}

export type Spec = {
    Bold: boolean?,
    Color: string?,
    Dim: boolean?,
    Italic: boolean?,
    Opacity: number?,
    Underline: boolean?
}

export type Theme = {
    Address: Spec,
    Count: Spec,
    Error: Spec,
    Faint: Spec,
    Heading: Spec,
    Identifier: Spec,
    Muted: Spec,
    Path: Spec,
    RobloxPath: Spec,
    StepBracket: Spec,
    StepCurrent: Spec,
    StepTotal: Spec,
    Success: Spec,
    TimestampBracket: Spec,
    TimestampFaint: Spec,
    TimestampText: Spec,
    Url: Spec,
    Warning: Spec
}

export type ThemeOverrides = { [string]: Spec }

-- Secondary text uses one muted gray. Timestamp brackets and leading zeros use the same
-- color with ANSI faint, letting the terminal apply its faint opacity. Gallery dividers
-- retain a separate solid faint gray.
const FAINT_GRAY = "#5a5a5a"
const MUTED_GRAY = "#a8a8a8"

const DEFAULT_THEME: Theme = table.freeze({
    Address = table.freeze({ Color = MUTED_GRAY }),
    Count = table.freeze({ Bold = true, Color = "yellowBright" }),
    Error = table.freeze({ Color = "red" }),
    Faint = table.freeze({ Color = FAINT_GRAY }),
    Heading = table.freeze({ Bold = true, Color = "blueBright" }),
    Identifier = table.freeze({ Color = MUTED_GRAY }),
    Muted = table.freeze({ Color = MUTED_GRAY }),
    Path = table.freeze({ Color = MUTED_GRAY }),
    RobloxPath = table.freeze({ Bold = true, Color = "cyanBright" }),
    StepBracket = table.freeze({ Color = MUTED_GRAY }),
    StepCurrent = table.freeze({ Bold = true, Color = "yellowBright" }),
    StepTotal = table.freeze({ Color = MUTED_GRAY }),
    Success = table.freeze({ Bold = true, Color = "greenBright" }),
    TimestampBracket = table.freeze({ Color = MUTED_GRAY, Dim = true }),
    TimestampFaint = table.freeze({ Color = MUTED_GRAY, Dim = true }),
    TimestampText = table.freeze({ Color = MUTED_GRAY }),
    Url = table.freeze({ Color = MUTED_GRAY }),
    Warning = table.freeze({ Color = "yellow" })
}) :: any

const specCheck = t.strictInterface({
    Bold = t.optional(t.boolean),
    Color = t.optional(t.string),
    Dim = t.optional(t.boolean),
    Italic = t.optional(t.boolean),
    Opacity = t.optional(t.number),
    Underline = t.optional(t.boolean)
})

const Style = {}

Style.DefaultTheme = DEFAULT_THEME

-- Opacity explicitly opts a hex foreground into the RGBA SGR extension. Palette colors
-- have no fixed RGB value, so cannot be given an alpha without guessing the theme.
function Style.colorCode(color: string, opacity: number?): string?
    assert(t.string(color))
    assert(t.optional(t.number)(opacity))

    if opacity ~= nil and not (opacity >= 0 and opacity <= 1) then
        return nil
    end
    const named = (NAMED_COLORS :: { [string]: number })[color]
    if named and opacity == nil then
        return tostring(named)
    end
    const red, green, blue = string.match(color, "^#(%x%x)(%x%x)(%x%x)$")
    if red and green and blue then
        if opacity ~= nil then
            return `38:6::{tonumber(red, 16)}:{tonumber(green, 16)}:{tonumber(blue, 16)}:{math.round(opacity * 255)}`
        end
        return `38;2;{tonumber(red, 16)};{tonumber(green, 16)};{tonumber(blue, 16)}`
    end
    return nil
end

function Style.validate(spec: Spec): (boolean, string?)
    const ok, problem = specCheck(spec)
    if not ok then
        return false, problem
    end
    if spec.Color ~= nil and Style.colorCode(spec.Color) == nil then
        return false, `Unknown color "{spec.Color}". Use a color name like "cyanBright" or a hex value like "#96cc22".`
    end
    if spec.Opacity ~= nil then
        if not (spec.Opacity >= 0 and spec.Opacity <= 1) then
            return false, "Opacity must be a finite number from 0 to 1."
        end
        if spec.Color == nil or Style.colorCode(spec.Color, spec.Opacity) == nil then
            return false, 'Opacity requires a hex foreground color like "#a8a8a8".'
        end
    end
    return true, nil
end

--[[
    Returns a new theme with every override replacing its default spec. Overrides must
    name a theme key and hold a valid spec, so a typo fails loudly instead of silently
    keeping the default.
]]
function Style.theme(overrides: ThemeOverrides?): Theme
    assert(t.optional(t.table)(overrides))

    const theme = table.clone(DEFAULT_THEME :: any)
    for key, spec in pairs(overrides or {}) do
        if (DEFAULT_THEME :: any)[key] == nil then
            error(`Unknown theme key "{key}".`, 2)
        end
        const ok, problem = Style.validate(spec)
        if not ok then
            error(`Invalid style for "{key}". {problem}`, 2)
        end
        theme[key] = table.freeze(table.clone(spec))
    end
    return table.freeze(theme) :: Theme
end

-- Returns the escape sequences that turn a spec on and off. Each closing code only resets
-- what the spec turned on, so styled text can sit inside other styled text.
function Style.codes(spec: Spec): (string, string)
    const valid, problem = Style.validate(spec)
    assert(valid, problem)

    const opening = {}
    const closing = {}
    if spec.Bold or spec.Dim then
        if spec.Bold then
            table.insert(opening, "1")
        end
        if spec.Dim then
            table.insert(opening, "2")
        end
        table.insert(closing, "22")
    end
    if spec.Italic then
        table.insert(opening, "3")
        table.insert(closing, "23")
    end
    if spec.Underline then
        table.insert(opening, "4")
        table.insert(closing, "24")
    end
    if spec.Color then
        const code = Style.colorCode(spec.Color, spec.Opacity)
        assert(code, `Unknown color "{spec.Color}".`)
        table.insert(opening, code)
        table.insert(closing, "39")
    end
    if #opening == 0 then
        return "", ""
    end
    return `{ESCAPE}{table.concat(opening, ";")}m`, `{ESCAPE}{table.concat(closing, ";")}m`
end

function Style.paint(spec: Spec, text: string, color: boolean): string
    assert(t.table(spec))
    assert(t.string(text))
    assert(t.boolean(color))

    if not color or text == "" then
        return text
    end
    const opening, closing = Style.codes(spec)
    if opening == "" then
        return text
    end
    -- Text painted inside this text ends with its own closing codes, which would also end
    -- this spec's color or weight. Reopening this spec after each one keeps it going.
    const nested = {}
    const tokens = Text.tokens(text)
    for index, token in tokens do
        table.insert(nested, token.Text)
        const parameters = if token.Escape then string.match(token.Text, "^\u{1b}%[([%d;:]*)m$") else nil
        const nextToken = tokens[index + 1]
        const dot = nextToken
            and nextToken.Text == PATH_SEPARATOR_DOT
            and parameters
            and (parameters == "22" or string.sub(parameters, 1, 3) == "22;")
        if parameters and Style.isClosing(parameters) and not dot then
            table.insert(nested, opening)
        end
        if token.Text == PATH_SEPARATOR_DOT and index > 1 then
            const previous = tokens[index - 1]
            if previous.Escape and string.match(previous.Text, "^\u{1b}%[22[;m]") then
                if spec.Bold then
                    table.insert(nested, `{ESCAPE}1m`)
                end
                if spec.Dim then
                    table.insert(nested, `{ESCAPE}2m`)
                end
            end
        end
    end
    return `{opening}{table.concat(nested)}{closing}`
end

-- Returns true for escape parameters that only turn attributes off, such as "22;39".
function Style.isClosing(parameters: string): boolean
    assert(t.string(parameters))
    if parameters == "" then
        return true
    end
    for parameter in string.gmatch(parameters, "[^;]+") do
        if not CLOSING_PARAMETERS[parameter] then
            return false
        end
    end
    return true
end

--[[
    Paints a path, showing each space as a center dot so the path reads as one token.
    The dot keeps the path's color but is never bold.
]]
function Style.paintPath(spec: Spec, text: string, color: boolean): string
    assert(t.table(spec))
    assert(t.string(text))
    assert(t.boolean(color))

    if not color then
        return (string.gsub(text, " ", PATH_SEPARATOR_DOT))
    end
    -- Built directly rather than through paint, which would reopen bold after the dot.
    -- The unbold code restates the color, so text painted around the path never mistakes
    -- it for a closing code and recolors the dot.
    const opening, closing = Style.codes(spec)
    const unbold = { "22" }
    if spec.Dim then
        table.insert(unbold, "2")
    end
    if spec.Color then
        table.insert(unbold, Style.colorCode(spec.Color, spec.Opacity) :: string)
    end
    const restore = if spec.Bold then `{ESCAPE}1m` else ""
    const separated = string.gsub(text, " ", `{ESCAPE}{table.concat(unbold, ";")}m{PATH_SEPARATOR_DOT}{restore}`)
    return `{opening}{separated}{closing}`
end

-- Returns only the active SGR settings, so replay stays bounded across streamed lines.
function Style.sgrState(previous: string, text: string): string
    assert(t.string(previous))
    assert(t.string(text))
    -- Plain text cannot change SGR state unless it completes a previous escape.
    -- Still parse previous so combined attributes, overrides, and resets canonicalize.
    const pending = string.sub(previous, -1) == "\u{1b}" or string.find(previous, "\u{1b}%[[%d;:]*$") ~= nil
    const input = if pending or string.find(text, "\u{1b}", 1, true) then `{previous}{text}` else previous
    const active: { [number]: string } = {}
    for _, token in Text.tokens(input) do
        const parameters = if token.Escape then string.match(token.Text, "^\u{1b}%[([%d;:]*)m$") else nil
        if parameters == nil then
            continue
        end
        const parts = string.split(if parameters == "" then "0" else parameters, ";")
        local index = 1
        while index <= #parts do
            const parameter = parts[index]
            const code = tonumber(string.match(parameter, "^%d+")) or 0
            local value = parameter
            if (code == 38 or code == 48 or code == 58) and not string.find(parameter, ":", 1, true) then
                const count = if parts[index + 1] == "2" then 4 elseif parts[index + 1] == "5" then 2 else 0
                value = table.concat(parts, ";", index, math.min(index + count, #parts))
                index += count
            end
            if code == 0 then
                table.clear(active)
            elseif SGR_RESETS[code] then
                active[SGR_RESETS[code]] = nil
                if code == 22 then
                    active[2] = nil
                end
            else
                const key = if (code >= 30 and code <= 38) or (code >= 90 and code <= 97)
                    then 30
                    elseif (code >= 40 and code <= 48) or (code >= 100 and code <= 107) then 40
                    elseif code == 6 then 5
                    elseif code == 21 then 4
                    elseif code == 52 then 51
                    else code
                active[key] = `{ESCAPE}{value}m`
            end
            index += 1
        end
    end
    const keys = {}
    for key in active do
        table.insert(keys, key)
    end
    table.sort(keys)
    const result = {}
    for _, key in keys do
        table.insert(result, active[key])
    end
    return table.concat(result)
end

-- Removes ANSI escape sequences, which is useful for measuring or comparing output.
function Style.strip(text: string): string
    assert(t.string(text))
    return Text.strip(text)
end

return Style

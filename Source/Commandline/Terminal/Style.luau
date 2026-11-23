--[[

Style

Turns semantic style specs into ANSI escape sequences. A theme maps each kind of terminal
text (paths, counts, headings, timestamps, and so on) to a spec, and any spec can be
overridden. Contains no I/O, so callers decide whether color is enabled.

--]]

const t = require("@packages/t")

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
    yellowBright = 93,
}
const PATH_SEPARATOR_DOT = "·"

export type Spec = {
    Bold: boolean?,
    Color: string?,
    Dim: boolean?,
    Italic: boolean?,
    Underline: boolean?,
}

export type Theme = {
    Address: Spec,
    Count: Spec,
    Error: Spec,
    Heading: Spec,
    Identifier: Spec,
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
    Warning: Spec,
}

export type ThemeOverrides = { [string]: Spec }

const DEFAULT_THEME: Theme = table.freeze({
    Address = table.freeze({ Color = "gray" }),
    Count = table.freeze({ Bold = true, Color = "yellowBright" }),
    Error = table.freeze({ Color = "red" }),
    Heading = table.freeze({ Bold = true, Color = "blueBright" }),
    Identifier = table.freeze({ Color = "gray" }),
    Path = table.freeze({ Color = "gray" }),
    RobloxPath = table.freeze({ Bold = true, Color = "cyanBright" }),
    StepBracket = table.freeze({}),
    StepCurrent = table.freeze({ Bold = true, Color = "yellowBright" }),
    StepTotal = table.freeze({}),
    Success = table.freeze({ Bold = true, Color = "greenBright" }),
    TimestampBracket = table.freeze({ Color = "#5a5a5a" }),
    TimestampFaint = table.freeze({ Color = "#5a5a5a" }),
    TimestampText = table.freeze({ Color = "#a8a8a8" }),
    Url = table.freeze({ Color = "gray" }),
    Warning = table.freeze({ Color = "yellow" }),
}) :: any

const specCheck = t.strictInterface({
    Bold = t.optional(t.boolean),
    Color = t.optional(t.string),
    Dim = t.optional(t.boolean),
    Italic = t.optional(t.boolean),
    Underline = t.optional(t.boolean),
})

const Style = {}

Style.DefaultTheme = DEFAULT_THEME

-- Returns the SGR parameter for a color name or "#rrggbb" hex value, or nil when the
-- color is unknown.
function Style.colorCode(color: string): string?
    assert(t.string(color))

    const named = (NAMED_COLORS :: { [string]: number })[color]
    if named then
        return tostring(named)
    end
    const red, green, blue = string.match(color, "^#(%x%x)(%x%x)(%x%x)$")
    if red and green and blue then
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
    for key, spec in overrides or {} do
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
        const code = Style.colorCode(spec.Color)
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
    return `{opening}{text}{closing}`
end

--[[
    Paints a path, showing each space as a center dot so the path reads as one token.
    The dot keeps the path's color but is never bold.
]]
function Style.paintPath(spec: Spec, text: string, color: boolean): string
    assert(t.table(spec))
    assert(t.string(text))
    assert(t.boolean(color))

    if not color or not spec.Bold then
        return Style.paint(spec, (string.gsub(text, " ", PATH_SEPARATOR_DOT)), color)
    end
    const unbold = if spec.Dim then `{ESCAPE}22;2m` else `{ESCAPE}22m`
    const separated = string.gsub(text, " ", `{unbold}{PATH_SEPARATOR_DOT}{ESCAPE}1m`)
    return Style.paint(spec, separated, color)
end

-- Removes ANSI escape sequences, which is useful for measuring or comparing output.
function Style.strip(text: string): string
    assert(t.string(text))
    return (string.gsub(text, "\u{1b}%[[%d;]*m", ""))
end

return Style

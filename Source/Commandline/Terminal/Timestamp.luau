--[[

Timestamp

Formats the timestamp that prefixes terminal lines. Supports a stopwatch measured from
when the terminal was created, UTC, local time, a fixed UTC offset, or no timestamp at
all. Contains no I/O, so callers sample the clocks and pass them in.

--]]

const t = require("@packages/t")

export type Mode = "Disabled" | "Local" | "Offset" | "Stopwatch" | "Utc"

export type Config = {
    Mode: Mode,
    OffsetMinutes: number?,
}

export type Sample = {
    ElapsedSeconds: number,
    LocalOffsetMinutes: number,
    UnixMillis: number,
}

const MILLIS_PER_DAY = 86400000
const MODES = {
    Disabled = true,
    Local = true,
    Offset = true,
    Stopwatch = true,
    Utc = true,
}
const NAMED_SPECS = {
    disabled = "Disabled",
    ["local"] = "Local",
    none = "Disabled",
    off = "Disabled",
    stopwatch = "Stopwatch",
    utc = "Utc",
}

const Timestamp = {}

Timestamp.Disabled = table.freeze({ Mode = "Disabled" }) :: Config

function Timestamp.validate(config: Config): (boolean, string?)
    if type(config) ~= "table" or not (MODES :: { [string]: boolean })[config.Mode] then
        return false, `Unknown timestamp mode "{if type(config) == "table" then config.Mode else config}".`
    end
    if config.Mode == "Offset" then
        const offset = config.OffsetMinutes
        if type(offset) ~= "number" or offset % 1 ~= 0 or math.abs(offset) > 18 * 60 then
            return false, "An offset timestamp needs whole OffsetMinutes between -1080 and 1080."
        end
    end
    return true, nil
end

--[[
    Parses a timestamp setting such as "stopwatch", "utc", "local", "disabled", or a fixed
    offset like "utc+9", "utc-05:30", or "+0530". Returns nil and a reason when the text
    is not a recognized setting.
]]
function Timestamp.parse(spec: string): (Config?, string?)
    assert(t.string(spec))

    const normalized = string.lower((string.gsub(spec, "%s", "")))
    const named = (NAMED_SPECS :: { [string]: Mode })[normalized]
    if named then
        return table.freeze({ Mode = named }) :: Config, nil
    end
    const offsetText = string.match(normalized, "^utc([+-].+)$") or string.match(normalized, "^([+-].+)$")
    if offsetText then
        local sign, hours, minutes = string.match(offsetText, "^([+-])(%d%d?):?(%d%d)$")
        if sign == nil then
            sign, hours = string.match(offsetText, "^([+-])(%d%d?)$")
            minutes = "0"
        end
        if sign and hours and minutes and (tonumber(minutes) :: number) < 60 then
            const total = (tonumber(hours) :: number) * 60 + (tonumber(minutes) :: number)
            const config: Config = { Mode = "Offset", OffsetMinutes = if sign == "-" then -total else total }
            if Timestamp.validate(config) then
                return table.freeze(config), nil
            end
        end
    end
    return nil,
        `Unknown timestamp setting "{spec}". Use "stopwatch", "utc", "local", "disabled", or an offset like "utc+9".`
end

const function pad(value: number, width: number): string
    return string.format(`%0{width}d`, value)
end

const function clock(millis: number): string
    const ofDay = millis % MILLIS_PER_DAY
    const hours = ofDay // 3600000
    const minutes = (ofDay // 60000) % 60
    const seconds = (ofDay // 1000) % 60
    return `{pad(hours, 2)}:{pad(minutes, 2)}:{pad(seconds, 2)}.{pad(ofDay % 1000, 3)}`
end

--[[
    Returns the timestamp split into a faint lead and the remaining text, or nil when
    timestamps are disabled. A stopwatch dims its leading zeros and colons, so the digits
    that have started counting stand out ("00:0" faint, then "1.234").
]]
function Timestamp.format(config: Config, sample: Sample): (string?, string?)
    assert(Timestamp.validate(config))
    assert(t.interface({
        ElapsedSeconds = t.number,
        LocalOffsetMinutes = t.number,
        UnixMillis = t.number,
    })(sample))

    if config.Mode == "Disabled" then
        return nil, nil
    end
    if config.Mode == "Stopwatch" then
        const elapsed = math.max(0, math.floor(sample.ElapsedSeconds * 1000))
        const hours = elapsed // 3600000
        const minutes = (elapsed // 60000) % 60
        const seconds = (elapsed // 1000) % 60
        const fraction = `{pad(seconds, 2)}.{pad(elapsed % 1000, 3)}`
        const text = if hours > 0 then `{hours}:{pad(minutes, 2)}:{fraction}` else `{pad(minutes, 2)}:{fraction}`
        const faint = string.match(text, "^[0:]*") or ""
        return faint, string.sub(text, #faint + 1)
    end
    const offset = if config.Mode == "Utc"
        then 0
        elseif config.Mode == "Local" then sample.LocalOffsetMinutes
        else config.OffsetMinutes :: number
    return "", clock(math.floor(sample.UnixMillis) + offset * 60000)
end

return Timestamp

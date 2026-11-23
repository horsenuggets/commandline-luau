--[[

Terminal

Writes styled, optionally timestamped lines for a CLI. Paints paths, counts, headings,
steps, and other kinds of text from a customizable theme, and prefixes every line,
including streamed child process output, with the configured timestamp. The
COMMANDLINE_TIMESTAMPS environment variable overrides the app's timestamp setting, and
NO_COLOR turns color off.

--]]

const DateTime = require("@lune/datetime")
const Path = require("@self/Path")
const Style = require("@self/Style")
const Timestamp = require("@self/Timestamp")
const process = require("@lune/process")
const stdio = require("@lune/stdio")
const t = require("@packages/t")

const TIMESTAMPS_VARIABLE = "COMMANDLINE_TIMESTAMPS"

export type Clock = {
    Elapsed: () -> number,
    LocalOffsetMinutes: () -> number,
    UnixMillis: () -> number,
}

export type Config = {
    Clock: Clock?,
    Color: boolean?,
    Env: { [string]: string? }?,
    Home: string?,
    Theme: Style.ThemeOverrides?,
    Timestamps: (Timestamp.Config | string)?,
    Write: ((string) -> ())?,
    WriteError: ((string) -> ())?,
}

export type PathOptions = {
    Directory: boolean?,
    Home: string?,
}

export type Stream = {
    Flush: () -> (),
    Write: (chunk: string) -> (),
}

export type Target = "Error" | "Output"

export type Terminal = {
    new: (config: Config?) -> Terminal,
    default: () -> Terminal,
    setDefault: (terminal: Terminal) -> (),
    Address: (self: Terminal, address: string) -> string,
    Color: boolean,
    Count: (self: Terminal, count: number | string) -> string,
    Error: (self: Terminal, text: string) -> string,
    Heading: (self: Terminal, text: string) -> string,
    Home: string?,
    Identifier: (self: Terminal, text: string) -> string,
    Paint: (self: Terminal, key: string, text: string) -> string,
    Path: (self: Terminal, path: string, options: PathOptions?) -> string,
    Prefix: (self: Terminal) -> string,
    Print: (self: Terminal, text: string?) -> (),
    PrintError: (self: Terminal, text: string?) -> (),
    RobloxPath: (self: Terminal, path: string) -> string,
    Step: (self: Terminal, index: number, total: number, text: string) -> string,
    Stream: (self: Terminal, target: Target?) -> Stream,
    Success: (self: Terminal, text: string) -> string,
    Theme: Style.Theme,
    Timestamps: Timestamp.Config,
    Url: (self: Terminal, url: string) -> string,
    Warning: (self: Terminal, text: string) -> string,
    _clock: Clock,
    _write: { [Target]: (string) -> () },
}

const configCheck = t.optional(t.strictInterface({
    Clock = t.optional(t.interface({
        Elapsed = t.callback,
        LocalOffsetMinutes = t.callback,
        UnixMillis = t.callback,
    })),
    Color = t.optional(t.boolean),
    Env = t.optional(t.table),
    Home = t.optional(t.string),
    Theme = t.optional(t.table),
    Timestamps = t.optional(t.union(t.string, t.table)),
    Write = t.optional(t.callback),
    WriteError = t.optional(t.callback),
}))

const Terminal = {}
Terminal.__index = Terminal

local defaultTerminal: Terminal? = nil

const function systemClock(): Clock
    const started = os.clock()
    return {
        Elapsed = function()
            return os.clock() - started
        end,
        LocalOffsetMinutes = function()
            -- Reading the UTC wall clock back as local time shifts it by the negated
            -- offset, which also follows daylight saving changes.
            const now = DateTime.now()
            return -(DateTime.fromLocalTime(now:toUniversalTime()).unixTimestamp - now.unixTimestamp) // 60
        end,
        UnixMillis = function()
            return DateTime.now().unixTimestampMillis
        end,
    }
end

const function resolveTimestamps(setting: (Timestamp.Config | string)?, env: { [string]: string? }): Timestamp.Config
    const override = env[TIMESTAMPS_VARIABLE]
    if override and override ~= "" then
        const parsed, problem = Timestamp.parse(override)
        if parsed == nil then
            error(`The "{TIMESTAMPS_VARIABLE}" environment variable is invalid. {problem}`, 0)
        end
        return parsed
    end
    if type(setting) == "string" then
        return assert(Timestamp.parse(setting))
    end
    if setting ~= nil then
        assert(Timestamp.validate(setting))
        return table.freeze(table.clone(setting))
    end
    return Timestamp.Disabled
end

--[[
    Creates a terminal. Every option has a default...

    > Clock - Time sources, which tests replace (system clocks)
    > Color - Whether to emit ANSI styles (on unless NO_COLOR is set)
    > Env - Environment variables to read (the process environment)
    > Home - The home folder that paths collapse to "~" (the OS home folder)
    > Theme - Style overrides keyed by theme entry (the default theme)
    > Timestamps - A timestamp config or setting such as "stopwatch" (disabled)
    > Write, WriteError - Output sinks (standard output and standard error)
]]
function Terminal.new(config: Config?): Terminal
    assert(configCheck(config))

    const options: Config = config or {}
    const env = options.Env or process.env
    const noColor = env.NO_COLOR
    const self = {
        Color = if options.Color ~= nil then options.Color else noColor == nil or noColor == "",
        Home = options.Home or Path.home(process.os, env),
        Theme = Style.theme(options.Theme),
        Timestamps = resolveTimestamps(options.Timestamps, env),
        _clock = options.Clock or systemClock(),
        _write = {
            Error = options.WriteError or stdio.ewrite,
            Output = options.Write or stdio.write,
        },
    }
    return setmetatable(self, Terminal) :: any
end

-- Returns the terminal shared by library code such as Toolkit, creating a default one
-- on first use. Apps call setDefault once at startup to apply their own settings.
function Terminal.default(): Terminal
    if defaultTerminal == nil then
        defaultTerminal = Terminal.new()
    end
    return defaultTerminal :: Terminal
end

function Terminal.setDefault(terminal: Terminal)
    assert(t.table(terminal) and getmetatable(terminal :: any) == Terminal, "Invalid terminal provided.")
    defaultTerminal = terminal
end

function Terminal.Paint(self: Terminal, key: string, text: string): string
    assert(t.string(key))
    assert(t.string(text))

    const spec = (self.Theme :: any)[key]
    assert(spec, `Unknown theme key "{key}".`)
    return Style.paint(spec, text, self.Color)
end

function Terminal.Address(self: Terminal, address: string): string
    return self:Paint("Address", address)
end

function Terminal.Count(self: Terminal, count: number | string): string
    assert(t.union(t.number, t.string)(count))
    return self:Paint("Count", tostring(count))
end

function Terminal.Error(self: Terminal, text: string): string
    return self:Paint("Error", text)
end

function Terminal.Heading(self: Terminal, text: string): string
    return self:Paint("Heading", text)
end

function Terminal.Identifier(self: Terminal, text: string): string
    return self:Paint("Identifier", text)
end

--[[
    Paints a filesystem path in its display form. Place and model files use the Roblox
    path style, and every other path uses the plain path style. Pass Directory to end the
    path with a slash, and Home to collapse a different folder than the terminal's own.
]]
function Terminal.Path(self: Terminal, path: string, options: PathOptions?): string
    assert(t.string(path))
    assert(t.optional(t.strictInterface({
        Directory = t.optional(t.boolean),
        Home = t.optional(t.string),
    }))(options))

    const directory = options ~= nil and options.Directory == true
    const home = if options ~= nil and options.Home ~= nil then options.Home else self.Home
    const display = Path.display(path, home, directory)
    const key = if not directory and Path.isRobloxFile(display) then "RobloxPath" else "Path"
    return Style.paintPath((self.Theme :: any)[key], display, self.Color)
end

-- Paints a Roblox path, such as a place file name or an instance path.
function Terminal.RobloxPath(self: Terminal, path: string): string
    assert(t.string(path))
    return Style.paintPath(self.Theme.RobloxPath, Path.display(path, self.Home), self.Color)
end

-- Formats a numbered step such as "[1/5] Text", highlighting the current step number.
function Terminal.Step(self: Terminal, index: number, total: number, text: string): string
    assert(t.integer(index))
    assert(t.integer(total))
    assert(t.string(text))

    const current = self:Paint("StepCurrent", tostring(index))
    const finalStep = self:Paint("StepTotal", tostring(total))
    return `{self:Paint("StepBracket", "[")}{current}{self:Paint("StepBracket", "/")}{finalStep}{self:Paint(
        "StepBracket",
        "]"
    )} {text}`
end

function Terminal.Success(self: Terminal, text: string): string
    return self:Paint("Success", text)
end

function Terminal.Url(self: Terminal, url: string): string
    return self:Paint("Url", url)
end

function Terminal.Warning(self: Terminal, text: string): string
    return self:Paint("Warning", text)
end

-- Returns the timestamp prefix for a line written now, including its trailing space, or
-- an empty string when timestamps are disabled.
function Terminal.Prefix(self: Terminal): string
    const faint, text = Timestamp.format(self.Timestamps, {
        ElapsedSeconds = self._clock.Elapsed(),
        LocalOffsetMinutes = if self.Timestamps.Mode == "Local" then self._clock.LocalOffsetMinutes() else 0,
        UnixMillis = self._clock.UnixMillis(),
    })
    if faint == nil or text == nil then
        return ""
    end
    const bracket = self.Theme.TimestampBracket
    return `{Style.paint(bracket, "[", self.Color)}{Style.paint(self.Theme.TimestampFaint, faint, self.Color)}{Style.paint(
        self.Theme.TimestampText,
        text,
        self.Color
    )}{Style.paint(bracket, "]", self.Color)} `
end

const function writeLines(self: Terminal, target: Target, text: string?)
    assert(t.optional(t.string)(text))

    const lines = {}
    for line in string.gmatch(`{text or ""}\n`, "([^\n]*)\n") do
        const trimmed = string.gsub(line, "\r$", "")
        -- Blank lines separate output, so they stay blank instead of showing a timestamp.
        table.insert(lines, if trimmed == "" then "\n" else `{self:Prefix()}{trimmed}\n`)
    end
    self._write[target](table.concat(lines))
end

-- Writes text to standard output, prefixing each line with the timestamp.
function Terminal.Print(self: Terminal, text: string?)
    writeLines(self, "Output", text)
end

-- Writes text to standard error, prefixing each line with the timestamp.
function Terminal.PrintError(self: Terminal, text: string?)
    writeLines(self, "Error", text)
end

--[[
    Returns a writer for streamed output, such as a child process's standard output.
    Chunks are split into lines, and each complete line is written with the timestamp
    from when it finished. Call Flush when the stream ends to write a final partial line.
]]
function Terminal.Stream(self: Terminal, target: Target?): Stream
    assert(t.optional(t.literal("Error", "Output"))(target))

    const destination: Target = target or "Output"
    local pending = ""
    return {
        Flush = function()
            if pending ~= "" then
                writeLines(self, destination, pending)
                pending = ""
            end
        end,
        Write = function(chunk: string)
            assert(t.string(chunk))
            pending ..= chunk
            const lastNewline = string.find(pending, "\n[^\n]*$")
            if lastNewline then
                writeLines(self, destination, string.sub(pending, 1, lastNewline - 1))
                pending = string.sub(pending, lastNewline + 1)
            end
        end,
    }
end

return Terminal

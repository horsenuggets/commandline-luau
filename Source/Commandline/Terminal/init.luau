--[[

Terminal

Writes styled, optionally timestamped lines for a CLI. Paints paths, counts, headings,
steps, and other kinds of text from a customizable theme, and prefixes every line,
including streamed child process output, with the configured timestamp. Lines written to
a terminal window wrap at word boundaries, aligned after the timestamp. The
COMMANDLINE_TIMESTAMPS environment variable overrides the app's timestamp setting, and
NO_COLOR turns color off.

--]]

const DateTime = require("@lune/datetime")
const Path = require("@self/Path")
const Style = require("@self/Style")
const Timestamp = require("@self/Timestamp")
const Wrap = require("@self/Wrap")
const process = require("@lune/process")
const stdio = require("@lune/stdio")
const t = require("@packages/t")

-- Each command prints the window width on standard error only when standard output is a
-- terminal, so piped and redirected output is never wrapped.
const UNIX_COLUMNS_SCRIPT = "test -t 1 && stty size </dev/tty >&2"
const WINDOWS_COLUMNS_SCRIPT =
    "if (-not [Console]::IsOutputRedirected) { [Console]::Error.Write([Console]::WindowWidth) }"

const TIMESTAMPS_VARIABLE = "COMMANDLINE_TIMESTAMPS"

export type Clock = {
    Elapsed: () -> number,
    LocalOffsetMinutes: (unixMillis: number) -> number,
    UnixMillis: () -> number,
}

export type Config = {
    Clock: Clock?,
    Color: boolean?,
    Columns: number?,
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

export type PrintOptions = {
    Wrap: boolean?,
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
    detectColumns: (os: string) -> number?,
    localOffsetMinutes: (unixMillis: number) -> number,
    Address: (self: Terminal, address: string) -> string,
    Color: boolean,
    Columns: (self: Terminal) -> number,
    Count: (self: Terminal, count: number | string) -> string,
    Error: (self: Terminal, text: string) -> string,
    Heading: (self: Terminal, text: string) -> string,
    Home: string?,
    Identifier: (self: Terminal, text: string) -> string,
    Paint: (self: Terminal, key: string, text: string) -> string,
    Path: (self: Terminal, path: string, options: PathOptions?) -> string,
    Prefix: (self: Terminal) -> string,
    Print: (self: Terminal, text: string?, options: PrintOptions?) -> (),
    PrintError: (self: Terminal, text: string?, options: PrintOptions?) -> (),
    RobloxPath: (self: Terminal, path: string) -> string,
    Step: (self: Terminal, index: number, total: number, text: string) -> string,
    Stream: (self: Terminal, target: Target?) -> Stream,
    Success: (self: Terminal, text: string) -> string,
    Theme: Style.Theme,
    Timestamps: Timestamp.Config,
    Url: (self: Terminal, url: string) -> string,
    Warning: (self: Terminal, text: string) -> string,
    _clock: Clock,
    _columns: number?,
    _write: { [Target]: (string) -> () },
}

const configCheck = t.optional(t.strictInterface({
    Clock = t.optional(t.interface({
        Elapsed = t.callback,
        LocalOffsetMinutes = t.callback,
        UnixMillis = t.callback,
    })),
    Color = t.optional(t.boolean),
    Columns = t.optional(t.numberMin(0)),
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

function Terminal.localOffsetMinutes(unixMillis: number): number
    assert(t.number(unixMillis))
    const instant = DateTime.fromUnixTimestamp(unixMillis / 1000)
    -- Actual local components are unambiguous when reinterpreted as UTC. Reading UTC
    -- components as local time instead can hit a DST gap or repeated hour.
    return (DateTime.fromUniversalTime(instant:toLocalTime()).unixTimestamp - instant.unixTimestamp) // 60
end

const function systemClock(): Clock
    const started = os.clock()
    return {
        Elapsed = function()
            return os.clock() - started
        end,
        LocalOffsetMinutes = Terminal.localOffsetMinutes,
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
    > Columns - Width to wrap lines at, or 0 to never wrap (the window width when writing
    >   to a terminal window, otherwise 0)
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
        -- Custom sinks are not a terminal window, so they only wrap when asked to.
        _columns = options.Columns or if options.Write or options.WriteError then 0 else nil,
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
    const unixMillis = self._clock.UnixMillis()
    const faint, text = Timestamp.format(self.Timestamps, {
        ElapsedSeconds = self._clock.Elapsed(),
        LocalOffsetMinutes = if self.Timestamps.Mode == "Local" then self._clock.LocalOffsetMinutes(unixMillis) else 0,
        UnixMillis = unixMillis,
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

--[[
    Returns the width of the terminal window that standard output is writing to, or nil
    when it is piped, redirected, or the width cannot be read. Runs a short command, so
    terminals call it once and keep the result.
]]
function Terminal.detectColumns(os: string): number?
    assert(t.string(os))

    const windows = os == "windows"
    const program = if windows then "powershell" else "sh"
    const arguments = if windows
        then { "-NoProfile", "-NonInteractive", "-Command", WINDOWS_COLUMNS_SCRIPT }
        else { "-c", UNIX_COLUMNS_SCRIPT }
    const spawned, result = pcall(process.exec, program, arguments, { stdio = { stdout = "forward" } })
    if not spawned or not result.ok then
        return nil
    end
    -- "stty size" prints rows before columns, and PowerShell prints only columns.
    const columns = tonumber(string.match(result.stderr, "(%d+)%s*$"))
    return if columns and columns > 0 then columns else nil
end

-- Returns the width lines wrap at, or 0 when they never wrap.
function Terminal.Columns(self: Terminal): number
    if self._columns == nil then
        self._columns = Terminal.detectColumns(process.os) or 0
    end
    return self._columns :: number
end

const function writeLines(
    self: Terminal,
    target: Target,
    text: string?,
    previousStyle: string?,
    options: PrintOptions?
): string
    assert(t.optional(t.string)(text))
    assert(t.optional(t.strictInterface({ Wrap = t.optional(t.boolean) }))(options))

    local activeStyle = previousStyle or ""
    const columns = if options and options.Wrap == false then 0 else self:Columns()
    const lines = {}
    for line in string.gmatch(`{text or ""}\n`, "([^\n]*)\n") do
        const trimmed = string.gsub(line, "\r$", "")
        -- Blank lines separate output, so they stay blank instead of showing a timestamp.
        if trimmed == "" then
            table.insert(lines, "\n")
            continue
        end
        const prefix = self:Prefix()
        const styledPrefix = if prefix ~= "" and self.Color then `\u{1b}[0m{prefix}{activeStyle}` else prefix
        const full = `{styledPrefix}{trimmed}`
        activeStyle = Style.sgrState(activeStyle, trimmed)
        const wrapped = if columns > 0 then Wrap.line(full, columns, string.rep(" ", Wrap.width(prefix))) else full
        table.insert(lines, `{wrapped}\n`)
    end
    self._write[target](table.concat(lines))
    return activeStyle
end

-- Writes timestamped text to standard output. Pass Wrap = false for preformatted text.
function Terminal.Print(self: Terminal, text: string?, options: PrintOptions?)
    writeLines(self, "Output", text, nil, options)
end

-- Writes timestamped text to standard error. Pass Wrap = false for preformatted text.
function Terminal.PrintError(self: Terminal, text: string?, options: PrintOptions?)
    writeLines(self, "Error", text, nil, options)
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
    local activeStyle = ""
    return {
        Flush = function()
            if pending ~= "" then
                activeStyle = writeLines(self, destination, pending, activeStyle)
                pending = ""
            end
        end,
        Write = function(chunk: string)
            assert(t.string(chunk))
            pending ..= chunk
            const lastNewline = string.find(pending, "\n[^\n]*$")
            if lastNewline then
                activeStyle = writeLines(self, destination, string.sub(pending, 1, lastNewline - 1), activeStyle)
                pending = string.sub(pending, lastNewline + 1)
            end
        end,
    }
end

return Terminal

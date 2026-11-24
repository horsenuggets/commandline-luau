--[[

Path

Normalizes filesystem paths for display so they read the same on macOS, Linux, and
Windows. Uses forward slashes, collapses the home folder to "~", and ends directories with
a slash. Display only, so paths passed to programs must stay unchanged.

--]]

const t = require("@packages/t")

const ROBLOX_EXTENSIONS = {
    rbxl = true,
    rbxlx = true,
    rbxm = true,
    rbxmx = true
}

const Path = {}

-- Returns the home folder the current OS uses, or nil when the environment has none.
function Path.home(os: string, env: { [string]: string? }): string?
    assert(t.string(os))
    assert(t.table(env))

    const candidates = if os == "windows"
        then {
            env.USERPROFILE,
            if env.HOMEDRIVE and env.HOMEPATH then `{env.HOMEDRIVE}{env.HOMEPATH}` else nil,
            env.HOME
        }
        else { env.HOME }
    for _, candidate in candidates do
        if candidate and candidate ~= "" then
            return candidate
        end
    end
    return nil
end

-- Converts backslashes to forward slashes and collapses repeated slashes, keeping the
-- leading pair of a UNC path such as "//server/share".
function Path.slashes(path: string): string
    assert(t.string(path))

    const forward = string.gsub(path, "\\", "/")
    const unc = string.sub(forward, 1, 2) == "//"
    const collapsed = string.gsub(forward, "/+", "/")
    return if unc then `/{collapsed}` else collapsed
end

--[[
    Returns the display form of a path. Pass the home folder to collapse it to "~", and
    mark directories so they end with a slash. Windows drive paths compare
    case-insensitively, since "C:\Users" and "c:/users" are the same folder there.
]]
function Path.display(path: string, home: string?, directory: boolean?): string
    assert(t.string(path))
    assert(t.optional(t.string)(home))
    assert(t.optional(t.boolean)(directory))

    local display = Path.slashes(path)
    if home and home ~= "" then
        const normalizedHome = string.gsub(Path.slashes(home), "/+$", "")
        const windows = string.match(display, "^%a:/") ~= nil
        const comparisonPath = if windows then string.lower(display) else display
        const comparisonHome = if windows then string.lower(normalizedHome) else normalizedHome
        if normalizedHome ~= "" then
            if comparisonPath == comparisonHome or comparisonPath == `{comparisonHome}/` then
                display = "~/"
            elseif string.sub(comparisonPath, 1, #comparisonHome + 1) == `{comparisonHome}/` then
                display = `~{string.sub(display, #normalizedHome + 1)}`
            end
        end
    end
    if directory and string.sub(display, -1) ~= "/" then
        display ..= "/"
    end
    if display == "~/" and not directory then
        return "~"
    end
    return display
end

-- Returns true for place and model files, which display in the Roblox path style.
function Path.isRobloxFile(path: string): boolean
    assert(t.string(path))

    const extension = string.match(path, "%.(%w+)$")
    return extension ~= nil and (ROBLOX_EXTENSIONS :: { [string]: boolean })[string.lower(extension)] == true
end

-- Returns the last component of a path, accepting either slash style.
function Path.fileName(path: string): string
    assert(t.string(path))

    const trimmed = string.gsub(Path.slashes(path), "/+$", "")
    return string.match(trimmed, "([^/]+)$") or trimmed
end

return Path

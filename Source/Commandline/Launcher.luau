--[[

Launcher

Generates the source code for a thin launcher executable. The launcher
reads a version pointer file and delegates execution to the versioned
binary. It also cleans up old versions on each run.

The generated source is a complete Lune script that gets compiled into
a standalone binary via Toolkit.buildLauncher().

--]]

local t = require("@packages/t")

local Launcher = {}

--[[
    Generates the Luau source code for a launcher executable.

    Options:
    > Name - CLI binary name (e.g., "rbxstudio")
    > InstallDir - Install directory name (e.g., ".rbxstudio-cli")
]]
function Launcher.generate(options: {
    Name: string,
    InstallDir: string,
}): string
    assert(t.interface({
        Name = t.string,
        InstallDir = t.string,
    })(options))

    local name = options.Name
    local installDir = options.InstallDir
    local lines = {}

    table.insert(lines, "local fs = require('@lune/fs')")
    table.insert(lines, "local process = require('@lune/process')")
    table.insert(lines, "local stdio = require('@lune/stdio')")
    table.insert(lines, "")
    table.insert(lines, "local IS_WINDOWS = process.os == 'windows'")
    table.insert(lines, "local HOME_DIR = if IS_WINDOWS then process.env.USERPROFILE else process.env.HOME")
    table.insert(lines, "local INSTALL_DIR = HOME_DIR .. '/" .. installDir .. "'")
    table.insert(lines, "local VERSIONS_DIR = INSTALL_DIR .. '/versions'")
    table.insert(lines, "local CURRENT_FILE = INSTALL_DIR .. '/current'")
    table.insert(lines, "local EXECUTABLE_SUFFIX = if IS_WINDOWS then '.exe' else ''")
    table.insert(lines, "local NAME = '" .. name .. "'")
    table.insert(lines, "")
    table.insert(lines, "local function normalizePath(path)")
    table.insert(lines, "    if IS_WINDOWS then")
    table.insert(lines, "        local normalized = path:gsub('/', '\\\\')")
    table.insert(lines, "        local prefix = ''")
    table.insert(lines, "        if normalized:sub(1, 2) == '\\\\\\\\' then")
    table.insert(lines, "            prefix = '\\\\\\\\'")
    table.insert(lines, "            normalized = normalized:sub(3)")
    table.insert(lines, "        end")
    table.insert(lines, "        return prefix .. normalized:gsub('\\\\\\\\+', '\\\\')")
    table.insert(lines, "    else")
    table.insert(lines, "        return path:gsub('//+', '/')")
    table.insert(lines, "    end")
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "local function exitWithError(message)")
    table.insert(lines, "    stdio.ewrite(NAME .. ': ' .. message .. '\\n')")
    table.insert(lines, "    process.exit(1)")
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "local function getCurrentVersion()")
    table.insert(lines, "    local currentFile = normalizePath(CURRENT_FILE)")
    table.insert(lines, "    if not fs.isFile(currentFile) then")
    table.insert(lines, "        return nil")
    table.insert(lines, "    end")
    table.insert(lines, "    local content = fs.readFile(currentFile)")
    table.insert(lines, "    return content:match('^%s*(.-)%s*$')")
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "local function cleanupOldVersions(currentVersion)")
    table.insert(lines, "    local versionsDir = normalizePath(VERSIONS_DIR)")
    table.insert(lines, "    if not fs.isDir(versionsDir) then")
    table.insert(lines, "        return")
    table.insert(lines, "    end")
    table.insert(lines, "    local prefix = NAME .. '-'")
    table.insert(lines, "    local currentExe = prefix .. currentVersion .. EXECUTABLE_SUFFIX")
    table.insert(lines, "    for _, entry in fs.readDir(versionsDir) do")
    table.insert(lines, "        if entry:sub(1, #prefix) == prefix and entry ~= currentExe then")
    table.insert(lines, "            pcall(function()")
    table.insert(lines, "                fs.removeFile(normalizePath(versionsDir .. '/' .. entry))")
    table.insert(lines, "            end)")
    table.insert(lines, "        end")
    table.insert(lines, "    end")
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "local function main()")
    table.insert(lines, "    local currentVersion = getCurrentVersion()")
    table.insert(lines, "    if not currentVersion or currentVersion == '' then")
    table.insert(lines, "        exitWithError('No version installed. Run \"' .. NAME .. ' install\" to set up.')")
    table.insert(lines, "    end")
    table.insert(lines, "")
    table.insert(lines, "    local executablePath = normalizePath(")
    table.insert(lines, "        VERSIONS_DIR .. '/' .. NAME .. '-' .. currentVersion .. EXECUTABLE_SUFFIX")
    table.insert(lines, "    )")
    table.insert(lines, "")
    table.insert(lines, "    if not fs.isFile(executablePath) then")
    table.insert(lines, "        exitWithError(")
    table.insert(
        lines,
        "            'Version ' .. currentVersion .. ' not found. Run \"' .. NAME .. ' update\" to reinstall.'"
    )
    table.insert(lines, "        )")
    table.insert(lines, "    end")
    table.insert(lines, "")
    table.insert(lines, "    cleanupOldVersions(currentVersion)")
    table.insert(lines, "")
    table.insert(lines, "    local result = process.exec(executablePath, process.args, {")
    table.insert(lines, "        stdio = 'forward',")
    table.insert(lines, "    })")
    table.insert(lines, "")
    table.insert(lines, "    process.exit(result.code)")
    table.insert(lines, "end")
    table.insert(lines, "")
    table.insert(lines, "main()")
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

return Launcher

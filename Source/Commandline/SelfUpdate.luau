--[[

SelfUpdate

Cross-platform binary self-replacement utilities. Handles the
platform-specific details of replacing a running executable:

> Unix (macOS/Linux) - The kernel keeps the old inode alive
>   via reference counting even after unlinking, so we can
>   simply delete and replace the file while the process runs.

> Windows - The OS locks the running binary. We rename the
>   running binary to .old, write the new binary in its place,
>   and clean up the .old file on the next invocation.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@packages/t")

local IS_WINDOWS = process.os == "windows"

local SelfUpdate = {}

--[[
    Replaces a binary file at the given path with new contents.
    Handles platform-specific locking behavior.

    On Unix, the running binary is unlinked and replaced directly.
    On Windows, the running binary is renamed to .old first, then
    the new binary is written to the original path.

    Options:
    > targetPath - Absolute path to the binary to replace
    > newContents - The raw binary data to write
]]
function SelfUpdate.replaceBinary(options: {
    targetPath: string,
    newContents: string,
})
    assert(t.interface({
        targetPath = t.string,
        newContents = t.string,
    })(options))

    local targetPath = options.targetPath
    local newContents = options.newContents

    if IS_WINDOWS then
        -- Windows locks running executables. Rename the old binary
        -- first (rename works even on locked files), then write the
        -- new one to the original path.
        local oldPath = targetPath .. ".old"
        if fs.isFile(oldPath) then
            fs.removeFile(oldPath)
        end
        if fs.isFile(targetPath) then
            -- Use OS rename since fs doesn't have a rename function
            process.exec("cmd", { "/c", "move", "/Y", targetPath, oldPath })
        end
        fs.writeFile(targetPath, newContents)
    else
        -- Unix: unlink and replace. The kernel keeps the old inode
        -- alive for the running process via reference counting.
        if fs.isFile(targetPath) then
            fs.removeFile(targetPath)
        end
        fs.writeFile(targetPath, newContents)
        process.exec("chmod", { "+x", targetPath })
    end
end

--[[
    Cleans up any leftover .old files from a previous Windows
    update. Should be called early in the CLI startup path.
    No-op on Unix systems.
]]
function SelfUpdate.cleanupOldBinary(binaryPath: string)
    assert(t.string(binaryPath))

    local oldPath = binaryPath .. ".old"
    if fs.isFile(oldPath) then
        pcall(function()
            fs.removeFile(oldPath)
        end)
    end
end

--[[
    Resolves the path to the currently running executable.
    Uses platform-specific tools (which/where) to find the
    binary on PATH.
]]
function SelfUpdate.findExecutable(name: string): string?
    assert(t.string(name))

    local command = if IS_WINDOWS then "where" else "which"
    local result = process.exec(command, { name })

    if result.ok then
        local path = result.stdout:match("^%s*(.-)%s*$")
        if path and fs.isFile(path) then
            return path
        end
    end

    return nil
end

--[[
    Returns the platform suffix for GitHub release asset names.
    Maps process.os and process.arch to the standard naming
    convention used by Lune cross-compilation targets.

    Examples: "macos-aarch64", "linux-x86_64", "windows-x86_64"
]]
function SelfUpdate.getPlatformSuffix(): string
    local os = process.os
    if os == "macos" or os == "darwin" then
        os = "macos"
    end

    local arch = process.arch
    if arch == "arm64" then
        arch = "aarch64"
    end

    return `{os}-{arch}`
end

return SelfUpdate

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

const fs = require("@lune/fs")
const process = require("@lune/process")
const t = require("@packages/t")

const IS_WINDOWS = process.os == "windows"

const SelfUpdate = {}

export type ReplacementStep = "MakeExecutable" | "MoveTargetToOld" | "RemoveOld" | "RemoveTarget" | "Write"

--[[
    Returns the ordered steps needed to replace a binary without ever writing into the
    file a running process may be executing. Pure, so the decision can be tested on any
    platform.

    Writing over an executable in place is never safe. On macOS, changing the pages of a
    running signed binary invalidates its code signature and the kernel kills the process
    with SIGKILL. Windows refuses the write entirely while the binary is running. Both
    platforms are fine once the old file is out of the way, so the new contents always
    land in a fresh file.

    Options:
    > IsWindows - Whether the replacement runs on Windows
    > OldExists - Whether a leftover .old file sits next to the target
    > TargetExists - Whether the target binary already exists
]]
function SelfUpdate.getReplacementSteps(options: {
    IsWindows: boolean,
    OldExists: boolean,
    TargetExists: boolean,
}): { ReplacementStep }
    assert(t.interface({
        IsWindows = t.boolean,
        OldExists = t.boolean,
        TargetExists = t.boolean,
    })(options))

    const steps: { ReplacementStep } = {}

    if options.IsWindows then
        -- Windows locks running executables, but renaming one still works. Move the old
        -- binary aside to .old so the original path is free for the new one.
        if options.OldExists then
            table.insert(steps, "RemoveOld")
        end
        if options.TargetExists then
            table.insert(steps, "MoveTargetToOld")
        end
        table.insert(steps, "Write")
    else
        -- Unlinking only drops the directory entry. The kernel keeps the old inode alive
        -- for any process still running it, and the write creates a brand new inode.
        if options.TargetExists then
            table.insert(steps, "RemoveTarget")
        end
        table.insert(steps, "Write")
        table.insert(steps, "MakeExecutable")
    end

    return steps
end

--[[
    Replaces a binary file at the given path with new contents. Handles platform-specific
    locking behavior, and never writes into the existing file (see getReplacementSteps).

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

    const targetPath = options.targetPath
    const newContents = options.newContents
    const oldPath = targetPath .. ".old"

    const steps = SelfUpdate.getReplacementSteps({
        IsWindows = IS_WINDOWS,
        OldExists = fs.isFile(oldPath),
        TargetExists = fs.isFile(targetPath),
    })

    for _, step in steps do
        if step == "RemoveOld" then
            fs.removeFile(oldPath)
        elseif step == "MoveTargetToOld" then
            -- A plain rename, which Windows allows even while the binary is running
            fs.move(targetPath, oldPath)
        elseif step == "RemoveTarget" then
            fs.removeFile(targetPath)
        elseif step == "Write" then
            fs.writeFile(targetPath, newContents)
        elseif step == "MakeExecutable" then
            const result = process.exec("chmod", { "+x", targetPath })
            if not result.ok then
                error(`Failed to make "{targetPath}" executable. {result.stderr}`)
            end
        end
    end
end

--[[
    Copies a binary to the given path through replaceBinary, so the destination is never
    written in place. The source is read in full before anything is replaced, which makes
    copying a binary onto itself (e.g., the installed binary running its own install
    command) safe.

    Options:
    > sourcePath - Path to the binary to copy
    > targetPath - Path to write the copy to
]]
function SelfUpdate.copyBinary(options: {
    sourcePath: string,
    targetPath: string,
})
    assert(t.interface({
        sourcePath = t.string,
        targetPath = t.string,
    })(options))

    const contents = fs.readFile(options.sourcePath)
    SelfUpdate.replaceBinary({
        targetPath = options.targetPath,
        newContents = contents,
    })
end

--[[
    Cleans up any leftover .old files from a previous Windows
    update. Should be called early in the CLI startup path.
    No-op on Unix systems.
]]
function SelfUpdate.cleanupOldBinary(binaryPath: string)
    assert(t.string(binaryPath))

    const oldPath = binaryPath .. ".old"
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

    const command = if IS_WINDOWS then "where" else "which"
    const result = process.exec(command, { name })

    if result.ok then
        const path = result.stdout:match("^%s*(.-)%s*$")
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

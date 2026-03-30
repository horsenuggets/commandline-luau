--[[

Toolkit

Build and install utilities for creating standalone CLI executables from Commandline
apps. Provides functions for building executables, generating version modules,
enabling shell completions, and patching requires for cross-platform compatibility.

--]]

local Chalk = require("@packages/Chalk")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@packages/t")

local Completions = require("@self/Completions")

local Toolkit = {}

-- Validation types

local buildOptionsCheck = t.interface({
    Name = t.string,
    EntryPoint = t.string,
    OutputDir = t.optional(t.string),
    Target = t.optional(t.string),
    AliasDirs = t.optional(t.array(t.interface({
        alias = t.string,
        dir = t.string,
    }))),
})

local generateVersionCheck = t.interface({
    VersionFile = t.optional(t.string),
    OutputPath = t.string,
})

------------------------------------------------------------------------------------------
-- Cross-platform require patching
------------------------------------------------------------------------------------------

-- Compiled Lune executables on Windows resolve relative paths ("./", "../",
-- "@self/") against the drive root instead of the virtual filesystem, breaking
-- requires at runtime. This patches all relative requires to use alias paths
-- which go through Lune's alias resolution and work correctly on all platforms.

type FileBackup = { path: string, content: string }

local function getParentDir(path: string): string
    return path:match("^(.*)/[^/]+$") or ""
end

local function resolveAlias(projectRelPath: string, aliasDirs: { { alias: string, dir: string } }): (string?, string?)
    for _, entry in aliasDirs do
        local prefix = entry.dir .. "/"
        if string.sub(projectRelPath, 1, #prefix) == prefix then
            local rest = string.sub(projectRelPath, #prefix + 1)
            return entry.alias, rest
        end
    end
    return nil
end

local function patchRelativeRequires(projectRoot: string, aliasDirs: { { alias: string, dir: string } }): { FileBackup }
    local backups: { FileBackup } = {}
    local patched = 0

    local function processFile(filePath: string, projectRelPath: string)
        local content = fs.readFile(filePath)
        local originalContent = content
        local modified = false
        local fileDir = getParentDir(projectRelPath)

        -- Replace @self requires (used in init.luau files, @self = containing
        -- directory)
        if string.find(content, "@self/", 1, true) then
            local selfDir = fileDir
            content = string.gsub(content, 'require%("@self/([^"]+)"', function(target)
                local fullPath = if selfDir == "" then target else selfDir .. "/" .. target
                local alias, rest = resolveAlias(fullPath, aliasDirs)
                if alias then
                    modified = true
                    return 'require("' .. alias .. "/" .. rest .. '"'
                end
                return nil
            end)
        end

        -- Replace "./" relative requires
        if string.find(content, 'require("./', 1, true) then
            content = string.gsub(content, 'require%("(%./[^"]+)"', function(relTarget)
                local target = string.sub(relTarget, 3)
                local fullPath = if fileDir == "" then target else fileDir .. "/" .. target
                local alias, rest = resolveAlias(fullPath, aliasDirs)
                if alias then
                    modified = true
                    return 'require("' .. alias .. "/" .. rest .. '"'
                end
                return nil
            end)
        end

        -- Replace "../" relative requires
        if string.find(content, 'require("../', 1, true) then
            content = string.gsub(content, 'require%("(%.%./[^"]+)"', function(relTarget)
                local target = string.sub(relTarget, 4)
                local parentDir = getParentDir(fileDir)
                local fullPath = if parentDir == "" then target else parentDir .. "/" .. target
                local alias, rest = resolveAlias(fullPath, aliasDirs)
                if alias then
                    modified = true
                    return 'require("' .. alias .. "/" .. rest .. '"'
                end
                return nil
            end)
        end

        if modified then
            table.insert(backups, { path = filePath, content = originalContent })
            fs.writeFile(filePath, content)
            patched += 1
        end
    end

    local function processDir(dirPath: string, projectRelPrefix: string)
        for _, entry in fs.readDir(dirPath) do
            local fullPath = dirPath .. "/" .. entry
            local relPath = if projectRelPrefix == "" then entry else projectRelPrefix .. "/" .. entry

            if fs.isDir(fullPath) then
                processDir(fullPath, relPath)
            elseif string.match(entry, "%.luau$") then
                processFile(fullPath, relPath)
            end
        end
    end

    -- Delete sub-package .luaurc files so @packages falls through to the
    -- project root definition
    local function deleteSubLuaurcs(dirPath: string)
        for _, entry in fs.readDir(dirPath) do
            local fullPath = dirPath .. "/" .. entry
            if fs.isDir(fullPath) then
                deleteSubLuaurcs(fullPath)
            elseif entry == ".luaurc" then
                table.insert(backups, { path = fullPath, content = fs.readFile(fullPath) })
                fs.removeFile(fullPath)
            end
        end
    end

    local packagesIndexDir = projectRoot .. "/Packages/_Index"
    if fs.isDir(packagesIndexDir) then
        deleteSubLuaurcs(packagesIndexDir)
    end

    for _, entry in aliasDirs do
        local dirPath = projectRoot .. "/" .. entry.dir
        if fs.isDir(dirPath) then
            processDir(dirPath, entry.dir)
        end
    end

    if patched > 0 then
        local label = if patched == 1 then "file" else "files"
        print("Patched " .. patched .. " " .. label .. " for cross-platform compatibility.")
    end

    return backups
end

local function restoreFiles(backups: { FileBackup })
    for _, backup in backups do
        fs.writeFile(backup.path, backup.content)
    end
end

------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------

--[[
    Generates a __VERSION__.luau module from a VERSION file.

    Options:
    > VersionFile - Path to the VERSION file (default "VERSION")
    > OutputPath - Path where the version module will be written
]]
function Toolkit.generateVersion(options: {
    VersionFile: string?,
    OutputPath: string,
})
    assert(generateVersionCheck(options))

    local versionFile = options.VersionFile or "VERSION"

    if not fs.isFile(versionFile) then
        print(Chalk.red('VERSION file not found at "' .. versionFile .. '".'))
        process.exit(1)
    end

    local version = string.gsub(fs.readFile(versionFile), "%s+", "")
    local versionModule = 'return "' .. version .. '"\n'

    -- Create parent directories if needed
    local parentDir = string.match(options.OutputPath, "(.+)/[^/]+$")
    if parentDir and not fs.isDir(parentDir) then
        fs.writeDir(parentDir)
    end

    fs.writeFile(options.OutputPath, versionModule)

    print("Generated version module with version " .. Chalk.bold(Chalk.blueBright(version)) .. ".")
end

--[[
    Builds a standalone executable from a Lune entry point.

    Options:
    > Name - Output binary name (e.g., "luauproject")
    > EntryPoint - Path to the entry point directory or file
    > OutputDir - Directory to write the binary (default "Build")
    > Target - Cross-compile target (e.g., "linux-x86_64"). Nil for current
    >   platform.
    > AliasDirs - Array of { alias, dir } for cross-platform require patching.
    >   If provided, relative requires (@self, ./, ../) are rewritten to alias
    >   paths before building and restored after.
]]
function Toolkit.build(options: {
    Name: string,
    EntryPoint: string,
    OutputDir: string?,
    Target: string?,
    AliasDirs: { { alias: string, dir: string } }?,
})
    assert(buildOptionsCheck(options))

    local outputDir = options.OutputDir or "Build"
    local target = options.Target

    print()
    print("Building " .. Chalk.bold(Chalk.blueBright(options.Name)) .. " executable...")

    -- Resolve entry point
    local entryPoint = options.EntryPoint
    if not fs.isDir(entryPoint) and not fs.isFile(entryPoint) then
        print(Chalk.red('Entry point "' .. entryPoint .. '" not found.'))
        process.exit(1)
    end

    -- Patch relative requires for cross-platform compatibility
    local backups: { FileBackup } = {}
    if options.AliasDirs then
        backups = patchRelativeRequires(".", options.AliasDirs)
    end

    -- Ensure output directory exists
    if not fs.isDir(outputDir) then
        fs.writeDir(outputDir)
    end

    -- Remove existing binary to avoid corruption issues
    local outputPath = outputDir .. "/" .. options.Name
    if fs.isFile(outputPath) then
        fs.removeFile(outputPath)
    end
    if fs.isFile(outputPath .. ".exe") then
        fs.removeFile(outputPath .. ".exe")
    end

    -- Strip shebang for building (lune build does not support shebangs). Temp
    -- file goes in same directory so relative requires resolve correctly.
    local buildTarget = entryPoint
    local tempFile: string? = nil

    if fs.isFile(entryPoint) then
        local entryContent = fs.readFile(entryPoint)
        if string.sub(entryContent, 1, 2) == "#!" then
            local entryDir = string.match(entryPoint, "(.*/)") or ""
            tempFile = entryDir .. "_build_entry.luau"
            local stripped = string.gsub(entryContent, "^#![^\n]*\n", "")
            fs.writeFile(tempFile, stripped)
            buildTarget = tempFile
        end
    end

    local args = { "build", buildTarget, "--output", outputPath }
    if target then
        table.insert(args, "--target")
        table.insert(args, target)
        print("Target is " .. Chalk.dim(target) .. ".")
    else
        print("Target is " .. Chalk.dim(process.os .. "-" .. process.arch) .. ".")
    end
    print("Entry point is " .. Chalk.dim(entryPoint) .. ".")

    local result = process.exec("lune", args)

    -- Clean up temp file and restore patched files
    if tempFile and fs.isFile(tempFile) then
        fs.removeFile(tempFile)
    end
    restoreFiles(backups)

    if result.ok then
        local outputFile = outputPath
        if (target and string.find(target, "windows")) or (not target and process.os == "windows") then
            outputFile = outputPath .. ".exe"
        end

        if fs.isFile(outputFile) then
            print("Output file is " .. Chalk.dim(outputFile) .. ".")
        end

        print()
        print(Chalk.bold(Chalk.greenBright("Build completed successfully!")))
    else
        print(Chalk.redBright("Build failed."))
        print(result.stderr)
        process.exit(1)
    end
end

--[[
    Creates a "completions" subcommand that generates shell completion scripts
    for bash, zsh, and fish.

    Returns a Command that should be included in the root command's Subcommands
    array. The rootCommand reference is captured by the closure and used at
    execution time to walk the full command tree.

    Usage:
        local rootCommand
        rootCommand = Command.new({
            Name = "mytool",
            Subcommands = {
                buildCommand,
                runCommand,
                Toolkit.completionsCommand(function()
                    return rootCommand
                end),
            },
        })
]]
function Toolkit.completionsCommand(getRootCommand: () -> any): any
    assert(t.callback(getRootCommand))

    local Command = require("@self/Command")
    local Arg = require("@self/Arg")

    return Command.new({
        Name = "completions",
        Description = "Generate shell completion script.",
        Args = {
            Arg.new({
                Name = "shell",
                Description = "Shell type (bash, zsh, or fish).",
            }),
        },
        Impl = function(args)
            print(Completions.generate(getRootCommand(), args.shell))
        end,
    })
end

--[[
    Installs shell completion scripts to ~/.commandline-luau/completions/
    and configures the user's shell to load them.

    Currently supports zsh. Adds fpath and compinit to ~/.zshrc if not
    already present, with a comment block explaining the addition.

    Options:
    > Command - The root command to generate completions from
    > Shell - Shell type (default "zsh")
]]
function Toolkit.installCompletions(options: {
    Command: any,
    Shell: string?,
})
    assert(t.table(options))
    assert(t.table(options.Command))

    local shell = options.Shell or "zsh"
    local homeDir = process.env.HOME or process.env.USERPROFILE or ""
    local completionsDir = homeDir .. "/.commandline-luau/completions"
    local commandName = options.Command.Name

    -- Generate the completion script
    local script = Completions.generate(options.Command, shell)

    -- Write the completion file
    if not fs.isDir(completionsDir) then
        fs.writeDir(completionsDir)
    end

    -- Use shell-appropriate file naming and config path
    local completionFile
    if shell == "powershell" or shell == "pwsh" then
        completionFile = completionsDir .. "/" .. commandName .. ".ps1"
    else
        completionFile = completionsDir .. "/_" .. commandName
    end

    fs.writeFile(completionFile, script)
    print("Installed " .. shell .. " completions to " .. Chalk.dim(completionFile) .. ".")

    -- Configure the shell to load completions
    local marker = "# Added by commandline-luau"

    if shell == "zsh" then
        local configPath = homeDir .. "/.zshrc"
        local fPathLine = "fpath=(~/.commandline-luau/completions $fpath)"
        local compInitLine = "autoload -Uz compinit && compinit"

        local content = ""
        if fs.isFile(configPath) then
            content = fs.readFile(configPath)
        end

        if string.find(content, marker, 1, true) then
            print(Chalk.dim("Shell config already configured."))
            return
        end

        if content ~= "" and not string.match(content, "\n$") then
            content = content .. "\n"
        end
        if content ~= "" then
            content = content .. "\n"
        end

        content = content .. marker .. "\n" .. fPathLine .. "\n" .. compInitLine .. "\n"

        fs.writeFile(configPath, content)
        print("Added completions to " .. Chalk.dim(configPath) .. ".")
        print(Chalk.yellow("Restart your terminal to enable completions."))
    elseif shell == "powershell" or shell == "pwsh" then
        -- Find or create the PowerShell profile
        local profileDir = homeDir .. "/.config/powershell"
        local profilePath = profileDir .. "/Microsoft.PowerShell_profile.ps1"

        if not fs.isDir(profileDir) then
            fs.writeDir(profileDir)
        end

        local content = ""
        if fs.isFile(profilePath) then
            content = fs.readFile(profilePath)
        end

        if string.find(content, marker, 1, true) then
            print(Chalk.dim("Shell config already configured."))
            return
        end

        if content ~= "" and not string.match(content, "\n$") then
            content = content .. "\n"
        end
        if content ~= "" then
            content = content .. "\n"
        end

        local sourceLine = ". " .. completionFile

        content = content .. marker .. "\n" .. sourceLine .. "\n"

        fs.writeFile(profilePath, content)
        print("Added completions to " .. Chalk.dim(profilePath) .. ".")
        print(Chalk.yellow("Restart PowerShell to enable completions."))
    end
end

-- Exposed for testing
Toolkit._patchRelativeRequires = patchRelativeRequires
Toolkit._restoreFiles = restoreFiles

return Toolkit

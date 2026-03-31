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
    local versionModule = '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "'
        .. version
        .. '"\n'

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
            local tempPath = entryDir .. "_build_entry.luau"
            tempFile = tempPath
            local stripped = string.gsub(entryContent, "^#![^\n]*\n", "")
            fs.writeFile(tempPath, stripped)
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

------------------------------------------------------------------------------------------
-- Install and Update (Direct Binary Replacement)
------------------------------------------------------------------------------------------

local SelfUpdate = require("@self/SelfUpdate")

local installOptionsCheck = t.interface({
    Name = t.string,
    InstallDir = t.string,
    Version = t.string,
    Repository = t.string,
})

--[[
    Returns a Command for an "install" subcommand that downloads the
    CLI binary to a dedicated directory and adds it to PATH.

    Directory structure:
    > ~/{installDir}/bin/{name}  (the binary)

    The install command downloads the platform-appropriate binary from
    the latest GitHub release and configures the user's shell to
    include the bin directory on PATH.

    Options:
    > Name - CLI binary name (e.g., "rbxstudio")
    > InstallDir - Install directory name (e.g., ".rbxstudio-cli")
    > Version - Current version string
    > Repository - GitHub repo (e.g., "horsenuggets/rbxstudio-cli")
]]
function Toolkit.installCommand(options: {
    Name: string,
    InstallDir: string,
    Version: string,
    Repository: string,
}): any
    assert(installOptionsCheck(options))

    local Command = require("@self/Command")
    local net = require("@lune/net")
    local serde = require("@lune/serde")

    local name = options.Name
    local installDir = options.InstallDir
    local version = options.Version
    local repository = options.Repository

    local IS_WINDOWS = process.os == "windows"
    local HOME_DIR = if IS_WINDOWS then process.env.USERPROFILE or "" else process.env.HOME or ""
    local INSTALL_PATH = HOME_DIR .. "/" .. installDir
    local BIN_DIR = INSTALL_PATH .. "/bin"
    local EXECUTABLE_SUFFIX = if IS_WINDOWS then ".exe" else ""
    local PATH_EXPORT_COMMENT = "# Added by " .. name
    local PATH_EXPORT_LINE = `export PATH="{BIN_DIR}:$PATH"`
    local SHELL_CONFIGS = {
        { file = ".bash_profile", shell = "bash" },
        { file = ".bashrc", shell = "bash" },
        { file = ".zshrc", shell = "zsh" },
    }
    local XSH_PATH_FILE = HOME_DIR .. "/.path"

    local function downloadLatestBinary(destPath: string): boolean
        local url = `https://api.github.com/repos/{repository}/releases/latest`
        local ok, response = pcall(net.request, {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = name },
        })

        if not ok or not response.ok then
            print(Chalk.red("Failed to fetch latest release."))
            return false
        end

        local success, release = pcall(serde.decode, "json" :: "json", response.body)
        if not success then
            print(Chalk.red("Failed to parse release data."))
            return false
        end

        local platformSuffix = SelfUpdate.getPlatformSuffix()
        local assetName = `{name}-{platformSuffix}{EXECUTABLE_SUFFIX}`
        local downloadUrl: string? = nil

        for _, asset in release.assets or {} do
            if asset.name == assetName then
                downloadUrl = asset.browser_download_url
                break
            end
        end

        if not downloadUrl then
            print(Chalk.red(`Asset "{assetName}" not found in latest release.`))
            return false
        end

        local dlOk, dlResponse = pcall(net.request, {
            url = downloadUrl,
            method = "GET",
            headers = { ["User-Agent"] = name },
        })

        if not dlOk or not dlResponse.ok then
            print(Chalk.red("Failed to download binary."))
            return false
        end

        fs.writeFile(destPath, dlResponse.body)
        if not IS_WINDOWS then
            process.exec("chmod", { "+x", destPath })
        end

        return true
    end

    local function addToPath()
        if IS_WINDOWS then
            local psCmd = "$p = [Environment]::GetEnvironmentVariable('PATH','User');"
                .. " if ($p -notlike '*"
                .. BIN_DIR
                .. "*') { [Environment]::SetEnvironmentVariable('PATH', '"
                .. BIN_DIR
                .. ";' + $p, 'User') }"
            local result = process.exec("powershell", { "-Command", psCmd })
            if result.ok then
                print(`Added {Chalk.dim(BIN_DIR)} to user PATH.`)
            end
            return
        end

        -- Check for xsh-compatible .path file
        if fs.isFile(XSH_PATH_FILE) then
            local content = fs.readFile(XSH_PATH_FILE)
            if not string.find(content, BIN_DIR, 1, true) then
                if content ~= "" and not string.match(content, "\n$") then
                    content ..= "\n"
                end
                content ..= BIN_DIR .. "\n"
                fs.writeFile(XSH_PATH_FILE, content)
                print(`Added {Chalk.dim(BIN_DIR)} to {Chalk.dim("~/.path")}.`)
            end
            return
        end

        -- Fall back to shell config files
        for _, config in SHELL_CONFIGS do
            local configPath = `{HOME_DIR}/{config.file}`
            if fs.isFile(configPath) then
                local content = fs.readFile(configPath)
                if not string.find(content, PATH_EXPORT_COMMENT, 1, true) then
                    if content ~= "" and not string.match(content, "\n$") then
                        content ..= "\n"
                    end
                    content ..= "\n" .. PATH_EXPORT_COMMENT .. "\n" .. PATH_EXPORT_LINE .. "\n"
                    fs.writeFile(configPath, content)
                    print(`Added {Chalk.dim(name)} to {Chalk.dim("~/" .. config.file)}.`)
                end
            end
        end
    end

    return Command.new({
        Name = "install",
        Description = `Install {name} CLI to ~/{installDir} and add to PATH.`,
        Impl = function()
            print(`Installing {Chalk.bold(Chalk.blueBright(name))} {Chalk.dim(version)}...`)
            print()

            -- Create directory structure
            if not fs.isDir(INSTALL_PATH) then
                fs.writeDir(INSTALL_PATH)
            end
            if not fs.isDir(BIN_DIR) then
                fs.writeDir(BIN_DIR)
            end

            local binaryPath = `{BIN_DIR}/{name}{EXECUTABLE_SUFFIX}`

            -- Try to copy current running binary first
            local currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                local contents = fs.readFile(currentExe)
                fs.writeFile(binaryPath, contents)
                if not IS_WINDOWS then
                    process.exec("chmod", { "+x", binaryPath })
                end
                print(`Copied executable to {Chalk.dim(binaryPath)}.`)
            else
                -- Download from GitHub releases
                print("Downloading binary...")
                if not downloadLatestBinary(binaryPath) then
                    print(Chalk.red("Failed to install. Could not download binary."))
                    process.exit(1)
                end
                print("Downloaded successfully.")
            end

            -- Add to PATH
            addToPath()

            print()
            print(Chalk.bold(Chalk.greenBright("Installation complete!")))
            print(Chalk.yellow("Restart your terminal for PATH changes to take effect."))
        end,
    })
end

--[[
    Returns a Command for an "update" subcommand that downloads the
    latest (or a specified) version from GitHub releases and replaces
    the current binary in-place.

    Uses SelfUpdate.replaceBinary() for atomic cross-platform binary
    replacement:
    > Unix - Unlink and replace (kernel keeps old inode alive)
    > Windows - Rename to .old, write new, clean up .old on next run

    Options:
    > Name - CLI binary name (e.g., "rbxstudio")
    > InstallDir - Install directory name (e.g., ".rbxstudio-cli")
    > Version - Current version string
    > Repository - GitHub repo (e.g., "horsenuggets/rbxstudio-cli")
]]
function Toolkit.updateCommand(options: {
    Name: string,
    InstallDir: string,
    Version: string,
    Repository: string,
}): any
    assert(installOptionsCheck(options))

    local Command = require("@self/Command")
    local Flag = require("@self/Flag")
    local net = require("@lune/net")
    local serde = require("@lune/serde")

    local name = options.Name
    local currentVersion = options.Version
    local repository = options.Repository

    local IS_WINDOWS = process.os == "windows"
    local EXECUTABLE_SUFFIX = if IS_WINDOWS then ".exe" else ""

    local function getRelease(targetVersion: string?): { version: string, assets: { any } }?
        local url: string
        if targetVersion then
            url = `https://api.github.com/repos/{repository}/releases/tags/{targetVersion}`
        else
            url = `https://api.github.com/repos/{repository}/releases/latest`
        end

        local ok, response = pcall(net.request, {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = name },
        })
        if not ok or not response.ok then
            return nil
        end

        local success, data = pcall(serde.decode, "json" :: "json", response.body)
        if not success then
            return nil
        end

        return {
            version = data.tag_name,
            assets = data.assets or {},
        }
    end

    return Command.new({
        Name = "update",
        Description = `Update {name} CLI to the latest version.`,
        Flags = {
            Flag.new({
                Name = "version",
                Shorthand = "v",
                Description = "Install a specific version instead of the latest.",
                Type = "string",
            }),
        },
        Impl = function(args)
            local targetVersion = args.version

            -- Clean up leftover .old file from previous Windows update
            local currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                SelfUpdate.cleanupOldBinary(currentExe)
            end

            print(`Checking for updates to {Chalk.bold(Chalk.blueBright(name))}...`)

            local release = getRelease(targetVersion)
            if not release then
                print(
                    Chalk.red(
                        if targetVersion
                            then `Version "{targetVersion}" not found.`
                            else "Failed to fetch latest release."
                    )
                )
                process.exit(1)
            end

            local newVersion = release.version
            if newVersion == currentVersion and not targetVersion then
                print(`Already on the latest version ({Chalk.bold(Chalk.blueBright(currentVersion))}).`)
                return
            end

            print(`Updating from {Chalk.dim(currentVersion)} to {Chalk.bold(Chalk.blueBright(newVersion))}...`)

            -- Find download URL for current platform
            local platformSuffix = SelfUpdate.getPlatformSuffix()
            local assetName = `{name}-{platformSuffix}{EXECUTABLE_SUFFIX}`
            local downloadUrl: string? = nil

            for _, asset in release.assets do
                if asset.name == assetName then
                    downloadUrl = asset.browser_download_url
                    break
                end
            end

            if not downloadUrl then
                print(Chalk.red(`Binary for {platformSuffix} not found in release {newVersion}.`))
                process.exit(1)
            end

            -- Download new binary
            local dlOk, dlResponse = pcall(net.request, {
                url = downloadUrl,
                method = "GET",
                headers = { ["User-Agent"] = name },
            })

            if not dlOk or not dlResponse.ok then
                print(Chalk.red("Failed to download update."))
                process.exit(1)
            end

            -- Replace the current binary in-place
            if currentExe then
                SelfUpdate.replaceBinary({
                    targetPath = currentExe,
                    newContents = dlResponse.body,
                })
            else
                print(Chalk.red(`Could not find {name} on PATH. Run "{name} install" first.`))
                process.exit(1)
            end

            print()
            print(Chalk.bold(Chalk.greenBright(`Updated to {newVersion}!`)))
        end,
    })
end

-- Exposed for testing
Toolkit._patchRelativeRequires = patchRelativeRequires
Toolkit._restoreFiles = restoreFiles
Toolkit._SelfUpdate = SelfUpdate

return Toolkit

--[[

Toolkit

Build and install utilities for creating standalone CLI executables from Commandline
apps. Provides functions for building executables, generating version modules, and
enabling shell completions.

--]]

const fs = require("@lune/fs")
const process = require("@lune/process")
const t = require("@packages/t")

const Completions = require("@self/Completions")
const SelfUpdate = require("@self/SelfUpdate")
const Terminal = require("@self/Terminal")

const Toolkit = {}

-- Validation types

const buildOptionsCheck = t.interface({
    DisplayName = t.optional(t.string),
    Name = t.string,
    EntryPoint = t.string,
    OutputDir = t.optional(t.string),
    Target = t.optional(t.string),
    Terminal = t.optional(t.table)
})

const generateVersionCheck = t.interface({
    VersionFile = t.optional(t.string),
    OutputPath = t.string
})

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
    OutputPath: string
})
    assert(generateVersionCheck(options))

    const versionFile = options.VersionFile or "VERSION"
    const terminal = Terminal.default()

    if not fs.isFile(versionFile) then
        terminal:PrintError(terminal:Error(`VERSION file not found at "{versionFile}".`))
        process.exit(1)
    end

    const version = string.gsub(fs.readFile(versionFile), "%s+", "")
    const versionModule = '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "'
        .. version
        .. '"\n'

    -- Create parent directories if needed
    const parentDir = string.match(options.OutputPath, "(.+)/[^/]+$")
    if parentDir and not fs.isDir(parentDir) then
        fs.writeDir(parentDir)
    end

    fs.writeFile(options.OutputPath, versionModule)

    terminal:Print(`Generated version module with version {terminal:Heading(version)}.`)
end

--[[
    Builds a standalone executable from a Lune entry point.

    Options:
    > DisplayName - Name shown in the build heading (default Name)
    > Name - Output binary name (e.g., "luauproject")
    > EntryPoint - Path to the entry point directory or file
    > OutputDir - Directory to write the binary (default "Build")
    > Target - Cross-compile target (e.g., "linux-x86_64"). Nil for current
    >   platform.
    > Terminal - Terminal to print progress through (default Terminal.default())
]]
function Toolkit.build(options: {
    DisplayName: string?,
    Name: string,
    EntryPoint: string,
    OutputDir: string?,
    Target: string?,
    Terminal: Terminal.Terminal?
})
    assert(buildOptionsCheck(options))

    const outputDir = options.OutputDir or "Build"
    const target = options.Target
    const terminal = options.Terminal or Terminal.default()

    terminal:Print(terminal:Heading(`Building {options.DisplayName or options.Name}...`))

    -- Resolve entry point
    const entryPoint = options.EntryPoint
    const entryIsDir = fs.isDir(entryPoint)
    if not entryIsDir and not fs.isFile(entryPoint) then
        terminal:Print(terminal:Error(`Entry point {terminal:Path(entryPoint)} not found.`))
        process.exit(1)
    end

    -- Ensure output directory exists
    if not fs.isDir(outputDir) then
        fs.writeDir(outputDir)
    end

    -- Remove existing binary to avoid corruption issues
    const outputPath = outputDir .. "/" .. options.Name
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
        const entryContent = fs.readFile(entryPoint)
        if string.sub(entryContent, 1, 2) == "#!" then
            const entryDir = string.match(entryPoint, "(.*/)") or ""
            const tempPath = entryDir .. "_build_entry.luau"
            tempFile = tempPath
            const stripped = string.gsub(entryContent, "^#![^\n]*\n", "")
            fs.writeFile(tempPath, stripped)
            buildTarget = tempFile
        end
    end

    const args = { "build", buildTarget, "--output", outputPath }
    if target then
        table.insert(args, "--target")
        table.insert(args, target)
    end
    terminal:Print(`Target is {terminal:Identifier(target or SelfUpdate.getPlatformSuffix())}.`)
    terminal:Print(`Entry point is {terminal:Path(entryPoint, { Directory = entryIsDir })}.`)

    const result = process.exec("lune", args)

    -- Clean up temp file
    if tempFile and fs.isFile(tempFile) then
        fs.removeFile(tempFile)
    end

    if result.ok then
        local outputFile = outputPath
        if (target and string.find(target, "windows")) or (not target and process.os == "windows") then
            outputFile = outputPath .. ".exe"
        end

        if fs.isFile(outputFile) then
            terminal:Print(`Output file is {terminal:Path(outputFile)}.`)
        end

        terminal:Print(terminal:Success("Build completed successfully!"))
    else
        terminal:Print(terminal:Error("Build failed."))
        terminal:Print(result.stderr)
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

    const Command = require("@self/Command")
    const Arg = require("@self/Arg")

    return Command.new({
        Name = "completions",
        Description = "Generate shell completion script.",
        Args = {
            Arg.new({
                Name = "shell",
                Description = "Shell type (bash, zsh, or fish)."
            })
        },
        Impl = function(args)
            print(Completions.generate(getRootCommand(), args.shell))
        end
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
    Shell: string?
})
    assert(t.table(options))
    assert(t.table(options.Command))

    const shell = options.Shell or "zsh"
    const homeDir = process.env.HOME or process.env.USERPROFILE or ""
    const completionsDir = homeDir .. "/.commandline-luau/completions"
    const commandName = options.Command.Name

    -- Generate the completion script
    const script = Completions.generate(options.Command, shell)

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
    const terminal = Terminal.default()
    terminal:Print(`Installed {shell} completions to {terminal:Path(completionFile)}.`)

    -- Configure the shell to load completions
    const marker = "# Added by commandline-luau"

    if shell == "zsh" then
        const configPath = homeDir .. "/.zshrc"
        const fPathLine = "fpath=(~/.commandline-luau/completions $fpath)"
        const compInitLine = "autoload -Uz compinit && compinit"

        local content = ""
        if fs.isFile(configPath) then
            content = fs.readFile(configPath)
        end

        if string.find(content, marker, 1, true) then
            terminal:Print("Shell config already configured.")
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
        terminal:Print(`Added completions to {terminal:Path(configPath)}.`)
        terminal:Print(terminal:Warning("Restart your terminal to enable completions."))
    elseif shell == "powershell" or shell == "pwsh" then
        -- Find or create the PowerShell profile
        const profileDir = homeDir .. "/.config/powershell"
        const profilePath = profileDir .. "/Microsoft.PowerShell_profile.ps1"

        if not fs.isDir(profileDir) then
            fs.writeDir(profileDir)
        end

        local content = ""
        if fs.isFile(profilePath) then
            content = fs.readFile(profilePath)
        end

        if string.find(content, marker, 1, true) then
            terminal:Print("Shell config already configured.")
            return
        end

        if content ~= "" and not string.match(content, "\n$") then
            content = content .. "\n"
        end
        if content ~= "" then
            content = content .. "\n"
        end

        const sourceLine = ". " .. completionFile

        content = content .. marker .. "\n" .. sourceLine .. "\n"

        fs.writeFile(profilePath, content)
        terminal:Print(`Added completions to {terminal:Path(profilePath)}.`)
        terminal:Print(terminal:Warning("Restart PowerShell to enable completions."))
    end
end

------------------------------------------------------------------------------------------
-- Install and Update (Direct Binary Replacement)
------------------------------------------------------------------------------------------

const installOptionsCheck = t.interface({
    Name = t.string,
    InstallDir = t.string,
    Version = t.string,
    Repository = t.string
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
    Repository: string
}): any
    assert(installOptionsCheck(options))

    const Command = require("@self/Command")
    const net = require("@lune/net")
    const serde = require("@lune/serde")

    const name = options.Name
    const installDir = options.InstallDir
    const version = options.Version
    const repository = options.Repository

    const IS_WINDOWS = process.os == "windows"
    const HOME_DIR = if IS_WINDOWS then process.env.USERPROFILE or "" else process.env.HOME or ""
    const INSTALL_PATH = HOME_DIR .. "/" .. installDir
    const BIN_DIR = INSTALL_PATH .. "/bin"
    const EXECUTABLE_SUFFIX = if IS_WINDOWS then ".exe" else ""
    const PATH_EXPORT_COMMENT = "# Added by " .. name
    const PATH_EXPORT_LINE = `export PATH="{BIN_DIR}:$PATH"`
    const SHELL_CONFIGS = {
        { file = ".bash_profile", shell = "bash" },
        { file = ".bashrc", shell = "bash" },
        { file = ".zshrc", shell = "zsh" }
    }
    const XSH_PATH_FILE = HOME_DIR .. "/.path"

    const function downloadLatestBinary(terminal: Terminal.Terminal): string?
        assert(t.table(terminal))

        const url = `https://api.github.com/repos/{repository}/releases/latest`
        const ok, response = pcall(net.request, {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = name }
        })

        if not ok or not response.ok then
            terminal:Print(terminal:Error("Failed to fetch latest release."))
            return nil
        end

        const success, release = pcall(serde.decode, "json" :: "json", response.body)
        if not success then
            terminal:Print(terminal:Error("Failed to parse release data."))
            return nil
        end

        const platformSuffix = SelfUpdate.getPlatformSuffix()
        const assetName = `{name}-{platformSuffix}{EXECUTABLE_SUFFIX}`
        const downloadUrl = SelfUpdate.getAssetDownloadUrl(name, release.assets or {}, platformSuffix)

        if not downloadUrl then
            terminal:Print(terminal:Error(`Asset "{terminal:Identifier(assetName)}" not found in latest release.`))
            return nil
        end

        const dlOk, dlResponse = pcall(net.request, {
            url = downloadUrl,
            method = "GET",
            headers = { ["User-Agent"] = name }
        })

        if not dlOk or not dlResponse.ok then
            terminal:Print(terminal:Error("Failed to download binary."))
            return nil
        end

        return dlResponse.body
    end

    const function addToPath(terminal: Terminal.Terminal)
        assert(t.table(terminal))

        if IS_WINDOWS then
            const psCmd = "$p = [Environment]::GetEnvironmentVariable('PATH','User');"
                .. " if ($p -notlike '*"
                .. BIN_DIR
                .. "*') { [Environment]::SetEnvironmentVariable('PATH', '"
                .. BIN_DIR
                .. ";' + $p, 'User') }"
            const result = process.exec("powershell", { "-Command", psCmd })
            if result.ok then
                terminal:Print(`Added {terminal:Path(BIN_DIR, { Directory = true })} to user PATH.`)
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
                terminal:Print(
                    `Added {terminal:Path(BIN_DIR, { Directory = true })} to {terminal:Path(XSH_PATH_FILE)}.`
                )
            end
            return
        end

        -- Fall back to shell config files
        for _, config in SHELL_CONFIGS do
            const configPath = `{HOME_DIR}/{config.file}`
            if fs.isFile(configPath) then
                local content = fs.readFile(configPath)
                if not string.find(content, PATH_EXPORT_COMMENT, 1, true) then
                    if content ~= "" and not string.match(content, "\n$") then
                        content ..= "\n"
                    end
                    content ..= "\n" .. PATH_EXPORT_COMMENT .. "\n" .. PATH_EXPORT_LINE .. "\n"
                    fs.writeFile(configPath, content)
                    terminal:Print(`Added {terminal:Identifier(name)} to {terminal:Path(configPath)}.`)
                end
            end
        end
    end

    return Command.new({
        Name = "install",
        Description = `Install {name} CLI to ~/{installDir} and add to PATH.`,
        Impl = function()
            const terminal = Terminal.default()
            terminal:Print(terminal:Heading(`Installing {name} {terminal:Identifier(version)}...`))
            terminal:Print()

            -- Create directory structure
            if not fs.isDir(INSTALL_PATH) then
                fs.writeDir(INSTALL_PATH)
            end
            if not fs.isDir(BIN_DIR) then
                fs.writeDir(BIN_DIR)
            end

            const binaryPath = `{BIN_DIR}/{name}{EXECUTABLE_SUFFIX}`

            -- Try to copy current running binary first. Both paths go through
            -- SelfUpdate so the installed binary is replaced rather than overwritten,
            -- which keeps any running copy (including this one) alive.
            const currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                SelfUpdate.copyBinary({
                    sourcePath = currentExe,
                    targetPath = binaryPath
                })
                terminal:Print(`Copied executable to {terminal:Path(binaryPath)}.`)
            else
                -- Download from GitHub releases
                terminal:Print("Downloading binary...")
                const contents = downloadLatestBinary(terminal)
                if not contents then
                    terminal:Print(terminal:Error("Failed to install. Could not download binary."))
                    process.exit(1)
                    return
                end
                SelfUpdate.replaceBinary({
                    targetPath = binaryPath,
                    newContents = contents
                })
                terminal:Print(terminal:Success("Downloaded successfully."))
            end

            -- Add to PATH
            addToPath(terminal)

            terminal:Print()
            terminal:Print(terminal:Success("Installation complete!"))
            terminal:Print(terminal:Warning("Restart your terminal for PATH changes to take effect."))
        end
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
    Repository: string
}): any
    assert(installOptionsCheck(options))

    const Command = require("@self/Command")
    const Flag = require("@self/Flag")
    const net = require("@lune/net")
    const serde = require("@lune/serde")

    const name = options.Name
    const currentVersion = options.Version
    const repository = options.Repository

    const function getRelease(targetVersion: string?): { version: string, assets: { any } }?
        local url: string
        if targetVersion then
            url = `https://api.github.com/repos/{repository}/releases/tags/{targetVersion}`
        else
            url = `https://api.github.com/repos/{repository}/releases/latest`
        end

        const ok, response = pcall(net.request, {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = name }
        })
        if not ok or not response.ok then
            return nil
        end

        const success, data = pcall(serde.decode, "json" :: "json", response.body)
        if not success then
            return nil
        end

        return {
            version = data.tag_name,
            assets = data.assets or {}
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
                Type = "string"
            })
        },
        Impl = function(args)
            const terminal = Terminal.default()
            const targetVersion = args.version

            -- Clean up leftover .old file from previous Windows update
            const currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                SelfUpdate.cleanupOldBinary(currentExe)
            end

            terminal:Print(terminal:Heading(`Checking for updates to {name}...`))

            const release = getRelease(targetVersion)
            if not release then
                terminal:Print(
                    terminal:Error(
                        if targetVersion
                            then `Version "{terminal:Identifier(targetVersion)}" not found.`
                            else "Failed to fetch latest release."
                    )
                )
                process.exit(1)
            end

            const newVersion = release.version
            if newVersion == currentVersion and not targetVersion then
                terminal:Print(`Already on the latest version ({terminal:Identifier(currentVersion)}).`)
                return
            end

            terminal:Print(
                `Updating from {terminal:Identifier(currentVersion)} to {terminal:Identifier(newVersion)}...`
            )

            -- Find download URL for current platform
            const platformSuffix = SelfUpdate.getPlatformSuffix()
            const downloadUrl = SelfUpdate.getAssetDownloadUrl(name, release.assets, platformSuffix)

            if not downloadUrl then
                terminal:Print(
                    terminal:Error(
                        `Binary for {terminal:Identifier(platformSuffix)} not found in release {terminal:Identifier(
                            newVersion
                        )}.`
                    )
                )
                process.exit(1)
            end

            -- Download new binary
            const dlOk, dlResponse = pcall(net.request, {
                url = downloadUrl,
                method = "GET",
                headers = { ["User-Agent"] = name }
            })

            if not dlOk or not dlResponse.ok then
                terminal:Print(terminal:Error("Failed to download update."))
                process.exit(1)
            end

            -- Replace the current binary in-place
            if currentExe then
                SelfUpdate.replaceBinary({
                    targetPath = currentExe,
                    newContents = dlResponse.body
                })
            else
                terminal:Print(
                    terminal:Error(
                        `Could not find {terminal:Identifier(name)} on PATH. Run "{terminal:Identifier(`{name} install`)}" first.`
                    )
                )
                process.exit(1)
            end

            terminal:Print()
            terminal:Print(terminal:Success(`Updated to {terminal:Identifier(newVersion)}!`))
        end
    })
end

-- Exposed for testing
Toolkit._SelfUpdate = SelfUpdate

return Toolkit

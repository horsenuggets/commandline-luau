--[[

Toolkit

Build and install utilities for creating standalone CLI executables from Commandline
apps. Provides functions for building executables, generating version modules, and
enabling shell completions.

--]]

const Chalk = require("@packages/Chalk")
const fs = require("@lune/fs")
const process = require("@lune/process")
const t = require("@packages/t")

const Completions = require("@self/Completions")

const Toolkit = {}

-- Validation types

const buildOptionsCheck = t.interface({
    Name = t.string,
    EntryPoint = t.string,
    OutputDir = t.optional(t.string),
    Target = t.optional(t.string),
})

const generateVersionCheck = t.interface({
    VersionFile = t.optional(t.string),
    OutputPath = t.string,
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
    OutputPath: string,
})
    assert(generateVersionCheck(options))

    const versionFile = options.VersionFile or "VERSION"

    if not fs.isFile(versionFile) then
        print(Chalk.red('VERSION file not found at "' .. versionFile .. '".'))
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
]]
function Toolkit.build(options: {
    Name: string,
    EntryPoint: string,
    OutputDir: string?,
    Target: string?,
})
    assert(buildOptionsCheck(options))

    const outputDir = options.OutputDir or "Build"
    const target = options.Target

    print()
    print("Building " .. Chalk.bold(Chalk.blueBright(options.Name)) .. " executable...")

    -- Resolve entry point
    const entryPoint = options.EntryPoint
    if not fs.isDir(entryPoint) and not fs.isFile(entryPoint) then
        print(Chalk.red('Entry point "' .. entryPoint .. '" not found.'))
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
        print("Target is " .. Chalk.dim(target) .. ".")
    else
        print("Target is " .. Chalk.dim(process.os .. "-" .. process.arch) .. ".")
    end
    print("Entry point is " .. Chalk.dim(entryPoint) .. ".")

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

    const Command = require("@self/Command")
    const Arg = require("@self/Arg")

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
    print("Installed " .. shell .. " completions to " .. Chalk.dim(completionFile) .. ".")

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
            print(Chalk.dim("Shell config already configured."))
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
        print("Added completions to " .. Chalk.dim(profilePath) .. ".")
        print(Chalk.yellow("Restart PowerShell to enable completions."))
    end
end

------------------------------------------------------------------------------------------
-- Install and Update (Direct Binary Replacement)
------------------------------------------------------------------------------------------

const SelfUpdate = require("@self/SelfUpdate")

const installOptionsCheck = t.interface({
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
        { file = ".zshrc", shell = "zsh" },
    }
    const XSH_PATH_FILE = HOME_DIR .. "/.path"

    const function downloadLatestBinary(destPath: string): boolean
        const url = `https://api.github.com/repos/{repository}/releases/latest`
        const ok, response = pcall(net.request, {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = name },
        })

        if not ok or not response.ok then
            print(Chalk.red("Failed to fetch latest release."))
            return false
        end

        const success, release = pcall(serde.decode, "json" :: "json", response.body)
        if not success then
            print(Chalk.red("Failed to parse release data."))
            return false
        end

        const platformSuffix = SelfUpdate.getPlatformSuffix()
        const assetName = `{name}-{platformSuffix}{EXECUTABLE_SUFFIX}`
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

        const dlOk, dlResponse = pcall(net.request, {
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

    const function addToPath()
        if IS_WINDOWS then
            const psCmd = "$p = [Environment]::GetEnvironmentVariable('PATH','User');"
                .. " if ($p -notlike '*"
                .. BIN_DIR
                .. "*') { [Environment]::SetEnvironmentVariable('PATH', '"
                .. BIN_DIR
                .. ";' + $p, 'User') }"
            const result = process.exec("powershell", { "-Command", psCmd })
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
            const configPath = `{HOME_DIR}/{config.file}`
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

            const binaryPath = `{BIN_DIR}/{name}{EXECUTABLE_SUFFIX}`

            -- Try to copy current running binary first
            const currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                const contents = fs.readFile(currentExe)
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

    const Command = require("@self/Command")
    const Flag = require("@self/Flag")
    const net = require("@lune/net")
    const serde = require("@lune/serde")

    const name = options.Name
    const currentVersion = options.Version
    const repository = options.Repository

    const IS_WINDOWS = process.os == "windows"
    const EXECUTABLE_SUFFIX = if IS_WINDOWS then ".exe" else ""

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
            headers = { ["User-Agent"] = name },
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
            const targetVersion = args.version

            -- Clean up leftover .old file from previous Windows update
            const currentExe = SelfUpdate.findExecutable(name)
            if currentExe then
                SelfUpdate.cleanupOldBinary(currentExe)
            end

            print(`Checking for updates to {Chalk.bold(Chalk.blueBright(name))}...`)

            const release = getRelease(targetVersion)
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

            const newVersion = release.version
            if newVersion == currentVersion and not targetVersion then
                print(`Already on the latest version ({Chalk.bold(Chalk.blueBright(currentVersion))}).`)
                return
            end

            print(`Updating from {Chalk.dim(currentVersion)} to {Chalk.bold(Chalk.blueBright(newVersion))}...`)

            -- Find download URL for current platform
            const platformSuffix = SelfUpdate.getPlatformSuffix()
            const assetName = `{name}-{platformSuffix}{EXECUTABLE_SUFFIX}`
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
            const dlOk, dlResponse = pcall(net.request, {
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
Toolkit._SelfUpdate = SelfUpdate

return Toolkit

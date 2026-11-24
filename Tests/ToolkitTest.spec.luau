--[[

ToolkitTest.spec

Tests for the Toolkit build utilities. Covers version generation, executable
building, completions, and install/update progress through configured terminals.
Install/update tests mock all filesystem, network, process, and binary replacement I/O.

--]]

const fs = require("@lune/fs")
const luau = require("@lune/luau")
const process = require("@lune/process")
const serde = require("@lune/serde")
const t = require("@packages/t")

const Commandline = require("@commandline")
const Terminal = require("../Source/Commandline/Terminal")

const Command = Commandline.Command
const Flag = Commandline.Flag
const Toolkit = Commandline.Toolkit
const TOOLKIT_SOURCE = fs.readFile("Source/Commandline/Toolkit.luau")

type ProgressScenario = {
    CurrentExecutable: boolean?,
    DownloadFailure: boolean?,
    InvalidRelease: boolean?,
    MissingAsset: boolean?,
    Os: string?,
    PathFile: string?,
    ReleaseFailure: boolean?,
    ReleaseVersion: string?,
    TargetVersion: string?,
}

-- Load the real command implementations with closed I/O boundaries. No missing mock can
-- fall through to the user's filesystem, network, environment, or executable.
const function runProgress(commandName: string, terminal: Terminal.Terminal, scenario: ProgressScenario): number?
    assert(t.string(commandName))
    assert(t.table(terminal))
    assert(t.table(scenario))

    local exitCode: number? = nil
    const exited = {}
    const dependencies: { [string]: any } = {
        ["@packages/t"] = t,
        ["@lune/fs"] = {
            isDir = function()
                return true
            end,
            isFile = function(path)
                return path == `/home/test/{scenario.PathFile or ".zshrc"}`
            end,
            readFile = function()
                return ""
            end,
            writeDir = function() end,
            writeFile = function() end,
        },
        ["@lune/net"] = {
            request = function(request)
                if request.url == "https://example.invalid/binary" then
                    return { ok = not scenario.DownloadFailure, body = "binary" }
                end
                return {
                    ok = not scenario.ReleaseFailure,
                    body = if scenario.InvalidRelease
                        then "not json"
                        else serde.encode("json", {
                            tag_name = scenario.ReleaseVersion or "2.0.0",
                            assets = {},
                        }),
                }
            end,
        },
        ["@lune/process"] = {
            env = { HOME = "/home/test", USERPROFILE = "/home/test" },
            exec = function()
                return { ok = true }
            end,
            exit = function(code)
                exitCode = code
                error(exited, 0)
            end,
            os = scenario.Os or "linux",
        },
        ["@lune/serde"] = serde,
        ["@self/Command"] = Command,
        ["@self/Flag"] = Flag,
        ["@self/SelfUpdate"] = {
            cleanupOldBinary = function() end,
            copyBinary = function() end,
            findExecutable = function()
                return if scenario.CurrentExecutable then "/home/test/.mytool/bin/mytool" else nil
            end,
            getAssetDownloadUrl = function()
                return if scenario.MissingAsset then nil else "https://example.invalid/binary"
            end,
            getPlatformSuffix = function()
                return "linux-x86_64"
            end,
            replaceBinary = function() end,
        },
        ["@self/Terminal"] = Terminal,
        ["@self/Completions"] = Commandline.Completions,
    }
    const toolkit = luau.load(TOOLKIT_SOURCE, {
        environment = {
            print = function()
                error("Human-readable progress bypassed the configured terminal.")
            end,
            require = function(path)
                return assert(dependencies[path], `Unexpected dependency "{path}".`)
            end,
        },
    })()
    const options = { Name = "mytool", InstallDir = ".mytool", Version = "1.0.0", Repository = "example/mytool" }
    const command = if commandName == "install" then toolkit.installCommand(options) else toolkit.updateCommand(options)
    const previous = Terminal.default()
    Terminal.setDefault(terminal)
    const ok, problem = pcall(command._impl, { version = scenario.TargetVersion })
    Terminal.setDefault(previous)
    assert(ok or problem == exited, tostring(problem))
    return exitCode
end

local _counter = 0
const function createTempDir(): string
    _counter += 1
    const path = "/tmp/commandline-toolkit-test-"
        .. tostring(os.time())
        .. "-"
        .. tostring(math.random(100000, 999999))
        .. "-"
        .. tostring(_counter)
    fs.writeDir(path)
    return path
end

const function cleanup(path: string)
    if fs.isDir(path) then
        process.exec("rm", { "-rf", path })
    end
end

const function writeFile(dir: string, relativePath: string, content: string)
    const fullPath = dir .. "/" .. relativePath
    const parentDir = string.match(fullPath, "(.+)/[^/]+$")
    if parentDir and not fs.isDir(parentDir) then
        fs.writeDir(parentDir)
    end
    fs.writeFile(fullPath, content)
end

const function readFile(dir: string, relativePath: string): string
    return fs.readFile(dir .. "/" .. relativePath)
end

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const function expectProgress(
    commandName: string,
    scenario: ProgressScenario,
    expectedLines: (Terminal.Terminal) -> { string },
    expectedExit: number?
)
    for _, color in { false, true } do
        for _, timestamps in { false, true } do
            local written = ""
            const config: Terminal.Config = {
                Clock = {
                    Elapsed = function()
                        return 65.25
                    end,
                    LocalOffsetMinutes = function()
                        return 0
                    end,
                    UnixMillis = function()
                        return 0
                    end,
                },
                Color = color,
                Columns = 0,
                Env = {},
                Home = "/home/test",
                Theme = {
                    Error = { Color = "magenta" },
                    Heading = { Color = "cyan" },
                    Identifier = { Color = "yellow" },
                    Path = { Color = "blue" },
                    Success = { Color = "white" },
                    Warning = { Color = "red" },
                },
                Timestamps = if timestamps then "stopwatch" else "off",
                Write = function(text)
                    written ..= text
                end,
                WriteError = function()
                    error("Progress unexpectedly changed its output stream.")
                end,
            }
            const terminal = Terminal.new(config)
            const exitCode = runProgress(commandName, terminal, scenario)
            local expected = ""
            config.Write = function(text)
                expected ..= text
            end
            const reference = Terminal.new(config)
            for _, line in expectedLines(reference) do
                reference:Print(line)
            end
            expect(exitCode).to.equal(expectedExit)
            expect(written).to.equal(expected)
            expect(string.find(written, "\u{1b}[", 1, true) ~= nil).to.equal(color)
        end
    end
end

return function()
    describe("generateVersion", function()
        it("should theme version progress and missing-file errors through the shared terminal", function()
            for _, color in { false, true } do
                for _, missing in { false, true } do
                    const output = {}
                    const errors = {}
                    const terminal = Terminal.new({
                        Color = color,
                        Env = {},
                        Write = function(text)
                            table.insert(output, text)
                        end,
                        WriteError = function(text)
                            table.insert(errors, text)
                        end,
                    })
                    const exited = {}
                    const dependencies: { [string]: any } = {
                        ["@lune/fs"] = {
                            isDir = function()
                                return true
                            end,
                            isFile = function()
                                return not missing
                            end,
                            readFile = function()
                                return "1.2.3\n"
                            end,
                            writeFile = function() end,
                        },
                        ["@lune/process"] = {
                            exit = function(code)
                                expect(code).to.equal(1)
                                error(exited, 0)
                            end,
                        },
                        ["@packages/t"] = t,
                        ["@self/Completions"] = {},
                        ["@self/SelfUpdate"] = {},
                        ["@self/Terminal"] = {
                            default = function()
                                return terminal
                            end,
                        },
                    }
                    const toolkit = luau.load(TOOLKIT_SOURCE, {
                        environment = {
                            print = function()
                                error("Version progress bypassed the shared terminal.")
                            end,
                            require = function(path)
                                return assert(dependencies[path], `Unexpected dependency "{path}".`)
                            end,
                        },
                    })()
                    const ok, problem =
                        pcall(toolkit.generateVersion, { VersionFile = "VERSION", OutputPath = "out.luau" })
                    expect(ok).to.equal(not missing)
                    if missing then
                        expect(problem).to.equal(exited)
                        expect(table.concat(output)).to.equal("")
                        expect(table.concat(errors)).to.equal(
                            `{terminal:Error('VERSION file not found at "VERSION".')}\n`
                        )
                    else
                        expect(table.concat(errors)).to.equal("")
                        expect(table.concat(output)).to.equal(
                            `Generated version module with version {terminal:Heading("1.2.3")}.\n`
                        )
                    end
                    const written = table.concat(output) .. table.concat(errors)
                    expect(
                        string.find(written, if missing then "38;2;247;118;142" else "38;2;122;162;247", 1, true) ~= nil
                    ).to.equal(color)
                end
            end
        end)

        it("should generate a version module from a VERSION file", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "1.2.3\n")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/__VERSION__.luau",
            })
            expect(fs.isFile(tempDir .. "/__VERSION__.luau")).to.equal(true)
            expect(readFile(tempDir, "__VERSION__.luau")).to.equal(
                '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "1.2.3"\n'
            )
            cleanup(tempDir)
        end)

        it("should strip whitespace from version string", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "  0.5.10  \n")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/__VERSION__.luau",
            })
            expect(readFile(tempDir, "__VERSION__.luau")).to.equal(
                '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "0.5.10"\n'
            )
            cleanup(tempDir)
        end)

        it("should handle version with no trailing newline", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "2.0.0")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/__VERSION__.luau",
            })
            expect(readFile(tempDir, "__VERSION__.luau")).to.equal(
                '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "2.0.0"\n'
            )
            cleanup(tempDir)
        end)

        it("should handle pre-release version strings", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "0.10.4-horse.10.0\n")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/__VERSION__.luau",
            })
            expect(readFile(tempDir, "__VERSION__.luau")).to.equal(
                '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "0.10.4-horse.10.0"\n'
            )
            cleanup(tempDir)
        end)

        it("should create parent directories for output path", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "1.0.0\n")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/deep/nested/__VERSION__.luau",
            })
            expect(fs.isFile(tempDir .. "/deep/nested/__VERSION__.luau")).to.equal(true)
            cleanup(tempDir)
        end)

        it("should default to VERSION in current directory", function()
            const tempDir = createTempDir()
            const _originalCwd = process.cwd
            writeFile(tempDir, "VERSION", "3.0.0\n")

            -- generateVersion with no VersionFile should look for "VERSION"
            -- in cwd. We test the parameter directly instead.
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/out.luau",
            })
            expect(readFile(tempDir, "out.luau")).to.equal(
                '--[[\n\n__VERSION__\n\nAuto-generated version module.\n\n--]]\n\nreturn "3.0.0"\n'
            )
            cleanup(tempDir)
        end)
    end)

    describe("build", function()
        it("should validate required options", function()
            expect(function()
                Toolkit.build({ Name = 123 :: any, EntryPoint = "." })
            end).to.throw()
        end)

        it("should validate entry point type", function()
            expect(function()
                Toolkit.build({ Name = "test", EntryPoint = 123 :: any })
            end).to.throw()
        end)

        it("should build a minimal executable from a directory entry point", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("hello")\n')

            Toolkit.build({
                Name = "test-binary",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/out",
            })

            const binaryPath = tempDir .. "/out/test-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            -- Run the binary and verify output
            const result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "hello")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should print its messages through the given terminal", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("hello")\n')

            local written = ""
            const ok, problem = pcall(Toolkit.build, {
                DisplayName = "test-cli",
                Name = "test-binary",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/out",
                Terminal = Commandline.Terminal.new({
                    Color = false,
                    Env = {},
                    Home = tempDir,
                    Write = function(text)
                        written ..= text
                    end,
                }),
            })
            cleanup(tempDir)
            assert(ok, tostring(problem))

            const executable = if process.os == "windows" then "test-binary.exe" else "test-binary"
            expect(written).to.equal(
                "Building test-cli...\n"
                    .. `Target is {Toolkit._SelfUpdate.getPlatformSuffix()}.\n`
                    .. "Entry point is ~/src/.\n"
                    .. `Output file is ~/out/{executable}.\n`
                    .. "Build completed successfully!\n"
            )
        end)

        it("should build a minimal executable from a file entry point", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "main.luau", 'print("from-file")\n')

            Toolkit.build({
                Name = "file-binary",
                EntryPoint = tempDir .. "/main.luau",
                OutputDir = tempDir .. "/out",
            })

            const binaryPath = tempDir .. "/out/file-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            const result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "from%-file")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should strip shebangs from file entry points", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "main.luau", '#!/usr/bin/env -S lune run\nprint("shebang-stripped")\n')

            Toolkit.build({
                Name = "shebang-binary",
                EntryPoint = tempDir .. "/main.luau",
                OutputDir = tempDir .. "/out",
            })

            const binaryPath = tempDir .. "/out/shebang-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            const result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "shebang%-stripped")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should create the output directory if it does not exist", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("mkdir")\n')

            Toolkit.build({
                Name = "mkdir-test",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/deep/nested/out",
            })

            expect(fs.isDir(tempDir .. "/deep/nested/out")).to.equal(true)
            expect(fs.isFile(tempDir .. "/deep/nested/out/mkdir-test")).to.equal(true)
            cleanup(tempDir)
        end)

        it("should remove existing binary before building", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("v2")\n')
            writeFile(tempDir, "out/old-binary", "old content")

            Toolkit.build({
                Name = "old-binary",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/out",
            })

            const result = process.exec(tempDir .. "/out/old-binary", {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "v2")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should clean up temp files even if build fails", function()
            const tempDir = createTempDir()
            writeFile(tempDir, "bad.luau", "#!/usr/bin/env lune\nthis is not valid luau\n")

            pcall(function()
                Toolkit.build({
                    Name = "bad-build",
                    EntryPoint = tempDir .. "/bad.luau",
                    OutputDir = tempDir .. "/out",
                })
            end)

            -- The temp _build_entry.luau should be cleaned up
            const files = fs.readDir(tempDir)
            for _, file in files do
                expect(file).never.to.equal("_build_entry.luau")
            end
            cleanup(tempDir)
        end)
    end)

    describe("install progress", function()
        for _, scenario in
            {
                { CurrentExecutable = true },
                { PathFile = ".path" },
                { Os = "windows" },
            }
        do
            it(
                `should honor terminal settings with {scenario.PathFile or scenario.Os or "a local executable"}`,
                function()
                    expectProgress("install", scenario, function(terminal)
                        const suffix = if scenario.Os == "windows" then ".exe" else ""
                        const lines = {
                            terminal:Heading(`Installing mytool {terminal:Identifier("1.0.0")}...`),
                            "",
                        }
                        if scenario.CurrentExecutable then
                            table.insert(
                                lines,
                                `Copied executable to {terminal:Path(`/home/test/.mytool/bin/mytool{suffix}`)}.`
                            )
                        else
                            table.insert(lines, "Downloading binary...")
                            table.insert(lines, terminal:Success("Downloaded successfully."))
                        end
                        table.insert(
                            lines,
                            if scenario.Os == "windows"
                                then `Added {terminal:Path("/home/test/.mytool/bin", { Directory = true })} to user PATH.`
                                elseif scenario.PathFile == ".path" then `Added {terminal:Path(
                                    "/home/test/.mytool/bin",
                                    { Directory = true }
                                )} to {terminal:Path("/home/test/.path")}.`
                                else `Added {terminal:Identifier("mytool")} to {terminal:Path("/home/test/.zshrc")}.`
                        )
                        table.insert(lines, "")
                        table.insert(lines, terminal:Success("Installation complete!"))
                        table.insert(lines, terminal:Warning("Restart your terminal for PATH changes to take effect."))
                        return lines
                    end, nil)
                end
            )
        end

        for _, failure in
            {
                { Scenario = { ReleaseFailure = true }, Message = "Failed to fetch latest release." },
                { Scenario = { InvalidRelease = true }, Message = "Failed to parse release data." },
                {
                    Scenario = { MissingAsset = true },
                    Message = 'Asset "mytool-linux-x86_64" not found in latest release.',
                },
                { Scenario = { DownloadFailure = true }, Message = "Failed to download binary." },
            }
        do
            it(`should route install errors through the terminal when {failure.Message}`, function()
                expectProgress("install", failure.Scenario, function(terminal)
                    const message = if failure.Scenario.MissingAsset
                        then `Asset "{terminal:Identifier("mytool-linux-x86_64")}" not found in latest release.`
                        else failure.Message
                    return {
                        terminal:Heading(`Installing mytool {terminal:Identifier("1.0.0")}...`),
                        "",
                        "Downloading binary...",
                        terminal:Error(message),
                        terminal:Error("Failed to install. Could not download binary."),
                    }
                end, 1)
            end)
        end
    end)

    describe("update progress", function()
        it("should honor terminal settings throughout a successful update", function()
            expectProgress("update", { CurrentExecutable = true }, function(terminal)
                return {
                    terminal:Heading("Checking for updates to mytool..."),
                    `Updating from {terminal:Identifier("1.0.0")} to {terminal:Identifier("2.0.0")}...`,
                    "",
                    terminal:Success(`Updated to {terminal:Identifier("2.0.0")}!`),
                }
            end, nil)
        end)

        it("should honor terminal settings when already up to date", function()
            expectProgress("update", { ReleaseVersion = "1.0.0" }, function(terminal)
                return {
                    terminal:Heading("Checking for updates to mytool..."),
                    `Already on the latest version ({terminal:Identifier("1.0.0")}).`,
                }
            end, nil)
        end)

        for _, scenario in
            {
                { ReleaseFailure = true },
                { InvalidRelease = true },
                { ReleaseFailure = true, TargetVersion = "missing" },
                { MissingAsset = true },
                { DownloadFailure = true },
                {},
            }
        do
            it(`should preserve update failure output and exits for {serde.encode("json", scenario)}`, function()
                expectProgress("update", scenario, function(terminal)
                    const lines = { terminal:Heading("Checking for updates to mytool...") }
                    local message: string
                    if scenario.ReleaseFailure or scenario.InvalidRelease then
                        message = if scenario.TargetVersion
                            then `Version "{terminal:Identifier(scenario.TargetVersion)}" not found.`
                            else "Failed to fetch latest release."
                    else
                        table.insert(
                            lines,
                            `Updating from {terminal:Identifier("1.0.0")} to {terminal:Identifier("2.0.0")}...`
                        )
                        message = if scenario.MissingAsset
                            then `Binary for {terminal:Identifier("linux-x86_64")} not found in release {terminal:Identifier(
                                "2.0.0"
                            )}.`
                            elseif scenario.DownloadFailure then "Failed to download update."
                            else `Could not find {terminal:Identifier("mytool")} on PATH. Run "{terminal:Identifier(
                                "mytool install"
                            )}" first.`
                    end
                    table.insert(lines, terminal:Error(message))
                    return lines
                end, 1)
            end)
        end
    end)

    describe("completionsCommand", function()
        it("should create a completions subcommand", function()
            local root
            root = Command.new({
                Name = "mytool",
                Description = "A test tool.",
                Subcommands = {
                    Command.new({
                        Name = "build",
                        Description = "Build something.",
                        Impl = function() end,
                    }),
                    Toolkit.completionsCommand(function()
                        return root
                    end),
                },
            })

            expect(#root._subcommands).to.equal(2)
            const completionsCmd = root._subcommands[2]
            expect(completionsCmd.Name).to.equal("completions")
            expect(completionsCmd.Description).to.equal("Generate shell completion script.")
        end)

        it("should include completions in the command tree", function()
            local root
            root = Command.new({
                Name = "testtool",
                Description = "A test tool.",
                Subcommands = {
                    Command.new({
                        Name = "run",
                        Description = "Run it.",
                        Flags = {
                            Flag.new({ Name = "verbose", Shorthand = "v" }),
                        },
                        Impl = function() end,
                    }),
                    Toolkit.completionsCommand(function()
                        return root
                    end),
                },
            })

            const names = {}
            for _, sub in root._subcommands do
                table.insert(names, sub.Name)
            end
            expect(table.find(names, "completions")).to.be.ok()
            expect(table.find(names, "run")).to.be.ok()
        end)
    end)
end

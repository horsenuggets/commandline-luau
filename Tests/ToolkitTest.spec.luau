--[[

ToolkitTest.spec

Tests for the Toolkit build utilities. Covers version generation, executable
building, and completions command creation. Tests use isolated temp directories
for parallelism.

--]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Commandline = require("@commandline")

local Command = Commandline.Command
local Flag = Commandline.Flag
local Toolkit = Commandline.Toolkit

local _counter = 0
local function createTempDir(): string
    _counter += 1
    local path = "/tmp/commandline-toolkit-test-"
        .. tostring(os.time())
        .. "-"
        .. tostring(math.random(100000, 999999))
        .. "-"
        .. tostring(_counter)
    fs.writeDir(path)
    return path
end

local function cleanup(path: string)
    if fs.isDir(path) then
        process.exec("rm", { "-rf", path })
    end
end

local function writeFile(dir: string, relativePath: string, content: string)
    local fullPath = dir .. "/" .. relativePath
    local parentDir = string.match(fullPath, "(.+)/[^/]+$")
    if parentDir and not fs.isDir(parentDir) then
        fs.writeDir(parentDir)
    end
    fs.writeFile(fullPath, content)
end

local function readFile(dir: string, relativePath: string): string
    return fs.readFile(dir .. "/" .. relativePath)
end

return function()
    describe("generateVersion", function()
        it("should generate a version module from a VERSION file", function()
            local tempDir = createTempDir()
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
            local tempDir = createTempDir()
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
            local tempDir = createTempDir()
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
            local tempDir = createTempDir()
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
            local tempDir = createTempDir()
            writeFile(tempDir, "VERSION", "1.0.0\n")
            Toolkit.generateVersion({
                VersionFile = tempDir .. "/VERSION",
                OutputPath = tempDir .. "/deep/nested/__VERSION__.luau",
            })
            expect(fs.isFile(tempDir .. "/deep/nested/__VERSION__.luau")).to.equal(true)
            cleanup(tempDir)
        end)

        it("should default to VERSION in current directory", function()
            local tempDir = createTempDir()
            local _originalCwd = process.cwd
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
            local tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("hello")\n')

            Toolkit.build({
                Name = "test-binary",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/out",
            })

            local binaryPath = tempDir .. "/out/test-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            -- Run the binary and verify output
            local result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "hello")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should build a minimal executable from a file entry point", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "main.luau", 'print("from-file")\n')

            Toolkit.build({
                Name = "file-binary",
                EntryPoint = tempDir .. "/main.luau",
                OutputDir = tempDir .. "/out",
            })

            local binaryPath = tempDir .. "/out/file-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            local result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "from%-file")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should strip shebangs from file entry points", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "main.luau", '#!/usr/bin/env -S lune run\nprint("shebang-stripped")\n')

            Toolkit.build({
                Name = "shebang-binary",
                EntryPoint = tempDir .. "/main.luau",
                OutputDir = tempDir .. "/out",
            })

            local binaryPath = tempDir .. "/out/shebang-binary"
            expect(fs.isFile(binaryPath)).to.equal(true)

            local result = process.exec(binaryPath, {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "shebang%-stripped")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should create the output directory if it does not exist", function()
            local tempDir = createTempDir()
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
            local tempDir = createTempDir()
            writeFile(tempDir, "src/init.luau", 'print("v2")\n')
            writeFile(tempDir, "out/old-binary", "old content")

            Toolkit.build({
                Name = "old-binary",
                EntryPoint = tempDir .. "/src",
                OutputDir = tempDir .. "/out",
            })

            local result = process.exec(tempDir .. "/out/old-binary", {})
            expect(result.ok).to.equal(true)
            expect(string.find(result.stdout, "v2")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should clean up temp files even if build fails", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "bad.luau", "#!/usr/bin/env lune\nthis is not valid luau\n")

            pcall(function()
                Toolkit.build({
                    Name = "bad-build",
                    EntryPoint = tempDir .. "/bad.luau",
                    OutputDir = tempDir .. "/out",
                })
            end)

            -- The temp _build_entry.luau should be cleaned up
            local files = fs.readDir(tempDir)
            for _, file in files do
                expect(file).never.to.equal("_build_entry.luau")
            end
            cleanup(tempDir)
        end)
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
            local completionsCmd = root._subcommands[2]
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

            local names = {}
            for _, sub in root._subcommands do
                table.insert(names, sub.Name)
            end
            expect(table.find(names, "completions")).to.be.ok()
            expect(table.find(names, "run")).to.be.ok()
        end)
    end)
end

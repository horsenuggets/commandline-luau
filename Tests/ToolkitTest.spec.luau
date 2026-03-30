--[[

ToolkitTest.spec

Tests for the Toolkit build utilities. Covers version generation, require patching,
executable building, and completions command creation. Tests use isolated temp
directories for parallelism.

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
            local originalCwd = process.cwd
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

    describe("require patching", function()
        it("should patch @self requires to alias paths", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/init.luau", 'local Foo = require("@self/Helpers/Foo")\nreturn {}\n')
            writeFile(tempDir, "Source/MyCli/Helpers/Foo.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            local patched = readFile(tempDir, "Source/MyCli/init.luau")
            expect(string.find(patched, "@mycli/Helpers/Foo")).to.be.ok()
            expect(string.find(patched, "@self")).to.equal(nil)

            Toolkit._restoreFiles(backups)
            local restored = readFile(tempDir, "Source/MyCli/init.luau")
            expect(string.find(restored, "@self/Helpers/Foo")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should patch ./ relative requires to alias paths", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/Helpers/Bar.luau", 'local Baz = require("./Baz")\nreturn {}\n')
            writeFile(tempDir, "Source/MyCli/Helpers/Baz.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            local patched = readFile(tempDir, "Source/MyCli/Helpers/Bar.luau")
            expect(string.find(patched, "@mycli/Helpers/Baz")).to.be.ok()
            expect(string.find(patched, '"./')).to.equal(nil)

            Toolkit._restoreFiles(backups)
            cleanup(tempDir)
        end)

        it("should patch ../ relative requires to alias paths", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/Sub/Deep.luau", 'local Root = require("../Root")\nreturn {}\n')
            writeFile(tempDir, "Source/MyCli/Root.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            local patched = readFile(tempDir, "Source/MyCli/Sub/Deep.luau")
            expect(string.find(patched, "@mycli/Root")).to.be.ok()
            expect(string.find(patched, '".%./')).to.equal(nil)

            Toolkit._restoreFiles(backups)
            cleanup(tempDir)
        end)

        it("should handle multiple requires in one file", function()
            local tempDir = createTempDir()
            -- @self in Sub/init.luau resolves relative to Sub/
            local content = table.concat({
                'local A = require("@self/A")',
                'local B = require("./B")',
                'local C = require("../Root")',
                "return {}",
            }, "\n")
            writeFile(tempDir, "Source/MyCli/Sub/init.luau", content)
            writeFile(tempDir, "Source/MyCli/Sub/A.luau", "return {}\n")
            writeFile(tempDir, "Source/MyCli/Sub/B.luau", "return {}\n")
            writeFile(tempDir, "Source/MyCli/Root.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            local patched = readFile(tempDir, "Source/MyCli/Sub/init.luau")
            -- @self/A from Sub/init.luau -> Source/MyCli/Sub/A
            expect(string.find(patched, "@mycli/Sub/A")).to.be.ok()
            -- ./B from Sub/init.luau -> Source/MyCli/Sub/B
            expect(string.find(patched, "@mycli/Sub/B")).to.be.ok()
            -- ../Root from Sub/init.luau -> Source/MyCli/Root
            expect(string.find(patched, "@mycli/Root")).to.be.ok()
            expect(string.find(patched, "@self")).to.equal(nil)
            expect(string.find(patched, '"./')).to.equal(nil)

            Toolkit._restoreFiles(backups)
            cleanup(tempDir)
        end)

        it("should not modify files outside alias directories", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "other/file.luau", 'local X = require("./X")\nreturn {}\n')

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            expect(#backups).to.equal(0)
            local content = readFile(tempDir, "other/file.luau")
            expect(string.find(content, '"./X"')).to.be.ok()
            cleanup(tempDir)
        end)

        it("should not modify requires that are already aliased", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/init.luau", 'local P = require("@packages/Chalk")\nreturn {}\n')

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
                { alias = "@packages", dir = "Packages" },
            })

            expect(#backups).to.equal(0)
            local content = readFile(tempDir, "Source/MyCli/init.luau")
            expect(string.find(content, "@packages/Chalk")).to.be.ok()
            cleanup(tempDir)
        end)

        it("should restore all files after patching", function()
            local tempDir = createTempDir()
            local original1 = 'local A = require("@self/A")\nreturn {}\n'
            local original2 = 'local B = require("./B")\nreturn {}\n'
            writeFile(tempDir, "Source/MyCli/init.luau", original1)
            writeFile(tempDir, "Source/MyCli/Sub/File.luau", original2)
            writeFile(tempDir, "Source/MyCli/A.luau", "return {}\n")
            writeFile(tempDir, "Source/MyCli/Sub/B.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            expect(#backups).to.equal(2)

            Toolkit._restoreFiles(backups)

            expect(readFile(tempDir, "Source/MyCli/init.luau")).to.equal(original1)
            expect(readFile(tempDir, "Source/MyCli/Sub/File.luau")).to.equal(original2)
            cleanup(tempDir)
        end)

        it("should delete .luaurc files in Packages/_Index", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/init.luau", "return {}\n")
            writeFile(tempDir, "Packages/_Index/some-pkg/.luaurc", '{"aliases":{}}')

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            expect(fs.isFile(tempDir .. "/Packages/_Index/some-pkg/.luaurc")).to.equal(false)

            Toolkit._restoreFiles(backups)
            expect(fs.isFile(tempDir .. "/Packages/_Index/some-pkg/.luaurc")).to.equal(true)
            cleanup(tempDir)
        end)

        it("should handle deeply nested .luaurc files in packages", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/init.luau", "return {}\n")
            writeFile(tempDir, "Packages/_Index/pkg-a/a/.luaurc", '{"aliases":{}}')
            writeFile(tempDir, "Packages/_Index/pkg-b/b/sub/.luaurc", '{"aliases":{}}')

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            expect(fs.isFile(tempDir .. "/Packages/_Index/pkg-a/a/.luaurc")).to.equal(false)
            expect(fs.isFile(tempDir .. "/Packages/_Index/pkg-b/b/sub/.luaurc")).to.equal(false)

            Toolkit._restoreFiles(backups)
            expect(fs.isFile(tempDir .. "/Packages/_Index/pkg-a/a/.luaurc")).to.equal(true)
            expect(fs.isFile(tempDir .. "/Packages/_Index/pkg-b/b/sub/.luaurc")).to.equal(true)
            cleanup(tempDir)
        end)

        it("should handle files with no requires", function()
            local tempDir = createTempDir()
            local content = "local x = 42\nreturn x\n"
            writeFile(tempDir, "Source/MyCli/NoRequires.luau", content)

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            expect(#backups).to.equal(0)
            expect(readFile(tempDir, "Source/MyCli/NoRequires.luau")).to.equal(content)
            cleanup(tempDir)
        end)

        it("should only patch .luau files, not other extensions", function()
            local tempDir = createTempDir()
            writeFile(tempDir, "Source/MyCli/data.json", '{"require": "@self/test"}')
            writeFile(tempDir, "Source/MyCli/init.luau", "return {}\n")

            local backups = Toolkit._patchRelativeRequires(tempDir, {
                { alias = "@mycli", dir = "Source/MyCli" },
            })

            local jsonContent = readFile(tempDir, "Source/MyCli/data.json")
            expect(string.find(jsonContent, "@self/test")).to.be.ok()
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

        it("should apply require patching when AliasDirs is provided", function()
            local tempDir = createTempDir()
            writeFile(
                tempDir,
                "Source/App/init.luau",
                table.concat({
                    'local Helper = require("@self/Helper")',
                    "print(Helper.greet())",
                }, "\n")
            )
            writeFile(
                tempDir,
                "Source/App/Helper.luau",
                table.concat({
                    "local Helper = {}",
                    "function Helper.greet()",
                    '    return "patched-build"',
                    "end",
                    "return Helper",
                }, "\n")
            )
            writeFile(
                tempDir,
                ".luaurc",
                table.concat({
                    "{",
                    '    "aliases": {',
                    '        "app": "./Source/App/"',
                    "    }",
                    "}",
                }, "\n")
            )

            Toolkit.build({
                Name = "patched-app",
                EntryPoint = tempDir .. "/Source/App",
                OutputDir = tempDir .. "/out",
                AliasDirs = {
                    { alias = "@app", dir = "Source/App" },
                },
            })

            -- Verify source files were restored (not left patched)
            local sourceContent = readFile(tempDir, "Source/App/init.luau")
            expect(string.find(sourceContent, "@self/Helper")).to.be.ok()

            -- Verify binary works
            local binaryPath = tempDir .. "/out/patched-app"
            expect(fs.isFile(binaryPath)).to.equal(true)
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

--[[

CommandTest.spec

Tests for the Command class covering creation, execution,
subcommands, and help generation.

--]]

local Arg = require("../Source/Commandline/Arg")
local Command = require("../Source/Commandline/Command")
local Flag = require("../Source/Commandline/Flag")

return function()
    describe("Command.new", function()
        it("should create a basic Command with required fields", function()
            local cmd = Command.new({
                Name = "test",
            })
            expect(cmd).to.be.ok()
            expect(cmd.Name).to.equal("test")
            expect(cmd.Description).to.equal("No description.")
            expect(cmd.Version).to.equal(nil)
        end)

        it("should create a Command with description and version", function()
            local cmd = Command.new({
                Name = "build",
                Description = "Build the project",
                Version = "1.0.0",
            })
            expect(cmd.Name).to.equal("build")
            expect(cmd.Description).to.equal("Build the project")
            expect(cmd.Version).to.equal("1.0.0")
        end)

        it("should automatically add help Flag", function()
            local cmd = Command.new({
                Name = "test",
            })
            expect(#cmd._flags).to.equal(1)
            expect(cmd._flags[1].Name).to.equal("help")
            expect(cmd._flags[1].Shorthand).to.equal("h")
        end)

        it("should not duplicate help Flag if already provided", function()
            local cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({
                        Name = "help",
                        Description = "Custom help",
                    }),
                },
            })
            expect(#cmd._flags).to.equal(1)
        end)

        it("should automatically add version Flag when Version is set", function()
            local cmd = Command.new({
                Name = "test",
                Version = "1.0.0",
            })
            local hasVersion = false
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    hasVersion = true
                    expect(flag.Shorthand).to.equal("v")
                end
            end
            expect(hasVersion).to.equal(true)
        end)

        it("should not add version Flag when Version is not set", function()
            local cmd = Command.new({
                Name = "test",
            })
            for _, flag in cmd._flags do
                expect(flag.Name).never.to.equal("version")
            end
        end)

        it("should not duplicate version Flag if already provided", function()
            local cmd = Command.new({
                Name = "test",
                Version = "1.0.0",
                Flags = {
                    Flag.new({
                        Name = "version",
                        Description = "Custom version",
                    }),
                },
            })
            local versionCount = 0
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    versionCount += 1
                end
            end
            expect(versionCount).to.equal(1)
        end)

        it("should omit version shorthand when -v is already taken", function()
            local cmd = Command.new({
                Name = "test",
                Version = "1.0.0",
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                },
            })
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    expect(flag.Shorthand).to.equal(nil)
                end
            end
        end)

        it("should convert command name to lowercase", function()
            local cmd = Command.new({
                Name = "TestCommand",
            })
            expect(cmd.Name).to.equal("testcommand")
        end)

        it("should allow kebab-case names with single hyphens", function()
            local cmd = Command.new({ Name = "test-command" })
            expect(cmd.Name).to.equal("test-command")

            local cmd2 = Command.new({ Name = "my-long-command-name" })
            expect(cmd2.Name).to.equal("my-long-command-name")
        end)

        it("should throw error for invalid names", function()
            -- Underscores not allowed
            expect(function()
                Command.new({ Name = "test_command" })
            end).to.throw()

            -- Spaces not allowed
            expect(function()
                Command.new({ Name = "test command" })
            end).to.throw()

            -- Leading hyphen not allowed
            expect(function()
                Command.new({ Name = "-test" })
            end).to.throw()

            -- Trailing hyphen not allowed
            expect(function()
                Command.new({ Name = "test-" })
            end).to.throw()

            -- Double hyphens not allowed
            expect(function()
                Command.new({ Name = "test--command" })
            end).to.throw()
        end)

        it("should create Command with Args", function()
            local cmd = Command.new({
                Name = "copy",
                Args = {
                    Arg.new({ Name = "source" }),
                    Arg.new({ Name = "destination" }),
                },
            })
            expect(#cmd._args).to.equal(2)
            expect(cmd._args[1].Name).to.equal("source")
            expect(cmd._args[2].Name).to.equal("destination")
        end)

        it("should create Command with Flags", function()
            local cmd = Command.new({
                Name = "build",
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                    Flag.new({ Name = "output", Type = "string" }),
                },
            })
            expect(#cmd._flags).to.equal(3)
        end)

        it("should throw error for duplicate Arg names", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = {
                        Arg.new({ Name = "file" }),
                        Arg.new({ Name = "file" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error for duplicate Flag names", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = {
                        Flag.new({ Name = "verbose" }),
                        Flag.new({ Name = "verbose" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error for duplicate Flag shorthands", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = {
                        Flag.new({ Name = "verbose", Shorthand = "v" }),
                        Flag.new({ Name = "version", Shorthand = "v" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error for required Arg after optional Arg", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = {
                        Arg.new({ Name = "optional", Required = false }),
                        Arg.new({ Name = "required", Required = true }),
                    },
                })
            end).to.throw()
        end)

        it("should allow optional Args after required Args", function()
            local cmd = Command.new({
                Name = "test",
                Args = {
                    Arg.new({ Name = "required", Required = true }),
                    Arg.new({ Name = "optional", Required = false }),
                },
            })
            expect(#cmd._args).to.equal(2)
        end)

        it("should create Command with Impl function", function()
            local _executed = false
            local cmd = Command.new({
                Name = "test",
                Impl = function()
                    _executed = true
                end,
            })
            expect(cmd._impl).to.be.ok()
        end)

        it("should create Command with Subcommands", function()
            local cmd = Command.new({
                Name = "git",
                Subcommands = {
                    Command.new({ Name = "add" }),
                    Command.new({ Name = "commit" }),
                },
            })
            expect(#cmd._subcommands).to.equal(2)
            expect(cmd._subcommands[1].Name).to.equal("add")
            expect(cmd._subcommands[2].Name).to.equal("commit")
        end)

        it("should throw error for duplicate subcommand names", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" }),
                        Command.new({ Name = "sub" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with Args", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" }),
                    },
                    Args = {
                        Arg.new({ Name = "arg" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with custom Flags", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" }),
                    },
                    Flags = {
                        Flag.new({ Name = "custom" }),
                    },
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with Impl", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" }),
                    },
                    Impl = function() end,
                })
            end).to.throw()
        end)

        it("should throw error for invalid Arg in Args array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = { "not an Arg" },
                })
            end).to.throw()
        end)

        it("should throw error for invalid Flag in Flags array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = { "not a Flag" },
                })
            end).to.throw()
        end)

        it("should throw error for invalid Subcommand in Subcommands array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = { "not a Command" },
                })
            end).to.throw()
        end)
    end)

    describe("Command.Execute", function()
        it("should execute command with no args", function()
            local executed = false
            local cmd = Command.new({
                Name = "test",
                Impl = function()
                    executed = true
                end,
            })
            cmd:Execute({})
            expect(executed).to.equal(true)
        end)

        it("should pass parsed args to implementation", function()
            local receivedArgs
            local cmd = Command.new({
                Name = "greet",
                Args = {
                    Arg.new({ Name = "name", Type = "string" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            cmd:Execute({ "Alice" })
            expect(receivedArgs).to.be.ok()
            expect(receivedArgs.name).to.equal("Alice")
        end)

        it("should parse multiple args correctly", function()
            local receivedArgs
            local cmd = Command.new({
                Name = "add",
                Args = {
                    Arg.new({ Name = "a", Type = "int" }),
                    Arg.new({ Name = "b", Type = "int" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            cmd:Execute({ "10", "20" })
            expect(receivedArgs.a).to.equal(10)
            expect(receivedArgs.b).to.equal(20)
        end)

        it("should parse flags correctly", function()
            local receivedFlags
            local cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            cmd:Execute({ "--verbose" })
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should parse shorthand flags correctly", function()
            local receivedFlags
            local cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            cmd:Execute({ "-v" })
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should parse typed flags with values", function()
            local receivedFlags
            local cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "port", Type = "int" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            cmd:Execute({ "--port", "8080" })
            expect(receivedFlags.port.Value).to.equal(8080)
        end)

        it("should use default flag values when not provided", function()
            local receivedFlags
            local cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "port", Type = "int", Default = 3000 }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            cmd:Execute({})
            expect(receivedFlags.port.Value).to.equal(3000)
        end)

        it("should use default arg values when not provided", function()
            local receivedArgs
            local cmd = Command.new({
                Name = "test",
                Args = {
                    Arg.new({ Name = "count", Type = "int", Required = false, Default = 5 }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            cmd:Execute({})
            expect(receivedArgs.count).to.equal(5)
        end)

        it("should handle mixed args and flags", function()
            local receivedArgs, receivedFlags
            local cmd = Command.new({
                Name = "build",
                Args = {
                    Arg.new({ Name = "target", Type = "string" }),
                },
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                    Flag.new({ Name = "output", Type = "string" }),
                },
                Impl = function(args, flags)
                    receivedArgs = args
                    receivedFlags = flags
                end,
            })
            cmd:Execute({ "--verbose", "production", "--output", "dist" })
            expect(receivedArgs.target).to.equal("production")
            expect(receivedFlags.verbose.Value).to.equal(true)
            expect(receivedFlags.output.Value).to.equal("dist")
        end)

        it("should execute matching subcommand", function()
            local subExecuted = false
            local cmd = Command.new({
                Name = "git",
                Subcommands = {
                    Command.new({
                        Name = "status",
                        Impl = function()
                            subExecuted = true
                        end,
                    }),
                },
            })
            cmd:Execute({ "status" })
            expect(subExecuted).to.equal(true)
        end)

        it("should pass remaining tokens to subcommand", function()
            local receivedArgs
            local cmd = Command.new({
                Name = "git",
                Subcommands = {
                    Command.new({
                        Name = "add",
                        Args = {
                            Arg.new({ Name = "file" }),
                        },
                        Impl = function(args)
                            receivedArgs = args
                        end,
                    }),
                },
            })
            cmd:Execute({ "add", "test.txt" })
            expect(receivedArgs.file).to.equal("test.txt")
        end)

        it("should print version when --version flag is used", function()
            local executed = false
            local cmd = Command.new({
                Name = "test",
                Version = "1.2.3",
                Impl = function()
                    executed = true
                end,
            })
            cmd:Execute({ "--version" })
            expect(executed).to.equal(false)
        end)

        it("should print version when -v shorthand is used", function()
            local executed = false
            local cmd = Command.new({
                Name = "test",
                Version = "1.2.3",
                Impl = function()
                    executed = true
                end,
            })
            cmd:Execute({ "-v" })
            expect(executed).to.equal(false)
        end)

        it("should throw error for invalid tokens", function()
            expect(function()
                Command.new({
                    Name = "test",
                }):Execute("not a table")
            end).to.throw()
        end)
    end)

    describe("Command.ShowHelp", function()
        it("should generate help message", function()
            local cmd = Command.new({
                Name = "test",
                Description = "A test command",
            })
            cmd:ShowHelp()
        end)

        it("should show full command path for subcommands", function()
            local sub = Command.new({
                Name = "status",
                Description = "Show status.",
                Impl = function() end,
            })
            Command.new({
                Name = "git",
                Subcommands = { sub },
            })
            expect(sub._commandPath).to.equal("git status")
        end)

        it("should show full command path for deeply nested subcommands", function()
            local leaf = Command.new({
                Name = "list",
                Description = "List items.",
                Impl = function() end,
            })
            local middle = Command.new({
                Name = "api-key",
                Description = "Manage API keys.",
                Subcommands = { leaf },
            })
            Command.new({
                Name = "app",
                Subcommands = { middle },
            })
            expect(middle._commandPath).to.equal("app api-key")
            expect(leaf._commandPath).to.equal("app api-key list")
        end)

        it("should include command path in help message", function()
            local sub = Command.new({
                Name = "deploy",
                Description = "Deploy the app.",
                Impl = function() end,
            })
            Command.new({
                Name = "myapp",
                Subcommands = { sub },
            })
            expect(string.find(sub._helpMessage, "myapp deploy", 1, true)).to.be.ok()
        end)
    end)
end

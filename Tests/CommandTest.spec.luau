--[[

CommandTest.spec

Tests for the Command class covering creation, execution,
subcommands, and help generation.

--]]

const Arg = require("../Source/Commandline/Arg")
const Chalk = require("@packages/Chalk")
const Command = require("../Source/Commandline/Command")
const Flag = require("../Source/Commandline/Flag")
const StringUtils = require("../Source/Commandline/Helpers/StringUtils")
const Style = require("../Source/Commandline/Terminal/Style")
const TypeUtils = require("../Source/Commandline/Helpers/TypeUtils")
const fs = require("@lune/fs")
const luau = require("@lune/luau")
const t = require("@packages/t")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const COMMAND_SOURCE = fs.readFile("Source/Commandline/Command.luau")
const function executeWithOutput(makeCommand: (typeof(Command)) -> Command.Command, tokens: { string }): string
    assert(t.callback(makeCommand))
    assert(t.array(t.string)(tokens))

    const output = {}
    const dependencies = {
        ["./Arg"] = Arg,
        ["./Flag"] = Flag,
        ["./Helpers/StringUtils"] = StringUtils,
        ["./Helpers/TypeUtils"] = TypeUtils,
        ["./Terminal/Style"] = Style,
        ["@packages/Chalk"] = Chalk,
        ["@packages/t"] = t,
    }
    const isolatedCommand = luau.load(COMMAND_SOURCE, {
        environment = {
            print = function(message)
                table.insert(output, `{message}\n`)
            end,
            require = function(path)
                return assert(dependencies[path], `Unexpected dependency "{path}".`)
            end,
        },
    })()
    makeCommand(isolatedCommand):Execute(tokens)
    return table.concat(output)
end

return function()
    describe("Command.new", function()
        it("should create a basic Command with required fields", function()
            const cmd = Command.new({
                Name = "test",
            })
            expect(cmd).to.be.ok()
            expect(cmd.Name).to.equal("test")
            expect(cmd.Description).to.equal("No description.")
            expect(cmd.Version).to.equal(nil)
        end)

        it("should create a Command with description and version", function()
            const cmd = Command.new({
                Name = "build",
                Description = "Build the project",
                Version = "1.0.0",
            })
            expect(cmd.Name).to.equal("build")
            expect(cmd.Description).to.equal("Build the project")
            expect(cmd.Version).to.equal("1.0.0")
        end)

        it("should automatically add help Flag", function()
            const cmd = Command.new({
                Name = "test",
            })
            expect(#cmd._flags).to.equal(1)
            expect(cmd._flags[1].Name).to.equal("help")
            expect(cmd._flags[1].Shorthand).to.equal("h")
        end)

        it("should not duplicate help Flag if already provided", function()
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
                Name = "test",
            })
            for _, flag in cmd._flags do
                expect(flag.Name).never.to.equal("version")
            end
        end)

        it("should not duplicate version Flag if already provided", function()
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
                Name = "TestCommand",
            })
            expect(cmd.Name).to.equal("testcommand")
        end)

        it("should allow kebab-case names with single hyphens", function()
            const cmd = Command.new({ Name = "test-command" })
            expect(cmd.Name).to.equal("test-command")

            const cmd2 = Command.new({ Name = "my-long-command-name" })
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
                Name = "test",
                Impl = function()
                    _executed = true
                end,
            })
            expect(cmd._impl).to.be.ok()
        end)

        it("should create Command with Subcommands", function()
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
            const cmd = Command.new({
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
                }):Execute("not a table" :: any)
            end).to.throw()
        end)
    end)

    describe("Command output", function()
        it("should print unlabelled red errors followed by one blank line before help", function()
            const cases = {
                { Message = "Missing required args.", Tokens = { "open" } },
                { Message = "Too many args provided.", Tokens = { "open", "one", "two" } },
                { Message = "Unknown flag --unknown.", Tokens = { "open", "--unknown" } },
                { Message = "Unknown flag -u.", Tokens = { "open", "-u" } },
                { Message = "Invalid shorthand flag format -bad.", Tokens = { "open", "-bad" } },
                { Message = "Invalid shorthand flag format --.", Tokens = { "open", "--" } },
                { Message = "flag --count requires a value.", Tokens = { "open", "--count" } },
                { Message = "flag -c requires a value.", Tokens = { "open", "-c" } },
                {
                    Message = 'flag --count - Unable to cast "bad" to int. Not a valid number.',
                    Tokens = { "open", "--count", "bad" },
                },
                {
                    Message = 'flag -c - Unable to cast "bad" to int. Not a valid number.',
                    Tokens = { "open", "-c", "bad" },
                },
                { Message = "Unknown subcommand unknown.", Tokens = { "unknown" } },
            }
            for _, case in cases do
                const output = executeWithOutput(function(command)
                    return command.new({
                        Name = "app",
                        Description = "Manage places.",
                        Subcommands = {
                            command.new({
                                Name = "open",
                                Description = "Open a place.",
                                Args = { Arg.new({ Name = "place" }) },
                                Flags = { Flag.new({ Name = "count", Shorthand = "c", Type = "int" }) },
                            }),
                        },
                    })
                end, case.Tokens)
                const lines = string.split(Style.strip(output), "\n")
                expect(lines[1]).to.equal(case.Message)
                expect(lines[2]).to.equal("")
                expect(lines[3]).to.equal(if case.Tokens[1] == "open" then "Open a place." else "app")
                expect(string.sub(output, 1, 5)).to.equal("\u{1b}[31m")
                expect(string.find(output, "[Error]", 1, true)).to.equal(nil)
            end
        end)

        it("should start explicit subcommand help at its description without a blank line", function()
            const output = executeWithOutput(function(command)
                return command.new({
                    Name = "app",
                    Subcommands = { command.new({ Name = "open", Description = "Open a place." }) },
                })
            end, { "open", "--help" })
            expect(string.split(Style.strip(output), "\n")[1]).to.equal("Open a place.")
        end)
    end)

    describe("Command.ShowHelp", function()
        it("should preserve root headings with and without a version and no opening blank line", function()
            for _, version in { "", "1.2.3" } do
                const cmd = Command.new({
                    Name = "app",
                    Description = "Manage places.",
                    Version = if version == "" then nil else version,
                })
                const lines = string.split(Style.strip(cmd._helpMessage), "\n")
                expect(lines[1]).to.equal(if version == "" then "app" else "app [1.2.3]")
                expect(lines[2]).to.equal("Manage places.")
                expect(lines[3]).to.equal("")
                expect(lines[4]).to.equal("[Usage]")
                expect(string.find(cmd._helpMessage, Chalk.bold("app"), 1, true)).to.equal(1)
            end
        end)

        it("should use the shared lighter gray for secondary help text", function()
            const cmd = Command.new({
                Name = "app",
                Description = "Manage places.",
                Version = "1.2.3",
                Subcommands = { Command.new({ Name = "open", Description = "Open a place." }) },
            })
            const muted = Chalk.hex(Style.DefaultTheme.Muted.Color :: string)
            expect(string.find(cmd._helpMessage, Chalk.italic(muted(cmd.Description)), 1, true)).to.be.ok()
            expect(string.find(cmd._helpMessage, Chalk.italic(muted("Open a place.")), 1, true)).to.be.ok()
            expect(string.find(cmd._helpMessage, "\u{1b}[90m", 1, true)).to.equal(nil)
        end)

        it("should generate help message", function()
            const cmd = Command.new({
                Name = "test",
                Description = "A test command",
            })
            cmd:ShowHelp()
        end)

        it("should show full command path for subcommands", function()
            const sub = Command.new({
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
            const leaf = Command.new({
                Name = "list",
                Description = "List items.",
                Impl = function() end,
            })
            const middle = Command.new({
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
            for _, command in { middle, leaf } do
                const lines = string.split(Style.strip(command._helpMessage), "\n")
                expect(lines[1]).to.equal(command.Description)
                expect(lines[2]).to.equal("")
                expect(lines[3]).to.equal("[Usage]")
                expect(string.find(lines[4], command._commandPath, 1, true)).to.be.ok()
                expect(string.find(command._helpMessage, Chalk.bold(command._commandPath), 1, true)).to.equal(nil)
            end
        end)

        it("should include command path in help message", function()
            const sub = Command.new({
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

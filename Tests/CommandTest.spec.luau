--[[

CommandTest.spec

Tests for the Command class covering creation, execution,
subcommands, and help generation.

--]]

const Arg = require("../Source/Commandline/Arg")
const Command = require("../Source/Commandline/Command")
const Flag = require("../Source/Commandline/Flag")
const Style = require("../Source/Commandline/Terminal/Style")
const Terminal = require("../Source/Commandline/Terminal")
const t = require("@packages/t")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

const CLOCK = {
    Elapsed = function()
        return 0
    end,
    LocalOffsetMinutes = function()
        return 0
    end,
    UnixMillis = function()
        return 0
    end
}
const function executeWithOutput(
    makeCommand: (typeof(Command)) -> Command.Command,
    tokens: { string },
    config: Terminal.Config?,
    afterExecute: ((Command.Command) -> ())?
): (string, string, string)
    assert(t.callback(makeCommand))
    assert(t.array(t.string)(tokens))
    assert(t.optional(t.table)(config))
    assert(t.optional(t.callback)(afterExecute))

    const combined = {}
    const output = {}
    const errors = {}
    const options: Terminal.Config = table.clone(config or {})
    options.Env = options.Env or {}
    options.Write = function(text)
        table.insert(combined, text)
        table.insert(output, text)
    end
    options.WriteError = function(text)
        table.insert(combined, text)
        table.insert(errors, text)
    end
    const previous = Terminal.default()
    const command = makeCommand(Command)
    Terminal.setDefault(Terminal.new(options))
    const ok, problem = pcall(function()
        command:Execute(tokens)
        if afterExecute then
            afterExecute(command)
        end
    end)
    Terminal.setDefault(previous)
    assert(ok, tostring(problem))
    return table.concat(combined), table.concat(output), table.concat(errors)
end

return function()
    describe("Command.new", function()
        it("should create a basic Command with required fields", function()
            const cmd = Command.new({
                Name = "test"
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
                Version = "1.0.0"
            })
            expect(cmd.Name).to.equal("build")
            expect(cmd.Description).to.equal("Build the project")
            expect(cmd.Version).to.equal("1.0.0")
        end)

        it("should automatically add help Flag", function()
            const cmd = Command.new({
                Name = "test"
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
                        Description = "Custom help"
                    })
                }
            })
            expect(#cmd._flags).to.equal(1)
        end)

        it("should automatically add version Flag when Version is set", function()
            const cmd = Command.new({
                Name = "test",
                Version = "1.0.0"
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
                Name = "test"
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
                        Description = "Custom version"
                    })
                }
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
                    Flag.new({ Name = "verbose", Shorthand = "v" })
                }
            })
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    expect(flag.Shorthand).to.equal(nil)
                end
            end
        end)

        it("should convert command name to lowercase", function()
            const cmd = Command.new({
                Name = "TestCommand"
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
                    Arg.new({ Name = "destination" })
                }
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
                    Flag.new({ Name = "output", Type = "string" })
                }
            })
            expect(#cmd._flags).to.equal(3)
        end)

        it("should throw error for duplicate Arg names", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = {
                        Arg.new({ Name = "file" }),
                        Arg.new({ Name = "file" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error for duplicate Flag names", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = {
                        Flag.new({ Name = "verbose" }),
                        Flag.new({ Name = "verbose" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error for duplicate Flag shorthands", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = {
                        Flag.new({ Name = "verbose", Shorthand = "v" }),
                        Flag.new({ Name = "version", Shorthand = "v" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error for required Arg after optional Arg", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = {
                        Arg.new({ Name = "optional", Required = false }),
                        Arg.new({ Name = "required", Required = true })
                    }
                })
            end).to.throw()
        end)

        it("should allow optional Args after required Args", function()
            const cmd = Command.new({
                Name = "test",
                Args = {
                    Arg.new({ Name = "required", Required = true }),
                    Arg.new({ Name = "optional", Required = false })
                }
            })
            expect(#cmd._args).to.equal(2)
        end)

        it("should create Command with Impl function", function()
            local _executed = false
            const cmd = Command.new({
                Name = "test",
                Impl = function()
                    _executed = true
                end
            })
            expect(cmd._impl).to.be.ok()
        end)

        it("should create Command with Subcommands", function()
            const cmd = Command.new({
                Name = "git",
                Subcommands = {
                    Command.new({ Name = "add" }),
                    Command.new({ Name = "commit" })
                }
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
                        Command.new({ Name = "sub" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with Args", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" })
                    },
                    Args = {
                        Arg.new({ Name = "arg" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with custom Flags", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" })
                    },
                    Flags = {
                        Flag.new({ Name = "custom" })
                    }
                })
            end).to.throw()
        end)

        it("should throw error when Subcommands are present with Impl", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = {
                        Command.new({ Name = "sub" })
                    },
                    Impl = function() end
                })
            end).to.throw()
        end)

        it("should throw error for invalid Arg in Args array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Args = { "not an Arg" }
                })
            end).to.throw()
        end)

        it("should throw error for invalid Flag in Flags array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Flags = { "not a Flag" }
                })
            end).to.throw()
        end)

        it("should throw error for invalid Subcommand in Subcommands array", function()
            expect(function()
                Command.new({
                    Name = "test",
                    Subcommands = { "not a Command" }
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
                end
            })
            cmd:Execute({})
            expect(executed).to.equal(true)
        end)

        it("should pass parsed args to implementation", function()
            local receivedArgs
            const cmd = Command.new({
                Name = "greet",
                Args = {
                    Arg.new({ Name = "name", Type = "string" })
                },
                Impl = function(args)
                    receivedArgs = args
                end
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
                    Arg.new({ Name = "b", Type = "int" })
                },
                Impl = function(args)
                    receivedArgs = args
                end
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
                    Flag.new({ Name = "verbose", Shorthand = "v" })
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end
            })
            cmd:Execute({ "--verbose" })
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should parse shorthand flags correctly", function()
            local receivedFlags
            const cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" })
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end
            })
            cmd:Execute({ "-v" })
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should parse typed flags with values", function()
            local receivedFlags
            const cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "port", Type = "int" })
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end
            })
            cmd:Execute({ "--port", "8080" })
            expect(receivedFlags.port.Value).to.equal(8080)
        end)

        it("should use default flag values when not provided", function()
            local receivedFlags
            const cmd = Command.new({
                Name = "test",
                Flags = {
                    Flag.new({ Name = "port", Type = "int", Default = 3000 })
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end
            })
            cmd:Execute({})
            expect(receivedFlags.port.Value).to.equal(3000)
        end)

        it("should use default arg values when not provided", function()
            local receivedArgs
            const cmd = Command.new({
                Name = "test",
                Args = {
                    Arg.new({ Name = "count", Type = "int", Required = false, Default = 5 })
                },
                Impl = function(args)
                    receivedArgs = args
                end
            })
            cmd:Execute({})
            expect(receivedArgs.count).to.equal(5)
        end)

        it("should handle mixed args and flags", function()
            local receivedArgs, receivedFlags
            const cmd = Command.new({
                Name = "build",
                Args = {
                    Arg.new({ Name = "target", Type = "string" })
                },
                Flags = {
                    Flag.new({ Name = "verbose", Shorthand = "v" }),
                    Flag.new({ Name = "output", Type = "string" })
                },
                Impl = function(args, flags)
                    receivedArgs = args
                    receivedFlags = flags
                end
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
                        end
                    })
                }
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
                            Arg.new({ Name = "file" })
                        },
                        Impl = function(args)
                            receivedArgs = args
                        end
                    })
                }
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
                end
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
                end
            })
            cmd:Execute({ "-v" })
            expect(executed).to.equal(false)
        end)

        it("should throw error for invalid tokens", function()
            expect(function()
                Command.new({
                    Name = "test"
                }):Execute("not a table" :: any)
            end).to.throw()
        end)
    end)

    describe("Command output", function()
        it("should render help against the current RGB theme after command construction", function()
            const theme = {
                Emphasis = { Bold = true, Color = "#112233" },
                HelpArgument = { Color = "#223344" },
                HelpCommand = { Color = "#334455" },
                HelpDescription = { Color = "#445566", Italic = true },
                HelpHeading = { Color = "#556677" },
                HelpVersion = { Color = "#667788" },
                Muted = { Color = "#778899" },
            }
            const output, _, errors = executeWithOutput(function(command)
                return command.new({
                    Name = "app",
                    Description = "Manage places.",
                    Version = "1.2.3",
                    Subcommands = { command.new({ Name = "open", Description = "Open a place." }) },
                })
            end, { "--help" }, { Color = true, Theme = theme })
            for key, text in
                {
                    Emphasis = "app",
                    HelpArgument = "subcommand",
                    HelpCommand = "open",
                    HelpDescription = "Manage places.",
                    HelpHeading = "Usage",
                    HelpVersion = "1.2.3",
                    Muted = "> ",
                }
            do
                expect(string.find(output, Style.paint((theme :: any)[key], text, true), 1, true) ~= nil).to.equal(true)
            end
            expect(errors).to.equal("")
        end)

        it("should honor disabled color and NO_COLOR throughout help and diagnostics", function()
            for _, config in
                {
                    { Color = false },
                    { Env = { NO_COLOR = "1" } },
                }
            do
                for _, tokens in { { "--help" }, { "--unknown" }, { "unknown" } } do
                    const output = executeWithOutput(function(command)
                        return command.new({
                            Name = "app",
                            Description = "Manage places.",
                            Version = "1.2.3",
                            Subcommands = { command.new({ Name = "open", Description = "Open a place." }) },
                        })
                    end, tokens, config)
                    expect(output).to.equal(Style.strip(output))
                end
            end
        end)

        it("should use RGB colors for every built-in help color and diagnostic", function()
            const output, help, errors = executeWithOutput(function(command)
                return command.new({ Name = "app", Description = "Manage places.", Version = "1.2.3" })
            end, { "--unknown" }, { Color = true })
            for _, code in
                { "38;2;122;162;247", "38;2;192;202;245", "38;2;224;175;104", "38;2;158;206;106", "38;2;168;168;168" }
            do
                expect(string.find(help, code, 1, true) ~= nil).to.equal(true)
            end
            expect(string.find(errors, "38;2;247;118;142", 1, true) ~= nil).to.equal(true)
            for _, code in
                { "2", "30", "31", "32", "33", "34", "35", "36", "37", "90", "91", "92", "93", "94", "95", "96", "97" }
            do
                expect(string.find(output, `\u{1b}[{code}m`, 1, true)).to.equal(nil)
            end
        end)

        it("should leave root and nested help untimestamped without wrapping or changing its layout", function()
            for _, timestamps in { false, true } do
                for _, nested in { false, true } do
                    const output, stdout, stderr = executeWithOutput(
                        function(command)
                            return command.new({
                                Name = "app",
                                Description = "Manage places without wrapping this long description.",
                                Version = "1.2.3",
                                Subcommands = {
                                    command.new({
                                        Name = "open",
                                        Description = "Open a place without wrapping this long description."
                                    })
                                }
                            })
                        end,
                        if nested then { "open", "--help" } else { "--help" },
                        {
                            Clock = CLOCK,
                            Color = false,
                            Columns = 12,
                            Env = if timestamps then { COMMANDLINE_TIMESTAMPS = "stopwatch" } else {}
                        }
                    )
                    const expected = if nested
                        then "Open a place without wrapping this long description.\n\n[Usage]\n> app open [flags...]\n\n[Flags]\n> -h, --help -- Show help message.\n"
                        else "app [1.2.3]\nManage places without wrapping this long description.\n\n[Usage]\n> app <subcommand>\n\n[Flags]\n> -h, --help -- Show help message.\n> -v, --version -- Show version.\n\n[Subcommands]\n> open -- Open a place without wrapping this long description.\n"
                    expect(Style.strip(output)).to.equal(expected)
                    expect(stdout).to.equal(output)
                    expect(stderr).to.equal("")
                    expect(output).to.equal(expected)
                end
            end
        end)

        it("should keep every help path untimestamped and retain timestamps on subsequent output", function()
            const cases = {
                { Tokens = {}, Nested = false },
                { Tokens = { "--help" }, Nested = false },
                { Tokens = { "-h" }, Nested = false },
                { Tokens = { "--unknown" }, Nested = false },
                { Tokens = { "unknown" }, Nested = false },
                { Tokens = { "group" }, Nested = true },
                { Tokens = { "group", "--help" }, Nested = true },
                { Tokens = { "group", "-h" }, Nested = true },
                { Tokens = { "group", "--unknown" }, Nested = true },
                { Tokens = { "group", "unknown" }, Nested = true },
                { Tokens = { "group", "open" }, Nested = true },
                { Tokens = { "group", "open", "one", "two" }, Nested = true }
            }
            for _, case in cases do
                const _, stdout, stderr = executeWithOutput(
                    function(command)
                        return command.new({
                            Name = "app",
                            Version = "1.2.3",
                            Subcommands = {
                                command.new({
                                    Name = "group",
                                    Description = "Manage places.",
                                    Subcommands = {
                                        command.new({
                                            Name = "open",
                                            Description = "Open a place.",
                                            Args = { Arg.new({ Name = "place" }) }
                                        })
                                    }
                                })
                            }
                        })
                    end,
                    case.Tokens,
                    {
                        Clock = CLOCK,
                        Color = false,
                        Columns = 0,
                        Timestamps = "stopwatch"
                    },
                    function(command)
                        command:ShowHelp()
                        command:Execute({ "--version" })
                        Terminal.default():Print("Ready.")
                        Terminal.default():PrintError("Later diagnostic.")
                    end
                )
                const help, later = string.match(Style.strip(stdout), "^(.-)(%[00:00%.000%] 1%.2%.3.*)$")
                assert(help and later)
                expect(string.find(help, "[00:00.000]", 1, true)).to.equal(nil)
                expect(string.sub(help, 1, 1)).to.equal(
                    if case.Tokens[2] == "open" then "O" elseif case.Nested then "M" else "a"
                )
                expect(later).to.equal("[00:00.000] 1.2.3\n[00:00.000] Ready.\n")
                for _, line in string.split(Style.strip(stderr), "\n") do
                    if line ~= "" then
                        expect(string.sub(line, 1, 12)).to.equal("[00:00.000] ")
                    end
                end
            end
        end)

        it("should print both version flags to stdout using the current default terminal", function()
            for _, timestamps in { false, true } do
                for _, flag in { "--version", "-v" } do
                    const output, stdout, stderr = executeWithOutput(function(command)
                        return command.new({ Name = "app", Version = "1.2.3" })
                    end, { flag }, {
                        Clock = CLOCK,
                        Color = false,
                        Timestamps = if timestamps then "stopwatch" else nil
                    })
                    expect(output).to.equal(if timestamps then "[00:00.000] 1.2.3\n" else "1.2.3\n")
                    expect(stdout).to.equal(output)
                    expect(stderr).to.equal("")
                end
            end
        end)

        it("should timestamp diagnostics on stderr and keep the separating blank line blank", function()
            const output, stdout, stderr = executeWithOutput(function(command)
                return command.new({ Name = "app", Description = "Manage places." })
            end, { "--unknown" }, {
                Clock = CLOCK,
                Color = false,
                Timestamps = "stopwatch"
            })
            expect(Style.strip(stderr)).to.equal("[00:00.000] Unknown flag --unknown.\n\n")
            expect(Style.strip(stdout):sub(1, 4)).to.equal("app\n")
            expect(string.find(stdout, "[00:00.000]", 1, true)).to.equal(nil)
            expect(output).to.equal(`{stderr}{stdout}`)
            expect(stderr).to.equal("[00:00.000] Unknown flag --unknown.\n\n")
        end)

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
                    Tokens = { "open", "--count", "bad" }
                },
                {
                    Message = 'flag -c - Unable to cast "bad" to int. Not a valid number.',
                    Tokens = { "open", "-c", "bad" }
                },
                { Message = "Unknown subcommand unknown.", Tokens = { "unknown" } }
            }
            for _, case in cases do
                const output, stdout, stderr = executeWithOutput(function(command)
                    return command.new({
                        Name = "app",
                        Description = "Manage places.",
                        Subcommands = {
                            command.new({
                                Name = "open",
                                Description = "Open a place.",
                                Args = { Arg.new({ Name = "place" }) },
                                Flags = { Flag.new({ Name = "count", Shorthand = "c", Type = "int" }) }
                            })
                        }
                    })
                end, case.Tokens)
                const lines = string.split(Style.strip(output), "\n")
                expect(Style.strip(stderr)).to.equal(`{case.Message}\n\n`)
                expect(output).to.equal(`{stderr}{stdout}`)
                expect(lines[1]).to.equal(case.Message)
                expect(lines[2]).to.equal("")
                expect(lines[3]).to.equal(if case.Tokens[1] == "open" then "Open a place." else "app")
                expect(string.sub(output, 1, #"\u{1b}[38;2;247;118;142m")).to.equal("\u{1b}[38;2;247;118;142m")
                expect(string.find(output, "[Error]", 1, true)).to.equal(nil)
            end
        end)

        it("should start explicit subcommand help at its description without a blank line", function()
            const output = executeWithOutput(function(command)
                return command.new({
                    Name = "app",
                    Subcommands = { command.new({ Name = "open", Description = "Open a place." }) }
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
                    Version = if version == "" then nil else version
                })
                const lines = string.split(Style.strip(cmd:_makeHelpMessage()), "\n")
                expect(lines[1]).to.equal(if version == "" then "app" else "app [1.2.3]")
                expect(lines[2]).to.equal("Manage places.")
                expect(lines[3]).to.equal("")
                expect(lines[4]).to.equal("[Usage]")
                expect(string.find(cmd:_makeHelpMessage(), Terminal.default():Paint("Emphasis", "app"), 1, true)).to.equal(
                    1
                )
            end
        end)

        it("should use the shared lighter gray for secondary help text", function()
            const cmd = Command.new({
                Name = "app",
                Description = "Manage places.",
                Version = "1.2.3",
                Subcommands = { Command.new({ Name = "open", Description = "Open a place." }) }
            })
            const terminal = Terminal.default()
            expect(string.find(cmd:_makeHelpMessage(), terminal:Paint("HelpDescription", cmd.Description), 1, true)).to.be.ok()
            expect(string.find(cmd:_makeHelpMessage(), terminal:Paint("HelpDescription", "Open a place."), 1, true)).to.be.ok()
            expect(string.find(cmd:_makeHelpMessage(), "\u{1b}[90m", 1, true)).to.equal(nil)
        end)

        it("should generate help message", function()
            const cmd = Command.new({
                Name = "test",
                Description = "A test command"
            })
            cmd:ShowHelp()
        end)

        it("should show full command path for subcommands", function()
            const sub = Command.new({
                Name = "status",
                Description = "Show status.",
                Impl = function() end
            })
            Command.new({
                Name = "git",
                Subcommands = { sub }
            })
            expect(sub._commandPath).to.equal("git status")
        end)

        it("should show full command path for deeply nested subcommands", function()
            const leaf = Command.new({
                Name = "list",
                Description = "List items.",
                Impl = function() end
            })
            const middle = Command.new({
                Name = "api-key",
                Description = "Manage API keys.",
                Subcommands = { leaf }
            })
            Command.new({
                Name = "app",
                Subcommands = { middle }
            })
            expect(middle._commandPath).to.equal("app api-key")
            expect(leaf._commandPath).to.equal("app api-key list")
            for _, command in { middle, leaf } do
                const lines = string.split(Style.strip(command:_makeHelpMessage()), "\n")
                expect(lines[1]).to.equal(command.Description)
                expect(lines[2]).to.equal("")
                expect(lines[3]).to.equal("[Usage]")
                expect(string.find(lines[4], command._commandPath, 1, true)).to.be.ok()
                expect(
                    string.find(
                        command:_makeHelpMessage(),
                        Terminal.default():Paint("Emphasis", command._commandPath),
                        1,
                        true
                    )
                ).to.equal(nil)
            end
        end)

        it("should include command path in help message", function()
            const sub = Command.new({
                Name = "deploy",
                Description = "Deploy the app.",
                Impl = function() end
            })
            Command.new({
                Name = "myapp",
                Subcommands = { sub }
            })
            expect(string.find(sub:_makeHelpMessage(), "myapp deploy", 1, true)).to.be.ok()
        end)
    end)
end

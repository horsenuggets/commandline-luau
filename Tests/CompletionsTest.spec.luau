--[[

CompletionsTest.spec

Tests for shell completion script generation. Verifies that bash, zsh, fish,
and PowerShell completion scripts are generated correctly from command
definitions.

--]]

const Commandline = require("@commandline")

const Command = Commandline.Command
const Completions = Commandline.Completions
const Flag = Commandline.Flag

const function makeSimpleCommand(): any
    return Command.new({
        Name = "mytool",
        Description = "A test tool.",
        Version = "1.0.0",
        Flags = {
            Flag.new({ Name = "verbose", Shorthand = "v", Description = "Enable verbose output." }),
            Flag.new({ Name = "output", Shorthand = "o", Type = "string", Description = "Output file." }),
        },
        Impl = function() end,
    })
end

const function makeCommandWithSubcommands(): any
    return Command.new({
        Name = "mytool",
        Description = "A test tool.",
        Version = "1.0.0",
        Subcommands = {
            Command.new({
                Name = "build",
                Description = "Build the project.",
                Flags = {
                    Flag.new({ Name = "release", Shorthand = "r", Description = "Build in release mode." }),
                    Flag.new({
                        Name = "target",
                        Shorthand = "t",
                        Type = "string",
                        Description = "Target platform.",
                    }),
                },
                Impl = function() end,
            }),
            Command.new({
                Name = "run",
                Description = "Run the project.",
                Flags = {
                    Flag.new({
                        Name = "port",
                        Shorthand = "p",
                        Type = "int",
                        Description = "Server port.",
                    }),
                },
                Impl = function() end,
            }),
            Command.new({
                Name = "init",
                Description = "Initialize a new project.",
                Impl = function() end,
            }),
        },
    })
end

return function()
    describe("generate", function()
        it("should keep nested fallbacks attached to the executable", function()
            const cmd = Command.new({
                Name = "outer",
                Description = "Nested test tool.",
                Subcommands = { makeCommandWithSubcommands() },
            })
            const fish = Completions.fish(cmd)
            expect(
                string.find(
                    fish,
                    'complete -c outer -n "__fish_seen_subcommand_from mytool; and not __fish_seen_subcommand_from build run init" -a "build"',
                    1,
                    true
                )
            ).to.be.ok()
            expect(string.find(fish, "complete -c mytool", 1, true)).to.equal(nil)
            expect(
                string.find(
                    fish,
                    "__fish_seen_subcommand_from mytool; and __fish_seen_subcommand_from build; and __outer_no_matches",
                    1,
                    true
                )
            ).to.be.ok()
            const zsh = Completions.zsh(cmd)
            expect(string.find(zsh, "[Target platform.]:value:", 1, true)).to.be.ok()
            expect(string.find(zsh, "        _files", 1, true)).to.be.ok()
        end)

        it("should throw for unsupported shell", function()
            const cmd = makeSimpleCommand()
            expect(function()
                Completions.generate(cmd, "nushell")
            end).to.throw()
        end)

        it("should accept all supported shells", function()
            const cmd = makeSimpleCommand()
            expect(Completions.generate(cmd, "bash")).to.be.ok()
            expect(Completions.generate(cmd, "fish")).to.be.ok()
            expect(Completions.generate(cmd, "powershell")).to.be.ok()
            expect(Completions.generate(cmd, "pwsh")).to.be.ok()
            expect(Completions.generate(cmd, "zsh")).to.be.ok()
        end)
    end)

    describe("bash", function()
        it("should continue to leaf flags when root flags have no matches", function()
            const output = Completions.bash(makeCommandWithSubcommands())
            expect(string.find(output, "if (( ${#COMPREPLY[@]} > 0 )); then\n            return\n        fi", 1, true)).to.be.ok()
            expect(string.find(output, "complete -o default -F _mytool mytool", 1, true)).to.be.ok()
        end)

        it("should generate a valid bash completion function", function()
            const cmd = makeSimpleCommand()
            const output = Completions.bash(cmd)
            expect(string.find(output, "_mytool()")).to.be.ok()
            expect(string.find(output, "complete %-o default %-F _mytool mytool")).to.be.ok()
        end)

        it("should include flag names", function()
            const cmd = makeSimpleCommand()
            const output = Completions.bash(cmd)
            expect(string.find(output, "%-%-verbose")).to.be.ok()
            expect(string.find(output, "%-%-output")).to.be.ok()
            expect(string.find(output, "%-%-help")).to.be.ok()
            expect(string.find(output, "%-%-version")).to.be.ok()
        end)

        it("should include subcommand names", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.bash(cmd)
            expect(string.find(output, "build")).to.be.ok()
            expect(string.find(output, "run")).to.be.ok()
            expect(string.find(output, "init")).to.be.ok()
        end)

        it("should include subcommand flags", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.bash(cmd)
            expect(string.find(output, "%-%-release")).to.be.ok()
            expect(string.find(output, "%-%-target")).to.be.ok()
            expect(string.find(output, "%-%-port")).to.be.ok()
        end)
    end)

    describe("zsh", function()
        it("should support path values for long-only typed options", function()
            const cmd = Command.new({
                Name = "mytool",
                Description = "A test tool.",
                Flags = { Flag.new({ Name = "output", Type = "string", Description = "Output file." }) },
                Impl = function() end,
            })
            const output = Completions.zsh(cmd)
            expect(string.find(output, "'--output[Output file.]:value:_files'", 1, true)).to.be.ok()
            expect(string.find(output, "--output=", 1, true)).to.equal(nil)
        end)

        it("should fall back to native paths only when no matches were added", function()
            for _, cmd in { makeSimpleCommand(), makeCommandWithSubcommands() } do
                const output = Completions.zsh(cmd)
                expect(string.find(output, "local matches_before=$compstate[nmatches]", 1, true)).to.be.ok()
                expect(
                    string.find(
                        output,
                        "if (( compstate[nmatches] == matches_before )); then\n        _files\n    fi",
                        1,
                        true
                    )
                ).to.be.ok()
                expect(string.find(output, "'*:arg:_files'", 1, true)).to.be.ok()
            end
        end)

        it("should parse typed leaf options before falling back to paths", function()
            const output = Completions.zsh(makeCommandWithSubcommands())
            expect(string.find(output, "[Target platform.]:value:", 1, true)).to.be.ok()
            expect(string.find(output, "[Server port.]:value:", 1, true)).to.be.ok()
        end)

        it("should generate a valid zsh completion function", function()
            const cmd = makeSimpleCommand()
            const output = Completions.zsh(cmd)
            expect(string.find(output, "#compdef mytool")).to.be.ok()
            expect(string.find(output, "_mytool()")).to.be.ok()
            expect(string.find(output, '_mytool "$@"')).to.be.ok()
        end)

        it("should include flag specs with shorthands", function()
            const cmd = makeSimpleCommand()
            const output = Completions.zsh(cmd)
            expect(string.find(output, "%-v")).to.be.ok()
            expect(string.find(output, "%-%-verbose")).to.be.ok()
            expect(string.find(output, "%-o")).to.be.ok()
            expect(string.find(output, "%-%-output")).to.be.ok()
        end)

        it("should include subcommand descriptions", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.zsh(cmd)
            expect(string.find(output, "build:Build the project")).to.be.ok()
            expect(string.find(output, "run:Run the project")).to.be.ok()
            expect(string.find(output, "init:Initialize a new project")).to.be.ok()
        end)

        it("should use compadd for subcommand completion", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.zsh(cmd)
            expect(string.find(output, "compadd %-V unsorted %-l %-d display_cmds %-a cmd_names")).to.be.ok()
        end)

        it("should complete native paths for typed flag values", function()
            const cmd = makeSimpleCommand()
            const output = Completions.zsh(cmd)
            expect(string.find(output, "{-o,--output}'[Output file.]:value:_files'", 1, true)).to.be.ok()
            expect(string.find(output, "--output=", 1, true)).to.equal(nil)
        end)
    end)

    describe("fish", function()
        it("should scope repeated leaf names to their ancestor branches", function()
            const branches = {}
            for _, name in { "a", "b" } do
                table.insert(
                    branches,
                    Command.new({
                        Name = name,
                        Description = "A command group.",
                        Subcommands = {
                            Command.new({
                                Name = "build",
                                Description = "Build a branch.",
                                Flags = {
                                    Flag.new({
                                        Name = name .. "-output",
                                        Type = "string",
                                        Description = "Output file.",
                                    }),
                                },
                                Impl = function() end,
                            }),
                        },
                    })
                )
            end
            const cmd = Command.new({ Name = "outer", Description = "Test tool.", Subcommands = branches })
            const output = Completions.fish(cmd)
            for _, name in { "a", "b" } do
                const condition = `__fish_seen_subcommand_from {name}; and __fish_seen_subcommand_from build`
                expect(string.find(output, `-l {name}-output -d 'Output file.' -n "{condition}" -x`, 1, true)).to.be.ok()
                expect(string.find(output, `-n "{condition}; and __outer_no_matches" -r -F`, 1, true)).to.be.ok()
                expect(
                    string.find(
                        output,
                        `-n "__fish_seen_subcommand_from {name}; and not __fish_seen_subcommand_from build" -a "build"`,
                        1,
                        true
                    )
                ).to.be.ok()
            end
        end)

        it("should use a valid recursion guard for hyphenated command names", function()
            const cmd = makeSimpleCommand()
            cmd.Name = "my-tool"
            const output = Completions.fish(cmd)
            expect(string.find(output, "function __my-tool_no_matches", 1, true)).to.be.ok()
            expect(string.find(output, "set -g __commandline_completion_probing 1", 1, true)).to.be.ok()
            expect(string.find(output, "set -g __my-tool", 1, true)).to.equal(nil)
        end)

        it("should enable native files only when custom completion has no matches", function()
            const output = Completions.fish(makeSimpleCommand())
            expect(string.find(output, 'complete -c mytool -F -n "__mytool_no_matches"', 1, true)).to.be.ok()
            expect(string.find(output, "set -q __commandline_completion_probing; and return 1", 1, true)).to.be.ok()
            expect(string.find(output, "complete -C (commandline -cp)", 1, true)).to.be.ok()
            expect(string.find(output, "set -e __commandline_completion_probing", 1, true)).to.be.ok()
            expect(string.find(output, "test (count $matches) -eq 0", 1, true)).to.be.ok()
        end)

        it("should include flag long names", function()
            const cmd = makeSimpleCommand()
            const output = Completions.fish(cmd)
            expect(string.find(output, "%-l verbose")).to.be.ok()
            expect(string.find(output, "%-l output")).to.be.ok()
        end)

        it("should include flag shorthands", function()
            const cmd = makeSimpleCommand()
            const output = Completions.fish(cmd)
            expect(string.find(output, "%-s v")).to.be.ok()
            expect(string.find(output, "%-s o")).to.be.ok()
        end)

        it("should include flag descriptions", function()
            const cmd = makeSimpleCommand()
            const output = Completions.fish(cmd)
            expect(string.find(output, "Enable verbose output")).to.be.ok()
            expect(string.find(output, "Output file")).to.be.ok()
        end)

        it("should probe typed options without files and enable their native fallback", function()
            const output = Completions.fish(makeSimpleCommand())
            expect(string.find(output, "-l output -s o -d 'Output file.' -x", 1, true)).to.be.ok()
            expect(string.find(output, '-n "__mytool_no_matches" -r -F', 1, true)).to.be.ok()
            for _, line in string.split(output, "\n") do
                if string.find(line, "-l verbose", 1, true) then
                    expect(string.find(line, "-r", 1, true)).to.equal(nil)
                    expect(string.find(line, "-x", 1, true)).to.equal(nil)
                    expect(string.find(line, "-F", 1, true)).to.equal(nil)
                end
            end
        end)

        it("should retain subcommand conditions on typed option fallbacks", function()
            const output = Completions.fish(makeCommandWithSubcommands())
            expect(
                string.find(output, '-n "__fish_seen_subcommand_from build; and __mytool_no_matches" -r -F', 1, true)
            ).to.be.ok()
            expect(string.find(output, '-n "__fish_seen_subcommand_from run; and __mytool_no_matches" -r -F', 1, true)).to.be.ok()
        end)

        it("should include subcommand completions with conditions", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.fish(cmd)
            expect(string.find(output, "__fish_use_subcommand")).to.be.ok()
            expect(string.find(output, '%-a "build"')).to.be.ok()
            expect(string.find(output, '%-a "run"')).to.be.ok()
            expect(string.find(output, "__fish_seen_subcommand_from build")).to.be.ok()
            expect(string.find(output, "__fish_seen_subcommand_from run")).to.be.ok()
        end)
    end)

    describe("powershell", function()
        it("should register an argument completer", function()
            const cmd = makeSimpleCommand()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "Register%-ArgumentCompleter %-CommandName mytool")).to.be.ok()
        end)

        it("should include flag names", function()
            const cmd = makeSimpleCommand()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "%-%-verbose")).to.be.ok()
            expect(string.find(output, "%-%-output")).to.be.ok()
        end)

        it("should include subcommand names", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "build")).to.be.ok()
            expect(string.find(output, "run")).to.be.ok()
            expect(string.find(output, "init")).to.be.ok()
        end)

        it("should include subcommand flags", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "%-%-release")).to.be.ok()
            expect(string.find(output, "%-%-target")).to.be.ok()
            expect(string.find(output, "%-%-port")).to.be.ok()
        end)

        it("should separate flags from subcommands by context", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "$wordToComplete %-like '%-%*'")).to.be.ok()
        end)

        it("should not include shorthand flags", function()
            const cmd = makeCommandWithSubcommands()
            const output = Completions.powershell(cmd)
            expect(string.find(output, "'%-r'")).to.equal(nil)
            expect(string.find(output, "'%-t'")).to.equal(nil)
            expect(string.find(output, "'%-p'")).to.equal(nil)
        end)
    end)
end

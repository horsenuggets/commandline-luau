--[[

CompletionsTest.spec

Tests for shell completion script generation. Verifies that bash, zsh, and fish
completion scripts are generated correctly from command definitions.

--]]

local Commandline = require("@commandline")

local Command = Commandline.Command
local Completions = Commandline.Completions
local Flag = Commandline.Flag

local function makeSimpleCommand(): any
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

local function makeCommandWithSubcommands(): any
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
        it("should throw for unsupported shell", function()
            local cmd = makeSimpleCommand()
            expect(function()
                Completions.generate(cmd, "powershell")
            end).to.throw()
        end)

        it("should accept bash, zsh, and fish", function()
            local cmd = makeSimpleCommand()
            expect(Completions.generate(cmd, "bash")).to.be.ok()
            expect(Completions.generate(cmd, "zsh")).to.be.ok()
            expect(Completions.generate(cmd, "fish")).to.be.ok()
        end)
    end)

    describe("bash", function()
        it("should generate a valid bash completion function", function()
            local cmd = makeSimpleCommand()
            local output = Completions.bash(cmd)
            expect(string.find(output, "_mytool()")).to.be.ok()
            expect(string.find(output, "complete %-o default %-F _mytool mytool")).to.be.ok()
        end)

        it("should include flag names", function()
            local cmd = makeSimpleCommand()
            local output = Completions.bash(cmd)
            expect(string.find(output, "%-%-verbose")).to.be.ok()
            expect(string.find(output, "%-%-output")).to.be.ok()
            expect(string.find(output, "%-%-help")).to.be.ok()
            expect(string.find(output, "%-%-version")).to.be.ok()
        end)

        it("should include subcommand names", function()
            local cmd = makeCommandWithSubcommands()
            local output = Completions.bash(cmd)
            expect(string.find(output, "build")).to.be.ok()
            expect(string.find(output, "run")).to.be.ok()
            expect(string.find(output, "init")).to.be.ok()
        end)

        it("should include subcommand flags", function()
            local cmd = makeCommandWithSubcommands()
            local output = Completions.bash(cmd)
            expect(string.find(output, "%-%-release")).to.be.ok()
            expect(string.find(output, "%-%-target")).to.be.ok()
            expect(string.find(output, "%-%-port")).to.be.ok()
        end)
    end)

    describe("zsh", function()
        it("should generate a valid zsh completion function", function()
            local cmd = makeSimpleCommand()
            local output = Completions.zsh(cmd)
            expect(string.find(output, "#compdef mytool")).to.be.ok()
            expect(string.find(output, "_mytool()")).to.be.ok()
            expect(string.find(output, '_mytool "$@"')).to.be.ok()
        end)

        it("should include flag specs with shorthands", function()
            local cmd = makeSimpleCommand()
            local output = Completions.zsh(cmd)
            expect(string.find(output, "%-v")).to.be.ok()
            expect(string.find(output, "%-%-verbose")).to.be.ok()
            expect(string.find(output, "%-o")).to.be.ok()
            expect(string.find(output, "%-%-output")).to.be.ok()
        end)

        it("should include subcommand descriptions", function()
            local cmd = makeCommandWithSubcommands()
            local output = Completions.zsh(cmd)
            expect(string.find(output, "build:Build the project")).to.be.ok()
            expect(string.find(output, "run:Run the project")).to.be.ok()
            expect(string.find(output, "init:Initialize a new project")).to.be.ok()
        end)

        it("should use _describe for subcommand completion", function()
            local cmd = makeCommandWithSubcommands()
            local output = Completions.zsh(cmd)
            expect(string.find(output, "_describe 'command' commands")).to.be.ok()
        end)

        it("should include typed flag value placeholder", function()
            local cmd = makeSimpleCommand()
            local output = Completions.zsh(cmd)
            -- --output is typed (string), should have :value:
            expect(string.find(output, "%[Output file%.%]:value:")).to.be.ok()
        end)
    end)

    describe("fish", function()
        it("should generate fish completions with disable-default", function()
            local cmd = makeSimpleCommand()
            local output = Completions.fish(cmd)
            expect(string.find(output, "complete %-c mytool %-f")).to.be.ok()
        end)

        it("should include flag long names", function()
            local cmd = makeSimpleCommand()
            local output = Completions.fish(cmd)
            expect(string.find(output, "%-l verbose")).to.be.ok()
            expect(string.find(output, "%-l output")).to.be.ok()
        end)

        it("should include flag shorthands", function()
            local cmd = makeSimpleCommand()
            local output = Completions.fish(cmd)
            expect(string.find(output, "%-s v")).to.be.ok()
            expect(string.find(output, "%-s o")).to.be.ok()
        end)

        it("should include flag descriptions", function()
            local cmd = makeSimpleCommand()
            local output = Completions.fish(cmd)
            expect(string.find(output, "Enable verbose output")).to.be.ok()
            expect(string.find(output, "Output file")).to.be.ok()
        end)

        it("should use -r for typed flags", function()
            local cmd = makeSimpleCommand()
            local output = Completions.fish(cmd)
            -- --output is typed, should have -r (requires argument)
            -- --verbose is boolean, should not have -r
            local lines = string.split(output, "\n")
            for _, line in lines do
                if string.find(line, "%-l output") then
                    expect(string.find(line, "%-r")).to.be.ok()
                end
                if string.find(line, "%-l verbose") and not string.find(line, "output") then
                    expect(string.find(line, "%-r")).to.equal(nil)
                end
            end
        end)

        it("should include subcommand completions with conditions", function()
            local cmd = makeCommandWithSubcommands()
            local output = Completions.fish(cmd)
            expect(string.find(output, "__fish_use_subcommand")).to.be.ok()
            expect(string.find(output, '%-a "build"')).to.be.ok()
            expect(string.find(output, '%-a "run"')).to.be.ok()
            expect(string.find(output, "__fish_seen_subcommand_from build")).to.be.ok()
            expect(string.find(output, "__fish_seen_subcommand_from run")).to.be.ok()
        end)
    end)
end

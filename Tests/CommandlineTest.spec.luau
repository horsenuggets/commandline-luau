local Commandline = require("../Source/Commandline")

return function()
    beforeEach(function()
        Commandline._commands = {}
    end)

    afterEach(function()
        Commandline._commands = {}
    end)

    describe("Commandline module exports", function()
        it("should export Arg class", function()
            expect(Commandline.Arg).to.be.ok()
            expect(typeof(Commandline.Arg.new)).to.equal("function")
        end)

        it("should export Command class", function()
            expect(Commandline.Command).to.be.ok()
            expect(typeof(Commandline.Command.new)).to.equal("function")
        end)

        it("should export Flag class", function()
            expect(Commandline.Flag).to.be.ok()
            expect(typeof(Commandline.Flag.new)).to.equal("function")
        end)
    end)

    describe("Commandline.registerCommand", function()
        it("should register a valid command", function()
            local cmd = Commandline.Command.new({
                Name = "test",
            })
            Commandline.registerCommand(cmd)
            expect(Commandline._commands["test"]).to.equal(cmd)
        end)

        it("should register multiple commands", function()
            local cmd1 = Commandline.Command.new({ Name = "build" })
            local cmd2 = Commandline.Command.new({ Name = "test" })

            Commandline.registerCommand(cmd1)
            Commandline.registerCommand(cmd2)

            expect(Commandline._commands["build"]).to.equal(cmd1)
            expect(Commandline._commands["test"]).to.equal(cmd2)
        end)

        it("should throw error for duplicate command names", function()
            local cmd1 = Commandline.Command.new({ Name = "test" })
            local cmd2 = Commandline.Command.new({ Name = "test" })

            Commandline.registerCommand(cmd1)

            expect(function()
                Commandline.registerCommand(cmd2)
            end).to.throw()
        end)

        it("should throw error for invalid command", function()
            expect(function()
                Commandline.registerCommand("not a command")
            end).to.throw()

            expect(function()
                Commandline.registerCommand({ Name = "fake" })
            end).to.throw()
        end)
    end)

    describe("Commandline.execute", function()
        it("should execute a registered command", function()
            local executed = false
            local cmd = Commandline.Command.new({
                Name = "test",
                Impl = function()
                    executed = true
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("test")
            expect(executed).to.equal(true)
        end)

        it("should pass arguments to command", function()
            local receivedArgs
            local cmd = Commandline.Command.new({
                Name = "greet",
                Args = {
                    Commandline.Arg.new({ Name = "name" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("greet Alice")
            expect(receivedArgs.name).to.equal("Alice")
        end)

        it("should handle quoted arguments", function()
            local receivedArgs
            local cmd = Commandline.Command.new({
                Name = "echo",
                Args = {
                    Commandline.Arg.new({ Name = "message" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute('echo "Hello World"')
            expect(receivedArgs.message).to.equal("Hello World")
        end)

        it("should handle flags", function()
            local receivedFlags
            local cmd = Commandline.Command.new({
                Name = "build",
                Flags = {
                    Commandline.Flag.new({ Name = "verbose", Shorthand = "v" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("build --verbose")
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should handle shorthand flags", function()
            local receivedFlags
            local cmd = Commandline.Command.new({
                Name = "build",
                Flags = {
                    Commandline.Flag.new({ Name = "verbose", Shorthand = "v" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("build -v")
            expect(receivedFlags.verbose.Value).to.equal(true)
        end)

        it("should handle typed flags with values", function()
            local receivedFlags
            local cmd = Commandline.Command.new({
                Name = "serve",
                Flags = {
                    Commandline.Flag.new({ Name = "port", Type = "int" }),
                },
                Impl = function(args, flags)
                    receivedFlags = flags
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("serve --port 8080")
            expect(receivedFlags.port.Value).to.equal(8080)
        end)

        it("should handle complex command strings", function()
            local receivedArgs, receivedFlags
            local cmd = Commandline.Command.new({
                Name = "deploy",
                Args = {
                    Commandline.Arg.new({ Name = "environment" }),
                },
                Flags = {
                    Commandline.Flag.new({ Name = "verbose", Shorthand = "v" }),
                    Commandline.Flag.new({ Name = "region", Type = "string" }),
                },
                Impl = function(args, flags)
                    receivedArgs = args
                    receivedFlags = flags
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute('deploy production --verbose --region "us-east-1"')
            expect(receivedArgs.environment).to.equal("production")
            expect(receivedFlags.verbose.Value).to.equal(true)
            expect(receivedFlags.region.Value).to.equal("us-east-1")
        end)

        it("should execute subcommands", function()
            local subExecuted = false
            local cmd = Commandline.Command.new({
                Name = "git",
                Subcommands = {
                    Commandline.Command.new({
                        Name = "status",
                        Impl = function()
                            subExecuted = true
                        end,
                    }),
                },
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("git status")
            expect(subExecuted).to.equal(true)
        end)

        it("should throw error for unknown command", function()
            expect(function()
                Commandline.execute("unknown")
            end).to.throw()
        end)

        it("should throw error for invalid command string", function()
            expect(function()
                Commandline.execute(123)
            end).to.throw()

            expect(function()
                Commandline.execute({ "not", "a", "string" })
            end).to.throw()
        end)

        it("should throw error for empty command string", function()
            expect(function()
                Commandline.execute("")
            end).to.throw()

            expect(function()
                Commandline.execute("   ")
            end).to.throw()
        end)

        it("should throw error for non-alphanumeric command names", function()
            expect(function()
                Commandline.execute("test-command")
            end).to.throw()

            expect(function()
                Commandline.execute("test_command")
            end).to.throw()
        end)

        it("should handle commands with multiple arguments", function()
            local receivedArgs
            local cmd = Commandline.Command.new({
                Name = "add",
                Args = {
                    Commandline.Arg.new({ Name = "a", Type = "int" }),
                    Commandline.Arg.new({ Name = "b", Type = "int" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("add 10 20")
            expect(receivedArgs.a).to.equal(10)
            expect(receivedArgs.b).to.equal(20)
        end)

        it("should handle commands with optional arguments", function()
            local receivedArgs
            local cmd = Commandline.Command.new({
                Name = "test",
                Args = {
                    Commandline.Arg.new({ Name = "required" }),
                    Commandline.Arg.new({
                        Name = "optional",
                        Required = false,
                        Default = "default",
                    }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute("test value")
            expect(receivedArgs.required).to.equal("value")
            expect(receivedArgs.optional).to.equal("default")
        end)

        it("should handle escaped characters in command string", function()
            local receivedArgs
            local cmd = Commandline.Command.new({
                Name = "echo",
                Args = {
                    Commandline.Arg.new({ Name = "message" }),
                },
                Impl = function(args)
                    receivedArgs = args
                end,
            })
            Commandline.registerCommand(cmd)
            Commandline.execute('echo "Message with \\"quotes\\""')
            expect(receivedArgs.message).to.equal('Message with "quotes"')
        end)

        it("should throw error for tokenization errors", function()
            local cmd = Commandline.Command.new({
                Name = "test",
                Impl = function() end,
            })
            Commandline.registerCommand(cmd)

            expect(function()
                Commandline.execute('test "unclosed quote')
            end).to.throw()

            expect(function()
                Commandline.execute("test trailing\\")
            end).to.throw()
        end)
    end)

    describe("Commandline integration tests", function()
        it("should support a complete command-line application workflow", function()
            local buildExecuted = false
            local testExecuted = false

            local buildCmd = Commandline.Command.new({
                Name = "build",
                Description = "Build the project",
                Args = {
                    Commandline.Arg.new({ Name = "target" }),
                },
                Flags = {
                    Commandline.Flag.new({
                        Name = "production",
                        Shorthand = "p",
                    }),
                },
                Impl = function(args, flags)
                    buildExecuted = true
                    expect(args.target).to.equal("web")
                    expect(flags.production.Value).to.equal(true)
                end,
            })

            local testCmd = Commandline.Command.new({
                Name = "test",
                Description = "Run tests",
                Flags = {
                    Commandline.Flag.new({
                        Name = "coverage",
                        Shorthand = "c",
                    }),
                },
                Impl = function(args, flags)
                    testExecuted = true
                    expect(flags.coverage.Value).to.equal(true)
                end,
            })

            Commandline.registerCommand(buildCmd)
            Commandline.registerCommand(testCmd)

            Commandline.execute("build web -p")
            expect(buildExecuted).to.equal(true)

            Commandline.execute("test --coverage")
            expect(testExecuted).to.equal(true)
        end)
    end)
end

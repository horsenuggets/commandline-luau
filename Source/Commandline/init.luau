--[[

Commandline

Main entry point for the commandline library. Provides registration and execution of
commands, along with exports of Arg, Command, and Flag classes for building command-line
interfaces.

--]]

const Arg = require("@self/Arg")
const Command = require("@self/Command")
const Completions = require("@self/Completions")
const Flag = require("@self/Flag")
const StringUtils = require("@self/Helpers/StringUtils")
const Toolkit = require("@self/Toolkit")
const t = require("@packages/t")

const Commandline = {
    -- Public static properties
    Arg = Arg,
    Command = Command,
    Completions = Completions,
    Flag = Flag,
    Toolkit = Toolkit,

    -- Private static properties
    _commands = {} :: { [string]: Command.Command },
}

function Commandline.registerCommand(command: Command.Command)
    assert(t.table(command) and getmetatable(command) == Command, "Invalid command provided.")
    assert(not Commandline._commands[command.Name], "Command with this name already registered.")

    Commandline._commands[command.Name] = command
end

function Commandline.execute(rawCommandString: string)
    assert(t.string(rawCommandString), "Invalid command string provided.")

    -- Tokenize the command string, respecting quotes and escapes
    const tokens, tokenizeErr = StringUtils.tokenize(rawCommandString)
    if tokenizeErr then
        error(tokenizeErr)
    end

    -- Check if we have at least one token (the command name)
    if #tokens == 0 then
        error("No command provided.")
    end

    -- Extract command name
    const commandName = StringUtils.assertAlphanumericLowercase(tokens[1], "Command name")

    -- Find the registered command first to get Flag definitions
    const command = Commandline._commands[commandName]
    if not command then
        error(`Unknown command "{commandName}".`)
    end

    const remainingTokens = {}
    for i = 2, #tokens do
        table.insert(remainingTokens, tokens[i])
    end
    command:Execute(table.freeze(remainingTokens))
end

return Commandline

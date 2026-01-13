--[[

Commandline

Main entry point for the commandline library. Provides registration and execution of
commands, along with exports of Arg, Command, and Flag classes for building command-line
interfaces.

--]]

local Arg = require("@self/Arg")
local Command = require("@self/Command")
local Flag = require("@self/Flag")
local StringUtils = require("@self/Helpers/StringUtils")
local t = require("@packages/t")

local Commandline = {
    -- Public static properties
    Arg = Arg,
    Command = Command,
    Flag = Flag,

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
    local tokens, tokenizeErr = StringUtils.tokenize(rawCommandString)
    if tokenizeErr then
        error(tokenizeErr)
    end

    -- Check if we have at least one token (the command name)
    if #tokens == 0 then
        error("No command provided.")
    end

    -- Extract command name
    local commandName = StringUtils.assertAlphanumericLowercase(tokens[1], "Command name")

    -- Find the registered command first to get Flag definitions
    local command = Commandline._commands[commandName]
    if not command then
        error(`Unknown command "{commandName}".`)
    end

    local remainingTokens = {}
    for i = 2, #tokens do
        table.insert(remainingTokens, tokens[i])
    end
    command:Execute(table.freeze(remainingTokens))
end

return Commandline

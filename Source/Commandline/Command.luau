--[[

Command

Defines the Command class for representing executable commands with Args, Flags, and
Subcommands. Handles parsing of command-line tokens, validation, help message generation,
and command execution. Commands can either have an implementation function or subcommands,
but not both.

--]]

local Arg = require("./Arg")
local Chalk = require("@packages/Chalk")
local Flag = require("./Flag")
local StringUtils = require("./Helpers/StringUtils")
local TypeUtils = require("./Helpers/TypeUtils")
local t = require("@packages/t")

export type Command = {
    -- Constructor
    new: (commandlineOptions: CommandlineOptions) -> Command,

    -- Public properties
    Name: string,
    Description: string,
    Version: string,

    -- Private properties
    _args: { Arg.Arg },
    _flags: { Flag.Flag },
    _helpMessage: string,
    _impl: ((args: { [string]: any }, flags: { [string]: { Value: any? } }) -> any)?,
    _subcommands: { Command },

    -- Public methods
    Execute: (self: Command, tokens: { string }) -> any,
    ShowHelp: (self: Command) -> (),

    -- Private methods
    _findFlagByName: (self: Command, name: string) -> Flag.Flag?,
    _findFlagByShorthand: (self: Command, shorthand: string) -> Flag.Flag?,
    _initializeFlagDefaults: (self: Command) -> { [string]: { Value: any? } },
    _makeHelpMessage: (self: Command) -> string,
    _parseArgsAndFlags: (
        self: Command,
        tokens: { string }
    ) -> ({ string }, { [string]: { Value: any? } }, string?),
    _parseFlag: (
        self: Command,
        arg: string,
        tokens: { string },
        index: number,
        parsedFlags: { [string]: { Value: any? } },
        isShorthand: boolean
    ) -> (number?, string?),
    _parsePositionalArgs: (
        self: Command,
        positionalArgs: { string }
    ) -> ({ [string]: any }?, string?),
    _printError: (self: Command, message: string) -> (),
}
export type CommandlineOptions = {
    Name: string,
    Description: string?,
    Version: string?,
    Args: { any }?,
    Flags: { any }?,
    Subcommands: { any }?,
    Impl: ((args: { [string]: any }, flags: { [string]: { Value: any? } }) -> any)?,
}

local ICommandlineOptions = t.strictInterface({
    Name = t.string,
    Description = t.optional(t.string),
    Version = t.optional(t.string),
    Args = t.optional(t.array(t.any)),
    Flags = t.optional(t.array(t.any)),
    Subcommands = t.optional(t.array(t.any)),
    Impl = t.optional(t.callback),
})
local ITokens = t.array(t.string)

local Command = {}
Command.__index = Command

function Command.new(commandlineOptions: CommandlineOptions): Command
    assert(ICommandlineOptions(commandlineOptions), "Invalid commandline options provided.")

    local self = setmetatable({}, Command)
    self.Name = commandlineOptions.Name:lower()
    self.Description = commandlineOptions.Description or "No description."
    self.Version = commandlineOptions.Version
    self._args = commandlineOptions.Args or {}
    self._flags = commandlineOptions.Flags or {}
    self._subcommands = commandlineOptions.Subcommands or {}
    self._impl = commandlineOptions.Impl

    -- Validate name is alphanumeric and lowercase
    StringUtils.assertAlphanumericLowercase(self.Name, "Name")

    -- Auto-include help Flag
    local hasHelpFlag = false
    for _, flag in self._flags do
        if flag.Name == "help" then
            hasHelpFlag = true
            break
        end
    end
    if not hasHelpFlag then
        table.insert(
            self._flags,
            Flag.new({
                Name = "help",
                Description = "Show help message.",
                Shorthand = "h",
            })
        )
    end

    -- Validate all elements are correct types
    for _, subcommand in self._subcommands do
        assert(getmetatable(subcommand) == Command, "All Subcommands must be instances of Command.")
    end
    for _, arg in self._args do
        assert(getmetatable(arg) == Arg, "All Args must be instances of Arg.")
    end
    for _, flag in self._flags do
        assert(getmetatable(flag) == Flag, "All Flags must be instances of Flag.")
    end

    -- Validate uniqueness of Arg names
    local argNames = {}
    for _, arg in self._args do
        StringUtils.assertAlphanumericLowercase(arg.Name, "Arg name")
        assert(not argNames[arg.Name], `Duplicate Arg name "{arg.Name}".`)
        argNames[arg.Name] = true
    end

    -- Validate uniqueness of flag names and shorthands
    local flagNames = {}
    local flagShorthands = {}
    for _, flag in self._flags do
        StringUtils.assertAlphanumericLowercase(flag.Name, "Flag name")
        assert(not flagNames[flag.Name], `Duplicate Flag name "{flag.Name}".`)
        flagNames[flag.Name] = true

        if flag.Shorthand then
            assert(not flagShorthands[flag.Shorthand], `Duplicate Flag shorthand "{flag.Shorthand}".`)
            flagShorthands[flag.Shorthand] = true
        end
    end

    -- Validate uniqueness of subcommand names
    local subcommandNames = {}
    for _, subcommand in self._subcommands do
        assert(not subcommandNames[subcommand.Name], `Duplicate subcommand name "{subcommand.Name}".`)
        subcommandNames[subcommand.Name] = true
    end

    -- If Subcommands are present, we canot have Args, user-defined Flags, or Impl
    if #self._subcommands > 0 then
        assert(#self._args == 0, "Cannot have Args when Subcommands are present.")
        -- Only the auto-generated help Flag is allowed
        assert(#self._flags == 1 and self._flags[1].Name == "help", "Cannot have Flags when Subcommands are present.")
        assert(self._impl == nil, "Cannot have Impl when Subcommands are present.")
    end

    -- If there are at least 2 Args, ensure no required Args come after optional
    -- Args
    if #self._args >= 2 then
        local foundOptional = false
        for _, arg in self._args do
            if not arg.Required then
                foundOptional = true
            elseif foundOptional and arg.Required then
                error("Cannot have required Args after optional Args.")
            end
        end
    end

    -- Freeze arrays to prevent modification
    table.freeze(self._args :: any)
    table.freeze(self._flags :: any)
    table.freeze(self._subcommands :: any)

    self:_makeHelpMessage()
    return self
end

function Command._makeHelpMessage(self: Command): string
    -- Build the usage line with Flags and Args
    local usageParts = { Chalk.blueBright(self.Name) }

    -- If subcommands are present, show <subcommand> instead of Args
    if #self._subcommands > 0 then
        table.insert(usageParts, `<{Chalk.white(`subcommand`)}>`)
    else
        -- Add Flags annotation if Flags are present
        if #self._flags > 0 then
            table.insert(usageParts, `[{Chalk.white(`flags...`)}]`)
        end

        -- Add Args (required as <Arg>, optional as [Arg])
        for _, arg in self._args do
            if arg.Required then
                table.insert(usageParts, `<{Chalk.white(arg.Name)}>`)
            else
                table.insert(usageParts, `[{Chalk.white(arg.Name)}]`)
            end
        end
    end

    local usageLine = `{Chalk.gray(`> {table.concat(usageParts, " ")}`)}`

    local messageParts = {
        ``,
        `{Chalk.bold(StringUtils.capitalizeFirstLetter(self.Name))}{if self.Version
            then ` {Chalk.gray(`[{Chalk.greenBright(self.Version)}]`)}`
            else ``}`,
        `{Chalk.italic(Chalk.gray(`{self.Description}`))}`,
        ``,
        `{Chalk.gray(`[{Chalk.yellow(`Usage`)}]`)}`,
        usageLine,
    }

    -- Add Flags section if present
    if #self._flags > 0 then
        table.insert(messageParts, ``)
        table.insert(messageParts, `{Chalk.gray(`[{Chalk.yellow(`Flags`)}]`)}`)
        for _, flag in self._flags do
            local flagParts = {}

            -- Add shorthand if available
            if flag.Shorthand then
                table.insert(flagParts, Chalk.blueBright(`-{flag.Shorthand}`))
            end

            -- Add full Flag name
            table.insert(flagParts, Chalk.blueBright(`--{flag.Name}`))

            -- Build the Flag line
            local flagLine =
                `{Chalk.gray(`> `)}{table.concat(flagParts, Chalk.gray(", "))} {Chalk.gray("--")} {Chalk.italic(
                    Chalk.gray(flag.Description)
                )}`
            table.insert(messageParts, flagLine)
        end
    end

    -- Add subcommands section if present
    if #self._subcommands > 0 then
        table.insert(messageParts, ``)
        table.insert(messageParts, `{Chalk.gray(`[{Chalk.yellow(`Subcommands`)}]`)}`)
        for _, subcommand in self._subcommands do
            local subcommandLine =
                `{Chalk.gray(`> `)}{Chalk.blueBright(subcommand.Name)} {Chalk.gray("--")} {Chalk.italic(
                    Chalk.gray(subcommand.Description)
                )}`
            table.insert(messageParts, subcommandLine)
        end
    end

    self._helpMessage = table.concat(messageParts, "\n")
    return self._helpMessage
end

function Command.ShowHelp(self: Command)
    print(self._helpMessage)
end

function Command._printError(self: Command, message: string)
    print(Chalk.red(`[Error] {message}`))
end

function Command._findFlagByName(self: Command, name: string): Flag.Flag?
    for _, flag in self._flags do
        if flag.Name == name then
            return flag
        end
    end
    return nil
end

function Command._findFlagByShorthand(self: Command, shorthand: string): Flag.Flag?
    for _, flag in self._flags do
        if flag.Shorthand == shorthand then
            return flag
        end
    end
    return nil
end

function Command._parseFlag(
    self: Command,
    token: string,
    tokens: { string },
    index: number,
    parsedFlags: { [string]: { Value: any? } },
    isShorthand: boolean
): (number?, string?)
    local flagDef

    if isShorthand then
        if #token ~= 2 or token:sub(1, 1) ~= "-" then
            return nil, `Invalid shorthand Flag format {Chalk.bold(token)}.`
        end

        local shorthand = token:sub(2, 2)
        flagDef = self:_findFlagByShorthand(shorthand)

        if not flagDef then
            return nil, `Unknown Flag {Chalk.bold(`-{shorthand}`)}.`
        end
    else
        if #token <= 2 or token:sub(1, 2) ~= "--" then
            return nil, `Invalid shorthand Flag format {Chalk.bold(token)}.`
        end

        local flagName = token:sub(3)
        flagDef = self:_findFlagByName(flagName)

        if not flagDef then
            return nil, `Unknown Flag {Chalk.bold(`--{flagName}`)}.`
        end
    end

    -- If the Flag has no type, it doesn't consume any following token
    if not flagDef.Type then
        parsedFlags[flagDef.Name] = { Value = true }
        return index
    end

    -- If the Flag has a type, it needs a value
    index += 1
    if index > #tokens then
        local flagDisplay = isShorthand and `-{token:sub(2, 2)}` or `--{flagDef.Name}`
        return nil, `Flag {Chalk.bold(flagDisplay)} requires a value.`
    end
    local flagValueToken = tokens[index]

    -- Cast the Flag value to the correct type
    local flagValue, castErr = TypeUtils.castFromString(flagValueToken, flagDef.Type)
    if castErr then
        local flagDisplay = isShorthand and `-{token:sub(2, 2)}` or `--{flagDef.Name}`
        return nil, `Flag {Chalk.bold(flagDisplay)} - {castErr}`
    end

    parsedFlags[flagDef.Name] = { Value = flagValue }
    return index
end

function Command._initializeFlagDefaults(self: Command): { [string]: { Value: any? } }
    local parsedFlags = {}
    for _, flag in self._flags do
        parsedFlags[flag.Name] = { Value = flag.Default }
    end
    return parsedFlags
end

function Command._parsePositionalArgs(self: Command, positionalArgs: { string }): ({ [string]: any }?, string?)
    local parsedArgs = {}

    -- Count required Args
    local requiredArgCount = 0
    for _, argDef in self._args do
        if argDef.Required then
            requiredArgCount += 1
        end
    end

    -- Validate Arg count
    if #positionalArgs < requiredArgCount then
        return nil, "Missing required Args."
    end

    if #positionalArgs > #self._args then
        return nil, "Too many Args provided."
    end

    -- Map positional Args to definitions
    for argIndex, argDef in self._args do
        if argIndex <= #positionalArgs then
            -- Cast the Arg value to the correct type
            local argValue, castErr = TypeUtils.castFromString(positionalArgs[argIndex], argDef.Type)
            if castErr then
                return nil, `Arg {Chalk.bold(argDef.Name)} - {castErr}`
            end
            parsedArgs[argDef.Name] = argValue
        elseif argDef.Default ~= nil then
            parsedArgs[argDef.Name] = argDef.Default
        end
    end

    return parsedArgs, nil
end

function Command._parseArgsAndFlags(
    self: Command,
    tokens: { string }
): ({ string }, { [string]: { Value: any? } }, string?)
    local parsedFlags = self:_initializeFlagDefaults()
    local positionalArgs = {}

    local i = 1
    while i <= #tokens do
        local token = tokens[i]

        if token:sub(1, 2) == "--" then
            local newIndex, err = self:_parseFlag(token, tokens, i, parsedFlags, false)
            if not newIndex then
                return positionalArgs, parsedFlags, err
            end
            i = newIndex
        elseif token:sub(1, 1) == "-" and #token > 1 then
            local newIndex, err = self:_parseFlag(token, tokens, i, parsedFlags, true)
            if not newIndex then
                return positionalArgs, parsedFlags, err
            end
            i = newIndex
        else
            table.insert(positionalArgs, token)
        end

        i = i + 1
    end

    return positionalArgs, parsedFlags, nil
end

function Command.Execute(self: Command, tokens: { string }): any
    assert(ITokens(tokens), "Invalid tokens provided.")

    -- Check if we have subcommands and if the first token matches a
    -- subcommand
    if #self._subcommands > 0 and #tokens > 0 then
        local potentialSubcommandName = tokens[1]

        -- Find matching subcommand
        local matchedSubcommand = nil
        for _, subcommand in self._subcommands do
            if subcommand.Name == potentialSubcommandName then
                matchedSubcommand = subcommand
                break
            end
        end

        -- If we found a matching subcommand, execute it with remaining tokens
        if matchedSubcommand then
            local remainingTokens = {}
            for i = 2, #tokens do
                table.insert(remainingTokens, tokens[i])
            end
            return matchedSubcommand:Execute(table.freeze(remainingTokens))
        end
    end

    -- Parse positional Args and Flags from tokens
    local positionalArgs, parsedFlags, err = self:_parseArgsAndFlags(tokens)
    if err then
        self:_printError(err)
        self:ShowHelp()
        return
    end

    -- Check for help Flag
    if parsedFlags.help and parsedFlags.help.Value then
        self:ShowHelp()
        return
    end

    -- If we have subcommands but didn't match any, show help
    if #self._subcommands > 0 then
        if #positionalArgs == 0 then
            self:ShowHelp()
            return
        else
            self:_printError(`Unknown subcommand {Chalk.bold(positionalArgs[1])}.`)
            self:ShowHelp()
            return
        end
    end

    -- Validate and parse positional Args
    local parsedArgs
    parsedArgs, err = self:_parsePositionalArgs(positionalArgs)
    if not parsedArgs then
        self:_printError(err)
        self:ShowHelp()
        return
    end

    -- Execute the implementation
    if self._impl then
        return self._impl(parsedArgs, parsedFlags)
    end
    return nil
end

return Command

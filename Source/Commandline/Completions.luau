--[[

Completions

Generates static shell completion scripts for bash, zsh, and fish. Walks the command
tree to extract all subcommands, flags, and their descriptions, then produces shell
scripts that enable tab completion.

--]]

local t = require("@packages/t")

type Command = {
    Name: string,
    Description: string,
    _args: { any },
    _flags: { any },
    _subcommands: { Command },
}

type Flag = {
    Name: string,
    Description: string,
    Type: string?,
    Shorthand: string?,
}

local Completions = {}

local function escapeShellString(str: string): string
    return (string.gsub(str, "'", "'\\''"))
end

local function escapeFishString(str: string): string
    return (string.gsub(str, "'", "\\'"))
end

local function getSubcommandNames(command: Command): { string }
    local names = {}
    for _, sub in command._subcommands do
        table.insert(names, sub.Name)
    end
    return names
end

local function getFlagCompletions(flags: { Flag }): { string }
    local completions = {}
    for _, flag in flags do
        table.insert(completions, "--" .. flag.Name)
    end
    return completions
end

-- Helper to emit a line with shell variable interpolation (avoids {{ in backtick
-- strings which stylua cannot parse)
local function shellVar(varName: string): string
    return "${" .. varName .. "}"
end

-- Bash completion generator

local function generateBashSubcommand(lines: { string }, command: Command, path: string, indent: string)
    local subNames = getSubcommandNames(command)

    if #subNames > 0 then
        table.insert(lines, indent .. 'if [[ "' .. shellVar("subcmd_" .. path) .. '" == "" ]]; then')
        table.insert(lines, indent .. '    COMPREPLY=($(compgen -W "' .. table.concat(subNames, " ") .. '" -- "$cur"))')
        table.insert(lines, indent .. "    return")
        table.insert(lines, indent .. "fi")

        for _, sub in command._subcommands do
            local subPath = path .. "_" .. sub.Name
            table.insert(
                lines,
                indent .. 'if [[ "' .. shellVar("subcmd_" .. path) .. '" == "' .. sub.Name .. '" ]]; then'
            )

            if #sub._subcommands > 0 then
                table.insert(lines, indent .. "    local subcmd_" .. subPath .. '=""')
                table.insert(lines, indent .. "    for ((i=1; i < cword; i++)); do")
                table.insert(
                    lines,
                    indent .. '        if [[ "' .. shellVar("words[i]") .. '" == "' .. sub.Name .. '" ]]; then'
                )
                table.insert(lines, indent .. "            for ((j=i+1; j < cword; j++)); do")
                table.insert(lines, indent .. '                if [[ "' .. shellVar("words[j]") .. '" != -* ]]; then')
                table.insert(
                    lines,
                    indent .. "                    subcmd_" .. subPath .. '="' .. shellVar("words[j]") .. '"'
                )
                table.insert(lines, indent .. "                    break")
                table.insert(lines, indent .. "                fi")
                table.insert(lines, indent .. "            done")
                table.insert(lines, indent .. "            break")
                table.insert(lines, indent .. "        fi")
                table.insert(lines, indent .. "    done")
                generateBashSubcommand(lines, sub, subPath, indent .. "    ")
            else
                local subFlags = getFlagCompletions(sub._flags)
                if #subFlags > 0 then
                    table.insert(lines, indent .. '    if [[ "$cur" == -* ]]; then')
                    table.insert(
                        lines,
                        indent .. '        COMPREPLY=($(compgen -W "' .. table.concat(subFlags, " ") .. '" -- "$cur"))'
                    )
                    table.insert(lines, indent .. "        return")
                    table.insert(lines, indent .. "    fi")
                end
            end

            table.insert(lines, indent .. "    return")
            table.insert(lines, indent .. "fi")
        end
    end
end

function Completions.bash(command: Command): string
    assert(t.table(command))

    local name = command.Name
    local lines = {}

    table.insert(lines, "_" .. name .. "() {")
    table.insert(lines, "    local cur prev words cword")
    table.insert(lines, "    if declare -F _init_completion >/dev/null 2>&1; then")
    table.insert(lines, "        _init_completion || return")
    table.insert(lines, "    else")
    table.insert(lines, '        cur="' .. shellVar("COMP_WORDS[COMP_CWORD]") .. '"')
    table.insert(lines, '        prev="' .. shellVar("COMP_WORDS[COMP_CWORD-1]") .. '"')
    table.insert(lines, '        words=("' .. shellVar("COMP_WORDS[@]") .. '")')
    table.insert(lines, "        cword=$COMP_CWORD")
    table.insert(lines, "    fi")
    table.insert(lines, "")

    local flagWords = getFlagCompletions(command._flags)
    if #flagWords > 0 then
        table.insert(lines, '    if [[ "$cur" == -* ]]; then')
        table.insert(lines, '        COMPREPLY=($(compgen -W "' .. table.concat(flagWords, " ") .. '" -- "$cur"))')
        table.insert(lines, "        return")
        table.insert(lines, "    fi")
        table.insert(lines, "")
    end

    if #command._subcommands > 0 then
        table.insert(lines, '    local subcmd_root=""')
        table.insert(lines, "    for ((i=1; i < cword; i++)); do")
        table.insert(lines, '        if [[ "' .. shellVar("words[i]") .. '" != -* ]]; then')
        table.insert(lines, '            subcmd_root="' .. shellVar("words[i]") .. '"')
        table.insert(lines, "            break")
        table.insert(lines, "        fi")
        table.insert(lines, "    done")
        table.insert(lines, "")
        generateBashSubcommand(lines, command, "root", "    ")
    end

    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "complete -o default -F _" .. name .. " " .. name)
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

-- Zsh completion generator

local function zshFlagSpec(flag: Flag): string
    local desc = escapeShellString(flag.Description)
    if flag.Shorthand then
        local exclusion = "(-" .. flag.Shorthand .. " --" .. flag.Name .. ")"
        local names = "{-" .. flag.Shorthand .. ",--" .. flag.Name .. "}"
        if flag.Type then
            return "'" .. exclusion .. "'" .. names .. "'[" .. desc .. "]:value:'"
        else
            return "'" .. exclusion .. "'" .. names .. "'[" .. desc .. "]'"
        end
    else
        if flag.Type then
            return "'--" .. flag.Name .. "[" .. desc .. "]:value:'"
        else
            return "'--" .. flag.Name .. "[" .. desc .. "]'"
        end
    end
end

local function generateZshSubcommands(lines: { string }, command: Command, indent: string)
    if #command._subcommands == 0 then
        return
    end

    table.insert(lines, indent .. "local -a commands=(")
    for _, sub in command._subcommands do
        local desc = escapeShellString(sub.Description)
        table.insert(lines, indent .. "    '" .. sub.Name .. ":" .. desc .. "'")
    end
    table.insert(lines, indent .. ")")
    table.insert(lines, "")

    local flagSpecs = {}
    for _, flag in command._flags do
        table.insert(flagSpecs, zshFlagSpec(flag))
    end

    table.insert(lines, indent .. "_arguments -C \\")
    for _, spec in flagSpecs do
        table.insert(lines, indent .. "    " .. spec .. " \\")
    end
    table.insert(lines, indent .. "    '1:command:->cmd' \\")
    table.insert(lines, indent .. "    '*::arg:->args'")
    table.insert(lines, "")

    table.insert(lines, indent .. "case $state in")
    table.insert(lines, indent .. "    cmd)")
    table.insert(lines, indent .. "        _describe 'command' commands")
    table.insert(lines, indent .. "        ;;")
    table.insert(lines, indent .. "    args)")
    table.insert(lines, indent .. "        case $words[1] in")

    for _, sub in command._subcommands do
        table.insert(lines, indent .. "            " .. sub.Name .. ")")

        if #sub._subcommands > 0 then
            generateZshSubcommands(lines, sub, indent .. "                ")
        else
            local subFlagSpecs = {}
            for _, flag in sub._flags do
                table.insert(subFlagSpecs, zshFlagSpec(flag))
            end
            table.insert(lines, indent .. "                _arguments \\")
            for _, spec in subFlagSpecs do
                table.insert(lines, indent .. "                    " .. spec .. " \\")
            end
            table.insert(lines, indent .. "                    '*:file:_files'")
        end

        table.insert(lines, indent .. "                ;;")
    end

    table.insert(lines, indent .. "        esac")
    table.insert(lines, indent .. "        ;;")
    table.insert(lines, indent .. "esac")
end

function Completions.zsh(command: Command): string
    assert(t.table(command))

    local name = command.Name
    local lines = {}

    table.insert(lines, "#compdef " .. name)
    table.insert(lines, "")
    table.insert(lines, "_" .. name .. "() {")

    if #command._subcommands > 0 then
        generateZshSubcommands(lines, command, "    ")
    else
        local flagSpecs = {}
        for _, flag in command._flags do
            table.insert(flagSpecs, zshFlagSpec(flag))
        end
        table.insert(lines, "    _arguments \\")
        for _, spec in flagSpecs do
            table.insert(lines, "        " .. spec .. " \\")
        end
        table.insert(lines, "        '*:file:_files'")
    end

    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "_" .. name .. ' "$@"')
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

-- Fish completion generator

local function generateFishSubcommands(lines: { string }, command: Command, parentCondition: string?)
    local name = command.Name
    local useSubcommand = parentCondition or "__fish_use_subcommand"

    for _, sub in command._subcommands do
        local desc = escapeFishString(sub.Description)
        table.insert(
            lines,
            "complete -c " .. name .. ' -n "' .. useSubcommand .. '" -a "' .. sub.Name .. "\" -d '" .. desc .. "'"
        )
    end
    table.insert(lines, "")

    for _, flag in command._flags do
        local desc = escapeFishString(flag.Description)
        local parts = { "complete -c " .. name }

        if parentCondition then
            table.insert(parts, '-n "' .. parentCondition .. '"')
        end

        table.insert(parts, "-l " .. flag.Name)

        if flag.Shorthand then
            table.insert(parts, "-s " .. flag.Shorthand)
        end

        table.insert(parts, "-d '" .. desc .. "'")

        if flag.Type then
            table.insert(parts, "-r")
        end

        table.insert(lines, table.concat(parts, " "))
    end

    if #command._flags > 0 then
        table.insert(lines, "")
    end

    for _, sub in command._subcommands do
        local subCondition = "__fish_seen_subcommand_from " .. sub.Name
        if #sub._subcommands > 0 then
            generateFishSubcommands(lines, sub, subCondition)
        else
            for _, flag in sub._flags do
                local desc = escapeFishString(flag.Description)
                local parts = { "complete -c " .. name .. ' -n "' .. subCondition .. '"' }
                table.insert(parts, "-l " .. flag.Name)
                if flag.Shorthand then
                    table.insert(parts, "-s " .. flag.Shorthand)
                end
                table.insert(parts, "-d '" .. desc .. "'")
                if flag.Type then
                    table.insert(parts, "-r")
                end
                table.insert(lines, table.concat(parts, " "))
            end
            if #sub._flags > 0 then
                table.insert(lines, "")
            end
        end
    end
end

function Completions.fish(command: Command): string
    assert(t.table(command))

    local name = command.Name
    local lines = {}

    table.insert(lines, "# Completions for " .. name)
    table.insert(lines, "complete -c " .. name .. " -f")
    table.insert(lines, "")

    if #command._subcommands > 0 then
        generateFishSubcommands(lines, command, nil)
    else
        for _, flag in command._flags do
            local desc = escapeFishString(flag.Description)
            local parts = { "complete -c " .. name }
            table.insert(parts, "-l " .. flag.Name)
            if flag.Shorthand then
                table.insert(parts, "-s " .. flag.Shorthand)
            end
            table.insert(parts, "-d '" .. desc .. "'")
            if flag.Type then
                table.insert(parts, "-r")
            end
            table.insert(lines, table.concat(parts, " "))
        end
    end

    table.insert(lines, "")
    return table.concat(lines, "\n")
end

function Completions.generate(command: Command, shell: string): string
    assert(t.table(command))
    assert(t.string(shell))

    if shell == "bash" then
        return Completions.bash(command)
    elseif shell == "zsh" then
        return Completions.zsh(command)
    elseif shell == "fish" then
        return Completions.fish(command)
    else
        error('Unsupported shell "' .. shell .. '". Supported shells are bash, zsh, and fish.')
    end
end

return Completions

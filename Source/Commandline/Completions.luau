--[[

Completions

Generates static shell completion scripts for bash, zsh, and fish. Walks the command
tree to extract all subcommands, flags, and their descriptions, then produces shell
scripts that enable tab completion.

--]]

const t = require("@packages/t")

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

const Completions = {}

const function escapeShellString(str: string): string
    return (string.gsub(str, "'", "'\\''"))
end

const function escapeFishString(str: string): string
    return (string.gsub(str, "'", "\\'"))
end

const function getSubcommandNames(command: Command): { string }
    const names = {}
    for _, sub in command._subcommands do
        table.insert(names, sub.Name)
    end
    return names
end

const function getFlagCompletions(flags: { Flag }): { string }
    const completions = {}
    for _, flag in flags do
        table.insert(completions, "--" .. flag.Name)
    end
    return completions
end

-- Helper to emit a line with shell variable interpolation (avoids {{ in backtick
-- strings which stylua cannot parse)
const function shellVar(varName: string): string
    return "${" .. varName .. "}"
end

-- Bash completion generator

const function generateBashSubcommand(lines: { string }, command: Command, path: string, indent: string)
    const subNames = getSubcommandNames(command)

    if #subNames > 0 then
        table.insert(lines, indent .. 'if [[ "' .. shellVar("subcmd_" .. path) .. '" == "" ]]; then')
        table.insert(lines, indent .. '    COMPREPLY=($(compgen -W "' .. table.concat(subNames, " ") .. '" -- "$cur"))')
        table.insert(lines, indent .. "    return")
        table.insert(lines, indent .. "fi")

        for _, sub in command._subcommands do
            const subPath = path .. "_" .. sub.Name
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
                const subFlags = getFlagCompletions(sub._flags)
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

    const name = command.Name
    const lines = {}

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

    const flagWords = getFlagCompletions(command._flags)
    if #flagWords > 0 then
        table.insert(lines, '    if [[ "$cur" == -* ]]; then')
        table.insert(lines, '        COMPREPLY=($(compgen -W "' .. table.concat(flagWords, " ") .. '" -- "$cur"))')
        table.insert(lines, "        if (( " .. shellVar("#COMPREPLY[@]") .. " > 0 )); then")
        table.insert(lines, "            return")
        table.insert(lines, "        fi")
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

const function zshFlagSpec(flag: Flag): string
    const desc = escapeShellString(flag.Description)
    if flag.Shorthand then
        const exclusion = "(-" .. flag.Shorthand .. " --" .. flag.Name .. ")"
        const names = "{-" .. flag.Shorthand .. ",--" .. flag.Name .. "}"
        if flag.Type then
            return "'" .. exclusion .. "'" .. names .. "'[" .. desc .. "]:value:_files'"
        else
            return "'" .. exclusion .. "'" .. names .. "'[" .. desc .. "]'"
        end
    else
        if flag.Type then
            return "'--" .. flag.Name .. "[" .. desc .. "]:value:_files'"
        else
            return "'--" .. flag.Name .. "[" .. desc .. "]'"
        end
    end
end

const function zshDisplay(text: string): string
    const escaped = string.gsub(string.gsub(string.gsub(text, "\\", "\\\\"), "'", "\\'"), "\n", "\\n")
    return "$'" .. string.gsub(escaped, "\27", "\\e") .. "'"
end

const function generateZshFlags(lines: { string }, command: Command, indent: string, rootName: string)
    table.insert(lines, indent .. "local -a flag_names=() flag_shorts=() flag_long_displays=() flag_pair_displays=()")
    for _, flag in command._flags do
        const long = "--" .. flag.Name
        const short = if flag.Shorthand then "-" .. flag.Shorthand else ""
        const description = "\27[90m-- \27[3m" .. flag.Description .. "\27[0m"
        const longDisplay = "\27[94m" .. long .. "\27[0m " .. description
        const paired = if short ~= ""
            then "\27[94m" .. short .. "\27[90m, \27[94m" .. long .. "\27[0m " .. description
            else longDisplay
        table.insert(lines, indent .. "flag_names+=(" .. zshDisplay(long) .. ")")
        table.insert(lines, indent .. "flag_shorts+=(" .. zshDisplay(short) .. ")")
        table.insert(lines, indent .. "flag_long_displays+=(" .. zshDisplay(longDisplay) .. ")")
        table.insert(lines, indent .. "flag_pair_displays+=(" .. zshDisplay(paired) .. ")")
    end
    table.insert(lines, indent .. "local -a command_names=(")
    for _, sub in command._subcommands do
        table.insert(lines, indent .. "    '" .. escapeShellString(sub.Name) .. "'")
    end
    table.insert(lines, indent .. ")")
    table.insert(lines, indent .. "local -a flag_specs=(")
    for _, flag in command._flags do
        table.insert(lines, indent .. "    " .. zshFlagSpec(flag))
    end
    table.insert(lines, indent .. ")")
    table.insert(lines, indent .. "if _" .. rootName .. '_options "$flag_specs[@]"; then')
    table.insert(lines, indent .. "    return")
    table.insert(lines, indent .. "fi")
end

const function generateZshSubcommands(lines: { string }, command: Command, indent: string, rootName: string)
    generateZshFlags(lines, command, indent, rootName)
    -- Hidden specs retain zsh's value parsing without its padded option display.
    table.insert(lines, indent .. 'local -a hidden_specs=( "${(@)^flag_specs/#/!}" )')
    table.insert(lines, indent .. '_arguments -C "$hidden_specs[@]" \\')
    if #command._subcommands == 0 then
        table.insert(lines, indent .. "    '*:arg:_files'")
        return
    end
    table.insert(lines, indent .. "    '1:command:->cmd' \\")
    table.insert(lines, indent .. "    '*::arg:->args'")
    table.insert(lines, indent .. "case $state in")
    table.insert(lines, indent .. "    cmd)")
    table.insert(lines, indent .. "        local -a display_cmds cmd_names")
    for _, sub in command._subcommands do
        const display = "\27[94m" .. sub.Name .. "\27[0m \27[90m-- \27[3m" .. sub.Description .. "\27[0m"
        table.insert(lines, indent .. "        display_cmds+=(" .. zshDisplay(display) .. ")")
        table.insert(lines, indent .. "        cmd_names+=('" .. escapeShellString(sub.Name) .. "')")
    end
    table.insert(lines, indent .. "        compadd -V unsorted -l -d display_cmds -a cmd_names")
    table.insert(lines, indent .. "        ;;")
    table.insert(lines, indent .. "    args)")
    table.insert(lines, indent .. "        case $words[1] in")
    for _, sub in command._subcommands do
        table.insert(lines, indent .. "            '" .. escapeShellString(sub.Name) .. "')")
        generateZshSubcommands(lines, sub, indent .. "                ", rootName)
        table.insert(lines, indent .. "                ;;")
    end
    table.insert(lines, indent .. "        esac")
    table.insert(lines, indent .. "        ;;")
    table.insert(lines, indent .. "esac")
end

function Completions.zsh(command: Command): string
    assert(t.table(command))

    const name = command.Name
    const lines = {}

    table.insert(lines, "#compdef " .. name)
    table.insert(lines, "")
    table.insert(lines, "_" .. name .. "_options() {")
    table.insert(
        lines,
        [=[
        [[ $PREFIX == -* ]] || return 1
        local -a next direct odirect equal descrs actions subcs positional available candidates displays
        local -A used
        local index candidate
        comparguments -i '' : "$@" '*:arg:->arg' || return 1
        comparguments -D descrs actions subcs
        # A dash can be part of a required value, not an option name.
        [[ -n ${subcs[(r)option-*]} ]] && return 1
        comparguments -W positional used 0
        # Let _arguments shift words before completing a nested command.
        [[ -n $positional[1] && -n ${command_names[(r)$positional[1]]} ]] && return 1
        comparguments -O next direct odirect equal || return 1
        available=( "${(@)next%%:*}" "${(@)direct%%:*}" "${(@)odirect%%:*}" "${(@)equal%%:*}" )
        for (( index=1; index <= $#flag_names; index++ )); do
            candidate=$flag_names[index]
            [[ -n ${available[(r)$candidate]} ]] || continue
            if [[ $PREFIX == --* || -z $flag_shorts[index] ]]; then
                displays+=( "$flag_long_displays[index]" )
            else
                candidate=$flag_shorts[index]
                displays+=( "$flag_pair_displays[index]" )
            fi
            candidates+=( "$candidate" )
        done
        compadd -V unsorted -l -d displays -a candidates
    }]=]
    )
    table.insert(lines, "_" .. name .. "() {")
    table.insert(lines, "    local context state state_descr line")
    table.insert(lines, "    local -A opt_args")
    table.insert(lines, "    local matches_before=$compstate[nmatches]")
    generateZshSubcommands(lines, command, "    ", name)

    table.insert(lines, "    if (( compstate[nmatches] == matches_before )); then")
    table.insert(lines, "        _files")
    table.insert(lines, "    fi")
    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "_" .. name .. ' "$@"')
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

-- Fish completion generator

const function generateFishFlag(lines: { string }, name: string, flag: Flag, condition: string?)
    const parts = { "complete -c " .. name }
    table.insert(parts, "-l " .. flag.Name)
    if flag.Shorthand then
        table.insert(parts, "-s " .. flag.Shorthand)
    end
    table.insert(parts, "-d '" .. escapeFishString(flag.Description) .. "'")
    if flag.Type then
        -- Probe without files first, then enable native files only for empty results.
        const fallbackCondition = (if condition then condition .. "; and " else "") .. "__" .. name .. "_no_matches"
        table.insert(
            lines,
            table.concat(parts, " ") .. (if condition then ' -n "' .. condition .. '"' else "") .. " -x"
        )
        table.insert(parts, '-n "' .. fallbackCondition .. '" -r -F')
    elseif condition then
        table.insert(parts, '-n "' .. condition .. '"')
    end
    table.insert(lines, table.concat(parts, " "))
end

const function generateFishSubcommands(lines: { string }, command: Command, name: string, path: { string })
    const pathWords = if #path > 0 then " " .. table.concat(path, " ") else ""
    const parentCondition = if #path > 0 then "__" .. name .. "_at_command prefix" .. pathWords else nil
    const useSubcommand = "__" .. name .. "_at_command exact" .. pathWords

    for _, sub in command._subcommands do
        const desc = escapeFishString(sub.Description)
        table.insert(
            lines,
            "complete -c " .. name .. ' -n "' .. useSubcommand .. '" -a "' .. sub.Name .. "\" -d '" .. desc .. "'"
        )
    end
    table.insert(lines, "")

    for _, flag in command._flags do
        generateFishFlag(lines, name, flag, parentCondition)
    end

    if #command._flags > 0 then
        table.insert(lines, "")
    end

    for _, sub in command._subcommands do
        const subPath = table.clone(path)
        table.insert(subPath, sub.Name)
        const subCondition = "__" .. name .. "_at_command prefix " .. table.concat(subPath, " ")
        if #sub._subcommands > 0 then
            generateFishSubcommands(lines, sub, name, subPath)
        else
            for _, flag in sub._flags do
                generateFishFlag(lines, name, flag, subCondition)
            end
            if #sub._flags > 0 then
                table.insert(lines, "")
            end
        end
    end
end

function Completions.fish(command: Command): string
    assert(t.table(command))

    const name = command.Name
    const lines = {}

    table.insert(lines, "# Completions for " .. name)
    table.insert(lines, "function __" .. name .. "_no_matches")
    table.insert(lines, "    set -q __commandline_completion_probing; and return 1")
    table.insert(lines, "    set -g __commandline_completion_probing 1")
    table.insert(lines, "    set -l matches (complete -C (commandline -cp))")
    table.insert(lines, "    set -e __commandline_completion_probing")
    table.insert(lines, "    test (count $matches) -eq 0")
    table.insert(lines, "end")
    table.insert(lines, "complete -c " .. name .. " -f")
    table.insert(lines, "complete -c " .. name .. ' -F -n "__' .. name .. '_no_matches"')
    table.insert(lines, "")

    if #command._subcommands > 0 then
        table.insert(lines, "function __" .. name .. "_at_command")
        table.insert(lines, "    set -l mode $argv[1]")
        table.insert(lines, "    set -e argv[1]")
        table.insert(lines, "    set -l words (commandline -opc)")
        table.insert(lines, "    set -e words[1]")
        table.insert(lines, "    for expected in $argv")
        table.insert(lines, '        test "$words[1]" = "$expected"; or return 1')
        table.insert(lines, "        set -e words[1]")
        table.insert(lines, "    end")
        table.insert(lines, '    test "$mode" = prefix; or test (count $words) -eq 0')
        table.insert(lines, "end")
        generateFishSubcommands(lines, command, name, {})
    else
        for _, flag in command._flags do
            generateFishFlag(lines, name, flag, nil)
        end
    end

    table.insert(lines, "")
    return table.concat(lines, "\n")
end

-- PowerShell completion generator

const function escapePowerShellString(str: string): string
    return (string.gsub(str, "'", "''"))
end

function Completions.powershell(command: Command): string
    assert(t.table(command))

    const name = command.Name
    const lines = {}
    const filter = [[| Where-Object { $_.CompletionText -like "$wordToComplete*" }]]
    const cr = "[System.Management.Automation.CompletionResult]"

    table.insert(lines, "# Completions for " .. name)
    table.insert(lines, "Register-ArgumentCompleter -CommandName " .. name .. " -ScriptBlock {")
    table.insert(lines, "    param($wordToComplete, $commandAst, $cursorPosition)")
    table.insert(
        lines,
        "    $tokens = $commandAst.ToString().Split(" .. "' ', [StringSplitOptions]::RemoveEmptyEntries)"
    )
    table.insert(
        lines,
        "    $sub = if ($tokens.Count -gt 1 -and " .. "$tokens[1] -notlike '-*') { $tokens[1] } else { $null }"
    )

    if #command._subcommands > 0 then
        -- Build subcommand list for validation
        const subNames = {}
        for _, sub in command._subcommands do
            table.insert(subNames, "'" .. sub.Name .. "'")
        end
        table.insert(lines, "    $subcommands = @(" .. table.concat(subNames, ", ") .. ")")
        table.insert(lines, "    $isValidSub = $sub -and ($subcommands -contains $sub)")
        table.insert(lines, "")

        -- Root level: show subcommands or root flags
        table.insert(lines, "    if (-not $isValidSub) {")
        table.insert(lines, "        if ($wordToComplete -like '-*') {")
        table.insert(lines, "            @(")
        for _, flag in command._flags do
            const desc = escapePowerShellString(flag.Description)
            table.insert(
                lines,
                "                "
                    .. cr
                    .. "::new('--"
                    .. flag.Name
                    .. "', '--"
                    .. flag.Name
                    .. "', 'ParameterName', '"
                    .. desc
                    .. "')"
            )
        end
        table.insert(lines, "            ) " .. filter)
        table.insert(lines, "        } else {")
        table.insert(lines, "            @(")
        for _, sub in command._subcommands do
            const desc = escapePowerShellString(sub.Description)
            table.insert(
                lines,
                "                "
                    .. cr
                    .. "::new('"
                    .. sub.Name
                    .. "', '"
                    .. sub.Name
                    .. "', 'ParameterValue', '"
                    .. desc
                    .. "')"
            )
        end
        table.insert(lines, "            ) " .. filter)
        table.insert(lines, "        }")

        -- Subcommand flags
        table.insert(lines, "    } elseif ($wordToComplete -ne $sub) {")
        table.insert(lines, "        switch ($sub) {")
        for _, sub in command._subcommands do
            table.insert(lines, "            '" .. sub.Name .. "' {")
            table.insert(lines, "                @(")
            for _, flag in sub._flags do
                const desc = escapePowerShellString(flag.Description)
                table.insert(
                    lines,
                    "                    "
                        .. cr
                        .. "::new('--"
                        .. flag.Name
                        .. "', '--"
                        .. flag.Name
                        .. "', 'ParameterName', '"
                        .. desc
                        .. "')"
                )
            end
            table.insert(lines, "                ) " .. filter)
            table.insert(lines, "            }")
        end
        table.insert(lines, "        }")
        table.insert(lines, "    }")
    else
        table.insert(lines, "    @(")
        for _, flag in command._flags do
            const desc = escapePowerShellString(flag.Description)
            table.insert(
                lines,
                "        "
                    .. cr
                    .. "::new('--"
                    .. flag.Name
                    .. "', '--"
                    .. flag.Name
                    .. "', 'ParameterName', '"
                    .. desc
                    .. "')"
            )
        end
        table.insert(lines, "    ) " .. filter)
    end

    table.insert(lines, "}")
    table.insert(lines, "")

    return table.concat(lines, "\n")
end

function Completions.generate(command: Command, shell: string): string
    assert(t.table(command))
    assert(t.string(shell))

    if shell == "bash" then
        return Completions.bash(command)
    elseif shell == "fish" then
        return Completions.fish(command)
    elseif shell == "powershell" or shell == "pwsh" then
        return Completions.powershell(command)
    elseif shell == "zsh" then
        return Completions.zsh(command)
    else
        error('Unsupported shell "' .. shell .. '". Supported shells are bash, fish, powershell, and zsh.')
    end
end

return Completions

#!/usr/bin/env -S lune run

--[[

ZshCompletionDemo.exec

Starts an isolated interactive zsh prompt using generated completions for a sample ae
command. Press Tab after "ae " to inspect command names and descriptions.

[Usage] ./Scripts/ZshCompletionDemo.exec.luau

--]]

const Commandline = require("@commandline")
const fs = require("@lune/fs")
const process = require("@lune/process")

const ZshCompletionDemo = {}

function ZshCompletionDemo.exec()
    const command = Commandline.Command.new({
        Name = "ae",
        Description = "Manage an example application.",
        Version = "demo",
        Subcommands = {
            Commandline.Command.new({
                Name = "edit",
                Description = "Open a temporary place that stays synced to Source/.",
                Impl = function() end,
            }),
            Commandline.Command.new({
                Name = "setup",
                Description = "Set up developer tools.",
                Subcommands = {
                    Commandline.Command.new({
                        Name = "luau-lsp",
                        Description = "Install or update the luau-lsp fork's editor extension.",
                        Flags = {
                            Commandline.Flag.new({
                                Name = "editor",
                                Shorthand = "e",
                                Type = "string",
                                Description = "Name or path of the editor command line tool.",
                            }),
                            Commandline.Flag.new({
                                Name = "force",
                                Shorthand = "f",
                                Description = "Reinstall even when already installed.",
                            }),
                        },
                        Impl = function() end,
                    }),
                },
            }),
            Commandline.Command.new({
                Name = "teamcreate",
                Description = "Open the Team Create place in Studio.",
                Impl = function() end,
            }),
            Commandline.Command.new({
                Name = "update",
                Description = "Rebuild ae and reinstall the Studio plugins from your checkout.",
                Impl = function() end,
            }),
        },
    })
    const completion = Commandline.Completions.zsh(command)
    const sessionDir = `{tostring(project)}/Build/ZshCompletionDemo/{os.time()}-{math.random(1, 1e9)}`
    fs.writeDir(sessionDir)
    fs.writeFile(
        `{sessionDir}/.zshrc`,
        [=[
        # Keep instructions and zle's prompt on the same stream through Lune.
        exec 1>&2
        autoload -Uz compinit
        compinit -D
        _demo_ae() { eval "$COMMANDLINE_DEMO_COMPLETION"; }
        compdef _demo_ae ae
        ae() {
            if [[ $1 == --help || $1 == -h ]]; then
                print -r -- "$COMMANDLINE_DEMO_HELP" >&2
            else
                print -r -- "Demo only. No command was executed. Arguments were $*." >&2
            fi
        }
        PROMPT='%F{yellow}Completion demo%f %F{blue}%~%f'$'\n''> '
        RPROMPT=''
        bindkey -e
        print -r -- 'Press Tab after "ae ", "ae --", and "ae -".'
        print -r -- 'Also try "ae setup luau-lsp -" and "ae setup luau-lsp --editor ".'
        print -r -- 'Run "ae --help" to compare the normal help colors.'
        print -r -- 'This shell does not change your configuration or installed ae. Type "exit" to leave.'
    ]=]
    )
    const ok, result = pcall(process.exec, "zsh", { "-d", "-i" }, {
        env = {
            ZDOTDIR = sessionDir,
            COMMANDLINE_DEMO_COMPLETION = completion,
            COMMANDLINE_DEMO_HELP = command._helpMessage,
        },
        stdio = "inherit",
    })
    fs.removeDir(sessionDir)
    assert(ok, tostring(result))
    assert(result.ok, "The interactive zsh demo failed.")
end

ZshCompletionDemo.exec()

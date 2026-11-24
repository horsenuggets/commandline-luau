# commandline-luau

A CLI builder for Luau.

## Basic Usage

```luau
local Commandline = require("@packages/Commandline")

-- Create a simple command
local greet = Commandline.Command.new({
    Name = "greet",
    Description = "Greet someone by name.",
    Args = {
        Commandline.Arg.new({
            Name = "name",
            Description = "The name to greet.",
        }),
    },
    Impl = function(args, flags)
        print(`Hello, {args.name}!`)
    end,
})

-- Register and execute
Commandline.registerCommand(greet)
Commandline.execute("greet world")  -- Prints: Hello, world!
```

## Arguments

Arguments are positional and required by default:

```luau
Commandline.Arg.new({
    Name = "count",
    Description = "Number of times to repeat.",
    Type = "int",  -- "boolean", "int", "number", or "string" (default)
})
```

Optional arguments with defaults:

```luau
Commandline.Arg.new({
    Name = "count",
    Type = "int",
    Required = false,
    Default = 1,
})
```

## Flags

Flags are optional and support both long (`--name`) and short (`-n`) forms:

```luau
-- Boolean flag (no value)
Commandline.Flag.new({
    Name = "verbose",
    Shorthand = "v",
    Description = "Enable verbose output.",
})

-- Typed flag (requires a value)
Commandline.Flag.new({
    Name = "count",
    Shorthand = "c",
    Type = "int",
    Default = 1,
    Description = "Number of iterations.",
})
```

Access flags in your implementation:

```luau
Impl = function(args, flags)
    if flags.verbose.Value then
        print("Verbose mode enabled")
    end
    local count = flags.count.Value
end
```

## Subcommands

Commands can have subcommands instead of arguments:

```luau
local app = Commandline.Command.new({
    Name = "app",
    Description = "My CLI application.",
    Subcommands = {
        Commandline.Command.new({
            Name = "init",
            Description = "Initialize a new project.",
            Impl = function() print("Initializing...") end,
        }),
        Commandline.Command.new({
            Name = "build",
            Description = "Build the project.",
            Impl = function() print("Building...") end,
        }),
    },
})
```

## Help

A `--help` / `-h` flag is automatically added to all commands.

## Terminal Output

`Commandline.Terminal` writes styled lines with an optional timestamp prefix. Each kind of
text has a helper that paints it from the theme...

```luau
local terminal = Commandline.Terminal.new({ Timestamps = "stopwatch" })
Commandline.Terminal.setDefault(terminal)

terminal:Print(terminal:Heading("Building my-app..."))
terminal:Print(terminal:Step(1, 3, `Building {terminal:Path("C:\\Users\\me\\My Place.rbxl")}...`))
terminal:Print(`Listening on {terminal:Address("localhost:34872")}.`)
terminal:Print(`Downloaded {terminal:Count(15)} packages!`)
terminal:Print(terminal:Success("Build completed successfully!"))
```

`Path` shows every path with forward slashes, collapses the home folder to `~`, ends
directories with `/` when given `{ Directory = true }`, and shows spaces as `·`. Place and
model files use the Roblox path style (cyan bold), and other paths are gray.

**Timestamps**

Pass `Timestamps` as a setting string or a `Commandline.Timestamp` config...

- `disabled` → No prefix (the default).
- `stopwatch` → Time since the terminal was created, like `[00:01.234]`.
- `utc` → UTC wall clock time, like `[19:05:09.042]`.
- `local` → Local wall clock time.
- `utc+9`, `utc-05:30` → Wall clock time at a fixed offset.

Setting the `COMMANDLINE_TIMESTAMPS` environment variable to any of these overrides the
app's choice, and `NO_COLOR` turns color off. Lines printed to a terminal window wrap at
word boundaries, with continuation lines aligned after the timestamp. Pass `Columns` to
choose a width, or `0` to never wrap. `terminal:Stream()` returns a writer that splits
streamed output, such as a child process's standard output, into timestamped lines.

**Themes**

Every theme entry (`Address`, `Count`, `Error`, `Faint`, `Heading`, `Identifier`, `Muted`,
`Path`, `RobloxPath`, `StepBracket`, `StepCurrent`, `StepTotal`, `Success`,
`TimestampBracket`, `TimestampFaint`, `TimestampText`, `Url`, and `Warning`) can be
overridden with a spec of `Bold`, `Color`, `Dim`, `Italic`, and `Underline`. Colors are
names like `cyanBright` or hex values like `#96cc22`. Secondary text uses solid RGB gray.
Timestamp brackets and leading zeros use the same gray with `Dim`, whose intensity or
opacity is controlled by the terminal. For example...

```luau
local terminal = Commandline.Terminal.new({
    Theme = {
        Heading = { Bold = true, Color = "magentaBright" },
        Path = { Color = "#8a8a8a", Italic = true },
    },
})
```

For terminals that support foreground RGBA (such as GhosttyX), explicitly set `Opacity`
from `0` to `1` alongside a hex `Color`. For example,
`TimestampFaint = { Color = "#a8a8a8", Opacity = 0.25 }` uses alpha `64/255`, approximately
25%. The same override on `TimestampBracket` fades the brackets. Overrides replace the
whole spec, so these do not inherit `Dim`. Do not add `Dim` unless you want its intensity
reduction multiplied by the explicit opacity.

This opts into the `ESC[38:6::R:G:B:Am` terminal extension, not ordinary truecolor. Only
use it on terminals known to support RGBA; no terminal capability is inferred. Ordinary
styles omit `Opacity` and keep their existing ANSI output. Closing the foreground style
restores full opacity, and disabling color emits no RGBA sequences.

Library code such as `Toolkit` prints through `Commandline.Terminal.default()`, so an app
that calls `setDefault` at startup gets the same timestamps and theme everywhere.

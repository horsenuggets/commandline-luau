# commandline-luau

A CLI builder for Luau.

## Installation

Add to your `wally.toml`:

```toml
[dependencies]
Commandline = "horsenuggets/commandline-luau@0.0.1"
```

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

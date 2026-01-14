# Changelog

## 0.0.3

- Add `Source/**` glob pattern to wally.toml include for nested file support

## 0.0.2

- Use `@self` alias in require path for better Wally compatibility
- Add `include`/`exclude` fields to wally.toml for cleaner package distribution

## 0.0.1

Initial release of the commandline-luau library.

- Command registration and execution system
- `Command` class for defining commands with arguments and flags
- `Arg` class for positional arguments with type validation
- `Flag` class for optional flags with short/long forms
- String tokenization with quote and escape handling

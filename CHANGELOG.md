# Changelog

## 0.0.3
- Added `Source/**` glob pattern to wally.toml include for nested file support

## 0.0.2
- Used `@self` alias in require path for better Wally compatibility
- Added `include`/`exclude` fields to wally.toml for cleaner package distribution

## 0.0.1
- Initial release of the commandline-luau library
- Added command registration and execution system
- Added `Command` class for defining commands with arguments and flags
- Added `Arg` class for positional arguments with type validation
- Added `Flag` class for optional flags with short/long forms
- Added string tokenization with quote and escape handling

# Changelog

## 0.0.7

- Fix chalk-luau dependency version to 0.0.1

## 0.0.6

- Fix Wally package to include kebab-case support

## 0.0.5

- (Re-release) Support kebab-case names for commands, flags, and args

## 0.0.4

- Support kebab-case names for commands, flags, and args (single hyphens between words)
- Validate against leading/trailing hyphens and consecutive hyphens

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

# Changelog

## 0.1.0
- Add Launcher module for generating launcher executable source code
- Add Toolkit.buildLauncher() for building thin launcher binaries
- Add Toolkit.installCommand() for self-install subcommands with PATH configuration
- Add Toolkit.updateCommand() for self-update subcommands with version management
- Bump lune to 0.10.4-horse.14.2

## 0.0.16
- Add file headers to auto-generated version modules
- Bump lune to 0.10.4-horse.14.1

## 0.0.15
- Add PowerShell completion generator with context-aware subcommand and flag filtering
- Add Toolkit.installCompletions() support for PowerShell profile integration
- Add colored zsh completions using compadd with ANSI escape display
- Update luau-cicd submodule with executable script bits
- Bump lune to 0.10.4-horse.14.0

## 0.0.14
- Add Toolkit.build() for compiling Lune entry points into standalone executables
- Add Toolkit.generateVersion() for creating version modules from VERSION files
- Add Toolkit.completionsCommand() for shell completion subcommands
- Add cross-platform require patching for Windows executable compatibility
- Fix test file headers to include .spec sub-extension

## 0.0.13
- Sort flags and subcommands alphabetically in help output
- Add shell completion generation for bash, zsh, and fish
- Add missing CI checks to match branch protection rules
- Add file headers to test files
- Fix .luaurc Lune typedef version

## 0.0.12
- Add auto-included --version (-v) flag when Version is set on a Command

## 0.0.11
- Fix subcommand help displaying incomplete command path instead of full path

## 0.0.10
- Show full command path in help display instead of capitalizing only the subcommand name
- Update lune to 0.10.4-horse.9.0

## 0.0.9
- Remove Packages entry from default.project.json to fix sourcemap generation in consuming projects
- Update chalk-luau dependency to 0.0.3

## 0.0.8
- Sync project config with luau-package-template
- Add claude-md submodule and switch submodule URLs to SSH
- Add dev.project.json and VS Code workspace file
- Update Testable dev-dependency to 0.1.0

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
- Add `Source/**` glob pattern to wally.toml include for nested file support

## 0.0.2
- Use `@self` alias in require path for better Wally compatibility
- Add `include`/`exclude` fields to wally.toml for cleaner package distribution

## 0.0.1
- Command registration and execution system
- `Command` class for defining commands with arguments and flags
- `Arg` class for positional arguments with type validation
- `Flag` class for optional flags with short/long forms
- String tokenization with quote and escape handling

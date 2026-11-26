# Changelog

## 0.2.14

- Returned `false` after usage errors so callers can set a failing process exit status.
- Preserved implementation results and successful help and version responses.

## 0.2.13

- Printed usage errors without timestamps, matching the untimestamped help that follows.
- Kept configured timestamps for application diagnostics and subsequent output.

## 0.2.12

- Collapsed long terminal filesystem paths to 40 columns by dropping leading folders.
- Preserved filename endings, directory slashes, Unicode clusters, and path styling.
- Left operational paths and Roblox instance paths unchanged.

## 0.2.11

- Applied a shared explicit RGB palette to built-in help, diagnostics, and progress output.
- Used foreground opacity only when the terminal confirms support, with RGB gray otherwise.
- Forwarded the shared semantic theme and color setting to every native prompt kind.
- Rendered help against the current theme and preserved disabled-color output.

## 0.2.10

- Avoided per-character tokenization of plain streamed output when tracking SGR state.
- Preserved previous-state canonicalization, resets, colors, and split escape sequences.

## 0.2.9

- Kept explicit, default, and error-following command help untimestamped and preformatted.
- Added per-write timestamp suppression without changing terminal settings or clocks.
- Preserved configured timestamps for diagnostics, versions, and subsequent output.

## 0.2.8

- Applied configured terminal timestamps to command help, diagnostics, and version output.
- Kept help and versions on standard output and sent command diagnostics to standard error.
- Added per-print wrapping control to preserve preformatted help without changing prose.
- Refined root and nested help headings, secondary text, and unlabelled error spacing.

## 0.2.7

- Added semantic terminal themes with configurable colors, attributes, and foreground opacity.
- Added optional stopwatch, UTC, local, and fixed-offset timestamps with streamed output.
- Normalized displayed paths, home prefixes, directory suffixes, and non-bold space dots.
- Wrapped terminal prose while preserving wide glyphs, combining marks, and terminal escapes.
- Kept local timestamp offsets correct through daylight saving gaps and repeated hours.
- Styled build, install, update, and completion messages through the shared terminal.

## 0.2.6

- Matched Zsh completion colors and compact spacing to CLI help output.
- Paired shorthand and long flag names for single-dash completion.
- Showed only long flag names for double-dash completion.
- Preserved nested flag parsing, exclusions, value completion, and native path fallback.
- Updated shared CI tooling, test dependencies, and published development tools.

## 0.2.5

- Standardized release asset architecture suffixes as x64 and arm64.
- Preserved installation and updates from historical release asset names.
- Preferred canonical asset names regardless of release asset ordering.
- Fixed native path completion fallback for Bash, Zsh, and Fish.
- Scoped nested Fish completions to the executable and ordered command path.
- Updated shared CI tooling, repository checks, and development dependencies.

## 0.2.4
- Fix the install command overwriting the installed binary in place, which got running copies killed on macOS
- Add SelfUpdate.copyBinary and SelfUpdate.getReplacementSteps so every binary write replaces the file instead of overwriting it
- Fix Windows replacements failing when a previous .old binary is still running by moving the binary aside to a numbered .old path
- Fix replacing a binary through a symlink giving the new file the symlink's 777 mode instead of the target's mode

## 0.2.3
- Remove .luaurc from Wally package to fix @packages alias resolution in downstream projects

## 0.2.2
- Standardize test runner with code coverage
- Include .luaurc in Wally package

## 0.2.1
- Remove Windows require patching workaround (AliasDirs, patchRelativeRequires)
- Lune now handles relative path resolution correctly in compiled executables

## 0.2.0
- Replace launcher pattern with Deno-style direct binary self-replacement
- Add SelfUpdate module for cross-platform atomic binary replacement
- Rewrite Toolkit.installCommand() to download binary directly (no launcher)
- Rewrite Toolkit.updateCommand() to replace binary in-place via SelfUpdate
- Remove Launcher module and Toolkit.buildLauncher()

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

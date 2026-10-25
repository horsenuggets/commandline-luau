--[[

SelfUpdateTest.spec

Tests for the SelfUpdate module. Verifies cross-platform binary
replacement, cleanup, and platform detection. Uses real filesystem
operations with temp directories to test actual behavior.

--]]

const Commandline = require("@commandline")
const fs = require("@lune/fs")
const process = require("@lune/process")

const SelfUpdate = Commandline.Toolkit._SelfUpdate

const IS_WINDOWS = process.os == "windows"

const function createTempDir(): string
    const timestamp = tostring(os.time()) .. tostring(math.random(10000, 99999))
    const dir = `/tmp/selfupdate-test-{timestamp}`
    fs.writeDir(dir)
    return dir
end

const function removeTempDir(dir: string)
    if fs.isDir(dir) then
        for _, entry in fs.readDir(dir) do
            const path = dir .. "/" .. entry
            if fs.isDir(path) then
                removeTempDir(path)
            else
                fs.removeFile(path)
            end
        end
        fs.removeDir(dir)
    end
end

const function indexOf(steps: { string }, step: string): number?
    return table.find(steps, step)
end

return function()
    describe("getReplacementSteps", function()
        const EXPECTED = {
            ["unix, no target, no old"] = { "Write", "MakeExecutable" },
            ["unix, no target, old"] = { "Write", "MakeExecutable" },
            ["unix, target, no old"] = { "RemoveTarget", "Write", "MakeExecutable" },
            ["unix, target, old"] = { "RemoveTarget", "Write", "MakeExecutable" },
            ["windows, no target, no old"] = { "Write" },
            ["windows, no target, old"] = { "RemoveOld", "Write" },
            ["windows, target, no old"] = { "MoveTargetToOld", "Write" },
            ["windows, target, old"] = { "RemoveOld", "MoveTargetToOld", "Write" },
        }

        for _, isWindows in { false, true } do
            for _, targetExists in { false, true } do
                for _, oldExists in { false, true } do
                    const platform = if isWindows then "windows" else "unix"
                    const target = if targetExists then "target" else "no target"
                    const old = if oldExists then "old" else "no old"
                    const label = `{platform}, {target}, {old}`
                    const options = {
                        IsWindows = isWindows,
                        OldExists = oldExists,
                        TargetExists = targetExists,
                    }

                    it(`should return the expected steps for {label}`, function()
                        expect(table.concat(SelfUpdate.getReplacementSteps(options), ",")).to.equal(
                            table.concat(EXPECTED[label], ",")
                        )
                    end)

                    it(`should never write into an existing target for {label}`, function()
                        const steps = SelfUpdate.getReplacementSteps(options)
                        const writeIndex = indexOf(steps, "Write")
                        expect(writeIndex).to.be.ok()

                        local writes = 0
                        for _, step in steps do
                            if step == "Write" then
                                writes += 1
                            end
                        end
                        expect(writes).to.equal(1)

                        if targetExists then
                            const clearIndex = indexOf(steps, if isWindows then "MoveTargetToOld" else "RemoveTarget")
                            expect(clearIndex).to.be.ok()
                            expect((clearIndex :: number) < (writeIndex :: number)).to.equal(true)
                        end
                    end)

                    it(`should only make the binary executable on Unix for {label}`, function()
                        const steps = SelfUpdate.getReplacementSteps(options)
                        if isWindows then
                            expect(indexOf(steps, "MakeExecutable")).to.equal(nil)
                        else
                            expect(steps[#steps]).to.equal("MakeExecutable")
                        end
                    end)

                    it(`should be pure for {label}`, function()
                        expect(table.concat(SelfUpdate.getReplacementSteps(options), ",")).to.equal(
                            table.concat(SelfUpdate.getReplacementSteps(options), ",")
                        )
                    end)
                end
            end
        end

        it("should validate options", function()
            expect(function()
                SelfUpdate.getReplacementSteps({ IsWindows = true } :: any)
            end).to.throw()
        end)
    end)

    describe("replaceBinary", function()
        it("should replace an existing file with new contents", function()
            const dir = createTempDir()
            const targetPath = dir .. "/testbinary"

            fs.writeFile(targetPath, "old contents")
            SelfUpdate.replaceBinary({
                targetPath = targetPath,
                newContents = "new contents",
            })

            expect(fs.readFile(targetPath)).to.equal("new contents")
            removeTempDir(dir)
        end)

        it("should create the file if it does not exist", function()
            const dir = createTempDir()
            const targetPath = dir .. "/newbinary"

            SelfUpdate.replaceBinary({
                targetPath = targetPath,
                newContents = "brand new",
            })

            expect(fs.isFile(targetPath)).to.equal(true)
            expect(fs.readFile(targetPath)).to.equal("brand new")
            removeTempDir(dir)
        end)

        if not IS_WINDOWS then
            it("should set executable permissions on Unix", function()
                const dir = createTempDir()
                const targetPath = dir .. "/execbinary"

                SelfUpdate.replaceBinary({
                    targetPath = targetPath,
                    newContents = "executable",
                })

                -- Verify executable bit via test -x
                const result = process.exec("test", { "-x", targetPath })
                expect(result.ok).to.equal(true)
                removeTempDir(dir)
            end)

            it("should handle replacing a file that is being read", function()
                -- On Unix, unlink + replace works even if the file
                -- has open references (kernel reference counting)
                const dir = createTempDir()
                const targetPath = dir .. "/readbinary"

                fs.writeFile(targetPath, "original data")

                -- Read the file to hold a reference (simulates a
                -- running process)
                const _content = fs.readFile(targetPath)

                SelfUpdate.replaceBinary({
                    targetPath = targetPath,
                    newContents = "replaced data",
                })

                expect(fs.readFile(targetPath)).to.equal("replaced data")
                removeTempDir(dir)
            end)

            it("should write to a fresh inode instead of the existing file", function()
                -- A hard link shares the target's inode, so it only changes if the
                -- target is written in place, which is what kills running binaries
                const dir = createTempDir()
                const targetPath = dir .. "/inodebinary"
                const linkPath = dir .. "/inodelink"

                fs.writeFile(targetPath, "running binary")
                expect(process.exec("ln", { targetPath, linkPath }).ok).to.equal(true)

                SelfUpdate.replaceBinary({
                    targetPath = targetPath,
                    newContents = "new binary",
                })

                expect(fs.readFile(targetPath)).to.equal("new binary")
                expect(fs.readFile(linkPath)).to.equal("running binary")
                removeTempDir(dir)
            end)
        end

        it("should validate options", function()
            expect(function()
                SelfUpdate.replaceBinary({ targetPath = 123 } :: any)
            end).to.throw()

            expect(function()
                SelfUpdate.replaceBinary({ newContents = "test" } :: any)
            end).to.throw()
        end)
    end)

    describe("copyBinary", function()
        it("should copy the source contents to the target", function()
            const dir = createTempDir()
            const sourcePath = dir .. "/source"
            const targetPath = dir .. "/target"

            fs.writeFile(sourcePath, "source binary")
            fs.writeFile(targetPath, "stale binary")
            SelfUpdate.copyBinary({
                sourcePath = sourcePath,
                targetPath = targetPath,
            })

            expect(fs.readFile(targetPath)).to.equal("source binary")
            expect(fs.readFile(sourcePath)).to.equal("source binary")
            removeTempDir(dir)
        end)

        it("should keep the contents when copying a binary onto itself", function()
            const dir = createTempDir()
            const path = dir .. "/selfbinary"

            fs.writeFile(path, "self binary")
            SelfUpdate.copyBinary({
                sourcePath = path,
                targetPath = path,
            })

            expect(fs.readFile(path)).to.equal("self binary")
            removeTempDir(dir)
        end)

        if not IS_WINDOWS then
            it("should replace rather than overwrite when copying onto itself", function()
                const dir = createTempDir()
                const path = dir .. "/selfbinary"
                const linkPath = dir .. "/selflink"

                fs.writeFile(path, "self binary")
                expect(process.exec("ln", { path, linkPath }).ok).to.equal(true)

                SelfUpdate.copyBinary({
                    sourcePath = path,
                    targetPath = path,
                })

                -- The link still points at the original inode. Rewriting it would show
                -- up in the copy if the copy had been written in place.
                fs.writeFile(linkPath, "changed")
                expect(fs.readFile(path)).to.equal("self binary")
                expect(process.exec("test", { "-x", path }).ok).to.equal(true)
                removeTempDir(dir)
            end)
        end

        it("should validate options", function()
            expect(function()
                SelfUpdate.copyBinary({ sourcePath = "a" } :: any)
            end).to.throw()

            expect(function()
                SelfUpdate.copyBinary({ targetPath = "b" } :: any)
            end).to.throw()
        end)
    end)

    describe("getFreeOldPath", function()
        it("should use .old when it is free", function()
            expect(SelfUpdate.getFreeOldPath("C:/bin/tool.exe", {})).to.equal("C:/bin/tool.exe.old")
        end)

        it("should skip paths that are still taken", function()
            expect(SelfUpdate.getFreeOldPath("C:/bin/tool.exe", {
                ["C:/bin/tool.exe.old"] = true,
            })).to.equal("C:/bin/tool.exe.old.1")

            expect(SelfUpdate.getFreeOldPath("C:/bin/tool.exe", {
                ["C:/bin/tool.exe.old"] = true,
                ["C:/bin/tool.exe.old.1"] = true,
                ["C:/bin/tool.exe.old.2"] = true,
            })).to.equal("C:/bin/tool.exe.old.3")
        end)

        it("should reuse a gap left by a removed path", function()
            expect(SelfUpdate.getFreeOldPath("C:/bin/tool.exe", {
                ["C:/bin/tool.exe.old.1"] = true,
            })).to.equal("C:/bin/tool.exe.old")
        end)
    end)

    describe("isOldBinaryName", function()
        it("should match .old and numbered .old names", function()
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.old")).to.equal(true)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.old.1")).to.equal(true)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.old.42")).to.equal(true)
        end)

        it("should not match other files", function()
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe")).to.equal(false)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.old.")).to.equal(false)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.old.bak")).to.equal(false)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "tool.exe.older")).to.equal(false)
            expect(SelfUpdate.isOldBinaryName("tool.exe", "other.exe.old")).to.equal(false)
            expect(SelfUpdate.isOldBinaryName("tool", "tool.exe.old")).to.equal(false)
        end)
    end)

    describe("findOldBinaries", function()
        it("should list only the leftover .old copies of the binary", function()
            const dir = createTempDir()
            const binaryPath = dir .. "/tool"

            for _, fileName in { "tool", "tool.old", "tool.old.1", "tool.old.bak", "other.old" } do
                fs.writeFile(dir .. "/" .. fileName, "")
            end

            const found = SelfUpdate.findOldBinaries(binaryPath)
            expect(table.concat(found, ",")).to.equal(`{binaryPath}.old,{binaryPath}.old.1`)
            removeTempDir(dir)
        end)

        it("should return nothing when the directory does not exist", function()
            expect(#SelfUpdate.findOldBinaries("/nonexistent-dir-" .. tostring(os.time()) .. "/tool")).to.equal(0)
        end)
    end)

    describe("cleanupOldBinary", function()
        it("should remove numbered .old files too", function()
            const dir = createTempDir()
            const binaryPath = dir .. "/tool"

            fs.writeFile(binaryPath .. ".old", "stale binary")
            fs.writeFile(binaryPath .. ".old.1", "stale binary")
            SelfUpdate.cleanupOldBinary(binaryPath)

            expect(fs.isFile(binaryPath .. ".old")).to.equal(false)
            expect(fs.isFile(binaryPath .. ".old.1")).to.equal(false)
            removeTempDir(dir)
        end)

        it("should remove .old file if it exists", function()
            const dir = createTempDir()
            const binaryPath = dir .. "/tool"
            const oldPath = binaryPath .. ".old"

            fs.writeFile(oldPath, "stale binary")
            SelfUpdate.cleanupOldBinary(binaryPath)

            expect(fs.isFile(oldPath)).to.equal(false)
            removeTempDir(dir)
        end)

        it("should do nothing if no .old file exists", function()
            const dir = createTempDir()
            const binaryPath = dir .. "/tool"

            -- Should not error
            SelfUpdate.cleanupOldBinary(binaryPath)
            removeTempDir(dir)
        end)
    end)

    describe("findExecutable", function()
        it("should find a known executable", function()
            -- "ls" exists on all Unix systems, "cmd" on Windows
            const name = if IS_WINDOWS then "cmd" else "ls"
            const path = SelfUpdate.findExecutable(name)
            expect(path).to.be.ok()
        end)

        it("should return nil for a non-existent executable", function()
            const path = SelfUpdate.findExecutable("nonexistent-tool-" .. tostring(os.time()))
            expect(path).to.equal(nil)
        end)
    end)

    describe("getPlatformSuffix", function()
        it("should return a non-empty string", function()
            const suffix = SelfUpdate.getPlatformSuffix()
            expect(type(suffix)).to.equal("string")
            expect(#suffix > 0).to.equal(true)
        end)

        it("should contain an OS component", function()
            const suffix = SelfUpdate.getPlatformSuffix()
            const hasOs = string.find(suffix, "macos") or string.find(suffix, "linux") or string.find(suffix, "windows")
            expect(hasOs).to.be.ok()
        end)

        it("should contain an architecture component", function()
            const suffix = SelfUpdate.getPlatformSuffix()
            const hasArch = string.find(suffix, "x86_64") or string.find(suffix, "aarch64")
            expect(hasArch).to.be.ok()
        end)

        it("should use dash as separator", function()
            const suffix = SelfUpdate.getPlatformSuffix()
            expect(string.find(suffix, "%-")).to.be.ok()
        end)
    end)
end

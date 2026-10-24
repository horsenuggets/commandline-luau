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

return function()
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

    describe("cleanupOldBinary", function()
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

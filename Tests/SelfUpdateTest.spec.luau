--[[

SelfUpdateTest.spec

Tests for the SelfUpdate module. Verifies cross-platform binary
replacement, cleanup, and platform detection. Uses real filesystem
operations with temp directories to test actual behavior.

--]]

local Commandline = require("@commandline")
local fs = require("@lune/fs")
local process = require("@lune/process")

local SelfUpdate = Commandline.Toolkit._SelfUpdate

local IS_WINDOWS = process.os == "windows"

local function createTempDir(): string
    local timestamp = tostring(os.time()) .. tostring(math.random(10000, 99999))
    local dir = `/tmp/selfupdate-test-{timestamp}`
    fs.writeDir(dir)
    return dir
end

local function removeTempDir(dir: string)
    if fs.isDir(dir) then
        for _, entry in fs.readDir(dir) do
            local path = dir .. "/" .. entry
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
            local dir = createTempDir()
            local targetPath = dir .. "/testbinary"

            fs.writeFile(targetPath, "old contents")
            SelfUpdate.replaceBinary({
                targetPath = targetPath,
                newContents = "new contents",
            })

            expect(fs.readFile(targetPath)).to.equal("new contents")
            removeTempDir(dir)
        end)

        it("should create the file if it does not exist", function()
            local dir = createTempDir()
            local targetPath = dir .. "/newbinary"

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
                local dir = createTempDir()
                local targetPath = dir .. "/execbinary"

                SelfUpdate.replaceBinary({
                    targetPath = targetPath,
                    newContents = "executable",
                })

                -- Verify executable bit via test -x
                local result = process.exec("test", { "-x", targetPath })
                expect(result.ok).to.equal(true)
                removeTempDir(dir)
            end)

            it("should handle replacing a file that is being read", function()
                -- On Unix, unlink + replace works even if the file
                -- has open references (kernel reference counting)
                local dir = createTempDir()
                local targetPath = dir .. "/readbinary"

                fs.writeFile(targetPath, "original data")

                -- Read the file to hold a reference (simulates a
                -- running process)
                local _content = fs.readFile(targetPath)

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
            local dir = createTempDir()
            local binaryPath = dir .. "/tool"
            local oldPath = binaryPath .. ".old"

            fs.writeFile(oldPath, "stale binary")
            SelfUpdate.cleanupOldBinary(binaryPath)

            expect(fs.isFile(oldPath)).to.equal(false)
            removeTempDir(dir)
        end)

        it("should do nothing if no .old file exists", function()
            local dir = createTempDir()
            local binaryPath = dir .. "/tool"

            -- Should not error
            SelfUpdate.cleanupOldBinary(binaryPath)
            removeTempDir(dir)
        end)
    end)

    describe("findExecutable", function()
        it("should find a known executable", function()
            -- "ls" exists on all Unix systems, "cmd" on Windows
            local name = if IS_WINDOWS then "cmd" else "ls"
            local path = SelfUpdate.findExecutable(name)
            expect(path).to.be.ok()
        end)

        it("should return nil for a non-existent executable", function()
            local path = SelfUpdate.findExecutable("nonexistent-tool-" .. tostring(os.time()))
            expect(path).to.equal(nil)
        end)
    end)

    describe("getPlatformSuffix", function()
        it("should return a non-empty string", function()
            local suffix = SelfUpdate.getPlatformSuffix()
            expect(type(suffix)).to.equal("string")
            expect(#suffix > 0).to.equal(true)
        end)

        it("should contain an OS component", function()
            local suffix = SelfUpdate.getPlatformSuffix()
            local hasOs = string.find(suffix, "macos") or string.find(suffix, "linux") or string.find(suffix, "windows")
            expect(hasOs).to.be.ok()
        end)

        it("should contain an architecture component", function()
            local suffix = SelfUpdate.getPlatformSuffix()
            local hasArch = string.find(suffix, "x86_64") or string.find(suffix, "aarch64")
            expect(hasArch).to.be.ok()
        end)

        it("should use dash as separator", function()
            local suffix = SelfUpdate.getPlatformSuffix()
            expect(string.find(suffix, "%-")).to.be.ok()
        end)
    end)
end

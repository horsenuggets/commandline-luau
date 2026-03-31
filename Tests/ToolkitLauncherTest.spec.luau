--[[

ToolkitLauncherTest.spec

Tests for the Toolkit launcher, install, and update command builders.
Verifies that the returned Commands have the correct structure and
metadata.

--]]

local Commandline = require("@commandline")

local Toolkit = Commandline.Toolkit

return function()
    describe("buildLauncher", function()
        it("should validate options", function()
            expect(function()
                Toolkit.buildLauncher({ Name = "test" } :: any)
            end).to.throw()
        end)
    end)

    describe("installCommand", function()
        it("should return a Command with the correct name", function()
            local cmd = Toolkit.installCommand({
                Name = "mytool",
                InstallDir = ".mytool-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(cmd.Name).to.equal("install")
        end)

        it("should include a description with the CLI name", function()
            local cmd = Toolkit.installCommand({
                Name = "rbxstudio",
                InstallDir = ".rbxstudio-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(string.find(cmd.Description, "rbxstudio")).to.be.ok()
        end)

        it("should validate options", function()
            expect(function()
                Toolkit.installCommand({ Name = "test" } :: any)
            end).to.throw()
        end)
    end)

    describe("updateCommand", function()
        it("should return a Command with the correct name", function()
            local cmd = Toolkit.updateCommand({
                Name = "mytool",
                InstallDir = ".mytool-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(cmd.Name).to.equal("update")
        end)

        it("should include a description with the CLI name", function()
            local cmd = Toolkit.updateCommand({
                Name = "rbxstudio",
                InstallDir = ".rbxstudio-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(string.find(cmd.Description, "rbxstudio")).to.be.ok()
        end)

        it("should include a version flag", function()
            local cmd = Toolkit.updateCommand({
                Name = "mytool",
                InstallDir = ".mytool-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            local hasVersionFlag = false
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    hasVersionFlag = true
                    break
                end
            end
            expect(hasVersionFlag).to.equal(true)
        end)

        it("should validate options", function()
            expect(function()
                Toolkit.updateCommand({ Name = "test" } :: any)
            end).to.throw()
        end)
    end)
end

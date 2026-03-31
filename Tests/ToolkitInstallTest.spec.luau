--[[

ToolkitInstallTest.spec

Tests for the Toolkit install and update command builders. Verifies
that the returned Commands have the correct structure, flags, and
metadata.

--]]

local Commandline = require("@commandline")

local Toolkit = Commandline.Toolkit

local TEST_OPTIONS = {
    Name = "mytool",
    InstallDir = ".mytool-cli",
    Version = "1.0.0",
    Repository = "user/repo",
}

return function()
    describe("installCommand", function()
        it("should return a Command with name 'install'", function()
            local cmd = Toolkit.installCommand(TEST_OPTIONS)
            expect(cmd.Name).to.equal("install")
        end)

        it("should include the CLI name in the description", function()
            local cmd = Toolkit.installCommand({
                Name = "rbxstudio",
                InstallDir = ".rbxstudio-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(string.find(cmd.Description, "rbxstudio")).to.be.ok()
        end)

        it("should include the install directory in the description", function()
            local cmd = Toolkit.installCommand(TEST_OPTIONS)
            expect(string.find(cmd.Description, ".mytool%-cli")).to.be.ok()
        end)

        it("should validate required options", function()
            expect(function()
                Toolkit.installCommand({ Name = "test" } :: any)
            end).to.throw()

            expect(function()
                Toolkit.installCommand({
                    Name = "test",
                    InstallDir = ".test",
                } :: any)
            end).to.throw()
        end)
    end)

    describe("updateCommand", function()
        it("should return a Command with name 'update'", function()
            local cmd = Toolkit.updateCommand(TEST_OPTIONS)
            expect(cmd.Name).to.equal("update")
        end)

        it("should include the CLI name in the description", function()
            local cmd = Toolkit.updateCommand({
                Name = "rbxstudio",
                InstallDir = ".rbxstudio-cli",
                Version = "1.0.0",
                Repository = "user/repo",
            })
            expect(string.find(cmd.Description, "rbxstudio")).to.be.ok()
        end)

        it("should include a --version flag", function()
            local cmd = Toolkit.updateCommand(TEST_OPTIONS)
            local hasVersionFlag = false
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    hasVersionFlag = true
                    break
                end
            end
            expect(hasVersionFlag).to.equal(true)
        end)

        it("should have a shorthand -v for the version flag", function()
            local cmd = Toolkit.updateCommand(TEST_OPTIONS)
            for _, flag in cmd._flags do
                if flag.Name == "version" then
                    expect(flag.Shorthand).to.equal("v")
                    break
                end
            end
        end)

        it("should validate required options", function()
            expect(function()
                Toolkit.updateCommand({ Name = "test" } :: any)
            end).to.throw()
        end)
    end)
end

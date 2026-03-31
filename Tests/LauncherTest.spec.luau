--[[

LauncherTest.spec

Tests for the Launcher source code generator. Verifies that the
generated Luau source code for launcher executables contains the
expected structure and configuration.

--]]

local Commandline = require("@commandline")

local Launcher = Commandline.Launcher

return function()
    describe("generate", function()
        it("should generate valid Luau source code", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(type(source)).to.equal("string")
            expect(#source > 0).to.equal(true)
        end)

        it("should include the CLI name", function()
            local source = Launcher.generate({
                Name = "rbxstudio",
                InstallDir = ".rbxstudio-cli",
            })
            expect(string.find(source, "rbxstudio")).to.be.ok()
        end)

        it("should include the install directory", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, ".mytool%-cli")).to.be.ok()
        end)

        it("should require lune modules", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, "@lune/fs")).to.be.ok()
            expect(string.find(source, "@lune/process")).to.be.ok()
            expect(string.find(source, "@lune/stdio")).to.be.ok()
        end)

        it("should include version management functions", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, "getCurrentVersion")).to.be.ok()
            expect(string.find(source, "cleanupOldVersions")).to.be.ok()
        end)

        it("should include cross-platform path normalization", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, "normalizePath")).to.be.ok()
            expect(string.find(source, "IS_WINDOWS")).to.be.ok()
        end)

        it("should reference the versions directory", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, "versions")).to.be.ok()
            expect(string.find(source, "current")).to.be.ok()
        end)

        it("should include process.exec for delegation", function()
            local source = Launcher.generate({
                Name = "mytool",
                InstallDir = ".mytool-cli",
            })
            expect(string.find(source, "process%.exec")).to.be.ok()
        end)

        it("should validate options", function()
            expect(function()
                Launcher.generate({ Name = "test" } :: any)
            end).to.throw()

            expect(function()
                Launcher.generate({ InstallDir = ".test" } :: any)
            end).to.throw()
        end)
    end)
end

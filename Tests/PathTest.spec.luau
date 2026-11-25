--[[

PathTest.spec

Tests for Path, covering home folder lookup on every OS and the display form of macOS,
Linux, Windows, and UNC paths.

--]]

const Path = require("../Source/Commandline/Terminal/Path")
const Text = require("../Source/Commandline/Terminal/Text")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

return function()
    describe("Path.home", function()
        it("should use HOME on macOS and Linux", function()
            expect(Path.home("macos", { HOME = "/Users/user" })).to.equal("/Users/user")
            expect(Path.home("linux", { HOME = "/home/user", USERPROFILE = "C:\\x" })).to.equal("/home/user")
        end)

        it("should prefer USERPROFILE, then HOMEDRIVE and HOMEPATH, on Windows", function()
            expect(Path.home("windows", { USERPROFILE = "C:\\Users\\user", HOME = "/x" })).to.equal("C:\\Users\\user")
            expect(Path.home("windows", { HOMEDRIVE = "D:", HOMEPATH = "\\Users\\user" })).to.equal("D:\\Users\\user")
            expect(Path.home("windows", { HOME = "/c/Users/user" })).to.equal("/c/Users/user")
        end)

        it("should return nil when no variable is set or they are empty", function()
            expect(Path.home("macos", {})).to.equal(nil)
            expect(Path.home("windows", { USERPROFILE = "" })).to.equal(nil)
        end)
    end)

    describe("Path.display", function()
        it("should match the same output on every platform", function()
            const cases = {
                { "/Users/user/.ae/bin/ae", "/Users/user", false, "~/.ae/bin/ae" },
                { "/home/user/project", "/home/user/", true, "~/project/" },
                { "C:\\Users\\user\\.ae\\bin\\ae.exe", "C:\\Users\\user", false, "~/.ae/bin/ae.exe" },
                { "c:/users/USER/Project", "C:\\Users\\user", true, "~/Project/" },
                { "C:\\Users\\user", "C:\\Users\\user", true, "~/" },
                { "/Users/user", "/Users/user", false, "~" },
                { "/Users/username/file", "/Users/user", false, "/Users/username/file" },
                { "/tmp/ae/Place.rbxl", "/Users/user", false, "/tmp/ae/Place.rbxl" },
                { "Source\\AeCliTool", nil, true, "Source/AeCliTool/" },
                { "Source//AeCliTool//", nil, true, "Source/AeCliTool/" },
                { "\\\\server\\share\\file", "C:\\Users\\user", false, "//server/share/file" },
                { "/", nil, true, "/" }
            }
            for _, case in cases do
                expect(Path.display(case[1], case[2], case[3])).to.equal(case[4])
            end
        end)

        it("should keep paths case-sensitive outside Windows", function()
            expect(Path.display("/users/user/x", "/Users/user")).to.equal("/users/user/x")
        end)

        it("should be stable when run on its own output", function()
            for _, path in { "C:\\Users\\user\\a b\\", "/Users/user/x", "relative\\dir" } do
                const once = Path.display(path, "C:\\Users\\user", true)
                expect(Path.display(once, "C:\\Users\\user", true)).to.equal(once)
            end
        end)
    end)

    describe("Path.shorten", function()
        it("should leave paths of at most 40 columns intact", function()
            for _, path in { "", "/", "~/", "Build/Place.rbxl", string.rep("a", 40), string.rep("界", 20) } do
                expect(Path.shorten(path)).to.equal(path)
            end
        end)

        it("should drop whole leading folders with either slash style", function()
            const ending = "Build/Place.dev.rbxl"
            for _, prefix in
                {
                    "/a-very-long-root-folder/project/",
                    "~/a-very-long-root-folder/project/",
                    "C:\\a-very-long-root-folder\\project\\",
                    "\\\\server\\a-very-long-root-folder\\project\\"
                }
            do
                const path = `{prefix}{ending}`
                expect(Path.shorten(path)).to.equal(`.../project/{ending}`)
                expect(Path.shorten(`{path}/`)).to.equal(`.../project/{ending}/`)
            end
            const exact = `folder/{string.rep("a", 34)}`
            expect(Path.shorten(exact)).to.equal(`.../{string.rep("a", 34)}`)
            expect(Path.shorten(`long-root/{string.rep("a", 36)}`)).to.equal(`.../{string.rep("a", 36)}`)
        end)

        it("should preserve the ending of oversized final components", function()
            for _, suffix in { "", "/" } do
                const path = `root/{string.rep("x", 50)}.rbxl{suffix}`
                expect(Path.shorten(path)).to.equal(`...{string.rep("x", 32 - #suffix)}.rbxl{suffix}`)
                expect(Text.width(Path.shorten(path))).to.equal(40)
            end
            expect(Path.shorten(string.rep("a", 41))).to.equal(`...{string.rep("a", 37)}`)
        end)

        it("should count display columns without splitting Unicode clusters", function()
            for _, cluster in
                { "界", "e\u{301}", "\u{1f469}\u{200d}\u{1f4bb}", "\u{1f1fa}\u{1f1f8}", "1\u{fe0f}\u{20e3}" }
            do
                const count = math.floor(37 / Text.width(cluster))
                const expected = `...{string.rep(cluster, count)}`
                expect(Path.shorten(string.rep(cluster, 50))).to.equal(expected)
                expect(Text.width(expected) <= 40).to.equal(true)
            end
        end)

        it("should keep every path within the limit and remain stable", function()
            for _, folderLength in { 1, 20, 40, 80 } do
                for _, filenameLength in { 1, 31, 32, 35, 36, 37, 40, 80 } do
                    for _, depth in { 0, 1, 4 } do
                        for _, suffix in { "", "/" } do
                            const filename = `{string.rep("f", filenameLength)}.txt`
                            const path = `{string.rep(`{string.rep("d", folderLength)}/`, depth)}{filename}{suffix}`
                            const shortened = Path.shorten(path)
                            expect(Text.width(shortened) <= 40).to.equal(true)
                            expect(Path.shorten(shortened)).to.equal(shortened)
                            expect(Path.shorten(path)).to.equal(shortened)
                            expect(string.sub(shortened, -4 - #suffix)).to.equal(`.txt{suffix}`)
                            if Text.width(path) <= 40 then
                                expect(shortened).to.equal(path)
                            elseif #filename + #suffix <= 36 then
                                expect(string.find(shortened, `/{filename}{suffix}`, 1, true) ~= nil).to.equal(true)
                            end
                        end
                    end
                end
            end
        end)
    end)

    describe("Path.isRobloxFile", function()
        it("should recognize place and model files in any case", function()
            for _, path in { "a.rbxl", "a.rbxlx", "a.rbxm", "a.rbxmx", "A.RBXL" } do
                expect(Path.isRobloxFile(path)).to.equal(true)
            end
            for _, path in { "a.luau", "rbxl", "a.rbxl.bak", "a.json" } do
                expect(Path.isRobloxFile(path)).to.equal(false)
            end
        end)
    end)

    describe("Path.fileName", function()
        it("should return the last component with either slash style", function()
            expect(Path.fileName("C:\\tmp\\Place.rbxl")).to.equal("Place.rbxl")
            expect(Path.fileName("/tmp/ae/")).to.equal("ae")
            expect(Path.fileName("Place.rbxl")).to.equal("Place.rbxl")
        end)
    end)
end

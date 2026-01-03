local Testable = require("@packages/Testable")
local process = require("@lune/process")

local TESTS = {
    { Name = "TypeUtilsTest", Func = require("../Tests/TypeUtilsTest.spec") },
    { Name = "StringUtilsTest", Func = require("../Tests/StringUtilsTest.spec") },
    { Name = "ArgTest", Func = require("../Tests/ArgTest.spec") },
    { Name = "FlagTest", Func = require("../Tests/FlagTest.spec") },
    { Name = "CommandTest", Func = require("../Tests/CommandTest.spec") },
    { Name = "CommandlineTest", Func = require("../Tests/CommandlineTest.spec") },
}

local function runTests()
    local _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

runTests()

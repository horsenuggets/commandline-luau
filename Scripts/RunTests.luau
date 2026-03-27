#!/usr/bin/env -S lune run

--[[

RunTests

Executes all test suites and exits with appropriate status code.

[Usage] ./Scripts/RunTests.luau

--]]

local Testable = require("@devpackages/Testable")
local process = require("@lune/process")

local TESTS = {
    { Name = "ArgTest", Func = require("../Tests/ArgTest.spec") },
    { Name = "CommandTest", Func = require("../Tests/CommandTest.spec") },
    { Name = "CommandlineTest", Func = require("../Tests/CommandlineTest.spec") },
    { Name = "CompletionsTest", Func = require("../Tests/CompletionsTest.spec") },
    { Name = "FlagTest", Func = require("../Tests/FlagTest.spec") },
    { Name = "StringUtilsTest", Func = require("../Tests/StringUtilsTest.spec") },
    { Name = "ToolkitTest", Func = require("../Tests/ToolkitTest.spec") },
    { Name = "TypeUtilsTest", Func = require("../Tests/TypeUtilsTest.spec") },
}

local function runTests()
    local _, passed = Testable.run(TESTS)
    process.exit(if passed then 0 else 1)
end

runTests()

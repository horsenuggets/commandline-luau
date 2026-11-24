--[[

TimestampTest.spec

Tests for Timestamp, covering setting parsing, validation, stopwatch formatting with its
faint lead, and clock formatting in UTC, local time, and fixed offsets.

--]]

const Timestamp = require("../Source/Commandline/Terminal/Timestamp")

const Testable = require("@devpackages/Testable")
const describe, expect, it = Testable.describe, Testable.expect, Testable.it

-- 2026-11-23 19:05:09.042 UTC
const UNIX_MILLIS = 1795460709042

const function sample(elapsed: number, localOffset: number?): Timestamp.Sample
    return { ElapsedSeconds = elapsed, LocalOffsetMinutes = localOffset or 0, UnixMillis = UNIX_MILLIS }
end

const function joined(config: Timestamp.Config, value: Timestamp.Sample): string?
    const faint, text = Timestamp.format(config, value)
    if faint == nil then
        return nil
    end
    return `{faint}|{text}`
end

return function()
    describe("Timestamp.parse", function()
        it("should parse named settings in any case and spacing", function()
            const cases = {
                { "stopwatch", "Stopwatch" },
                { " UTC ", "Utc" },
                { "Local", "Local" },
                { "disabled", "Disabled" },
                { "off", "Disabled" },
                { "none", "Disabled" }
            }
            for _, case in cases do
                const config = Timestamp.parse(case[1])
                expect(config and config.Mode).to.equal(case[2])
            end
        end)

        it("should parse fixed offsets", function()
            const cases = {
                { "utc+9", 540 },
                { "UTC-05:30", -330 },
                { "+0530", 330 },
                { "-8", -480 },
                { "utc+14", 840 }
            }
            for _, case in cases do
                const config = Timestamp.parse(case[1])
                expect(config and config.Mode).to.equal("Offset")
                expect(config and config.OffsetMinutes).to.equal(case[2])
            end
        end)

        it("should reject unknown settings and impossible offsets", function()
            for _, spec in { "", "sometimes", "utc+", "utc+9:75", "+19", "utc*3" } do
                const config, problem = Timestamp.parse(spec)
                expect(config).to.equal(nil)
                expect(type(problem)).to.equal("string")
            end
        end)
    end)

    describe("Timestamp.format", function()
        it("should return nothing when disabled", function()
            expect(joined(Timestamp.Disabled, sample(5))).to.equal(nil)
        end)

        it("should dim a stopwatch's leading zeros and colons", function()
            const cases = {
                { 0, "00:00|.000" },
                { 0.001, "00:00|.001" },
                { 1.234, "00:0|1.234" },
                { 12.345, "00:|12.345" },
                { 83.5, "0|1:23.500" },
                { 754.9999, "|12:34.999" },
                { 3723.004, "|1:02:03.004" }
            }
            for _, case in cases do
                expect(joined({ Mode = "Stopwatch" }, sample(case[1]))).to.equal(case[2])
            end
        end)

        it("should clamp a negative stopwatch to zero", function()
            expect(joined({ Mode = "Stopwatch" }, sample(-1))).to.equal("00:00|.000")
        end)

        it("should format clock modes without a faint lead", function()
            expect(joined({ Mode = "Utc" }, sample(0))).to.equal("|19:05:09.042")
            expect(joined({ Mode = "Local" }, sample(0, -360))).to.equal("|13:05:09.042")
            expect(joined({ Mode = "Offset", OffsetMinutes = 330 }, sample(0))).to.equal("|00:35:09.042")
            expect(joined({ Mode = "Offset", OffsetMinutes = -1080 }, sample(0))).to.equal("|01:05:09.042")
        end)

        it("should give the same result for the same input", function()
            for _, mode in { "Stopwatch", "Utc", "Local" } do
                const config = { Mode = mode } :: Timestamp.Config
                expect(joined(config, sample(9.5, 60))).to.equal(joined(config, sample(9.5, 60)))
            end
        end)

        it("should reject invalid configs", function()
            expect(function()
                Timestamp.format({ Mode = "Sometimes" } :: any, sample(0))
            end).to.throw()
            expect(function()
                Timestamp.format({ Mode = "Offset" }, sample(0))
            end).to.throw()
            expect(function()
                Timestamp.format({ Mode = "Offset", OffsetMinutes = 1.5 }, sample(0))
            end).to.throw()
        end)
    end)
end

--[[

Flag

Defines the Flag class for representing optional command-line flags. Flags can be boolean
(no value) or typed (boolean, int, number, string). They support both long form (--name)
and optional single-character shorthand (-n).

--]]

local TypeUtils = require("./Helpers/TypeUtils")
local t = require("@packages/t")

export type Flag = {
    Name: string,
    Description: string,
    Type: TypeUtils.ArgType?,
    Shorthand: string?,
    Default: any?,
}
export type FlagOptions = {
    Name: string,
    Description: string?,
    Type: TypeUtils.ArgType?,
    Shorthand: string?,
    Default: any?,
}

local IFlagOptions = t.strictInterface({
    Name = t.string,
    Description = t.optional(t.string),
    Type = t.optional(t.string),
    Shorthand = t.optional(t.string),
    Default = t.optional(t.any),
})

local Flag = {}
Flag.__index = Flag

function Flag.new(flagOptions: FlagOptions)
    assert(IFlagOptions(flagOptions), "Invalid Flag options provided.")

    local self = setmetatable({}, Flag)

    self.Name = flagOptions.Name
    self.Description = flagOptions.Description or "No description."
    self.Type = flagOptions.Type -- No default type
    self.Shorthand = flagOptions.Shorthand
    self.Default = flagOptions.Default

    -- If shorthand is provided, it must be a single character
    if self.Shorthand then
        assert(#self.Shorthand == 1, "Shorthand must be a single character.")
    end

    -- If Type is provided, validate it
    if self.Type then
        assert(
            TypeUtils.isValidType(self.Type),
            `Invalid type "{self.Type}". Must be one of: boolean, int, number, ` .. `string.`
        )

        -- If Default is provided, validate it matches the type
        if self.Default ~= nil then
            assert(
                TypeUtils.validateValueType(self.Default, self.Type),
                `Default value for Flag "{self.Name}" does not match type ` .. `"{self.Type}".`
            )
        end
    else
        -- If Type is not provided, then Default should be nil
        assert(self.Default == nil, "No Default should be provided if there is no Type.")
    end

    return self
end

return Flag

--[[

Arg

Defines the Arg class for representing positional command-line arguments. Args are
required by default and support type validation (boolean, int, number, string). They can
have optional default values, which makes them non-required.

--]]

local TypeUtils = require("./Helpers/TypeUtils")
local t = require("@packages/t")

export type Arg = {
    Name: string,
    Description: string,
    Type: TypeUtils.ArgType,
    Required: boolean,
    Default: any?,
}
export type ArgOptions = {
    Name: string,
    Description: string?,
    Type: TypeUtils.ArgType?,
    Required: boolean?,
    Default: any?,
}

local IArgOptions = t.strictInterface({
    Name = t.string,
    Description = t.optional(t.string),
    Type = t.optional(t.string),
    Required = t.optional(t.boolean),
    Default = t.optional(t.any),
})

local Arg = {}
Arg.__index = Arg

function Arg.new(argOptions: ArgOptions)
    assert(IArgOptions(argOptions), "Invalid Arg options provided.")

    local self = setmetatable({}, Arg)

    self.Name = argOptions.Name
    self.Description = argOptions.Description or "No description."
    self.Type = argOptions.Type or "string"
    self.Required = if argOptions.Required ~= nil
        then argOptions.Required
        else true
    self.Default = argOptions.Default

    -- Validate type is valid
    assert(
        TypeUtils.isValidType(self.Type),
        `Invalid type "{self.Type}". Must be one of: boolean, int, number, ` ..
            `string.`
    )

    -- If a default value is provided, the Arg cannot be required
    if self.Default ~= nil then
        assert(
            not self.Required,
            "Cannot have a default value for a required Arg."
        )

        -- Validate that the default value matches the type
        assert(
            TypeUtils.validateValueType(self.Default, self.Type),
            `Default value for Arg "{self.Name}" does not match type ` ..
                `"{self.Type}".`
        )
    end

    return self
end

return Arg

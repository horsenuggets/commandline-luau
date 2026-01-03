--[[

TypeUtils

Type validation and casting utilities for Args and Flags. Supports boolean, int, number,
and string types with conversion from string tokens.

--]]

local TypeUtils = {
    None = {},
    ValidTypes = {
        boolean = true,
        int = true,
        number = true,
        string = true,
    } :: { [string]: boolean },
}

export type ArgType = "boolean" | "int" | "number" | "string"

-- Returns the value if it's not nil and matches the type of defaultValue, otherwise
-- returns the defaultValue.
function TypeUtils.default<T>(value: T?, defaultValue: T): T
    if value == nil or typeof(value) ~= typeof(defaultValue) then
        return defaultValue
    else
        return value
    end
end

-- Checks if a type name is one of the valid ArgType values.
function TypeUtils.isValidType(typeName: string): boolean
    return TypeUtils.ValidTypes[typeName] == true
end

-- Validates that a value matches the specified ArgType (for "int" type, ensures the
-- number is a whole number).
function TypeUtils.validateValueType(value: any, typeName: ArgType): boolean
    if typeName == "boolean" then
        return type(value) == "boolean"
    elseif typeName == "int" then
        return type(value) == "number" and value == math.floor(value)
    elseif typeName == "number" then
        return type(value) == "number"
    elseif typeName == "string" then
        return type(value) == "string"
    end
    return false
end

-- Attempts to cast a string token to the specified ArgType, returning (value, nil) on
-- success or (nil, errorMessage) on failure.
function TypeUtils.castFromString(token: string, typeName: ArgType): (any?, string?)
    if typeName == "boolean" then
        local lower = token:lower()
        if lower == "true" then
            return true, nil
        elseif lower == "false" then
            return false, nil
        else
            return nil, `Unable to cast "{token}" to boolean. Expected "true" or "false".`
        end
    elseif typeName == "int" then
        local num = tonumber(token)
        if num == nil then
            return nil, `Unable to cast "{token}" to int. Not a valid number.`
        end
        if num ~= math.floor(num) then
            return nil, `Unable to cast "{token}" to int. Expected an integer.`
        end
        return num, nil
    elseif typeName == "number" then
        local num = tonumber(token)
        if num == nil then
            return nil, `Unable to cast "{token}" to number. Not a valid number.`
        end
        return num, nil
    elseif typeName == "string" then
        return token, nil
    end

    return nil, `Unknown type "{typeName}".`
end

return TypeUtils

--[[

StringUtils

Utility functions for string manipulation and validation. Includes tokenization of command
strings with support for quotes and escape sequences.

--]]

local StringUtils = {}

-- Capitalizes the first letter of a string, leaving the rest unchanged.
function StringUtils.capitalizeFirstLetter(str: string): string
    if #str == 0 then
        return str
    end
    return `{str:sub(1, 1):upper()}{str:sub(2)}`
end

-- Checks if a string contains only lowercase alphanumeric characters (a-z, 0-9).
function StringUtils.isAlphanumericLowercase(str: string): boolean
    if #str == 0 then
        return false
    end
    return str:match("^[a-z0-9]+$") ~= nil
end

-- Asserts that a string is alphanumeric and lowercase, throwing an error if not.
function StringUtils.assertAlphanumericLowercase(str: string, fieldName: string): string
    assert(
        StringUtils.isAlphanumericLowercase(str),
        `{fieldName} must be alphanumeric and lowercase, got "{str}".`
    )
    return str
end

--[[

Tokenize a command string, respecting quotes and escape sequences.

[Rules]
- Quoted strings (") are treated as a single token
- Quotes are removed from the final token
- Escape sequences are processed: \" (quote) and \\ (backslash)
- Whitespace outside quotes separates tokens

[Examples]
- 'foo bar' -> {"foo", "bar"}
- 'foo "bar baz"' -> {"foo", "bar baz"}
- 'foo "bar \"quoted\" baz"' -> {"foo", "bar "quoted" baz"}
- 'foo "bar\\baz"' -> {"foo", "bar\baz"}

--]]
function StringUtils.tokenize(input: string): ({ string }, string?)
    local tokens = {}
    local currentToken = {}
    local inQuote = false
    local escaped = false
    local i = 1

    while i <= #input do
        local char = input:sub(i, i)

        if escaped then
            -- Process escape sequence
            if char == '"' then
                table.insert(currentToken, '"')
            elseif char == "\\" then
                table.insert(currentToken, "\\")
            else
                -- Unknown escape sequence, treat backslash literally
                table.insert(currentToken, "\\")
                table.insert(currentToken, char)
            end
            escaped = false
        elseif char == "\\" then
            -- Start escape sequence
            escaped = true
        elseif char == '"' then
            -- Toggle quote mode
            inQuote = not inQuote
        elseif char:match("%s") then
            -- Whitespace
            if inQuote then
                -- Inside quotes, preserve whitespace
                table.insert(currentToken, char)
            else
                -- Outside quotes, whitespace ends the current token
                if #currentToken > 0 then
                    table.insert(tokens, table.concat(currentToken))
                    currentToken = {}
                end
            end
        else
            -- Regular character
            table.insert(currentToken, char)
        end

        i = i + 1
    end

    -- Check for unclosed quote
    if inQuote then
        return {}, "Unclosed quote in command string."
    end

    -- Check for trailing backslash
    if escaped then
        return {}, "Trailing backslash in command string."
    end

    -- Add final token if any
    if #currentToken > 0 then
        table.insert(tokens, table.concat(currentToken))
    end

    return tokens, nil
end

return StringUtils

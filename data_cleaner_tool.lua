-- data_cleaner.lua
local Cleaner = {}

------------------------------------------------------------
-- BASIC STRING CLEANERS
------------------------------------------------------------

-- Trim whitespace from start and end
function Cleaner.trim(s)
    if type(s) ~= "string" then return s end
    return s:match("^%s*(.-)%s*$")
end

-- Remove *all* spaces from a string
function Cleaner.removeSpaces(s)
    if type(s) ~= "string" then return s end
    return s:gsub("%s+", "")
end

-- Replace spaces with underscores
function Cleaner.replaceSpacesWithUnderscore(s)
    if type(s) ~= "string" then return s end
    return s:gsub("%s+", "_")
end

-- Keep only alphanumeric characters (letters and numbers)
function Cleaner.keepAlphanumeric(s)
    if type(s) ~= "string" then return s end
    return s:gsub("[^%w]", "")  -- %w matches alphanumeric characters
end

------------------------------------------------------------
-- NUMERIC + FORMAT CLEANERS
------------------------------------------------------------

-- Remove trailing zeroes after a decimal (e.g. "3.5000" -> "3.5", "4.0" -> "4")
function Cleaner.removeTrailingZeroes(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("(%d+)%.?0*$", "%1")
    s = s:gsub("(%.%d*[1-9])0+$", "%1")
    return s
end

-- Remove leading zeros from numeric strings
function Cleaner.removeLeadingZeros(s)
    if type(s) ~= "string" then return s end
    return s:gsub("^(0+)(%d)", "%2")
end

-- Clean string to integer
function Cleaner.cleanIntegerString(s)
    if type(s) ~= "string" then return s end
    local num = tonumber(s)
    if num then return tostring(math.floor(num)) end
    return s
end

-- Format string to decimal
function Cleaner.formatDecimalString(s)
    if type(s) ~= "string" then return s end
    local num = tonumber(s)
    if num then return tostring(num) end
    return s
end

-- Extract last 3 characters (example: day code)
function Cleaner.formatDay(s)
    if type(s) == "string" and #s >= 3 then return s:sub(-3) end
    return s
end

-- Clean focal length strings (remove MM/mm and leading zeros)
function Cleaner.cleanFocalLength(s)
    if type(s) ~= "string" then return s end
    s = Cleaner.trim(s)
    s = s:gsub("[Mm][Mm]?", "") -- remove "mm" or "MM"
    s = Cleaner.removeLeadingZeros(s)
    local num = tonumber(s)
    if num then return tostring(math.floor(num)) end
    return s
end

-- Clean T-stop values (e.g. "T2.8000" -> "2.8", "11.220000" -> "11.22")
-- Keeps up to 2 digits before and 2 digits after the decimal, removes trailing zeros
function Cleaner.cleanTStop(s)
    if type(s) ~= "string" then return s end
    s = Cleaner.trim(s)
    
    -- Remove "T" or "t" prefix if present
    s = s:gsub("^[Tt]", "")
    
    -- Convert to number
    local num = tonumber(s)
    if not num then return s end
    
    -- Round to 2 decimal places
    num = math.floor(num * 100 + 0.5) / 100
    
    -- Convert to string with 2 decimal places
    local result = string.format("%.2f", num)
    
    -- Remove trailing zeros after decimal
    result = result:gsub("(%d+%.%d*[1-9])0+$", "%1")  -- Remove trailing zeros
    result = result:gsub("(%d+)%.0+$", "%1")           -- Remove .00 or .0
    
    return result
end

-- Remove file extension from a filename (case-insensitive)
function Cleaner.removeFileExtension(s)
    if type(s) ~= "string" then return s end
    local withoutExt = s:gsub("%.[^%.\\/]+$", "")
    return withoutExt
end

------------------------------------------------------------
-- DATE FORMATTING
------------------------------------------------------------

-- Convert a wide range of date formats to YYYYMMDD
function Cleaner.formatDate(s)
    if type(s) ~= "string" then return s end
    s = Cleaner.trim(s)

    local patterns = {
        {"(%d%d?)/(%d%d?)/(%d%d%d%d)", "mdy"},  -- 3/25/2025
        {"(%d%d?)-(%d%d?)-(%d%d%d%d)", "mdy"},  -- 3-25-2025
        {"(%d%d%d%d)/(%d%d?)/(%d%d?)", "ymd"},  -- 2025/3/25
        {"(%d%d%d%d)-(%d%d?)-(%d%d?)", "ymd"},  -- 2025-3-25
        {"(%d%d?)/(%d%d?)/(%d%d)", "mdy"},      -- 3/25/25
        {"(%d%d?)-(%d%d?)-(%d%d)", "mdy"},      -- 3-25-25
        {"(%d%d%d%d)%.(%d%d)%.(%d%d)", "ymd"},  -- 2025.03.25
    }

    for _, p in ipairs(patterns) do
        local a, b, c = s:match(p[1])
        if a and b and c then
            local y, m, d
            if p[2] == "ymd" then y, m, d = a, b, c
            else m, d, y = a, b, c end

            if #y == 2 then y = "20" .. y end
            return string.format("%04d%02d%02d", tonumber(y), tonumber(m), tonumber(d))
        end
    end

    -- Month name formats: Jan 3, 2025 or March 3 2025
    local monthMap = {
        Jan=1, January=1, Feb=2, February=2, Mar=3, March=3,
        Apr=4, April=4, May=5, Jun=6, June=6, Jul=7, July=7,
        Aug=8, August=8, Sep=9, September=9, Oct=10, October=10,
        Nov=11, November=11, Dec=12, December=12
    }

    local mStr, d, y = s:match("([A-Za-z]+)%s+(%d%d?),?%s*(%d%d%d%d)")
    if mStr and d and y then
        local mNum = monthMap[mStr]
        if mNum then
            return string.format("%04d%02d%02d", tonumber(y), mNum, tonumber(d))
        end
    end

    -- fallback: return original string if nothing matched
    return s
end

------------------------------------------------------------
-- NULL HANDLING
------------------------------------------------------------

-- Replace empty or nil values with "null"
function Cleaner.toNullIfEmpty(s)
    if s == nil or s == "" then return "null" end
    return s
end

------------------------------------------------------------
-- BULK APPLICATION
------------------------------------------------------------

-- Apply a set of cleaning rules to a metadata table
function Cleaner.applyRules(metadata, rules)
    for key, func in pairs(rules) do
        if metadata[key] ~= nil then
            local cleaned = func(metadata[key])
            metadata[key] = Cleaner.toNullIfEmpty(cleaned)
        end
    end
end

return Cleaner

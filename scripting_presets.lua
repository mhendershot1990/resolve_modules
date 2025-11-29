-- ===============================
-- Scripting Presets Module
-- ===============================
-- JSON-based preset storage for DaVinci Resolve scripts
-- Automatically creates "script_name"_presets folder in Utility directory
-- Provides save/load/list/delete functions for preset configurations
--
-- USAGE EXAMPLE:
--
-- local ScriptingPresets = require("scripting_presets")
--
-- -- Initialize with script name (or auto-detect from calling script)
-- local presets = ScriptingPresets.init("my_tool")
-- -- Or: local presets = ScriptingPresets.init()  -- auto-detects from debug info
--
-- -- Save a preset
-- local success, err = presets:save("preset1", {
--     field1 = "value1",
--     field2 = 123,
--     field3 = true,
--     nested = {data = "here"}
-- })
--
-- -- Load a preset
-- local preset, err = presets:load("preset1")
--
-- -- List all presets
-- local presetNames = presets:list()
--
-- -- Delete a preset
-- local success, err = presets:delete("preset1")
--
-- -- Get preset file path
-- local filePath = presets:getPresetPath("preset1")
-- ===============================

local ScriptingPresets = {}

-- ===============================
-- Configuration
-- ===============================

-- Get the Utility folder path
local function getUtilityFolder()
    -- Get the path to the Utility folder
    -- This assumes the module is in Modules/Lua and Utility is in Scripts/Utility
    local modulePath = debug.getinfo(1, "S").source
    if modulePath:match("^@") then
        modulePath = modulePath:sub(2)  -- Remove @ prefix
    end
    
    -- Navigate from Modules/Lua to Scripts/Utility
    local utilityPath = modulePath:match("(.*)/Modules/Lua/")
    if utilityPath then
        return utilityPath .. "/Scripts/Utility"
    end
    
    -- Fallback: try to construct from common Resolve path
    return "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"
end

-- ===============================
-- JSON Handling
-- ===============================

-- Simple JSON encoder (fallback if bmd.toJson unavailable)
-- Produces compact single-line JSON
local function encodeJSON(value)
    local valueType = type(value)
    
    if valueType == "nil" then
        return "null"
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        return tostring(value)
    elseif valueType == "string" then
        -- Escape special characters
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    elseif valueType == "table" then
        -- Check if it's an array (sequential numeric indices starting at 1)
        local isArray = true
        local maxIndex = 0
        local count = 0
        for k, v in pairs(value) do
            count = count + 1
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                isArray = false
                break
            end
            if k > maxIndex then
                maxIndex = k
            end
        end
        
        if isArray and maxIndex == count then
            -- It's an array
            local parts = {}
            for i = 1, maxIndex do
                table.insert(parts, encodeJSON(value[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- It's an object
            local parts = {}
            for k, v in pairs(value) do
                local key = type(k) == "string" and ('"' .. k:gsub('"', '\\"') .. '"') or tostring(k)
                table.insert(parts, key .. ":" .. encodeJSON(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return '"' .. tostring(value):gsub('"', '\\"') .. '"'
    end
end

-- JSON decoder (handles nested objects and arrays)
-- Since bmd.parseJson is not available in DaVinci Resolve, we implement a proper parser
local function decodeJSON(jsonStr)
    if not jsonStr or jsonStr == "" then
        return nil
    end
    
    -- Try bmd.parseJson first if available
    if bmd and bmd.parseJson then
        local ok, result = pcall(bmd.parseJson, jsonStr)
        if ok and result then
            return result
        end
    end
    
    -- Implement a proper JSON parser
    local pos = 1
    local len = #jsonStr
    
    -- Skip whitespace
    local function skipWhitespace()
        while pos <= len do
            local char = jsonStr:sub(pos, pos)
            if char == ' ' or char == '\t' or char == '\n' or char == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end
    
    -- Parse a string value
    local function parseString()
        if pos > len or jsonStr:sub(pos, pos) ~= '"' then
            return nil
        end
        pos = pos + 1
        local result = {}
        while pos <= len do
            local char = jsonStr:sub(pos, pos)
            if char == '\\' then
                pos = pos + 1
                if pos > len then break end
                char = jsonStr:sub(pos, pos)
                if char == 'n' then
                    table.insert(result, '\n')
                elseif char == 'r' then
                    table.insert(result, '\r')
                elseif char == 't' then
                    table.insert(result, '\t')
                elseif char == '\\' then
                    table.insert(result, '\\')
                elseif char == '"' then
                    table.insert(result, '"')
                else
                    table.insert(result, char)
                end
            elseif char == '"' then
                pos = pos + 1
                return table.concat(result)
            else
                table.insert(result, char)
            end
            pos = pos + 1
        end
        return nil
    end
    
    -- Parse a number
    local function parseNumber()
        local start = pos
        if jsonStr:sub(pos, pos) == '-' then
            pos = pos + 1
        end
        while pos <= len and jsonStr:match("^%d", pos) do
            pos = pos + 1
        end
        if jsonStr:sub(pos, pos) == '.' then
            pos = pos + 1
            while pos <= len and jsonStr:match("^%d", pos) do
                pos = pos + 1
            end
        end
        if pos > start then
            return tonumber(jsonStr:sub(start, pos - 1))
        end
        return nil
    end
    
    -- Parse a value (recursive)
    local function parseValue()
        skipWhitespace()
        if pos > len then return nil end
        
        local char = jsonStr:sub(pos, pos)
        
        if char == '{' then
            -- Parse object
            pos = pos + 1
            skipWhitespace()
            local obj = {}
            if jsonStr:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            
            while pos <= len do
                skipWhitespace()
                local key = parseString()
                if not key then break end
                skipWhitespace()
                if jsonStr:sub(pos, pos) ~= ':' then break end
                pos = pos + 1
                skipWhitespace()
                local value = parseValue()
                obj[key] = value
                skipWhitespace()
                if jsonStr:sub(pos, pos) == '}' then
                    pos = pos + 1
                    return obj
                elseif jsonStr:sub(pos, pos) == ',' then
                    pos = pos + 1
                else
                    break
                end
            end
            return nil
            
        elseif char == '[' then
            -- Parse array
            pos = pos + 1
            skipWhitespace()
            local arr = {}
            if jsonStr:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            
            while pos <= len do
                skipWhitespace()
                local value = parseValue()
                table.insert(arr, value)
                skipWhitespace()
                if jsonStr:sub(pos, pos) == ']' then
                    pos = pos + 1
                    return arr
                elseif jsonStr:sub(pos, pos) == ',' then
                    pos = pos + 1
                else
                    break
                end
            end
            return nil
            
        elseif char == '"' then
            return parseString()
        elseif char == '-' or jsonStr:match("^%d", pos) then
            return parseNumber()
        elseif jsonStr:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif jsonStr:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif jsonStr:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        
        return nil
    end
    
    -- Parse the JSON
    skipWhitespace()
    local result = parseValue()
    skipWhitespace()
    if pos <= len then
        return nil, "Unexpected characters after JSON: " .. jsonStr:sub(pos, math.min(pos + 20, len))
    end
    return result
end

-- ===============================
-- Preset Manager Class
-- ===============================

-- Create a new preset manager instance
-- @param scriptName: String name of the script (optional, will auto-detect if not provided)
-- @return preset manager object
function ScriptingPresets.init(scriptName)
    -- Auto-detect script name from calling script if not provided
    if not scriptName then
        local level = 2  -- Skip this function and the init call
        local info = debug.getinfo(level, "S")
        if info and info.source then
            local source = info.source
            if source:match("^@") then
                source = source:sub(2)
            end
            -- Extract script name from path
            local filename = source:match("([^/\\]+)%.lua$")
            if filename then
                scriptName = filename
            end
        end
    end
    
    if not scriptName or scriptName == "" then
        error("Could not determine script name. Please provide scriptName parameter.")
    end
    
    -- Create preset manager object
    local manager = {
        scriptName = scriptName,
        utilityFolder = getUtilityFolder(),
        presetsFolder = nil,
        presetsFile = nil
    }
    
    -- Build presets folder name: "script_name"_presets
    manager.presetsFolder = manager.utilityFolder .. "/" .. scriptName .. "_presets"
    -- Note: We now save each preset as a separate JSON file instead of one combined file
    -- Keep presetsFile for backward compatibility but it's not used anymore
    manager.presetsFile = manager.presetsFolder .. "/presets.json"
    
    -- Ensure presets folder exists
    local function ensureFolder()
        -- Check if folder exists
        local handle = io.popen('test -d "' .. manager.presetsFolder .. '" && echo "exists"')
        local result = nil
        if handle then
            result = handle:read("*a")
            handle:close()
        end
        
        if not result or result:match("exists") == nil then
            -- Create folder
            local mkdirCmd = 'mkdir -p "' .. manager.presetsFolder .. '"'
            os.execute(mkdirCmd)
        end
    end
    
    -- Ensure folder exists on first access
    ensureFolder()
    
    -- ===============================
    -- Instance Methods
    -- ===============================
    
    -- Get preset file path for a specific preset
    -- @param presetName: String name of the preset
    -- @return file path string
    function manager:getPresetPath(presetName)
        -- Sanitize preset name for filename (remove invalid characters)
        local safeName = presetName:gsub("[^%w_%-]", "_")
        return self.presetsFolder .. "/" .. safeName .. ".json"
    end
    
    -- Save a preset (as individual JSON file)
    -- @param presetName: String name of the preset
    -- @param presetData: Table containing preset configuration
    -- @return success (bool), error message (string or nil)
    function manager:save(presetName, presetData)
        if not presetName or presetName == "" then
            return false, "Preset name cannot be empty"
        end
        
        if type(presetData) ~= "table" then
            return false, "Preset data must be a table"
        end
        
        -- Ensure folder exists
        ensureFolder()
        
        -- Get file path for this preset
        local presetFile = self:getPresetPath(presetName)
        print("DEBUG: Saving preset to: " .. presetFile)
        
        -- Serialize to JSON
        local json
        if bmd and bmd.toJson then
            local ok, result = pcall(bmd.toJson, presetData)
            if ok and result then
                json = result
                print("DEBUG: Used bmd.toJson")
            else
                print("DEBUG: bmd.toJson failed: " .. tostring(result))
            end
        end
        
        if not json then
            -- Fallback to manual encoding
            json = encodeJSON(presetData)
            print("DEBUG: Used manual encodeJSON")
        end
        
        if not json or json == "" then
            return false, "Failed to encode preset data to JSON"
        end
        
        print("DEBUG: JSON length: " .. string.len(json))
        
        -- Write to file
        local file = io.open(presetFile, "w")
        if not file then
            return false, "Could not open preset file for writing: " .. presetFile
        end
        
        file:write(json)
        file:close()
        
        print("DEBUG: Preset file written successfully")
        
        return true, nil
    end
    
    -- Load a specific preset (from individual JSON file)
    -- @param presetName: String name of the preset
    -- @return preset data (table) or nil, error message (string or nil)
    function manager:load(presetName)
        if not presetName or presetName == "" then
            return nil, "Preset name cannot be empty"
        end
        
        local presetFile = self:getPresetPath(presetName)
        print("DEBUG: Loading preset from: " .. presetFile)
        
        -- Check if file exists
        local file = io.open(presetFile, "r")
        if not file then
            return nil, "Preset file not found: " .. presetName
        end
        
        local content = file:read("*a")
        file:close()
        
        if not content or content == "" then
            return nil, "Preset file is empty: " .. presetName
        end
        
        -- Parse JSON
        local preset
        if bmd and bmd.parseJson then
            local ok, result = pcall(bmd.parseJson, content)
            if ok and result then
                preset = result
                print("DEBUG: Used bmd.parseJson for preset")
            end
        end
        
        if not preset then
            -- Try custom JSON parser
            local ok, result, err = pcall(decodeJSON, content)
            if ok and result then
                preset = result
                print("DEBUG: Used custom JSON parser for preset")
            else
                return nil, "Failed to parse preset JSON: " .. tostring(err or result)
            end
        end
        
        return preset, nil
    end
    
    -- Load all presets (from individual JSON files)
    -- @return table of all presets or nil, error message (string or nil)
    function manager:loadAll()
        print("DEBUG: Loading presets from folder: " .. self.presetsFolder)
        
        -- Ensure folder exists
        ensureFolder()
        
        -- List all JSON files in the presets folder
        local presets = {}
        local handle = io.popen('find "' .. self.presetsFolder .. '" -maxdepth 1 -name "*.json" 2>/dev/null')
        if handle then
            for filename in handle:lines() do
                -- Extract preset name from filename (remove path and .json extension)
                local presetName = filename:match("([^/]+)%.json$")
                if presetName then
                    -- Load the preset
                    local preset, err = self:load(presetName)
                    if preset then
                        presets[presetName] = preset
                    else
                        print("DEBUG: Warning: Could not load preset '" .. presetName .. "': " .. tostring(err))
                    end
                end
            end
            handle:close()
        end
        
        local count = 0
        for _ in pairs(presets) do count = count + 1 end
        print("DEBUG: Loaded " .. count .. " preset(s) from individual files")
        
        return presets, nil
    end
    
    -- List all preset names
    -- @return array of preset names
    function manager:list()
        local allPresets = self:loadAll() or {}
        local names = {}
        for name, _ in pairs(allPresets) do
            table.insert(names, name)
        end
        table.sort(names)
        return names
    end
    
    -- Delete a preset (delete individual JSON file)
    -- @param presetName: String name of the preset to delete
    -- @return success (bool), error message (string or nil)
    function manager:delete(presetName)
        if not presetName or presetName == "" then
            return false, "Preset name cannot be empty"
        end
        
        local presetFile = self:getPresetPath(presetName)
        
        -- Check if file exists
        local file = io.open(presetFile, "r")
        if not file then
            return false, "Preset not found: " .. presetName
        end
        file:close()
        
        -- Delete the file
        local success = os.remove(presetFile)
        if success then
            print("DEBUG: Deleted preset file: " .. presetFile)
            return true, nil
        else
            return false, "Could not delete preset file: " .. presetFile
        end
    end
    
    -- Get the path to a preset file (for external access)
    -- Get the presets folder path
    -- @return folder path string
    function manager:getPresetsFolder()
        return self.presetsFolder
    end
    
    -- Check if a preset exists
    -- @param presetName: String name of the preset
    -- @return boolean
    function manager:exists(presetName)
        if not presetName or presetName == "" then
            return false
        end
        
        local allPresets = self:loadAll() or {}
        return allPresets[presetName] ~= nil
    end
    
    -- Get the script name used for this preset manager
    -- @return string
    function manager:getScriptName()
        return self.scriptName
    end
    
    return manager
end

return ScriptingPresets


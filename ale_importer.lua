-- ale_importer.lua (Improved Version)
-- A robust module to parse an Avid Log Exchange (ALE) file.
-- It now correctly handles empty columns and detects the field delimiter.

local M = {}

--- Trims leading/trailing whitespace from a string.
-- @param s The input string.
-- @return The trimmed string.
local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

--- A robust string split function that correctly handles empty fields.
-- For example, it will correctly parse "a\t\tc" into {"a", "", "c"}.
-- @param str The string to split.
-- @param sep The separator character.
-- @return A table of string values.
local function split(str, sep)
    local result = {}
    local current_pos = 1
    if str == "" then return {""} end
    
    while true do
        local start_pos, end_pos = str:find(sep, current_pos, true) -- Plain search
        if not start_pos then
            -- No more separators, add the rest of the string and break
            table.insert(result, str:sub(current_pos))
            break
        end
        -- Add the field found before the separator
        table.insert(result, str:sub(current_pos, start_pos - 1))
        current_pos = end_pos + 1
    end
    return result
end

--- Parses the specified ALE file.
-- @param filepath The full path to the .ale file.
-- @return A table containing 'headers' and 'data' on success.
-- @return nil and an error string on failure.
function M.parseFile(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Error: Could not open file at path: " .. filepath
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  local headers = {}
  local data = {}
  local state = "Header" -- Current parsing state: Header, Column, Data
  local delimiter = "\t" -- Default to tab-delimited, as is standard

  for _, line in ipairs(lines) do
    local trimmed_line = trim(line)

    if state == "Header" then
      -- While in the header, look for the delimiter definition
      if trimmed_line:match("^FIELD_DELIM%s+(.+)") then
        local delim_type = trimmed_line:match("^FIELD_DELIM%s+(.+)")
        if trim(delim_type) == "COMMAS" then
          delimiter = ","
        end
      -- Transition to the next state when 'Column' is found
      elseif trimmed_line == "Column" then
        state = "Column"
      end

    elseif state == "Column" then
      -- The line immediately following 'Column' contains the headers
      headers = split(line, delimiter)
      -- Clean up each header name by trimming whitespace
      for i, h in ipairs(headers) do
          headers[i] = trim(h)
      end
      state = "AwaitingData" -- Move to a state waiting for the 'Data' marker

    elseif state == "AwaitingData" then
      if trimmed_line == "Data" then
        state = "Data" -- Data marker found, start parsing data rows
      end

    elseif state == "Data" then
      if trimmed_line ~= "" then
        local row_values = split(line, delimiter)
        local row_data = {}
        -- Map each value to its corresponding header
        for i, header in ipairs(headers) do
          -- Also trim data values to prevent subtle spacing issues
          row_data[header] = row_values[i] and trim(row_values[i]) or ""
        end
        table.insert(data, row_data)
      end
    end
  end

  if #headers == 0 or #data == 0 then
    return nil, "Parsing failed: Could not find valid 'Column' or 'Data' sections in the file."
  end

  return { headers = headers, data = data }
end

return M


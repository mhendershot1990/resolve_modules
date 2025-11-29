-- ===============================
-- CSV Tool Module
-- ===============================
-- Combined CSV import and export utilities
-- Supports various CSV formats and parsing options
-- ===============================

local CSVTool = {}

-- ===============================
-- Helper Functions
-- ===============================

local function trim(s) 
    return s and s:match("^%s*(.-)%s*$") or "" 
end

-- ===============================
-- CSV Import Functions
-- ===============================

-- Generic CSV parser with customizable delimiter
-- @param filePath: Full path to CSV file
-- @param options: Optional table { delimiter = ",", skipEmptyLines = true, trimFields = true }
-- @return headers (array), data (array of objects)
function CSVTool.parseCSV(filePath, options)
    options = options or {}
    local delimiter = options.delimiter or ","
    local skipEmptyLines = options.skipEmptyLines ~= false  -- default true
    local trimFields = options.trimFields ~= false  -- default true
    
    local f = io.open(filePath, "r")
    if not f then 
        return {}, {} 
    end

    local lines, headers, data = {}, {}, {}

    -- Read and clean lines
    for line in f:lines() do
        local cleanLine = line:gsub("\r", "")
        if not skipEmptyLines or cleanLine:gsub("%s", "") ~= "" then 
            table.insert(lines, cleanLine) 
        end
    end

    if #lines < 1 then 
        f:close()
        return {}, {} 
    end

    -- Split line into fields, handling quoted values
    local function split(line)
        local fields, currentField, inQuotes = {}, "", false
        for i = 1, #line do
            local char = line:sub(i, i)
            if char == '"' then 
                inQuotes = not inQuotes
            elseif char == delimiter and not inQuotes then
                local field = trimFields and trim(currentField) or currentField
                table.insert(fields, field)
                currentField = ""
            else
                currentField = currentField .. char
            end
        end
        local field = trimFields and trim(currentField) or currentField
        table.insert(fields, field)
        return fields
    end

    -- Parse headers
    headers = split(lines[1])
    if trimFields then
        for i, h in ipairs(headers) do
            headers[i] = trim(h)
        end
    end

    -- Parse data rows
    for i = 2, #lines do
        local values = split(lines[i])
        local row = {}
        for j, h in ipairs(headers) do
            local value = values[j] or ""
            row[h] = value
        end
        table.insert(data, row)
    end

    f:close()
    return headers, data
end

-- Parse CSV with tab delimiter (TSV)
-- @param filePath: Full path to TSV file
-- @param options: Optional table (same as parseCSV)
-- @return headers (array), data (array of objects)
function CSVTool.parseTSV(filePath, options)
    options = options or {}
    options.delimiter = "\t"
    return CSVTool.parseCSV(filePath, options)
end

-- Parse CSV with semicolon delimiter
-- @param filePath: Full path to CSV file
-- @param options: Optional table (same as parseCSV)
-- @return headers (array), data (array of objects)
function CSVTool.parseSemicolonCSV(filePath, options)
    options = options or {}
    options.delimiter = ";"
    return CSVTool.parseCSV(filePath, options)
end

-- Find CSV files in folder recursively
-- @param baseFolder: Directory to search
-- @param extension: File extension (e.g., "csv", "tsv") - without dot
-- @return array of file paths
function CSVTool.findFilesRecursively(baseFolder, extension)
    local files = {}
    local isWindows = package.config:sub(1,1) == "\\"
    local cmd = isWindows
        and ('dir "' .. baseFolder .. '" /s /b | findstr /i "\\.' .. extension .. '$"')
        or  ('find "' .. baseFolder .. '" -type f -iname "*.' .. extension .. '"')

    local pipe = io.popen(cmd)
    if pipe then
        for path in pipe:lines() do 
            table.insert(files, path) 
        end
        pipe:close()
    end

    return files
end

-- ===============================
-- CSV Export Functions
-- ===============================

-- Escape and format value for CSV
-- Only quotes if value contains comma or quote
-- Converts spaces to underscores
-- Returns "null" for empty values
-- @param value: Value to escape
-- @return escaped string
function CSVTool.escapeCSV(value)
    if value == nil or tostring(value) == "" then 
        return "null" 
    end
    
    local s = tostring(value)
    s = s:gsub("%s+", "_")  -- Replace spaces with underscores
    
    -- Only quote if contains comma or quote character
    if s:find('[,"]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    
    return s
end

-- Write CSV file from 2D array (rows of columns)
-- @param filepath: Full path to output file
-- @param headers: Array of header strings (used as-is)
-- @param rows: Array of arrays (each inner array is a row of values)
-- @param options: Optional table { utf8BOM = false }
-- @return success (bool), error message (string or nil)
function CSVTool.writeCSV(filepath, headers, rows, options)
    options = options or {}
    local utf8BOM = options.utf8BOM or false
    
    local file = io.open(filepath, "w")
    if not file then
        return false, "Could not open file for writing: " .. filepath
    end
    
    -- Write UTF-8 BOM if requested (Excel compatibility)
    if utf8BOM then
        file:write("\239\187\191")
    end
    
    -- Write headers (no formatting, use as-is)
    file:write(table.concat(headers, ",") .. "\n")
    
    -- Write data rows
    for _, row in ipairs(rows) do
        local escapedRow = {}
        for _, value in ipairs(row) do
            table.insert(escapedRow, CSVTool.escapeCSV(value))
        end
        file:write(table.concat(escapedRow, ",") .. "\n")
    end
    
    file:close()
    return true, nil
end

-- Write CSV from table of objects (each object is a row)
-- @param filepath: Full path to output file
-- @param fieldOrder: Array of field names in desired column order
-- @param data: Array of tables/objects
-- @param options: Optional table { utf8BOM = false, fieldMap = {} }
-- @return success (bool), error message (string or nil)
function CSVTool.writeCSVFromObjects(filepath, fieldOrder, data, options)
    options = options or {}
    local fieldMap = options.fieldMap or {}
    
    -- Build headers (use fieldMap or field name as-is)
    local headers = {}
    for _, field in ipairs(fieldOrder) do
        local headerName = fieldMap[field] or field
        table.insert(headers, headerName)
    end
    
    -- Build rows
    local rows = {}
    for _, obj in ipairs(data) do
        local row = {}
        for _, field in ipairs(fieldOrder) do
            table.insert(row, obj[field])
        end
        table.insert(rows, row)
    end
    
    return CSVTool.writeCSV(filepath, headers, rows, options)
end

-- Stream-based CSV writer (for large datasets)
-- Opens file and returns writer object
-- @param filepath: Full path to output file
-- @param headers: Array of header strings (used as-is)
-- @param options: Optional table { utf8BOM = false }
-- @return writer object or nil, error message
function CSVTool.createWriter(filepath, headers, options)
    options = options or {}
    local utf8BOM = options.utf8BOM or false
    
    local file = io.open(filepath, "w")
    if not file then
        return nil, "Could not open file for writing: " .. filepath
    end
    
    -- Write UTF-8 BOM if requested
    if utf8BOM then
        file:write("\239\187\191")
    end
    
    -- Write headers (no formatting, use as-is)
    file:write(table.concat(headers, ",") .. "\n")
    
    -- Return writer object
    local writer = {
        file = file,
        rowCount = 0
    }
    
    -- Write a single row
    function writer:writeRow(row)
        local escapedRow = {}
        for _, value in ipairs(row) do
            table.insert(escapedRow, CSVTool.escapeCSV(value))
        end
        self.file:write(table.concat(escapedRow, ",") .. "\n")
        self.rowCount = self.rowCount + 1
    end
    
    -- Close the file
    function writer:close()
        self.file:close()
    end
    
    return writer, nil
end

return CSVTool


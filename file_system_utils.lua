-- file_system_utils.lua
--
-- A collection of reliable file system utility functions that bypass the
-- often unreliable bmd.readdir() function in DaVinci Resolve by using
-- system-level commands.

local M = {}

--- Uses `ls -A1F` to get directory contents and types in one command.
-- This is a reliable replacement for bmd.readdir.
-- @param path The directory to list.
-- @return A table of objects { name = "...", isDir = boolean }, or nil if an error occurs.
function M.getDirectoryEntries(path)
    -- Using `ls -A1F`:
    -- -A: almost all, doesn't list . and ..
    -- -1: one file per line
    -- -F: appends indicator (e.g., / for directory, @ for symlink)
    local command = 'ls -A1F "' .. path .. '"'
    local handle = io.popen(command)
    if not handle then return nil end

    local result = handle:read("*a")
    handle:close()

    local entries = {}
    for line in result:gmatch("[^\r\n]+") do
        local isDir = false
        local name = line
        if name:sub(-1) == "/" then
            isDir = true
            name = name:sub(1, -2) -- Remove the trailing slash
        end
        -- Also handle other indicators `ls -F` might add to avoid them becoming part of the name
        name = name:gsub("[@=*|]$", "")

        table.insert(entries, { name = name, isDir = isDir })
    end
    return entries
end

return M

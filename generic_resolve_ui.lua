-- ===============================
-- Generic Resolve UI Template Module
-- ===============================
-- Reusable UI template for DaVinci Resolve scripts
-- Prevents UI elements from being cut off on right/bottom
-- Based on proven layout patterns from proxy_linker.lua
--
-- USAGE EXAMPLE:
-- 
-- local GenericResolveUI = require("generic_resolve_ui")
-- 
-- local win, disp, ui, err = GenericResolveUI.createStandardWindow({
--     windowID = "MyToolWindow",
--     windowTitle = "My Tool",
--     geometry = {100, 100, 1100, 980},  -- Optional
--     
--     sections = {
--         {
--             title = "Input Section",
--             weight = 0,  -- Fixed size
--             content = function(ui)
--                 return {
--                     GenericResolveUI.createLabeledInput(ui, {
--                         labelText = "Name:",
--                         elementType = "LineEdit",
--                         elementID = "NameInput",
--                         elementConfig = {PlaceholderText = "Enter name"}
--                     }),
--                     GenericResolveUI.createLabeledInput(ui, {
--                         labelText = "Type:",
--                         elementType = "ComboBox",
--                         elementID = "TypeCombo"
--                     })
--                 }
--             end
--         }
--     },
--     
--     buttons = {
--         {id = "ProcessBtn", text = "Process", enabled = true},
--         {id = "CancelBtn", text = "Cancel", enabled = true}
--     },
--     
--     resultsArea = {
--         id = "ResultsText",
--         title = "Results",
--         weight = 1  -- Expandable
--     },
--     
--     closeButton = {
--         id = "CloseBtn",
--         text = "Close"
--     }
-- })
-- 
-- if err then
--     print(err)
--     return
-- end
-- 
-- -- Setup event handlers
-- function win.On.ProcessBtn.Clicked(ev)
--     -- Your code here
-- end
-- 
-- GenericResolveUI.setupCloseHandlers(win, disp)
-- GenericResolveUI.runLoop(win, disp)
-- ===============================

local GenericResolveUI = {}

-- ===============================
-- Default Configuration
-- ===============================

GenericResolveUI.defaultConfig = {
    windowWidth = 1100,
    windowHeight = 980,
    windowX = 100,
    windowY = 100,
    margin = {15, 15, 15, 20},  -- left, top, right, bottom
    spacing = 12,
    buttonMinWidth = 120,
    buttonMinHeight = 30,
    labelMinWidth = 100,
    labelMinHeight = 24,
    closeButtonMinWidth = 120,
    closeButtonMinHeight = 40,
    resultsFont = {
        Family = "Courier",
        Style = "Regular",
        Size = 10
    }
}

-- ===============================
-- Core UI Creation
-- ===============================

-- Initialize Fusion UI system
-- @return fusion, ui, disp or nil, error message
function GenericResolveUI.initFusionUI()
    local fusion = bmd.scriptapp("Fusion")
    if not fusion then
        return nil, nil, nil, "ERROR: Cannot access Fusion."
    end
    
    local ui = fusion.UIManager
    if not ui then
        return nil, nil, nil, "ERROR: Cannot access UIManager."
    end
    
    local disp = bmd.UIDispatcher(ui)
    return fusion, ui, disp, nil
end

-- Create a base window with proper layout structure
-- @param config: Table with window configuration (optional)
--   - windowID: String ID for the window
--   - windowTitle: Window title string
--   - geometry: {x, y, width, height} or nil for defaults
--   - margin: {left, top, right, bottom} or nil for defaults
--   - spacing: Number for spacing between elements
--   - content: Function that returns UI elements to insert in main VGroup
-- @return window, dispatcher, ui or nil, error message
function GenericResolveUI.createWindow(config)
    config = config or {}
    
    local fusion, ui, disp, err = GenericResolveUI.initFusionUI()
    if err then
        return nil, nil, nil, err
    end
    
    local windowID = config.windowID or "GenericWindow"
    local windowTitle = config.windowTitle or "DaVinci Resolve Tool"
    
    -- Geometry: {x, y, width, height}
    local geometry = config.geometry or {
        GenericResolveUI.defaultConfig.windowX,
        GenericResolveUI.defaultConfig.windowY,
        GenericResolveUI.defaultConfig.windowWidth,
        GenericResolveUI.defaultConfig.windowHeight
    }
    
    local margin = config.margin or GenericResolveUI.defaultConfig.margin
    local spacing = config.spacing or GenericResolveUI.defaultConfig.spacing
    
    -- Get content from config or use empty
    local contentFunc = config.content
    local contentElements = {}
    if contentFunc then
        local result = contentFunc(ui)
        if result then
            if type(result) == "table" then
                contentElements = result
            else
                contentElements = {result}
            end
        end
    end
    
    -- Build main window structure with content
    local vgroupElements = {
        Margin = margin,
        Spacing = spacing,
    }
    
    -- Add content elements
    for _, element in ipairs(contentElements) do
        table.insert(vgroupElements, element)
    end
    
    -- Create window
    local win = disp:AddWindow({
        ID = windowID,
        WindowTitle = windowTitle,
        Geometry = geometry,
        ui:VGroup(vgroupElements)
    })
    
    return win, disp, ui, nil
end

-- ===============================
-- UI Element Builders
-- ===============================

-- Create a labeled input section (Label + LineEdit/ComboBox)
-- @param ui: UI manager object
-- @param config: Table with configuration
--   - labelText: String for label
--   - elementType: "LineEdit" or "ComboBox"
--   - elementID: String ID for the element
--   - elementConfig: Table of element properties (ReadOnly, PlaceholderText, etc.)
--   - labelWidth: Number for label minimum width (optional)
-- @return UI element group
function GenericResolveUI.createLabeledInput(ui, config)
    config = config or {}
    local labelText = config.labelText or "Label:"
    local elementType = config.elementType or "LineEdit"
    local elementID = config.elementID or "Input"
    local elementConfig = config.elementConfig or {}
    local labelWidth = config.labelWidth or GenericResolveUI.defaultConfig.labelMinWidth
    
    local element
    if elementType == "ComboBox" then
        element = ui:ComboBox{ID = elementID, Weight = 1}
    else
        element = ui:LineEdit{ID = elementID, Weight = 1}
    end
    
    -- Apply element config
    for key, value in pairs(elementConfig) do
        element[key] = value
    end
    
    return ui:HGroup{
        ui:Label{
            Text = labelText,
            Weight = 0,
            MinimumSize = {labelWidth, GenericResolveUI.defaultConfig.labelMinHeight}
        },
        element
    }
end

-- Create a section with title and content
-- @param ui: UI manager object
-- @param config: Table with configuration
--   - title: String section title
--   - content: Function that returns UI elements, or table of elements, or single element
--   - weight: Number for section weight (0 for fixed, 1 for expandable)
-- @return UI VGroup element
function GenericResolveUI.createSection(ui, config)
    config = config or {}
    local title = config.title or "Section"
    local content = config.content
    local weight = config.weight or 0
    
    local sectionElements = {
        ui:Label{Text = title, Font = {Style = "Bold"}}
    }
    
    if content then
        if type(content) == "function" then
            local contentResult = content(ui)
            if contentResult then
                if type(contentResult) == "table" then
                    for _, element in ipairs(contentResult) do
                        if element then
                            table.insert(sectionElements, element)
                        end
                    end
                else
                    table.insert(sectionElements, contentResult)
                end
            end
        elseif type(content) == "table" then
            for _, element in ipairs(content) do
                if element then
                    table.insert(sectionElements, element)
                end
            end
        else
            table.insert(sectionElements, content)
        end
    end
    
    return ui:VGroup{
        Weight = weight,
        sectionElements
    }
end

-- Create a button group
-- @param ui: UI manager object
-- @param config: Table with configuration
--   - buttons: Array of button configs {id, text, minWidth, minHeight, enabled}
--   - spacing: Number for spacing between buttons
-- @return UI HGroup element
function GenericResolveUI.createButtonGroup(ui, config)
    config = config or {}
    local buttons = config.buttons or {}
    local spacing = config.spacing or 8
    
    local buttonElements = {}
    for _, btnConfig in ipairs(buttons) do
        local btn = ui:Button{
            ID = btnConfig.id or "Button",
            Text = btnConfig.text or "Button",
            Weight = 0,
            MinimumSize = {
                btnConfig.minWidth or GenericResolveUI.defaultConfig.buttonMinWidth,
                btnConfig.minHeight or GenericResolveUI.defaultConfig.buttonMinHeight
            },
            Enabled = btnConfig.enabled ~= false
        }
        table.insert(buttonElements, btn)
    end
    
    return ui:HGroup{
        Weight = 0,
        Spacing = spacing,
        buttonElements
    }
end

-- Create a results text area
-- @param ui: UI manager object
-- @param config: Table with configuration
--   - id: String ID for the TextEdit
--   - title: String title for the section (optional)
--   - weight: Number for weight (default 1 for expandable)
--   - font: Table with font config (optional)
-- @return UI VGroup element with label and TextEdit
function GenericResolveUI.createResultsArea(ui, config)
    config = config or {}
    local id = config.id or "ResultsText"
    local title = config.title or "Results"
    local weight = config.weight or 1
    local font = config.font or GenericResolveUI.defaultConfig.resultsFont
    
    local elements = {
        ui:Label{Text = title, Font = {Style = "Bold"}}
    }
    
    table.insert(elements, ui:TextEdit{
        ID = id,
        Weight = weight,
        ReadOnly = true,
        Font = font
    })
    
    return ui:VGroup{
        Weight = weight,
        elements
    }
end

-- Create a close button section (aligned right)
-- @param ui: UI manager object
-- @param config: Table with configuration
--   - id: String ID for close button (default "CloseBtn")
--   - text: String button text (default "Close")
--   - minWidth: Number (optional)
--   - minHeight: Number (optional)
--   - margin: Table {left, top, right, bottom} (optional)
-- @return Table of UI elements (VGap and HGroup)
function GenericResolveUI.createCloseButton(ui, config)
    config = config or {}
    local id = config.id or "CloseBtn"
    local text = config.text or "Close"
    local minWidth = config.minWidth or GenericResolveUI.defaultConfig.closeButtonMinWidth
    local minHeight = config.minHeight or GenericResolveUI.defaultConfig.closeButtonMinHeight
    local margin = config.margin or {0, 0, 0, 5}
    
    return {
        ui:VGap(10),
        ui:HGroup{
            Weight = 0,
            Spacing = 8,
            Margin = margin,
            ui:HGap(),  -- Push button to right
            ui:Button{
                ID = id,
                Text = text,
                Weight = 0,
                MinimumSize = {minWidth, minHeight}
            }
        }
    }
end

-- ===============================
-- Complete Window Template
-- ===============================

-- Create a complete window with standard structure
-- @param config: Table with configuration
--   - windowID: String
--   - windowTitle: String
--   - geometry: {x, y, width, height} (optional)
--   - sections: Array of section configs (see createSection)
--   - buttons: Array of button configs (see createButtonGroup)
--   - resultsArea: Results area config (see createResultsArea)
--   - closeButton: Close button config (see createCloseButton)
-- @return window, dispatcher, ui or nil, error message
function GenericResolveUI.createStandardWindow(config)
    config = config or {}
    
    -- Build content function
    local function buildContent(ui)
        local content = {}
        
        -- Add sections
        if config.sections then
            for _, sectionConfig in ipairs(config.sections) do
                table.insert(content, GenericResolveUI.createSection(ui, sectionConfig))
            end
        end
        
        -- Add button group
        if config.buttons then
            table.insert(content, GenericResolveUI.createButtonGroup(ui, {buttons = config.buttons}))
        end
        
        -- Add results area
        if config.resultsArea then
            table.insert(content, GenericResolveUI.createResultsArea(ui, config.resultsArea))
        end
        
        -- Add close button
        if config.closeButton ~= false then  -- Default to true
            local closeBtnElements = GenericResolveUI.createCloseButton(ui, config.closeButton)
            for _, element in ipairs(closeBtnElements) do
                table.insert(content, element)
            end
        end
        
        return content
    end
    
    config.content = buildContent
    return GenericResolveUI.createWindow(config)
end

-- ===============================
-- Event Handler Helpers
-- ===============================

-- Setup standard close handlers
-- @param win: Window object
-- @param disp: Dispatcher object
-- @param closeBtnID: String ID for close button (default "CloseBtn")
-- @param windowID: String ID for window (optional, for Close event)
-- Note: This is a helper function. For custom button/window IDs, set up handlers manually.
-- Example: function win.On.YourButtonID.Clicked(ev) disp:ExitLoop() end
function GenericResolveUI.setupCloseHandlers(win, disp, closeBtnID, windowID)
    closeBtnID = closeBtnID or "CloseBtn"
    
    -- Set up close button handler for standard "CloseBtn" ID
    if closeBtnID == "CloseBtn" then
        function win.On.CloseBtn.Clicked(ev)
            disp:ExitLoop()
        end
    end
    
    -- Set up window close handler if windowID is provided
    -- Note: Window close handlers must be set up manually for each specific window ID
    -- This is a limitation of Lua's syntax - we can't use dynamic property access
    -- Users should add: function win.On.YourWindowID.Close(ev) disp:ExitLoop() end
end

-- Run the UI loop
-- @param win: Window object
-- @param disp: Dispatcher object
function GenericResolveUI.runLoop(win, disp)
    win:Show()
    disp:RunLoop()
    win:Hide()
end

return GenericResolveUI


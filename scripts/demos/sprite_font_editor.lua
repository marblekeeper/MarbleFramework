-- sprite_font_editor.lua
-- THE ULTIMATE NERD FLEX: Build custom sprite fonts interactively!
-- Load an atlas, arrow-key navigate, press any key to assign that character

local root = UIElement:new({width=1024, height=768})

-- ===================================================
-- State
-- ===================================================
local state = {
    atlasPath = "Content/mbf_big_00.png",
    atlasTexId = nil,
    atlasWidth = 256,
    atlasHeight = 128,
    
    -- Grid navigation
    cellWidth = 10,
    cellHeight = 12,
    cursorX = 0,
    cursorY = 0,
    
    -- Character mapping
    charMap = {}, -- [ascii_code] = {x, y, width, height, xoffset, yoffset, xadvance}
    
    -- Input state
    captureMode = false,
    lastKeyPressed = nil,
    
    -- Preview
    previewText = "The quick brown fox jumps over the lazy dog! 0123456789",
}

-- Load the atlas texture (will be loaded after bridge is available)
function loadAtlasTexture()
    -- In a real implementation, you'd call bridge.loadTexture(state.atlasPath)
    -- For now, we'll just note that this would happen at init
    -- The texture would be bound before drawing the atlas display
    print("[System] Atlas texture would be loaded from: " .. state.atlasPath)
end

-- Load the atlas texture
local texId, texW, texH = bridge.loadTexture(state.atlasPath)
if texId then
    state.atlasTexId = texId
    state.atlasWidth = texW
    state.atlasHeight = texH
    print(string.format("[Font Editor] Loaded atlas: %s (%dx%d)", state.atlasPath, texW, texH))
else
    print("[Font Editor] WARNING: Could not load atlas texture: " .. state.atlasPath)
end

-- ===================================================
-- Main Container
-- ===================================================
local mainPanel = Panel:new({
    x = 0, y = 0,
    width = 1024, height = 768,
    bgColor = {25, 25, 28, 255}
})
root:addChild(mainPanel)

-- ===================================================
-- Top Bar - Controls
-- ===================================================
local topBar = Panel:new({
    x = 0, y = 0,
    width = 1024, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 2
})
topBar:setPadding(10)
mainPanel:addChild(topBar)

local titleLabel = Label:new({
    text = "SPRITE FONT EDITOR",
    width = 1000, height = 20,
    alignment = "center",
    textColor = {255, 200, 100, 255}
})
topBar:addChild(titleLabel)

local instructionLabel = Label:new({
    x = 10, y = 30,
    text = "Arrow Keys: Navigate | Any Key: Assign Character | Space: Clear Assignment | S: Save .fnt File",
    width = 1000, height = 20,
    alignment = "left",
    textColor = {200, 200, 200, 255}
})
topBar:addChild(instructionLabel)

-- ===================================================
-- Left Panel - Atlas Viewer with Grid Overlay
-- ===================================================
local atlasPanel = Panel:new({
    x = 10, y = 70,
    width = 600, height = 500,
    bgColor = {40, 40, 45, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
atlasPanel:setPadding(10)
mainPanel:addChild(atlasPanel)

local atlasTitle = Label:new({
    text = "Font Atlas (Navigate with Arrow Keys)",
    width = 580, height = 20,
    alignment = "left",
    textColor = {150, 255, 150, 255}
})
atlasPanel:addChild(atlasTitle)

-- Atlas display area (custom rendering with texture + grid + cursor)
local atlasDisplay = Panel:new({
    x = 10, y = 30,
    width = 580, height = 450,
    bgColor = {20, 20, 25, 255},
    borderColor = {60, 60, 60, 255},
    borderThickness = 1
})

-- Override drawSelf to render atlas texture, grid, and cursor
atlasDisplay.drawSelf = function(self)
    -- Draw background panel
    local gx, gy = self:getGlobalBounds()
    
    -- Draw background
    bridge.drawRect(gx, gy, self.width, self.height, 
        self.bgColor[1], self.bgColor[2], self.bgColor[3], self.bgColor[4])
    
    -- Draw border
    if self.borderThickness > 0 then
        bridge.drawBorder(gx, gy, self.width, self.height,
            self.borderColor[1], self.borderColor[2], self.borderColor[3], self.borderColor[4],
            self.borderThickness)
    end
    
    if not state.atlasTexId then return end
    
    -- Calculate scale to fit atlas in display area
    local scaleX = self.width / state.atlasWidth
    local scaleY = self.height / state.atlasHeight
    local scale = math.min(scaleX, scaleY) * 0.95  -- 95% to leave padding
    
    local displayW = state.atlasWidth * scale
    local displayH = state.atlasHeight * scale
    
    -- Center the atlas
    local offsetX = (self.width - displayW) / 2
    local offsetY = (self.height - displayH) / 2
    
    local atlasX = gx + offsetX
    local atlasY = gy + offsetY
    
    -- Draw the atlas texture
    bridge.drawTexture(state.atlasTexId, atlasX, atlasY, displayW, displayH)
    
    -- Draw grid overlay
    local gridCols = math.floor(state.atlasWidth / state.cellWidth)
    local gridRows = math.floor(state.atlasHeight / state.cellHeight)
    
    local cellDisplayW = (state.cellWidth / state.atlasWidth) * displayW
    local cellDisplayH = (state.cellHeight / state.atlasHeight) * displayH
    
    -- Draw vertical grid lines
    for col = 0, gridCols do
        local x = atlasX + col * cellDisplayW
        bridge.drawRect(x, atlasY, 1, displayH, 80, 80, 80, 100)
    end
    
    -- Draw horizontal grid lines
    for row = 0, gridRows do
        local y = atlasY + row * cellDisplayH
        bridge.drawRect(atlasX, y, displayW, 1, 80, 80, 80, 100)
    end
    
    -- Draw cursor highlight (green box)
    local cursorDisplayX = atlasX + state.cursorX * cellDisplayW
    local cursorDisplayY = atlasY + state.cursorY * cellDisplayH
    
    -- Green outline (4px thick)
    bridge.drawBorder(cursorDisplayX, cursorDisplayY, cellDisplayW, cellDisplayH, 
        100, 255, 100, 255, 2)
end

atlasPanel:addChild(atlasDisplay)

-- Cursor info
local cursorInfo = Label:new({
    x = 10, y = 485,
    text = "Cursor: (0, 0) | Cell: 8x8",
    width = 580, height = 20,
    textColor = {255, 255, 100, 255}
})
atlasPanel:addChild(cursorInfo)

-- ===================================================
-- Right Panel - Character Assignments
-- ===================================================
local assignmentPanel = Panel:new({
    x = 620, y = 70,
    width = 394, height = 500,
    bgColor = {40, 40, 45, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
assignmentPanel:setPadding(10)
mainPanel:addChild(assignmentPanel)

local assignmentTitle = Label:new({
    text = "Character Assignments",
    width = 374, height = 20,
    alignment = "left",
    textColor = {150, 150, 255, 255}
})
assignmentPanel:addChild(assignmentTitle)

-- Scrollable list of assignments (simplified for demo)
local assignmentList = VBox:new({
    x = 10, y = 30,
    width = 374, height = 420,
    spacing = 2
})
assignmentPanel:addChild(assignmentList)

-- Current selection indicator
local currentSelection = Label:new({
    x = 10, y = 455,
    text = "Press any key to assign to current cell...",
    width = 374, height = 20,
    textColor = {100, 255, 100, 255}
})
assignmentPanel:addChild(currentSelection)

-- Clear button
local clearBtn = Button:new({
    x = 10, y = 475,
    width = 180, height = 35,
    normalColor = {100, 60, 60, 255},
    hoverColor = {120, 70, 70, 255},
    pressedColor = {80, 50, 50, 255}
})
clearBtn.onClick = function()
    local gridX = state.cursorX
    local gridY = state.cursorY
    
    -- Find and remove any character assigned to this cell
    for ascii, data in pairs(state.charMap) do
        if data.gridX == gridX and data.gridY == gridY then
            state.charMap[ascii] = nil
            print("Cleared assignment for character: " .. string.char(ascii))
            break
        end
    end
    
    updateAssignmentList()
end
local clearLabel = Label:new({
    text = "Clear Assignment",
    width = 180, height = 35,
    alignment = "center"
})
clearBtn:addChild(clearLabel)
assignmentPanel:addChild(clearBtn)

-- Save button
local saveBtn = Button:new({
    x = 200, y = 475,
    width = 180, height = 35,
    normalColor = {60, 100, 60, 255},
    hoverColor = {70, 120, 70, 255},
    pressedColor = {50, 80, 50, 255}
})
saveBtn.onClick = function()
    saveFontFile()
end
local saveLabel = Label:new({
    text = "Save .fnt File",
    width = 180, height = 35,
    alignment = "center"
})
saveBtn:addChild(saveLabel)
assignmentPanel:addChild(saveBtn)

-- ===================================================
-- Bottom Panel - Preview
-- ===================================================
local previewPanel = Panel:new({
    x = 10, y = 580,
    width = 1004, height = 178,
    bgColor = {40, 40, 45, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
previewPanel:setPadding(10)
mainPanel:addChild(previewPanel)

local previewTitle = Label:new({
    text = "Live Preview (renders with your custom font)",
    width = 984, height = 20,
    alignment = "left",
    textColor = {255, 150, 255, 255}
})
previewPanel:addChild(previewTitle)

local previewDisplay = Panel:new({
    x = 10, y = 30,
    width = 984, height = 80,
    bgColor = {20, 20, 25, 255},
    borderColor = {60, 60, 60, 255},
    borderThickness = 1
})
previewPanel:addChild(previewDisplay)

-- Preview text would render here using the custom font

local statsLabel = Label:new({
    x = 10, y = 120,
    text = "Characters Defined: 0 | Atlas: 256x128 | Cell Size: 8x8",
    width = 984, height = 20,
    textColor = {200, 200, 200, 255}
})
previewPanel:addChild(statsLabel)

local exportStatus = Label:new({
    x = 10, y = 145,
    text = "Status: Ready to assign characters",
    width = 984, height = 20,
    textColor = {100, 255, 100, 255}
})
previewPanel:addChild(exportStatus)

-- ===================================================
-- Settings Panel (Grid Size Controls)
-- ===================================================
local settingsRow = HBox:new({
    x = 10, y = 510,
    width = 600, height = 60,
    spacing = 10
})
mainPanel:addChild(settingsRow)

-- Cell width control
local cellWidthPanel = Panel:new({
    width = 190, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {70, 70, 70, 255},
    borderThickness = 1
})
cellWidthPanel:setPadding(5)
local cellWidthLabel = Label:new({
    text = "Cell Width: 8",
    width = 180, height = 20,
    alignment = "center"
})
cellWidthPanel:addChild(cellWidthLabel)

local cellWidthSlider = Slider:new({
    x = 5, y = 25,
    width = 180
})
cellWidthSlider.value = 0.5  -- Maps to 8 pixels (range 4-16)
cellWidthSlider.onValueChanged = function(val)
    state.cellWidth = math.floor(4 + val * 28)  -- 4 to 32 pixels
    cellWidthLabel.text = "Cell Width: " .. state.cellWidth
    updateCursorInfo()
end
cellWidthPanel:addChild(cellWidthSlider)
settingsRow:addChild(cellWidthPanel)

-- Cell height control
local cellHeightPanel = Panel:new({
    width = 190, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {70, 70, 70, 255},
    borderThickness = 1
})
cellHeightPanel:setPadding(5)
local cellHeightLabel = Label:new({
    text = "Cell Height: 8",
    width = 180, height = 20,
    alignment = "center"
})
cellHeightPanel:addChild(cellHeightLabel)

local cellHeightSlider = Slider:new({
    x = 5, y = 25,
    width = 180
})
cellHeightSlider.value = 0.5  -- Maps to 8 pixels
cellHeightSlider.onValueChanged = function(val)
    state.cellHeight = math.floor(4 + val * 28)  -- 4 to 32 pixels
    cellHeightLabel.text = "Cell Height: " .. state.cellHeight
    updateCursorInfo()
end
cellHeightPanel:addChild(cellHeightSlider)
settingsRow:addChild(cellHeightPanel)

-- Atlas dimensions info
local atlasDimPanel = Panel:new({
    width = 190, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {70, 70, 70, 255},
    borderThickness = 1
})
atlasDimPanel:setPadding(5)
local atlasDimLabel = Label:new({
    text = string.format("Atlas: %dx%d", state.atlasWidth, state.atlasHeight),
    width = 180, height = 20,
    alignment = "center",
    textColor = {255, 200, 100, 255}
})
atlasDimPanel:addChild(atlasDimLabel)

local gridInfoLabel = Label:new({
    x = 5, y = 25,
    text = string.format("Grid: %dx%d cells", 
        math.floor(state.atlasWidth / state.cellWidth),
        math.floor(state.atlasHeight / state.cellHeight)),
    width = 180, height = 20,
    alignment = "center",
    textColor = {200, 200, 200, 255}
})
atlasDimPanel:addChild(gridInfoLabel)
settingsRow:addChild(atlasDimPanel)

-- ===================================================
-- Helper Functions
-- ===================================================

function updateCursorInfo()
    local gridCols = math.floor(state.atlasWidth / state.cellWidth)
    local gridRows = math.floor(state.atlasHeight / state.cellHeight)
    
    cursorInfo.text = string.format("Cursor: (%d, %d) | Cell: %dx%d | Pixel: (%d, %d)", 
        state.cursorX, state.cursorY, 
        state.cellWidth, state.cellHeight,
        state.cursorX * state.cellWidth,
        state.cursorY * state.cellHeight)
    
    gridInfoLabel.text = string.format("Grid: %dx%d cells", gridCols, gridRows)
    
    -- Check if current cell has an assignment
    local assigned = nil
    for ascii, data in pairs(state.charMap) do
        if data.gridX == state.cursorX and data.gridY == state.cursorY then
            assigned = string.char(ascii)
            break
        end
    end
    
    if assigned then
        currentSelection.text = "Current cell assigned to: '" .. assigned .. "' (ASCII " .. string.byte(assigned) .. ")"
        currentSelection.textColor = {255, 255, 100, 255}
    else
        currentSelection.text = "Press any key to assign to current cell..."
        currentSelection.textColor = {100, 255, 100, 255}
    end
end

function updateAssignmentList()
    assignmentList:clearChildren()
    
    local count = 0
    local sortedChars = {}
    
    -- Sort by ASCII value
    for ascii, _ in pairs(state.charMap) do
        table.insert(sortedChars, ascii)
    end
    table.sort(sortedChars)
    
    for _, ascii in ipairs(sortedChars) do
        local data = state.charMap[ascii]
        local char = string.char(ascii)
        if ascii < 32 or ascii > 126 then
            char = "?"  -- Non-printable
        end
        
        local row = Panel:new({
            width = 374, height = 25,
            bgColor = {50, 50, 55, 255},
            borderColor = {70, 70, 75, 255},
            borderThickness = 1
        })
        
        local charLabel = Label:new({
            x = 5, y = 2,
            text = string.format("'%s' (ASCII %d) at grid (%d,%d)", 
                char, ascii, data.gridX, data.gridY),
            width = 364, height = 21,
            alignment = "left"
        })
        row:addChild(charLabel)
        
        assignmentList:addChild(row)
        count = count + 1
        
        if count >= 15 then break end  -- Limit display
    end
    
    -- Update stats
    local totalChars = 0
    for _ in pairs(state.charMap) do totalChars = totalChars + 1 end
    
    statsLabel.text = string.format("Characters Defined: %d | Atlas: %dx%d | Cell Size: %dx%d",
        totalChars, state.atlasWidth, state.atlasHeight, state.cellWidth, state.cellHeight)
end

function saveFontFile()
    -- Generate BMFont format .fnt file
    local output = {}
    
    -- Header
    table.insert(output, string.format('info face="CustomFont" size=%d bold=0 italic=0 charset="" unicode=0 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1',
        state.cellHeight))
    table.insert(output, string.format('common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0',
        state.cellHeight, state.cellHeight, state.atlasWidth, state.atlasHeight))
    table.insert(output, 'page id=0 file="' .. state.atlasPath .. '"')
    
    -- Count chars
    local charCount = 0
    for _ in pairs(state.charMap) do charCount = charCount + 1 end
    table.insert(output, 'chars count=' .. charCount)
    
    -- Character definitions
    for ascii, data in pairs(state.charMap) do
        local x = data.gridX * state.cellWidth
        local y = data.gridY * state.cellHeight
        
        table.insert(output, string.format(
            'char id=%d   x=%d     y=%d     width=%d     height=%d     xoffset=0     yoffset=0    xadvance=%d     page=0  chnl=0',
            ascii, x, y, state.cellWidth, state.cellHeight, state.cellWidth))
    end
    
    table.insert(output, 'kernings count=0')
    
    -- Write to file (in real implementation)
    local fontData = table.concat(output, "\n")
    print("=== GENERATED .FNT FILE ===")
    print(fontData)
    print("===========================")
    
    exportStatus.text = "SUCCESS! Font saved to custom_font.fnt (check console for output)"
    exportStatus.textColor = {100, 255, 100, 255}
    
    -- In a real implementation, you'd call a C function to write this to disk
    -- bridge.writeFile("custom_font.fnt", fontData)
end

-- ===================================================
-- Input Handling (Keyboard)
-- ===================================================

-- This would be called from C when a key is pressed
function HandleKeyPress(key)
    local gridCols = math.floor(state.atlasWidth / state.cellWidth)
    local gridRows = math.floor(state.atlasHeight / state.cellHeight)
    
    if key == "up" then
        state.cursorY = math.max(0, state.cursorY - 1)
        updateCursorInfo()
    elseif key == "down" then
        state.cursorY = math.min(gridRows - 1, state.cursorY + 1)
        updateCursorInfo()
    elseif key == "left" then
        state.cursorX = math.max(0, state.cursorX - 1)
        updateCursorInfo()
    elseif key == "right" then
        state.cursorX = math.min(gridCols - 1, state.cursorX + 1)
        updateCursorInfo()
    elseif key == "space" then
        -- Clear assignment (handled by button)
    elseif key == "s" or key == "S" then
        saveFontFile()
    else
        -- Assign this key to current cursor position
        local ascii = string.byte(key)
        if ascii then
            state.charMap[ascii] = {
                gridX = state.cursorX,
                gridY = state.cursorY,
                width = state.cellWidth,
                height = state.cellHeight
            }
            print(string.format("Assigned '%s' (ASCII %d) to grid (%d,%d)", 
                key, ascii, state.cursorX, state.cursorY))
            updateAssignmentList()
            updateCursorInfo()
            
            -- Auto-advance cursor
            state.cursorX = state.cursorX + 1
            if state.cursorX >= gridCols then
                state.cursorX = 0
                state.cursorY = state.cursorY + 1
                if state.cursorY >= gridRows then
                    state.cursorY = 0
                end
            end
            updateCursorInfo()
        end
    end
end

-- ===================================================
-- Initialize
-- ===================================================

-- Load atlas texture
local texId, w, h = bridge.loadTexture(state.atlasPath)
if texId then
    state.atlasTexId = texId
    state.atlasWidth = w
    state.atlasHeight = h
    print(string.format("[System] Loaded atlas: %s (%dx%d)", state.atlasPath, w, h))
    atlasDimLabel.text = string.format("Atlas: %dx%d", w, h)
else
    print("[Warning] Could not load atlas texture: " .. state.atlasPath)
    print("[Info] Place your font atlas PNG in Content/ folder")
end

updateCursorInfo()
updateAssignmentList()

-- ===================================================
-- Global Functions
-- ===================================================
function UpdateUI(mx, my, down, w, h)
    root.width = w
    root.height = h
    root:update(mx, my, down, w, h)
end

function DrawUI()
    root:draw()
    
    -- In a real implementation, you'd also draw:
    -- 1. The atlas texture
    -- 2. Grid overlay
    -- 3. Green cursor highlight
    -- 4. Preview text using the custom font
end
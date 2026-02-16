-- demo.lua
-- Comprehensive demonstration of all UI primitives

local root = UIElement:new({width=800, height=600})

-- ===================================================
-- Main container with VBox layout
-- ===================================================
local mainPanel = Panel:new({
    x = 50, y = 20, 
    width = 700, height = 550,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
mainPanel:setPadding(15)
root:addChild(mainPanel)

-- Title
local title = Label:new({
    text = "Project Bridge UI - Complete Primitives Demo",
    width = 670, 
    height = 30,
    alignment = "center",
    textColor = {255, 200, 100, 255}
})
mainPanel:addChild(title)

-- ===================================================
-- Section 1: Buttons & Labels
-- ===================================================
local buttonSection = Panel:new({
    x = 15, y = 45,
    width = 670, height = 120,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 1
})
buttonSection:setPadding(10)
mainPanel:addChild(buttonSection)

local sectionLabel1 = Label:new({
    text = "Buttons & Events",
    width = 650, height = 20,
    alignment = "left",
    textColor = {200, 200, 255, 255}
})
buttonSection:addChild(sectionLabel1)

-- Status label
local statusLabel = Label:new({
    x = 10, y = 30,
    text = "Status: Ready",
    width = 650, height = 20,
    alignment = "left"
})
buttonSection:addChild(statusLabel)

-- HBox for buttons
local btnRow = HBox:new({
    x = 10, y = 55,
    width = 650, height = 45,
    spacing = 10
})

for i = 1, 4 do
    local btn = Button:new({width = 155, height = 45})
    btn.onHover = function()
        statusLabel.text = "Hovered: Button " .. i
    end
    btn.onClick = function()
        statusLabel.text = "Clicked: Button " .. i
    end
    
    local lbl = Label:new({
        text = "Button " .. i,
        width = 155, height = 45,
        alignment = "center"
    })
    btn:addChild(lbl)
    btnRow:addChild(btn)
end

buttonSection:addChild(btnRow)

-- ===================================================
-- Section 2: Layout Systems
-- ===================================================
local layoutSection = Panel:new({
    x = 15, y = 175,
    width = 670, height = 160,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 1
})
layoutSection:setPadding(10)
mainPanel:addChild(layoutSection)

local sectionLabel2 = Label:new({
    text = "Layout Groups: VBox, HBox, GridLayout",
    width = 650, height = 20,
    alignment = "left",
    textColor = {100, 255, 150, 255}
})
layoutSection:addChild(sectionLabel2)

-- VBox example
local vbox = VBox:new({
    x = 10, y = 30,
    width = 100, height = 120,
    spacing = 5,
    expandChildren = true
})
for i = 1, 3 do
    local btn = Button:new({height = 30})
    local lbl = Label:new({text = "V" .. i, height = 30, alignment = "center"})
    btn:addChild(lbl)
    vbox:addChild(btn)
end
layoutSection:addChild(vbox)

-- HBox example
local hbox = HBox:new({
    x = 120, y = 30,
    width = 250, height = 35,
    spacing = 5
})
for i = 1, 4 do
    local btn = Button:new({width = 55, height = 35})
    local lbl = Label:new({text = "H" .. i, width = 55, height = 35, alignment = "center"})
    btn:addChild(lbl)
    hbox:addChild(btn)
end
layoutSection:addChild(hbox)

-- GridLayout example
local grid = GridLayout:new({
    x = 120, y = 75,
    width = 250, height = 75,
    columns = 4,
    spacing = 5,
    expandChildren = true
})
for i = 1, 8 do
    local btn = Button:new({})
    local lbl = Label:new({text = tostring(i), alignment = "center"})
    btn:addChild(lbl)
    grid:addChild(btn)
end
layoutSection:addChild(grid)

-- Label alignment showcase
local alignBox = VBox:new({
    x = 380, y = 30,
    width = 260, height = 120,
    spacing = 2
})

local alignments = {
    {text = "Left Align", align = "left"},
    {text = "Center", align = "center"},
    {text = "Right", align = "right"}
}

for _, cfg in ipairs(alignments) do
    local bg = Panel:new({
        width = 260, height = 25,
        bgColor = {50, 50, 50, 255},
        borderColor = {70, 70, 70, 255},
        borderThickness = 1
    })
    local lbl = Label:new({
        text = cfg.text,
        width = 260, height = 25,
        alignment = cfg.align,
        textColor = {200, 255, 255, 255}
    })
    bg:addChild(lbl)
    alignBox:addChild(bg)
end
layoutSection:addChild(alignBox)

-- ===================================================
-- Section 3: Sliders & Progress Bars
-- ===================================================
local controlSection = Panel:new({
    x = 15, y = 345,
    width = 670, height = 120,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 1
})
controlSection:setPadding(10)
mainPanel:addChild(controlSection)

local sectionLabel3 = Label:new({
    text = "Sliders & Progress Bars",
    width = 650, height = 20,
    alignment = "left",
    textColor = {255, 150, 100, 255}
})
controlSection:addChild(sectionLabel3)

-- Progress bar 1
local progressBar1 = ProgressBar:new({
    x = 10, y = 30,
    width = 300, height = 25
})
progressBar1:setValue(0.5)
controlSection:addChild(progressBar1)

-- Value label (define BEFORE slider callback uses it)
local progressValueLabel = Label:new({
    x = 10, y = 85,
    text = "Value: 50%",
    width = 300, height = 20
})
controlSection:addChild(progressValueLabel)

-- Slider 1
local slider1 = Slider:new({
    x = 10, y = 60,
    width = 300
})
slider1.value = 0.5
slider1.onValueChanged = function(val)
    progressBar1:setValue(val)
    progressValueLabel.text = string.format("Value: %d%%", math.floor(val * 100))
end
controlSection:addChild(slider1)

-- Health bar styled
local healthBar = ProgressBar:new({
    x = 320, y = 30,
    width = 330, height = 25,
    fillColor = {200, 60, 60, 255},
    emptyColor = {60, 30, 30, 255}
})
healthBar:setValue(0.75)
controlSection:addChild(healthBar)

local healthLabel = Label:new({
    x = 320, y = 60,
    text = "Health: 75/100",
    width = 330, height = 20,
    textColor = {255, 100, 100, 255},
})
controlSection:addChild(healthLabel)

-- ===================================================
-- Section 4: Toggles & Indicators
-- ===================================================
local toggleSection = Panel:new({
    x = 15, y = 475,
    width = 320, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 1
})
toggleSection:setPadding(10)
mainPanel:addChild(toggleSection)

local sectionLabel4 = Label:new({
    text = "Toggles & Indicators",
    width = 300, height = 20,
    alignment = "left",
    textColor = {200, 255, 200, 255}
})
toggleSection:addChild(sectionLabel4)

-- Toggle row
local toggleRow = HBox:new({
    x = 10, y = 30,
    width = 300, height = 24,
    spacing = 10
})

for i = 1, 3 do
    local toggle = Toggle:new({size = 24})
    toggleRow:addChild(toggle)
    
    local label = Label:new({
        text = "Option " .. i,
        width = 70, height = 24,
        alignment = "left"
    })
    toggleRow:addChild(label)
end

toggleSection:addChild(toggleRow)

-- Color indicators
local indicatorSection = Panel:new({
    x = 345, y = 475,
    width = 340, height = 60,
    bgColor = {35, 35, 38, 255},
    borderColor = {80, 80, 80, 255},
    borderThickness = 1
})
indicatorSection:setPadding(10)
mainPanel:addChild(indicatorSection)

local sectionLabel5 = Label:new({
    text = "Status Indicators",
    width = 320, height = 20,
    alignment = "left",
    textColor = {255, 255, 100, 255}
})
indicatorSection:addChild(sectionLabel5)

local indicatorRow = HBox:new({
    x = 10, y = 30,
    width = 320, height = 24,
    spacing = 10
})

local greenInd = ColorIndicator:new({
    width = 80, height = 24,
    baseColor = {60, 180, 60, 255}
})
indicatorRow:addChild(greenInd)

local yellowInd = ColorIndicator:new({
    width = 80, height = 24,
    baseColor = {200, 180, 60, 255},
    pulsing = true
})
indicatorRow:addChild(yellowInd)

local redInd = ColorIndicator:new({
    width = 80, height = 24,
    baseColor = {200, 60, 60, 255},
    pulsing = true
})
indicatorRow:addChild(redInd)

indicatorSection:addChild(indicatorRow)

-- ===================================================
-- Global Functions called by C Host
-- ===================================================
function UpdateUI(mx, my, down, w, h)
    root.width = w
    root.height = h
    root:update(mx, my, down, w, h)
end

function DrawUI()
    root:draw()
end
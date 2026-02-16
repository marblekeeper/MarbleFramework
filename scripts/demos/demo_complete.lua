-- demo_complete.lua
-- Comprehensive demonstration of ALL UI widgets

local root = UIElement:new({width=1200, height=800})

-- ===================================================
-- DEMO 1: Buttons & Labels with Full Event System
-- ===================================================
local buttonDemo = Panel:new({
    x = 20, y = 20,
    width = 280, height = 200,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
buttonDemo:setPadding(10)
root:addChild(buttonDemo)

local buttonTitle = Label:new({
    text = "Button Events Demo",
    width = 260, height = 25,
    alignment = "center",
    textColor = {200, 200, 255, 255}
})
buttonDemo:addChild(buttonTitle)

-- Status label to show events
local statusLabel = Label:new({
    x = 10, y = 35,
    text = "Status: Ready",
    width = 260, height = 20,
    alignment = "left"
})
buttonDemo:addChild(statusLabel)

-- Button with ALL events
local interactiveBtn = Button:new({
    x = 10, y = 60,
    width = 260, height = 40,
    normalColor = {60, 100, 140, 255},
    hoverColor = {80, 120, 160, 255},
    pressedColor = {40, 80, 120, 255}
})
interactiveBtn.onHover = function()
    statusLabel.text = "Status: Hovered!"
end
interactiveBtn.onPress = function()
    statusLabel.text = "Status: Pressed!"
end
interactiveBtn.onClick = function()
    statusLabel.text = "Status: Clicked!"
end
interactiveBtn.onRelease = function()
    statusLabel.text = "Status: Released!"
end
buttonDemo:addChild(interactiveBtn)

local btnLabel = Label:new({
    text = "Interactive Button", 
    width = 260, height = 40,
    alignment = "center"
})
interactiveBtn:addChild(btnLabel)

-- Disabled button demo
local disabledBtn = Button:new({
    x = 10, y = 110,
    width = 260, height = 40
})
disabledBtn.isEnabled = false
buttonDemo:addChild(disabledBtn)

local disabledLabel = Label:new({
    text = "Disabled Button",
    width = 260, height = 40,
    alignment = "center",
    textColor = {150, 150, 150, 255}
})
disabledBtn:addChild(disabledLabel)

-- Toggle disabled state
local enableToggle = Toggle:new({
    x = 10, y = 160,
    size = 24,
    isToggled = false
})
enableToggle.onToggleChanged = function(state)
    disabledBtn.isEnabled = state
    if state then
        disabledLabel.text = "Enabled Button"
        disabledLabel.textColor = {255, 255, 255, 255}
    else
        disabledLabel.text = "Disabled Button"
        disabledLabel.textColor = {150, 150, 150, 255}
    end
end
buttonDemo:addChild(enableToggle)

local toggleLabel = Label:new({
    x = 40, y = 160,
    text = "Enable button above",
    width = 220, height = 24,
    alignment = "left"
})
buttonDemo:addChild(toggleLabel)

-- ===================================================
-- DEMO 2: Layout Systems (VBox, HBox, GridLayout)
-- ===================================================
local layoutDemo = Panel:new({
    x = 320, y = 20,
    width = 400, height = 300,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
layoutDemo:setPadding(10)
root:addChild(layoutDemo)

local layoutTitle = Label:new({
    text = "Layout Systems",
    width = 380, height = 25,
    alignment = "center",
    textColor = {255, 200, 100, 255}
})
layoutDemo:addChild(layoutTitle)

-- HBox Demo
local hbox = HBox:new({
    x = 10, y = 35,
    width = 380, height = 40,
    spacing = 10,
    alignment = "center"
})
for i = 1, 4 do
    local btn = Button:new({width = 80, height = 40})
    local lbl = Label:new({text = "Btn " .. i, width = 80, height = 40, alignment = "center"})
    btn:addChild(lbl)
    hbox:addChild(btn)
end
layoutDemo:addChild(hbox)

-- VBox Demo
local vbox = VBox:new({
    x = 10, y = 85,
    width = 180, height = 200,
    spacing = 5,
    expandChildren = true
})
for i = 1, 4 do
    local btn = Button:new({height = 35})
    local lbl = Label:new({text = "Item " .. i, height = 35, alignment = "center"})
    btn:addChild(lbl)
    vbox:addChild(btn)
end
layoutDemo:addChild(vbox)

-- GridLayout Demo
local grid = GridLayout:new({
    x = 200, y = 85,
    width = 180, height = 200,
    columns = 3,
    spacing = 5,
    expandChildren = true
})
for i = 1, 9 do
    local btn = Button:new({})
    local lbl = Label:new({text = tostring(i), alignment = "center"})
    btn:addChild(lbl)
    grid:addChild(btn)
end
layoutDemo:addChild(grid)

-- ===================================================
-- DEMO 3: ProgressBar & Sliders
-- ===================================================
local progressDemo = Panel:new({
    x = 740, y = 20,
    width = 300, height = 200,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
progressDemo:setPadding(10)
root:addChild(progressDemo)

local progressTitle = Label:new({
    text = "Progress & Sliders",
    width = 280, height = 25,
    alignment = "center",
    textColor = {100, 255, 150, 255}
})
progressDemo:addChild(progressTitle)

-- Progress bar
local progressBar = ProgressBar:new({
    x = 10, y = 40,
    width = 280, height = 30
})
progressBar:setValue(0.5)
progressDemo:addChild(progressBar)

-- Slider to control progress
local progressSlider = Slider:new({
    x = 10, y = 80,
    width = 280
})
progressSlider.value = 0.5
progressSlider.onValueChanged = function(val)
    progressBar:setValue(val)
    progressValueLabel.text = string.format("Progress: %d%%", math.floor(val * 100))
end
progressDemo:addChild(progressSlider)

local progressValueLabel = Label:new({
    x = 10, y = 110,
    text = "Progress: 50%",
    width = 280, height = 20
})
progressDemo:addChild(progressValueLabel)

-- Another styled progress bar
local healthBar = ProgressBar:new({
    x = 10, y = 140,
    width = 280, height = 25,
    fillColor = {200, 60, 60, 255},
    emptyColor = {60, 30, 30, 255}
})
healthBar:setValue(0.75)
progressDemo:addChild(healthBar)

local healthLabel = Label:new({
    x = 10, y = 170,
    text = "Health: 75%",
    width = 280, height = 20,
    textColor = {255, 100, 100, 255}
})
progressDemo:addChild(healthLabel)

-- ===================================================
-- DEMO 4: Toggles & ColorIndicators
-- ===================================================
local indicatorDemo = Panel:new({
    x = 20, y = 240,
    width = 280, height = 250,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
indicatorDemo:setPadding(10)
root:addChild(indicatorDemo)

local indicatorTitle = Label:new({
    text = "Toggles & Indicators",
    width = 260, height = 25,
    alignment = "center",
    textColor = {255, 150, 200, 255}
})
indicatorDemo:addChild(indicatorTitle)

-- Toggle switches
local toggleGroup = VBox:new({
    x = 10, y = 35,
    width = 260, height = 100,
    spacing = 8
})

for i = 1, 3 do
    local toggleRow = HBox:new({
        width = 260, height = 24,
        spacing = 10
    })
    
    local toggle = Toggle:new({size = 24})
    toggleRow:addChild(toggle)
    
    local label = Label:new({
        text = "Option " .. i,
        width = 200, height = 24,
        alignment = "left"
    })
    toggleRow:addChild(label)
    
    toggleGroup:addChild(toggleRow)
end
indicatorDemo:addChild(toggleGroup)

-- Color indicators
local indicatorLabel = Label:new({
    x = 10, y = 145,
    text = "Status Indicators:",
    width = 260, height = 20
})
indicatorDemo:addChild(indicatorLabel)

local statusRow = HBox:new({
    x = 10, y = 170,
    width = 260, height = 30,
    spacing = 10
})

local greenIndicator = ColorIndicator:new({
    width = 60, height = 30,
    baseColor = {60, 180, 60, 255},
    pulsing = false
})
statusRow:addChild(greenIndicator)

local yellowIndicator = ColorIndicator:new({
    width = 60, height = 30,
    baseColor = {200, 180, 60, 255},
    pulsing = true
})
statusRow:addChild(yellowIndicator)

local redIndicator = ColorIndicator:new({
    width = 60, height = 30,
    baseColor = {200, 60, 60, 255},
    pulsing = true
})
statusRow:addChild(redIndicator)

indicatorDemo:addChild(statusRow)

local pulseToggle = Toggle:new({
    x = 10, y = 210,
    size = 24,
    isToggled = true
})
pulseToggle.onToggleChanged = function(state)
    yellowIndicator.pulsing = state
    redIndicator.pulsing = state
end
indicatorDemo:addChild(pulseToggle)

local pulseLabel = Label:new({
    x = 40, y = 210,
    text = "Enable pulsing",
    width = 220, height = 24
})
indicatorDemo:addChild(pulseLabel)

-- ===================================================
-- DEMO 5: Draggable Window
-- ===================================================
local window = Window:new({
    x = 320, y = 340,
    width = 400, height = 300
})
root:addChild(window)

-- Window title label (on title bar)
local windowTitleLabel = Label:new({
    x = 10, y = 5,
    text = "Draggable Window (Drag Me!)",
    width = 380, height = 20,
    textColor = {255, 255, 255, 255}
})
window:addChild(windowTitleLabel)

-- Content in window
local windowContent = VBox:new({
    x = 10, y = 40,
    width = 380, height = 250,
    spacing = 10
})

local welcomeLabel = Label:new({
    text = "This is a draggable window!",
    width = 380, height = 25,
    alignment = "center",
    textColor = {200, 255, 200, 255}
})
windowContent:addChild(welcomeLabel)

local infoLabel = Label:new({
    text = "Click and drag the title bar to move",
    width = 380, height = 20,
    alignment = "center"
})
windowContent:addChild(infoLabel)

-- Add some buttons to window
for i = 1, 3 do
    local btn = Button:new({height = 35})
    local lbl = Label:new({
        text = "Window Action " .. i,
        height = 35,
        alignment = "center"
    })
    btn:addChild(lbl)
    windowContent:addChild(btn)
end

window:addContent(windowContent)

-- ===================================================
-- DEMO 6: Label Alignment Showcase
-- ===================================================
local alignmentDemo = Panel:new({
    x = 740, y = 240,
    width = 300, height = 250,
    bgColor = {45, 45, 48, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 2
})
alignmentDemo:setPadding(10)
root:addChild(alignmentDemo)

local alignTitle = Label:new({
    text = "Label Alignments",
    width = 280, height = 25,
    alignment = "center",
    textColor = {255, 255, 100, 255}
})
alignmentDemo:addChild(alignTitle)

-- Left aligned
local leftBox = Panel:new({
    x = 10, y = 35,
    width = 280, height = 30,
    bgColor = {60, 60, 60, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 1
})
local leftLabel = Label:new({
    text = "Left Aligned",
    width = 280, height = 30,
    alignment = "left",
    textColor = {255, 200, 200, 255}
})
leftBox:addChild(leftLabel)
alignmentDemo:addChild(leftBox)

-- Center aligned
local centerBox = Panel:new({
    x = 10, y = 75,
    width = 280, height = 30,
    bgColor = {60, 60, 60, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 1
})
local centerLabel = Label:new({
    text = "Center Aligned",
    width = 280, height = 30,
    alignment = "center",
    textColor = {200, 255, 200, 255}
})
centerBox:addChild(centerLabel)
alignmentDemo:addChild(centerBox)

-- Right aligned
local rightBox = Panel:new({
    x = 10, y = 115,
    width = 280, height = 30,
    bgColor = {60, 60, 60, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 1
})
local rightLabel = Label:new({
    text = "Right Aligned",
    width = 280, height = 30,
    alignment = "right",
    textColor = {200, 200, 255, 255}
})
rightBox:addChild(rightLabel)
alignmentDemo:addChild(rightBox)

-- Top-left aligned
local topleftBox = Panel:new({
    x = 10, y = 155,
    width = 280, height = 80,
    bgColor = {60, 60, 60, 255},
    borderColor = {100, 100, 100, 255},
    borderThickness = 1
})
local topleftLabel = Label:new({
    text = "Top-Left\nMulti-line\nText",
    width = 280, height = 80,
    alignment = "topleft",
    textColor = {255, 255, 200, 255}
})
topleftBox:addChild(topleftLabel)
alignmentDemo:addChild(topleftBox)

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
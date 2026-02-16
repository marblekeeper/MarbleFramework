-- framework.lua
-- Complete port of ProjectBridge.UI.Primitives to Lua
-- Matches C# structure 1:1

-- ==========================================
-- Simple Class System
-- ==========================================
Object = {}
Object.__index = Object
function Object:new(o)
    o = o or {}
    setmetatable(o, self)
    return o
end
function Object:extend()
    local cls = {}
    for k, v in pairs(self) do
        if k:find("__") == 1 then
            cls[k] = v
        end
    end
    cls.__index = cls
    cls.super = self
    setmetatable(cls, self)
    return cls
end

-- ==========================================
-- UIElement.cs
-- ==========================================
UIElement = Object:extend()

function UIElement:new(o)
    o = o or {}
    setmetatable(o, self)
    o.x = o.x or 0
    o.y = o.y or 0
    o.width = o.width or 0
    o.height = o.height or 0
    o.visible = true
    o.isEnabled = true
    o.children = {}
    o.parent = nil
    
    -- Modder hooks
    o.onUpdate = nil
    o.onDraw = nil
    
    return o
end

function UIElement:getGlobalPosition()
    if not self.parent then return self.x, self.y end
    local px, py = self.parent:getGlobalPosition()
    return px + self.x, py + self.y
end

function UIElement:getBounds()
    return self.x, self.y, self.width, self.height
end

function UIElement:getGlobalBounds()
    local gx, gy = self:getGlobalPosition()
    return gx, gy, self.width, self.height
end

function UIElement:addChild(child)
    if child.parent then child.parent:removeChild(child) end
    child.parent = self
    table.insert(self.children, child)
end

function UIElement:removeChild(child)
    for i, c in ipairs(self.children) do
        if c == child then
            table.remove(self.children, i)
            child.parent = nil
            break
        end
    end
end

function UIElement:clearChildren()
    for _, child in ipairs(self.children) do
        child.parent = nil
    end
    self.children = {}
end

function UIElement:containsPoint(px, py)
    local gx, gy = self:getGlobalPosition()
    return px >= gx and px <= gx + self.width and
           py >= gy and py <= gy + self.height
end

function UIElement:update(mx, my, mouseDown, screenW, screenH)
    if not self.visible or not self.isEnabled then return end
    
    if self.onUpdate then self.onUpdate() end
    
    if self.updateSelf then self:updateSelf(mx, my, mouseDown, screenW, screenH) end
    
    for _, child in ipairs(self.children) do
        child:update(mx, my, mouseDown, screenW, screenH)
    end
end

function UIElement:draw()
    if not self.visible then return end
    
    if self.onDraw then self.onDraw(self) end
    
    if self.drawSelf then self:drawSelf() end
    
    for _, child in ipairs(self.children) do
        child:draw()
    end
end

-- ==========================================
-- Panel.cs
-- ==========================================
Panel = UIElement:extend()

function Panel:new(o)
    o = UIElement.new(self, o)
    o.bgColor = o.bgColor or {0,0,0,0}
    o.borderColor = o.borderColor or {0,0,0,0}
    o.borderThickness = o.borderThickness or 0
    o.paddingLeft = o.paddingLeft or 0
    o.paddingTop = o.paddingTop or 0
    o.paddingRight = o.paddingRight or 0
    o.paddingBottom = o.paddingBottom or 0
    return o
end

function Panel:setPadding(l, t, r, b)
    if not t then
        -- Uniform
        self.paddingLeft = l
        self.paddingTop = l
        self.paddingRight = l
        self.paddingBottom = l
    elseif not r then
        -- Horizontal, Vertical
        self.paddingLeft = l
        self.paddingRight = l
        self.paddingTop = t
        self.paddingBottom = t
    else
        -- All four
        self.paddingLeft = l
        self.paddingTop = t
        self.paddingRight = r
        self.paddingBottom = b
    end
end

function Panel:getContentBounds()
    return self.x + self.paddingLeft,
           self.y + self.paddingTop,
           self.width - self.paddingLeft - self.paddingRight,
           self.height - self.paddingTop - self.paddingBottom
end

function Panel:drawSelf()
    local gx, gy = self:getGlobalPosition()
    
    -- Draw Background
    if self.bgColor[4] > 0 then
        bridge.drawRect(gx, gy, self.width, self.height, 
            self.bgColor[1], self.bgColor[2], self.bgColor[3], self.bgColor[4])
    end
    
    -- Draw Border
    if self.borderColor[4] > 0 and self.borderThickness > 0 then
        if bridge.drawBorder then
            bridge.drawBorder(gx, gy, self.width, self.height,
                self.borderColor[1], self.borderColor[2], self.borderColor[3], self.borderColor[4],
                self.borderThickness)
        else
            -- Fallback to 1px border
            local c = self.borderColor
            bridge.drawRect(gx, gy, self.width, 1, c[1], c[2], c[3], c[4])
            bridge.drawRect(gx, gy + self.height - 1, self.width, 1, c[1], c[2], c[3], c[4])
            bridge.drawRect(gx, gy, 1, self.height, c[1], c[2], c[3], c[4])
            bridge.drawRect(gx + self.width - 1, gy, 1, self.height, c[1], c[2], c[3], c[4])
        end
    end
end

-- ==========================================
-- Button.cs
-- ==========================================
Button = Panel:extend()

function Button:new(o)
    o = Panel.new(self, o)
    o.normalColor = o.normalColor or {60, 60, 60, 255}
    o.hoverColor = o.hoverColor or {80, 80, 80, 255}
    o.pressedColor = o.pressedColor or {40, 40, 40, 255}
    o.disabledColor = o.disabledColor or {30, 30, 30, 255}
    o.bgColor = o.normalColor
    o.isHovered = false
    o.isPressed = false
    o.wasMouseDown = false
    
    -- Events
    o.onClick = nil
    o.onHover = nil
    o.onPress = nil
    o.onRelease = nil
    
    return o
end

function Button:updateSelf(mx, my, mouseDown, sw, sh)
    local wasHovered = self.isHovered
    self.isHovered = self.isEnabled and self:containsPoint(mx, my)
    
    -- Hover event
    if self.isHovered and not wasHovered then
        if self.onHover then self.onHover() end
    end
    
    -- Disabled state
    if not self.isEnabled then
        self.bgColor = self.disabledColor
        self.isPressed = false
        self.wasMouseDown = mouseDown
        return
    end
    
    if self.isHovered then
        -- Press
        if mouseDown and not self.wasMouseDown then
            self.isPressed = true
            if self.onPress then self.onPress() end
        end
        
        -- Release (click)
        if not mouseDown and self.wasMouseDown and self.isPressed then
            if self.onClick then self.onClick() end
            if self.onRelease then self.onRelease() end
            self.isPressed = false
        end
        
        -- Visual feedback
        if self.isPressed then
            self.bgColor = self.pressedColor
        else
            self.bgColor = self.hoverColor
        end
    else
        self.bgColor = self.normalColor
        
        -- Cancel press if mouse leaves
        if self.isPressed then
            self.isPressed = false
            if self.onRelease then self.onRelease() end
        end
    end
    
    self.wasMouseDown = mouseDown
end

-- ==========================================
-- Label.cs
-- ==========================================
Label = UIElement:extend()

function Label:new(o)
    o = UIElement.new(self, o)
    o.text = o.text or ""
    o.textColor = o.textColor or {255, 255, 255, 255}
    o.alignment = o.alignment or "left" -- "left", "center", "right", "topleft"
    o.width = o.width or 100
    o.height = o.height or 20
    
    -- Drop shadow
    o.dropShadow = o.dropShadow or false
    o.shadowColor = o.shadowColor or {0, 0, 0, 255}
    o.shadowOffsetX = o.shadowOffsetX or 1
    o.shadowOffsetY = o.shadowOffsetY or 1
    
    return o
end

function Label:drawSelf()
    if not self.text or self.text == "" then return end
    
    local gx, gy = self:getGlobalPosition()
    
    -- Measure text if available
    local textWidth, textHeight = 0, 14
    if bridge.measureText then
        textWidth, textHeight = bridge.measureText(self.text)
    end
    
    local drawX = gx
    local drawY = gy
    
    -- Apply alignment
    if self.alignment == "center" then
        drawX = gx + (self.width - textWidth) / 2
        drawY = gy + (self.height - textHeight) / 2
    elseif self.alignment == "right" then
        drawX = gx + (self.width - textWidth)
        drawY = gy + (self.height - textHeight) / 2
    elseif self.alignment == "topleft" then
        -- No adjustment
    else -- "left"
        drawY = gy + (self.height - textHeight) / 2
    end
    
    -- Snap to pixel boundaries
    drawX = math.floor(drawX + 0.5)
    drawY = math.floor(drawY + 0.5)
    
    -- Draw shadow
    if self.dropShadow then
        bridge.drawText(self.text, drawX + self.shadowOffsetX, drawY + self.shadowOffsetY, 
            self.shadowColor[1], self.shadowColor[2], self.shadowColor[3], self.shadowColor[4])
    end
    
    -- Draw text
    bridge.drawText(self.text, drawX, drawY, 
        self.textColor[1], self.textColor[2], self.textColor[3], self.textColor[4])
end

-- ==========================================
-- LayoutGroup.cs (Abstract Base)
-- ==========================================
LayoutGroup = Panel:extend()

function LayoutGroup:new(o)
    o = Panel.new(self, o)
    o.spacing = o.spacing or 0
    o.alignment = o.alignment or "start" -- "start", "center", "end"
    o.expandChildren = o.expandChildren or false
    o.needsLayout = true
    return o
end

function LayoutGroup:addChild(child)
    Panel.addChild(self, child)
    self.needsLayout = true
end

function LayoutGroup:removeChild(child)
    Panel.removeChild(self, child)
    self.needsLayout = true
end

function LayoutGroup:invalidateLayout()
    self.needsLayout = true
end

function LayoutGroup:updateSelf(mx, my, mouseDown, sw, sh)
    if self.needsLayout then
        if self.performLayout then
            self:performLayout()
        end
        self.needsLayout = false
    end
end

-- ==========================================
-- VBox (Vertical Box)
-- ==========================================
VBox = LayoutGroup:extend()

function VBox:performLayout()
    local totalChildHeight = 0
    local visibleCount = 0
    
    -- Calculate total height needed
    for _, child in ipairs(self.children) do
        if child.visible then
            totalChildHeight = totalChildHeight + child.height
            visibleCount = visibleCount + 1
        end
    end
    
    local totalSpacing = self.spacing * math.max(0, visibleCount - 1)
    local contentHeight = self.height - self.paddingTop - self.paddingBottom
    local availableSpace = contentHeight - totalChildHeight - totalSpacing
    
    local currentY = self.paddingTop
    
    -- Apply alignment offset
    if self.alignment == "center" then
        currentY = currentY + availableSpace / 2
    elseif self.alignment == "end" then
        currentY = currentY + availableSpace
    end
    
    -- Position children
    for _, child in ipairs(self.children) do
        if not child.visible then goto continue end
        
        child.x = self.paddingLeft
        child.y = currentY
        
        -- Optionally expand width to fill container
        if self.expandChildren then
            child.width = self.width - self.paddingLeft - self.paddingRight
        end
        
        currentY = currentY + child.height + self.spacing
        
        ::continue::
    end
end

function VBox:autoSize()
    local totalHeight = self.paddingTop + self.paddingBottom
    local maxWidth = 0
    local visibleCount = 0
    
    for _, child in ipairs(self.children) do
        if child.visible then
            totalHeight = totalHeight + child.height
            maxWidth = math.max(maxWidth, child.width)
            visibleCount = visibleCount + 1
        end
    end
    
    totalHeight = totalHeight + self.spacing * math.max(0, visibleCount - 1)
    
    self.height = totalHeight
    self.width = math.max(self.width, maxWidth + self.paddingLeft + self.paddingRight)
end

-- ==========================================
-- HBox (Horizontal Box)
-- ==========================================
HBox = LayoutGroup:extend()

function HBox:performLayout()
    local totalChildWidth = 0
    local visibleCount = 0
    
    -- Calculate total width needed
    for _, child in ipairs(self.children) do
        if child.visible then
            totalChildWidth = totalChildWidth + child.width
            visibleCount = visibleCount + 1
        end
    end
    
    local totalSpacing = self.spacing * math.max(0, visibleCount - 1)
    local contentWidth = self.width - self.paddingLeft - self.paddingRight
    local availableSpace = contentWidth - totalChildWidth - totalSpacing
    
    local currentX = self.paddingLeft
    
    -- Apply alignment offset
    if self.alignment == "center" then
        currentX = currentX + availableSpace / 2
    elseif self.alignment == "end" then
        currentX = currentX + availableSpace
    end
    
    -- Position children
    for _, child in ipairs(self.children) do
        if not child.visible then goto continue end
        
        child.x = currentX
        child.y = self.paddingTop
        
        -- Optionally expand height to fill container
        if self.expandChildren then
            child.height = self.height - self.paddingTop - self.paddingBottom
        end
        
        currentX = currentX + child.width + self.spacing
        
        ::continue::
    end
end

function HBox:autoSize()
    local totalWidth = self.paddingLeft + self.paddingRight
    local maxHeight = 0
    local visibleCount = 0
    
    for _, child in ipairs(self.children) do
        if child.visible then
            totalWidth = totalWidth + child.width
            maxHeight = math.max(maxHeight, child.height)
            visibleCount = visibleCount + 1
        end
    end
    
    totalWidth = totalWidth + self.spacing * math.max(0, visibleCount - 1)
    
    self.width = totalWidth
    self.height = math.max(self.height, maxHeight + self.paddingTop + self.paddingBottom)
end

-- ==========================================
-- GridLayout
-- ==========================================
GridLayout = LayoutGroup:extend()

function GridLayout:new(o)
    o = LayoutGroup.new(self, o)
    o.columns = o.columns or 3
    o.rows = o.rows or 0 -- 0 = auto-calculate
    return o
end

function GridLayout:performLayout()
    if #self.children == 0 then return end
    
    local cols = math.max(1, self.columns)
    local rows = self.rows > 0 and self.rows or math.ceil(#self.children / cols)
    
    local contentX, contentY, contentWidth, contentHeight = self:getContentBounds()
    
    local cellWidth = (contentWidth - self.spacing * (cols - 1)) / cols
    local cellHeight = (contentHeight - self.spacing * (rows - 1)) / rows
    
    local index = 0
    for _, child in ipairs(self.children) do
        if not child.visible then goto continue end
        
        local col = index % cols
        local row = math.floor(index / cols)
        
        child.x = self.paddingLeft + col * (cellWidth + self.spacing)
        child.y = self.paddingTop + row * (cellHeight + self.spacing)
        
        if self.expandChildren then
            child.width = cellWidth
            child.height = cellHeight
        end
        
        index = index + 1
        
        ::continue::
    end
end

-- ==========================================
-- Slider.cs
-- ==========================================
Slider = Panel:extend()

function Slider:new(o)
    o = Panel.new(self, o)
    o.value = o.value or 0.5
    o.height = o.height or 20
    o.isDragging = false
    o.onValueChanged = nil
    o.trackColor = {60, 60, 60, 255}
    o.handleColor = {100, 100, 100, 255}
    o.handleHoverColor = {120, 120, 120, 255}
    return o
end

function Slider:setValue(v)
    self.value = math.max(0, math.min(1, v))
    if self.onValueChanged then 
        self.onValueChanged(self.value) 
    end
end

function Slider:updateSelf(mx, my, mouseDown, sw, sh)
    local gx, gy = self:getGlobalPosition()
    
    local handleX = gx + (self.width - 16) * self.value
    local mouseInHandle = mx >= handleX and mx <= handleX + 16 and 
                          my >= gy and my <= gy + 20
                          
    if mouseDown and mouseInHandle and not self.isDragging then
        self.isDragging = true
    end
    
    if not mouseDown then 
        self.isDragging = false 
    end
    
    if self.isDragging then
        local relX = mx - gx
        self:setValue(relX / self.width)
    end
    
    -- Hover effect
    if mouseInHandle or self.isDragging then
        self.handleColor = self.handleHoverColor
    else
        self.handleColor = {100, 100, 100, 255}
    end
end

function Slider:drawSelf()
    local gx, gy = self:getGlobalPosition()
    
    -- Draw Track
    local c = self.trackColor
    bridge.drawRect(gx, gy + 8, self.width, 4, c[1], c[2], c[3], c[4])
    
    if self.borderColor[4] > 0 then
        bridge.drawRect(gx, gy + 8, self.width, 1, 
            self.borderColor[1], self.borderColor[2], self.borderColor[3], self.borderColor[4])
        bridge.drawRect(gx, gy + 11, self.width, 1,
            self.borderColor[1], self.borderColor[2], self.borderColor[3], self.borderColor[4])
    end
    
    -- Draw Handle
    local hx = (self.width - 16) * self.value
    local h = self.handleColor
    bridge.drawRect(gx + hx, gy, 16, 20, h[1], h[2], h[3], h[4])
    
    -- Handle border
    if self.borderColor[4] > 0 then
        local b = self.borderColor
        bridge.drawRect(gx + hx, gy, 16, 2, b[1], b[2], b[3], b[4])
        bridge.drawRect(gx + hx, gy + 18, 16, 2, b[1], b[2], b[3], b[4])
        bridge.drawRect(gx + hx, gy, 2, 20, b[1], b[2], b[3], b[4])
        bridge.drawRect(gx + hx + 14, gy, 2, 20, b[1], b[2], b[3], b[4])
    end
end

-- ==========================================
-- ProgressBar.cs
-- ==========================================
ProgressBar = Panel:extend()

function ProgressBar:new(o)
    o = Panel.new(self, o)
    o.value = o.value or 0
    o.fillColor = o.fillColor or {60, 180, 60, 255}
    o.emptyColor = o.emptyColor or {40, 40, 40, 255}
    o.bgColor = o.emptyColor
    o.borderColor = o.borderColor or {100, 100, 100, 255}
    o.borderThickness = o.borderThickness or 1
    return o
end

function ProgressBar:setValue(v)
    self.value = math.max(0, math.min(1, v))
end

function ProgressBar:drawSelf()
    local gx, gy = self:getGlobalPosition()
    
    -- Draw background (empty state)
    Panel.drawSelf(self)
    
    -- Draw fill
    local fillWidth = (self.width - 4) * self.value
    if fillWidth > 0 then
        local c = self.fillColor
        bridge.drawRect(gx + 2, gy + 2, fillWidth, self.height - 4,
            c[1], c[2], c[3], c[4])
    end
end

-- ==========================================
-- Toggle.cs
-- ==========================================
Toggle = Button:extend()

function Toggle:new(o)
    o = Button.new(self, o)
    local size = o.size or 24
    o.width = size
    o.height = size
    o.isToggled = o.isToggled or false
    o.toggledColor = o.toggledColor or {60, 180, 60, 255}
    o.untoggledColor = o.untoggledColor or {60, 60, 60, 255}
    o.indicatorColor = o.indicatorColor or {255, 255, 255, 255}
    o.borderColor = o.borderColor or {100, 100, 100, 255}
    o.borderThickness = 2
    o.onToggleChanged = nil
    
    -- Override button onClick
    local oldOnClick = o.onClick
    o.onClick = function()
        o:setToggled(not o.isToggled)
        if oldOnClick then oldOnClick() end
    end
    
    return o
end

function Toggle:setToggled(state)
    self.isToggled = state
    self.normalColor = state and self.toggledColor or self.untoggledColor
    self.bgColor = self.normalColor
    if self.onToggleChanged then
        self.onToggleChanged(state)
    end
end

function Toggle:drawSelf()
    -- Draw base (border + background)
    Panel.drawSelf(self)
    
    -- Draw indicator if toggled
    if self.isToggled then
        local gx, gy = self:getGlobalPosition()
        local c = self.indicatorColor
        bridge.drawRect(gx + 4, gy + 4, self.width - 8, self.height - 8,
            c[1], c[2], c[3], c[4])
    end
end

-- ==========================================
-- ColorIndicator.cs
-- ==========================================
ColorIndicator = Panel:extend()

function ColorIndicator:new(o)
    o = Panel.new(self, o)
    o.baseColor = o.baseColor or o.bgColor or {100, 100, 100, 255}
    o.bgColor = o.baseColor
    o.pulsing = o.pulsing or false
    o.pulseTimer = 0
    o.borderColor = o.borderColor or {
        math.min(255, math.floor(o.baseColor[1] * 1.5)),
        math.min(255, math.floor(o.baseColor[2] * 1.5)),
        math.min(255, math.floor(o.baseColor[3] * 1.5)),
        255
    }
    o.borderThickness = o.borderThickness or 1
    return o
end

function ColorIndicator:updateSelf(mx, my, mouseDown, sw, sh)
    if self.pulsing then
        self.pulseTimer = self.pulseTimer + 0.05
        local pulse = math.sin(self.pulseTimer) * 0.5 + 0.5
        
        local b = self.baseColor
        self.bgColor = {
            math.floor(b[1] + (255 - b[1]) * pulse * 0.5),
            math.floor(b[2] + (255 - b[2]) * pulse * 0.5),
            math.floor(b[3] + (255 - b[3]) * pulse * 0.5),
            b[4]
        }
    end
end

-- ==========================================
-- Window.cs
-- ==========================================
Window = Panel:extend()

function Window:new(o)
    o = Panel.new(self, o)
    o.titleBarHeight = o.titleBarHeight or 30
    o.titleBarColor = o.titleBarColor or {60, 120, 180, 255}
    o.bgColor = o.bgColor or {40, 40, 40, 255}
    o.borderColor = o.borderColor or {80, 80, 80, 255}
    o.borderThickness = o.borderThickness or 2
    
    o.isDragging = false
    o.dragOffsetX = 0
    o.dragOffsetY = 0
    
    o.titleBar = {
        color = o.titleBarColor,
        height = o.titleBarHeight
    }
    
    o.contentY = o.titleBarHeight
    
    return o
end

function Window:addContent(element)
    element.y = element.y + self.contentY
    self:addChild(element)
end

function Window:updateSelf(mx, my, mouseDown, sw, sh)
    local gx, gy = self:getGlobalPosition()
    local inTitleBar = mx >= gx and mx <= gx + self.width and
                       my >= gy and my <= gy + self.titleBarHeight
    
    if inTitleBar and mouseDown and not self.isDragging then
        self.isDragging = true
        self.dragOffsetX = mx - self.x
        self.dragOffsetY = my - self.y
    end
    
    if not mouseDown then
        self.isDragging = false
    end
    
    if self.isDragging then
        self.x = mx - self.dragOffsetX
        self.y = my - self.dragOffsetY
    end
    
    -- Hover effect
    if inTitleBar or self.isDragging then
        local c = self.titleBarColor
        self.titleBar.color = {
            math.min(255, math.floor(c[1] * 1.2)),
            math.min(255, math.floor(c[2] * 1.2)),
            math.min(255, math.floor(c[3] * 1.2)),
            c[4]
        }
    else
        self.titleBar.color = self.titleBarColor
    end
end

function Window:drawSelf()
    local gx, gy = self:getGlobalPosition()
    
    -- Draw window background
    Panel.drawSelf(self)
    
    -- Draw title bar
    local c = self.titleBar.color
    bridge.drawRect(gx, gy, self.width, self.titleBarHeight,
        c[1], c[2], c[3], c[4])
end
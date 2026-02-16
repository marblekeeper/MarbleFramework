-- assets.lua
-- MINDMARR: Optional sprite asset loading and rendering
-- Falls back to procedural rendering if assets unavailable

local floor = math.floor

local K = require("constants")

local M = {}

-- Cache for loaded textures (stores {texture, width, height})
local textureCache = {}

-- Attempt to load a sprite texture
-- Returns {texture, width, height} or nil if loading fails
function M.loadSprite(key)
    if textureCache[key] ~= nil then
        return textureCache[key] -- Return cached (could be false for failed loads)
    end
    
    local path = K.assets.sprites[key]
    if not path then
        textureCache[key] = false
        return nil
    end
    
    -- Attempt to load texture via bridge
    if not bridge or not bridge.loadTexture then
        textureCache[key] = false
        return nil
    end
    
    -- loadTexture returns (textureId, width, height)
    local success, texture, w, h = pcall(bridge.loadTexture, path)
    if success and texture then
        if key == "enemy_mindcrab" then
            print(string.format("loadTexture('%s') returned: texture=%s, w=%s, h=%s", 
                path, tostring(texture), tostring(w), tostring(h)))
        end
        textureCache[key] = {texture = texture, width = w or K.TS, height = h or K.TS}
        return textureCache[key]
    else
        textureCache[key] = false
        return nil
    end
end

-- Draw a sprite if available, return true if drawn
-- x, y: screen coordinates (top-left of tile)
-- w, h: width and height to draw (optional - uses sprite's natural size if nil)
-- key: sprite key from K.assets.sprites
-- frame: which frame to draw (1-indexed, optional)
-- frameCols, frameRows: sprite sheet layout (optional)
-- frameWidth, frameHeight: dimensions of each frame in pixels (optional)
function M.tryDrawSprite(key, x, y, w, h, frame, frameCols, frameRows, frameWidth, frameHeight)
    local spriteData = M.loadSprite(key)
    if not spriteData or spriteData == false then
        return false
    end
    
    -- Calculate source rectangle for frame
    local srcX, srcY = 0, 0
    local srcW, srcH = spriteData.width, spriteData.height
    
    if frame and frameCols and frameRows then
        local fWidth = frameWidth or (spriteData.width / frameCols)
        local fHeight = frameHeight or (spriteData.height / frameRows)
        local frameIdx = frame - 1  -- 0-indexed
        local col = frameIdx % frameCols
        local row = floor(frameIdx / frameCols)
        srcX = col * fWidth
        srcY = row * fHeight
        srcW = fWidth
        srcH = fHeight
        
        -- DEBUG: Print frame info for mind_crab
        if key == "enemy_mindcrab" then
            print(string.format("MindCrab Frame: %d, Src(%d,%d %dx%d) -> frameCols=%d rows=%d fW=%d fH=%d", 
                frame, srcX, srcY, srcW, srcH, frameCols, frameRows, fWidth, fHeight))
        end
    end
    
    -- Use frame dimensions for drawing if this is an animated sprite
    local drawW, drawH
    if frame and frameCols and frameRows then
        -- For animated sprites, draw at frame size (srcW x srcH), not full texture size
        drawW = w or srcW  -- srcW is already the frame width after calculation above
        drawH = h or srcH  -- srcH is already the frame height
    else
        -- For static sprites, use full texture size
        drawW = w or spriteData.width
        drawH = h or spriteData.height
    end
    
    -- Center the sprite in the tile if it's smaller than tile size
    local offsetX = 0
    local offsetY = 0
    if not w and drawW < K.TS then
        offsetX = (K.TS - drawW) / 2
    end
    if not h and drawH < K.TS then
        offsetY = (K.TS - drawH) / 2
    end
    
    if bridge and bridge.DrawTextureRegion and frame then
        -- DEBUG: Print what we're about to send (after all calculations)
        if key == "enemy_mindcrab" then
            print(string.format("  About to call DrawTextureRegion with:"))
            print(string.format("    texture=%s, width=%s, height=%s", 
                tostring(spriteData.texture), tostring(spriteData.width), tostring(spriteData.height)))
            print(string.format("    srcX=%s, srcY=%s, srcW=%s, srcH=%s",
                tostring(srcX), tostring(srcY), tostring(srcW), tostring(srcH)))
            print(string.format("    dstX=%s, dstY=%s, dstW=%s, dstH=%s",
                tostring(x + offsetX), tostring(y + offsetY), tostring(drawW), tostring(drawH)))
        end
        -- Use region drawing for sprite sheets (preferred)
        bridge.DrawTextureRegion(spriteData.texture, 
            spriteData.width, spriteData.height,  -- Texture dimensions
            srcX, srcY, srcW, srcH,  -- Source rect
            x + offsetX, y + offsetY, drawW, drawH)  -- Dest rect
        return true
    elseif bridge and bridge.drawTexture then
        -- Fallback: draw full texture (works for non-animated or shows first frame)
        bridge.drawTexture(spriteData.texture, x + offsetX, y + offsetY, drawW, drawH)
        return true
    end
    
    return false
end

-- Clear texture cache (call on game reset if needed)
function M.clearCache()
    textureCache = {}
end

return M
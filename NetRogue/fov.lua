-- netrogue/fov.lua
-- Field of View computation using raycasting

local MapGen = require("mapgen")
local Config = require("config")

local FOV = {
    seen = {},  -- Tracks seen tiles (1 = explored, 2 = currently visible)
    radius = 7,
}

function FOV.compute()
    local Entities = require("entities")
    local player = Entities.player
    
    -- Decay visible tiles to "seen"
    for k, v in pairs(FOV.seen) do
        if v == 2 then FOV.seen[k] = 1 end
    end
    
    -- Raycast in 360 degrees
    for a = 0, 359, 2 do
        local rad = a * math.pi / 180
        local dx = math.cos(rad)
        local dy = math.sin(rad)
        local fx, fy = player.x + 0.5, player.y + 0.5
        
        for d = 0, FOV.radius do
            local tx, ty = math.floor(fx), math.floor(fy)
            if tx < 1 or tx > Config.MW or ty < 1 or ty > Config.MH then
                break
            end
            
            FOV.seen[ty * 1000 + tx] = 2
            
            if MapGen.getTile(tx, ty) == 1 then
                break
            end
            
            fx = fx + dx * 0.5
            fy = fy + dy * 0.5
        end
    end
end

function FOV.isVisible(x, y)
    return (FOV.seen[y * 1000 + x] or 0) == 2
end

function FOV.isSeen(x, y)
    return (FOV.seen[y * 1000 + x] or 0) >= 1
end

return FOV
-- netrogue/mapgen.lua
-- Procedural map generation with seeded RNG

local Config = require("config")

local MapGen = {
    map = {},
    rooms = {},
}

local function carveRoom(rx, ry, rw, rh)
    for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
            if x >= 1 and x <= Config.MW and y >= 1 and y <= Config.MH then
                MapGen.map[y][x] = 0
            end
        end
    end
    return {
        x = rx, y = ry, w = rw, h = rh,
        cx = math.floor(rx + rw/2),
        cy = math.floor(ry + rh/2)
    }
end

local function carveCorridor(x1, y1, x2, y2)
    local x, y = x1, y1
    while x ~= x2 do
        if x >= 1 and x <= Config.MW and y >= 1 and y <= Config.MH then
            MapGen.map[y][x] = 0
        end
        x = x + (x2 > x and 1 or -1)
    end
    while y ~= y2 do
        if x >= 1 and x <= Config.MW and y >= 1 and y <= Config.MH then
            MapGen.map[y][x] = 0
        end
        y = y + (y2 > y and 1 or -1)
    end
end

function MapGen.generate(seed)
    math.randomseed(seed)
    MapGen.map = {}
    
    -- Initialize with walls
    for y = 1, Config.MH do
        MapGen.map[y] = {}
        for x = 1, Config.MW do
            MapGen.map[y][x] = 1
        end
    end

    -- Generate rooms
    MapGen.rooms = {}
    local attempts = 0
    local numRooms = math.random(7, 12)
    
    while #MapGen.rooms < numRooms and attempts < 200 do
        attempts = attempts + 1
        local rw = math.random(4, 8)
        local rh = math.random(3, 6)
        local rx = math.random(2, Config.MW - rw - 1)
        local ry = math.random(2, Config.MH - rh - 1)
        
        -- Check overlap
        local ok = true
        for _, r in ipairs(MapGen.rooms) do
            if rx < r.x + r.w + 1 and rx + rw + 1 > r.x and
               ry < r.y + r.h + 1 and ry + rh + 1 > r.y then
                ok = false
                break
            end
        end
        
        if ok then
            local room = carveRoom(rx, ry, rw, rh)
            
            -- Connect to previous room
            if #MapGen.rooms > 0 then
                local prev = MapGen.rooms[#MapGen.rooms]
                if math.random() < 0.5 then
                    carveCorridor(prev.cx, prev.cy, room.cx, prev.cy)
                    carveCorridor(room.cx, prev.cy, room.cx, room.cy)
                else
                    carveCorridor(prev.cx, prev.cy, prev.cx, room.cy)
                    carveCorridor(prev.cx, room.cy, room.cx, room.cy)
                end
            end
            
            table.insert(MapGen.rooms, room)
        end
    end
    
    -- Add extra connections
    for i = 1, math.floor(#MapGen.rooms / 3) do
        local a = MapGen.rooms[math.random(1, #MapGen.rooms)]
        local b = MapGen.rooms[math.random(1, #MapGen.rooms)]
        if a ~= b then
            carveCorridor(a.cx, a.cy, b.cx, b.cy)
        end
    end
    
    print(string.format("[MapGen] Generated %d rooms from seed %d", #MapGen.rooms, seed))
end

function MapGen.getTile(x, y)
    if x < 1 or x > Config.MW or y < 1 or y > Config.MH then
        return 1  -- Wall
    end
    return MapGen.map[y][x]
end

function MapGen.isWalkable(x, y)
    return MapGen.getTile(x, y) == 0
end

return MapGen
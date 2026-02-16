-- space_shooter_mult2.lua
-- Multiplayer arena - works with auto-connecting WebSocket in HTML

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local TAU = math.pi * 2
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local sqrt, max, min = math.sqrt, math.max, math.min

-- Network state
local net = {
    playerId = nil,
    connected = false,
}

-- Game state (received from server)
local game = {
    wave = 1,
    enemies = {},
    players = {},
}

local playerColors = {
    {50, 255, 80}, {255, 50, 255}, {50, 200, 255}, {255, 200, 50},
    {255, 100, 50}, {150, 50, 255}, {50, 255, 200}, {255, 255, 50}
}

local stars = {}
for i = 1, 120 do
    stars[i] = {
        x = rand(0, W), y = rand(0, H),
        brightness = rand(30, 100),
        size = rand() < 0.3 and 2 or 1,
        speed = rand(5, 30),
    }
end

print("Space Shooter Multiplayer loaded - WebSocket auto-connecting via HTML")

-- Simple JSON string builder
local function buildInputJSON(keys)
    return string.format(
        '{"type":"input","input":{"left":%s,"right":%s,"up":%s,"space":%s}}',
        keys.left and "true" or "false",
        keys.right and "true" or "false",
        keys.up and "true" or "false",
        keys.space and "true" or "false"
    )
end

-- Parse JSON manually - improved version
local function parseJSON(str)
    if not str or str == "" then return nil end
    
    local result = { type = "", playerId = "", colorIdx = 1, wave = 1, players = {}, enemies = {} }
    
    -- Extract type
    local typeMatch = str:match('"type"%s*:%s*"([^"]+)"')
    if typeMatch then result.type = typeMatch end
    
    -- Extract playerId
    local pidMatch = str:match('"playerId"%s*:%s*"([^"]+)"')
    if pidMatch then result.playerId = pidMatch end
    
    -- Extract colorIdx
    local colorMatch = str:match('"colorIdx"%s*:%s*(%d+)')
    if colorMatch then result.colorIdx = tonumber(colorMatch) end
    
    -- Extract wave
    local waveMatch = str:match('"wave"%s*:%s*(%d+)')
    if waveMatch then result.wave = tonumber(waveMatch) end
    
    -- Parse state messages
    if result.type == "state" then
        -- Find the players object - look for "players":{...}
        -- We need to find the matching closing brace
        local playersStart = str:find('"players"%s*:%s*{')
        if playersStart then
            -- Find matching }
            local depth = 0
            local i = playersStart
            local foundStart = false
            while i <= #str do
                local c = str:sub(i, i)
                if c == '{' then
                    depth = depth + 1
                    foundStart = true
                elseif c == '}' then
                    depth = depth - 1
                    if foundStart and depth == 0 then
                        -- Found the end
                        local playersStr = str:sub(playersStart, i)
                        
                        -- Now extract each player
                        -- Pattern: "playerid":{...}
                        for playerId, playerJson in playersStr:gmatch('"([^"]+)"%s*:%s*({[^}]*})') do
                            local p = {}
                            p.x = tonumber(playerJson:match('"x"%s*:%s*([%d%.%-]+)')) or 400
                            p.y = tonumber(playerJson:match('"y"%s*:%s*([%d%.%-]+)')) or 300
                            p.angle = tonumber(playerJson:match('"angle"%s*:%s*([%d%.%-]+)')) or 0
                            p.health = tonumber(playerJson:match('"health"%s*:%s*(%d+)')) or 3
                            p.alive = not playerJson:match('"alive"%s*:%s*false')
                            p.invincible = tonumber(playerJson:match('"invincible"%s*:%s*([%d%.]+)')) or 0
                            p.score = tonumber(playerJson:match('"score"%s*:%s*(%d+)')) or 0
                            p.colorIdx = tonumber(playerJson:match('"colorIdx"%s*:%s*(%d+)')) or 1
                            result.players[playerId] = p
                        end
                        break
                    end
                end
                i = i + 1
            end
        end
        
        -- Parse enemies array - simpler since they're in an array
        local enemiesStart = str:find('"enemies"%s*:%s*%[')
        if enemiesStart then
            local enemiesEnd = str:find('%]', enemiesStart)
            if enemiesEnd then
                local enemiesStr = str:sub(enemiesStart, enemiesEnd)
                
                -- Extract each enemy object
                for enemyJson in enemiesStr:gmatch('{[^}]*}') do
                    local e = {}
                    e.x = tonumber(enemyJson:match('"x"%s*:%s*([%d%.%-]+)')) or 400
                    e.y = tonumber(enemyJson:match('"y"%s*:%s*([%d%.%-]+)')) or 300
                    e.type = enemyJson:match('"type"%s*:%s*"([^"]+)"') or "grunt"
                    e.radius = tonumber(enemyJson:match('"radius"%s*:%s*(%d+)')) or 10
                    result.enemies[#result.enemies + 1] = e
                end
            end
        end
    end
    
    return result
end

-- Check connection using window function
local function checkConnection()
    if bridge and bridge.callJS then
        local status = bridge.callJS("wsIsConnected()")
        net.connected = (status == 1 or status == "1")
    end
end

-- Get message from JavaScript queue
local msgCount = 0
local function pollMessage()
    if bridge and bridge.callJS then
        local msg = bridge.callJS("wsGetMessage()")
        if msg and msg ~= "" and msg ~= "null" then
            msgCount = msgCount + 1
            return msg
        end
    end
    return nil
end

-- Send message to server
local function sendMessage(msg)
    if not net.connected then return end
    
    if bridge and bridge.callJS then
        bridge.callJS("wsSendMessage('" .. msg .. "')")
    end
end

local function pollKeys()
    if not bridge.getKeyState then return {} end
    return {
        left = bridge.getKeyState("left") == 1 or bridge.getKeyState("a") == 1,
        right = bridge.getKeyState("right") == 1 or bridge.getKeyState("d") == 1,
        up = bridge.getKeyState("up") == 1 or bridge.getKeyState("w") == 1,
        space = bridge.getKeyState("space") == 1,
    }
end

-- Update
local frameCount = 0
function UpdateGame(dt)
    frameCount = frameCount + 1
    local keys = pollKeys()
    
    -- Check connection every 30 frames
    if frameCount % 30 == 0 then
        checkConnection()
    end
    
    -- Poll for messages every frame
    local msg = pollMessage()
    if msg then
        -- Debug: print first 200 chars of message
        if frameCount % 60 == 0 then
            print("MSG: " .. msg:sub(1, 200))
        end
        
        local data = parseJSON(msg)
        
        if data and data.type == "welcome" then
            net.playerId = data.playerId
            print("Connected! You are " .. net.playerId)
            
        elseif data and data.type == "state" then
            game.wave = data.wave
            
            -- Update players from server
            game.players = data.players
            
            -- Update enemies from server
            game.enemies = data.enemies
            
            -- Debug: print counts
            if frameCount % 60 == 0 then
                local pcount = 0
                for _ in pairs(game.players) do pcount = pcount + 1 end
                print("Players: " .. pcount .. ", Enemies: " .. #game.enemies)
            end
            
        elseif data and data.type == "playerJoined" then
            if data.playerId and data.playerId ~= "" then
                print("Player " .. data.playerId .. " joined")
            end
            
        elseif data and data.type == "playerLeft" then
            if data.playerId and data.playerId ~= "" then
                print("Player " .. data.playerId .. " left")
            end
        end
    end
    
    -- Send input to server
    if net.connected then
        local inputJSON = buildInputJSON(keys)
        sendMessage(inputJSON)
    end
    
    -- Update stars
    for _, s in ipairs(stars) do
        s.y = s.y + s.speed * dt
        if s.y > H then s.y = 0; s.x = rand(0, W) end
    end
end

-- Draw
local function drawShip(x, y, angle, r, g, b)
    local nx, ny = cos(angle), sin(angle)
    local px, py = -ny, nx

    local tipX, tipY = x + nx * 14, y + ny * 14
    local lx, ly = x - nx * 10 + px * 8, y - ny * 10 + py * 8
    local rx, ry = x - nx * 10 - px * 8, y - ny * 10 - py * 8

    for t = 0, 1, 0.08 do
        local ax = lx + (tipX - lx) * t
        local ay = ly + (tipY - ly) * t
        local bx = rx + (tipX - rx) * t
        local by = ry + (tipY - ry) * t
        local minx = min(ax, bx)
        local maxx = max(ax, bx)
        local miny = min(ay, by)
        local maxy = max(ay, by)
        local w = max(2, maxx - minx)
        local h = max(2, maxy - miny)
        bridge.drawRect(minx, miny, w, h, r, g, b, 255)
    end

    local ex, ey = x - nx * 6, y - ny * 6
    bridge.drawRect(ex - 3, ey - 3, 6, 6, floor(r*0.5), floor(g*0.5), floor(b*0.5), 255)
end

function DrawGame()
    bridge.drawRect(0, 0, W, H, 5, 5, 12, 255)

    -- Stars
    for _, s in ipairs(stars) do
        local br = s.brightness
        bridge.drawRect(s.x, s.y, s.size, s.size, br, br, floor(br * 1.2), 255)
    end

    -- Enemies (placeholder)
    for _, e in ipairs(game.enemies) do
        local ex, ey = e.x or 400, e.y or 300
        bridge.drawRect(ex - 8, ey - 8, 16, 16, 255, 60, 30, 255)
    end

    -- Players (placeholder)
    for pid, p in pairs(game.players) do
        if p.alive then
            local c = playerColors[p.colorIdx] or {255, 255, 255}
            drawShip(p.x or 400, p.y or 300, p.angle or 0, c[1], c[2], c[3])
        end
    end

    -- HUD
    bridge.drawText(string.format("WAVE %d", game.wave), W/2 - 30, 8, 255, 255, 100, 255)
    
    -- Connection status
    if net.connected then
        bridge.drawText("CONNECTED", 10, 8, 50, 255, 50, 255)
        if net.playerId then
            bridge.drawText("YOU: " .. net.playerId, 10, 28, 200, 200, 200, 255)
        end
        bridge.drawText("MSG: " .. msgCount, 10, 48, 150, 150, 255, 255)
    else
        bridge.drawRect(W/2 - 100, H/2 - 30, 200, 60, 20, 20, 20, 220)
        bridge.drawText("CONNECTING...", W/2 - 50, H/2 - 15, 255, 200, 50, 255)
        bridge.drawText("Check console (F12)", W/2 - 60, H/2 + 5, 150, 150, 150, 200)
    end
end

-- Global hooks
function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    UpdateGame(0.016)
end

function DrawUI()
    DrawGame()
end

-- space_shooter_mp.lua
-- Retro Asteroids-style shooter with LAN multiplayer via WebSockets
-- Host creates game, others join via IP:port

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local TAU = math.pi * 2
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, sqrt, max, min = math.abs, math.sqrt, math.max, math.min
local atan2 = atan2 or math.atan

-- Network state
local net = {
    mode = "none", -- "none", "host", "client"
    ws = nil,
    playerId = nil,
    players = {}, -- playerId -> player data
    serverUrl = "",
    connected = false,
    pingTimer = 0,
    inputSeq = 0,
}

-- Game state
local game = {
    state = "menu", -- "menu", "lobby", "playing", "gameover"
    score = 0,
    lives = 3,
    wave = 1,
    waveTimer = 0,
    shakeTimer = 0,
    shakeIntensity = 0,
    dt = 0.016,
    menuSelection = 1,
}

local playerColors = {
    {50, 255, 80},    -- Green
    {255, 50, 255},   -- Magenta
    {50, 200, 255},   -- Cyan
    {255, 200, 50},   -- Yellow
}

local function createPlayer(pid, colorIdx)
    return {
        id = pid,
        x = 400, y = 300,
        vx = 0, vy = 0,
        angle = -math.pi/2,
        rotSpeed = 4.5,
        thrust = 320,
        drag = 0.985,
        radius = 12,
        health = 3,
        maxHealth = 3,
        bullets = {},
        fireRate = 0.12,
        fireCooldown = 0,
        invincible = 0,
        thrustOn = false,
        alive = true,
        respawnTimer = 0,
        score = 0,
        colorIdx = colorIdx or 1,
        -- Client prediction
        lastInputSeq = 0,
        inputBuffer = {},
    }
end

local player = createPlayer("local", 1)

local enemies = {}
local particles = {}
local stars = {}
local pickups = {}

-- Star field
for i = 1, 120 do
    stars[i] = {
        x = rand(0, W),
        y = rand(0, H),
        brightness = rand(30, 100),
        size = rand() < 0.3 and 2 or 1,
        speed = rand(5, 30),
    }
end

-- Network helpers
local function sendMessage(msg)
    if net.ws and net.connected then
        local json = require("json")
        local ok, err = pcall(function()
            net.ws:send(json.encode(msg))
        end)
        if not ok then
            print("Send error:", err)
        end
    end
end

local function broadcastGameState()
    if net.mode ~= "host" then return end
    
    local enemyData = {}
    for _, e in ipairs(enemies) do
        enemyData[#enemyData+1] = {
            x = e.x, y = e.y,
            vx = e.vx, vy = e.vy,
            angle = e.angle,
            type = e.type,
            health = e.health,
            radius = e.radius,
        }
    end
    
    local playerData = {}
    for pid, p in pairs(net.players) do
        playerData[pid] = {
            x = p.x, y = p.y,
            vx = p.vx, vy = p.vy,
            angle = p.angle,
            health = p.health,
            alive = p.alive,
            thrustOn = p.thrustOn,
            score = p.score,
            invincible = p.invincible,
            colorIdx = p.colorIdx,
        }
    end
    
    sendMessage({
        type = "state",
        wave = game.wave,
        enemies = enemyData,
        players = playerData,
        particles = {}, -- Don't sync particles, too heavy
    })
end

local function hostGame()
    -- In WASM, you'd need a separate WebSocket server
    -- For now, we'll simulate hosting
    net.mode = "host"
    net.playerId = "host"
    net.connected = true
    
    -- Add host as player 1
    player.id = "host"
    player.colorIdx = 1
    net.players["host"] = player
    
    game.state = "lobby"
    print("Hosting game - waiting for players...")
    print("Tell others to connect to your IP")
end

local function joinGame(url)
    -- WebSocket connection to host
    local ok, ws = pcall(function()
        return WebSocket.new(url)
    end)
    
    if not ok then
        print("Failed to connect to", url)
        return
    end
    
    net.ws = ws
    net.serverUrl = url
    net.mode = "client"
    
    ws.onopen = function()
        net.connected = true
        sendMessage({type = "join"})
        print("Connected to host!")
    end
    
    ws.onmessage = function(data)
        local json = require("json")
        local msg = json.decode(data)
        handleNetMessage(msg)
    end
    
    ws.onerror = function(err)
        print("Connection error:", err)
        net.connected = false
    end
    
    ws.onclose = function()
        print("Disconnected from host")
        net.connected = false
        game.state = "menu"
    end
end

function handleNetMessage(msg)
    if msg.type == "welcome" then
        net.playerId = msg.playerId
        player.id = msg.playerId
        player.colorIdx = msg.colorIdx
        game.state = "lobby"
        
    elseif msg.type == "state" then
        -- Server authoritative state
        game.wave = msg.wave
        
        -- Update enemies
        enemies = {}
        for _, edata in ipairs(msg.enemies) do
            local e = {
                x = edata.x, y = edata.y,
                vx = edata.vx, vy = edata.vy,
                angle = edata.angle,
                type = edata.type,
                health = edata.health,
                radius = edata.radius,
                bullets = {},
                alive = true,
            }
            enemies[#enemies+1] = e
        end
        
        -- Update remote players
        for pid, pdata in pairs(msg.players) do
            if pid ~= net.playerId then
                if not net.players[pid] then
                    net.players[pid] = createPlayer(pid, pdata.colorIdx)
                end
                local p = net.players[pid]
                -- Interpolate position
                p.x = pdata.x
                p.y = pdata.y
                p.vx = pdata.vx
                p.vy = pdata.vy
                p.angle = pdata.angle
                p.health = pdata.health
                p.alive = pdata.alive
                p.thrustOn = pdata.thrustOn
                p.score = pdata.score
                p.invincible = pdata.invincible
            end
        end
        
    elseif msg.type == "input" then
        -- Host receives client input
        if net.mode == "host" then
            local p = net.players[msg.playerId]
            if p then
                -- Apply input to player
                applyInput(p, msg.input, game.dt)
            end
        end
        
    elseif msg.type == "start" then
        game.state = "playing"
        resetGame()
        
    elseif msg.type == "playerJoined" then
        print("Player", msg.playerId, "joined")
        
    elseif msg.type == "playerLeft" then
        net.players[msg.playerId] = nil
        print("Player", msg.playerId, "left")
    end
end

-- Helpers
local function wrap(x, y)
    if x < -20 then x = x + W + 40 end
    if x > W + 20 then x = x - W - 40 end
    if y < -20 then y = y + H + 40 end
    if y > H + 20 then y = y - H - 40 end
    return x, y
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx*dx + dy*dy)
end

local function spawnParticles(x, y, count, r, g, b, speed, life)
    for i = 1, count do
        local a = rand() * TAU
        local s = rand() * speed + speed * 0.3
        particles[#particles+1] = {
            x = x, y = y,
            vx = cos(a) * s,
            vy = sin(a) * s,
            life = life * (0.5 + rand() * 0.5),
            maxLife = life,
            r = r, g = g, b = b,
            size = rand() < 0.4 and 3 or 2,
        }
    end
end

local function screenShake(intensity, duration)
    game.shakeTimer = duration
    game.shakeIntensity = intensity
end

-- Enemy types
local function spawnEnemy(etype)
    local side = rand(1, 4)
    local x, y
    if side == 1 then x, y = rand(0, W), -20
    elseif side == 2 then x, y = rand(0, W), H + 20
    elseif side == 3 then x, y = -20, rand(0, H)
    else x, y = W + 20, rand(0, H) end

    -- Pick random alive player to target
    local targetX, targetY = 400, 300
    for _, p in pairs(net.players) do
        if p.alive then
            targetX, targetY = p.x, p.y
            break
        end
    end

    local e = {
        x = x, y = y, vx = 0, vy = 0,
        angle = rand() * TAU,
        rotSpeed = (rand() - 0.5) * 3,
        radius = 10,
        health = 1,
        type = etype or "grunt",
        fireTimer = rand() * 2,
        bullets = {},
        alive = true,
    }

    if e.type == "grunt" then
        local spd = 60 + game.wave * 8
        local a = atan2(targetY - y, targetX - x) + (rand() - 0.5) * 0.8
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 10
        e.health = 1
        e.score = 100
    elseif e.type == "tank" then
        local spd = 35 + game.wave * 4
        local a = atan2(targetY - y, targetX - x)
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 16
        e.health = 3
        e.score = 300
    elseif e.type == "fast" then
        local spd = 140 + game.wave * 10
        local a = atan2(targetY - y, targetX - x) + (rand() - 0.5) * 0.3
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 8
        e.health = 1
        e.score = 200
    elseif e.type == "shooter" then
        local spd = 50 + game.wave * 5
        local a = atan2(targetY - y, targetX - x) + (rand() - 0.5) * 1.0
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 12
        e.health = 2
        e.fireRate = max(0.8, 2.0 - game.wave * 0.1)
        e.score = 250
    end

    enemies[#enemies+1] = e
end

local function spawnWave()
    local w = game.wave
    local grunts = 3 + w * 2
    local tanks = floor(w / 2)
    local fasts = floor(w / 3) + (w > 2 and 1 or 0)
    local shooters = floor(w / 4) + (w > 3 and 1 or 0)

    for i = 1, grunts do spawnEnemy("grunt") end
    for i = 1, tanks do spawnEnemy("tank") end
    for i = 1, fasts do spawnEnemy("fast") end
    for i = 1, shooters do spawnEnemy("shooter") end
end

local function spawnPickup(x, y)
    if rand() < 0.25 then
        pickups[#pickups+1] = {
            x = x, y = y,
            type = rand() < 0.5 and "health" or "rapid",
            life = 8,
            radius = 8,
            pulse = 0,
        }
    end
end

local function fireBullet(e, angle, speed, isEnemy)
    local bx = e.x + cos(angle) * (e.radius + 4)
    local by = e.y + sin(angle) * (e.radius + 4)
    local list = isEnemy and e.bullets or e.bullets
    list[#list+1] = {
        x = bx, y = by,
        vx = cos(angle) * speed,
        vy = sin(angle) * speed,
        alive = true,
        life = 2.5,
        isEnemy = isEnemy,
    }
end

local function resetPlayer(p)
    p.x = W / 2 + rand(-50, 50)
    p.y = H / 2 + rand(-50, 50)
    p.vx = 0
    p.vy = 0
    p.angle = -math.pi / 2
    p.alive = true
    p.invincible = 2.0
    p.health = p.maxHealth
    p.bullets = {}
    p.fireCooldown = 0
end

local function resetGame()
    game.score = 0
    game.wave = 1
    game.waveTimer = 0
    game.state = "playing"
    enemies = {}
    particles = {}
    pickups = {}
    
    for _, p in pairs(net.players) do
        resetPlayer(p)
        p.score = 0
    end
    
    if net.mode == "host" then
        spawnWave()
    end
end

-- Input handling
local function applyInput(p, input, dt)
    if not p.alive then return end
    
    if input.left then p.angle = p.angle - p.rotSpeed * dt end
    if input.right then p.angle = p.angle + p.rotSpeed * dt end
    
    p.thrustOn = input.up
    if input.up then
        p.vx = p.vx + cos(p.angle) * p.thrust * dt
        p.vy = p.vy + sin(p.angle) * p.thrust * dt
        
        if rand() < 0.7 then
            local ba = p.angle + math.pi + (rand() - 0.5) * 0.8
            spawnParticles(
                p.x - cos(p.angle) * 12,
                p.y - sin(p.angle) * 12,
                1, playerColors[p.colorIdx][1], rand(100, 200), 30,
                40 + rand() * 30, 0.3
            )
        end
    end
    
    p.vx = p.vx * p.drag
    p.vy = p.vy * p.drag
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.x, p.y = wrap(p.x, p.y)
    
    p.invincible = max(0, p.invincible - dt)
    p.fireCooldown = max(0, p.fireCooldown - dt)
    
    if input.space and p.fireCooldown <= 0 then
        fireBullet(p, p.angle, 500, false)
        p.fireCooldown = p.fireRate
        
        spawnParticles(
            p.x + cos(p.angle) * 16,
            p.y + sin(p.angle) * 16,
            3, 255, 255, 150, 60, 0.15
        )
    end
end

local function pollKeys()
    if not bridge.getKeyState then return {} end
    return {
        left = bridge.getKeyState("left") == 1 or bridge.getKeyState("a") == 1,
        right = bridge.getKeyState("right") == 1 or bridge.getKeyState("d") == 1,
        up = bridge.getKeyState("up") == 1 or bridge.getKeyState("w") == 1,
        space = bridge.getKeyState("space") == 1,
        enter = bridge.getKeyState("return") == 1,
        escape = bridge.getKeyState("escape") == 1,
    }
end

-- Update
function UpdateGame(dt)
    game.dt = dt
    local keys = pollKeys()
    
    -- Shake decay
    if game.shakeTimer > 0 then
        game.shakeTimer = game.shakeTimer - dt
    end
    
    -- Menu
    if game.state == "menu" then
        if keys.up and game.menuSelection > 1 then
            game.menuSelection = game.menuSelection - 1
        elseif keys.down and game.menuSelection < 3 then
            game.menuSelection = game.menuSelection + 1
        elseif keys.enter or keys.space then
            if game.menuSelection == 1 then
                hostGame()
            elseif game.menuSelection == 2 then
                -- Join - in real impl, show IP input
                joinGame("ws://localhost:8080")
            elseif game.menuSelection == 3 then
                -- Single player
                net.mode = "host"
                net.playerId = "solo"
                net.connected = true
                player.id = "solo"
                net.players["solo"] = player
                resetGame()
            end
        end
        return
    end
    
    -- Lobby
    if game.state == "lobby" then
        if net.mode == "host" and keys.enter then
            game.state = "playing"
            resetGame()
            sendMessage({type = "start"})
        end
        return
    end
    
    -- Game over
    if game.state == "gameover" then
        if keys.space then
            if net.mode == "host" then
                resetGame()
                sendMessage({type = "start"})
            end
        end
        
        -- Update particles
        for i = #particles, 1, -1 do
            local p = particles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            p.vx = p.vx * 0.97
            p.vy = p.vy * 0.97
            if p.life <= 0 then table.remove(particles, i) end
        end
        return
    end
    
    -- Playing
    if game.state == "playing" then
        -- Send local input
        if net.mode == "client" then
            net.inputSeq = net.inputSeq + 1
            sendMessage({
                type = "input",
                playerId = net.playerId,
                seq = net.inputSeq,
                input = keys,
            })
        end
        
        -- Apply input to local player (client prediction)
        local localPlayer = net.players[net.playerId]
        if localPlayer then
            applyInput(localPlayer, keys, dt)
        end
        
        -- Host simulates everything
        if net.mode == "host" then
            -- Update all players
            for pid, p in pairs(net.players) do
                if p.alive then
                    if not p.respawnTimer or p.respawnTimer <= 0 then
                        -- Bullets
                        for bi = #p.bullets, 1, -1 do
                            local b = p.bullets[bi]
                            b.x = b.x + b.vx * dt
                            b.y = b.y + b.vy * dt
                            b.life = b.life - dt
                            b.x, b.y = wrap(b.x, b.y)
                            if b.life <= 0 then
                                table.remove(p.bullets, bi)
                            end
                        end
                    end
                else
                    p.respawnTimer = (p.respawnTimer or 0) - dt
                    if p.respawnTimer <= 0 then
                        resetPlayer(p)
                    end
                end
            end
            
            -- Enemies
            for ei = #enemies, 1, -1 do
                local e = enemies[ei]
                e.x = e.x + e.vx * dt
                e.y = e.y + e.vy * dt
                e.x, e.y = wrap(e.x, e.y)
                e.angle = e.angle + e.rotSpeed * dt
                
                -- Shooter fires
                if e.type == "shooter" and e.fireRate then
                    e.fireTimer = e.fireTimer - dt
                    if e.fireTimer <= 0 then
                        -- Find nearest alive player
                        local nearestDist = 99999
                        local nearestP = nil
                        for _, p in pairs(net.players) do
                            if p.alive then
                                local d = dist(e.x, e.y, p.x, p.y)
                                if d < nearestDist then
                                    nearestDist = d
                                    nearestP = p
                                end
                            end
                        end
                        
                        if nearestP then
                            local a = atan2(nearestP.y - e.y, nearestP.x - e.x)
                            fireBullet(e, a, 200 + game.wave * 10, true)
                            e.fireTimer = e.fireRate
                            spawnParticles(e.x, e.y, 2, 255, 80, 80, 30, 0.15)
                        end
                    end
                end
                
                -- Enemy bullets
                for bi = #e.bullets, 1, -1 do
                    local b = e.bullets[bi]
                    b.x = b.x + b.vx * dt
                    b.y = b.y + b.vy * dt
                    b.life = b.life - dt
                    b.x, b.y = wrap(b.x, b.y)
                    
                    -- Hit players
                    for _, p in pairs(net.players) do
                        if p.alive and p.invincible <= 0 and b.life > 0 then
                            if dist(b.x, b.y, p.x, p.y) < p.radius then
                                b.life = 0
                                p.health = p.health - 1
                                screenShake(4, 0.15)
                                spawnParticles(p.x, p.y, 8, 255, 200, 50, 80, 0.4)
                                if p.health <= 0 then
                                    p.alive = false
                                    p.respawnTimer = 2.0
                                    spawnParticles(p.x, p.y, 30, playerColors[p.colorIdx][1], 
                                                 playerColors[p.colorIdx][2], 
                                                 playerColors[p.colorIdx][3], 150, 0.8)
                                    screenShake(8, 0.3)
                                end
                            end
                        end
                    end
                    
                    if b.life <= 0 then table.remove(e.bullets, bi) end
                end
                
                -- Player bullets hit enemy
                for _, p in pairs(net.players) do
                    for bi = #p.bullets, 1, -1 do
                        local b = p.bullets[bi]
                        if b.life > 0 and dist(b.x, b.y, e.x, e.y) < e.radius + 3 then
                            b.life = 0
                            table.remove(p.bullets, bi)
                            e.health = e.health - 1
                            spawnParticles(b.x, b.y, 5, 255, 200, 100, 60, 0.3)
                            screenShake(2, 0.08)
                            if e.health <= 0 then
                                p.score = p.score + (e.score or 100)
                                local cr, cg, cb = 255, 100, 50
                                if e.type == "tank" then cr, cg, cb = 255, 150, 50
                                elseif e.type == "fast" then cr, cg, cb = 50, 200, 255
                                elseif e.type == "shooter" then cr, cg, cb = 255, 50, 200 end
                                spawnParticles(e.x, e.y, 20, cr, cg, cb, 120, 0.6)
                                screenShake(5, 0.15)
                                spawnPickup(e.x, e.y)
                                table.remove(enemies, ei)
                                break
                            end
                        end
                    end
                end
                
                -- Collide with players
                for _, p in pairs(net.players) do
                    if p.alive and p.invincible <= 0 then
                        if dist(e.x, e.y, p.x, p.y) < e.radius + p.radius then
                            p.health = p.health - 2
                            e.health = e.health - 2
                            screenShake(6, 0.2)
                            spawnParticles(p.x, p.y, 12, 255, 150, 50, 100, 0.5)
                            if p.health <= 0 then
                                p.alive = false
                                p.respawnTimer = 2.0
                                spawnParticles(p.x, p.y, 30, playerColors[p.colorIdx][1],
                                             playerColors[p.colorIdx][2],
                                             playerColors[p.colorIdx][3], 150, 0.8)
                                screenShake(8, 0.3)
                            end
                            if e.health <= 0 then
                                p.score = p.score + (e.score or 100)
                                spawnParticles(e.x, e.y, 15, 255, 100, 50, 100, 0.5)
                                table.remove(enemies, ei)
                                break
                            end
                        end
                    end
                end
            end
            
            -- Pickups
            for i = #pickups, 1, -1 do
                local pk = pickups[i]
                pk.life = pk.life - dt
                pk.pulse = pk.pulse + dt * 5
                if pk.life <= 0 then
                    table.remove(pickups, i)
                else
                    for _, p in pairs(net.players) do
                        if p.alive and dist(pk.x, pk.y, p.x, p.y) < pk.radius + p.radius then
                            if pk.type == "health" then
                                p.health = min(p.maxHealth, p.health + 1)
                                spawnParticles(pk.x, pk.y, 10, 50, 255, 50, 60, 0.4)
                            elseif pk.type == "rapid" then
                                p.fireRate = max(0.05, p.fireRate - 0.02)
                                spawnParticles(pk.x, pk.y, 10, 50, 150, 255, 60, 0.4)
                            end
                            table.remove(pickups, i)
                            break
                        end
                    end
                end
            end
            
            -- Wave check
            if #enemies == 0 then
                game.waveTimer = game.waveTimer + dt
                if game.waveTimer > 2.0 then
                    game.wave = game.wave + 1
                    game.waveTimer = 0
                    spawnWave()
                end
            end
            
            -- Broadcast state to clients
            net.pingTimer = net.pingTimer + dt
            if net.pingTimer > 0.05 then -- 20Hz update rate
                broadcastGameState()
                net.pingTimer = 0
            end
        end
        
        -- Particles
        for i = #particles, 1, -1 do
            local p = particles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            p.vx = p.vx * 0.97
            p.vy = p.vy * 0.97
            if p.life <= 0 then table.remove(particles, i) end
        end
        
        -- Stars
        for _, s in ipairs(stars) do
            s.y = s.y + s.speed * dt
            if s.y > H then s.y = 0; s.x = rand(0, W) end
        end
    end
end

-- Draw helpers
local function drawShip(x, y, angle, r, g, b, a, scale)
    scale = scale or 1.0
    local nx, ny = cos(angle), sin(angle)
    local px, py = -ny, nx

    local tipX, tipY = x + nx * 14 * scale, y + ny * 14 * scale
    local lx, ly = x - nx * 10 * scale + px * 8 * scale, y - ny * 10 * scale + py * 8 * scale
    local rx, ry = x - nx * 10 * scale - px * 8 * scale, y - ny * 10 * scale - py * 8 * scale

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
        bridge.drawRect(minx, miny, w, h, r, g, b, a)
    end

    local ex, ey = x - nx * 6 * scale, y - ny * 6 * scale
    bridge.drawRect(ex - 3*scale, ey - 3*scale, 6*scale, 6*scale, floor(r*0.5), floor(g*0.5), floor(b*0.5), a)
end

function DrawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = (rand() - 0.5) * game.shakeIntensity * 2
        sy = (rand() - 0.5) * game.shakeIntensity * 2
    end

    bridge.drawRect(sx, sy, W, H, 5, 5, 12, 255)

    -- Menu
    if game.state == "menu" then
        bridge.drawText("SPACE SHOOTER MP", W/2 - 70, 100, 255, 255, 100, 255)
        
        local options = {"HOST GAME", "JOIN GAME", "SINGLE PLAYER"}
        for i, opt in ipairs(options) do
            local y = 200 + (i-1) * 40
            local col = i == game.menuSelection and 255 or 150
            bridge.drawText(opt, W/2 - 50, y, col, col, col, 255)
            if i == game.menuSelection then
                bridge.drawText(">", W/2 - 70, y, 255, 255, 50, 255)
            end
        end
        
        bridge.drawText("WASD/ARROWS: Move, SPACE: Shoot", W/2 - 100, H - 50, 150, 150, 150, 255)
        return
    end
    
    -- Lobby
    if game.state == "lobby" then
        bridge.drawText("LOBBY", W/2 - 30, 100, 255, 255, 100, 255)
        
        local y = 150
        bridge.drawText("Players:", 50, y, 200, 200, 200, 255)
        y = y + 30
        
        for pid, p in pairs(net.players) do
            local c = playerColors[p.colorIdx]
            bridge.drawText(pid, 70, y, c[1], c[2], c[3], 255)
            y = y + 25
        end
        
        if net.mode == "host" then
            bridge.drawText("Press ENTER to start", W/2 - 70, H - 100, 255, 255, 50, 255)
        else
            bridge.drawText("Waiting for host...", W/2 - 60, H - 100, 150, 150, 150, 255)
        end
        return
    end

    -- Game
    -- Stars
    for _, s in ipairs(stars) do
        local br = s.brightness
        bridge.drawRect(sx + s.x, sy + s.y, s.size, s.size, br, br, floor(br * 1.2), 255)
    end

    -- Pickups
    for _, p in ipairs(pickups) do
        local pulse = 0.6 + sin(p.pulse) * 0.4
        local sz = p.radius * pulse * 2
        if p.type == "health" then
            bridge.drawRect(sx + p.x - sz/2, sy + p.y - 2, sz, 4, 50, 255, 50, 200)
            bridge.drawRect(sx + p.x - 2, sy + p.y - sz/2, 4, sz, 50, 255, 50, 200)
        else
            bridge.drawRect(sx + p.x - sz/2, sy + p.y - sz/2, sz, sz, 50, 150, 255, 200)
        end
    end

    -- Enemies
    for _, e in ipairs(enemies) do
        if e.type == "grunt" then
            bridge.drawRect(sx + e.x - 8, sy + e.y - 8, 16, 16, 255, 60, 30, 255)
        elseif e.type == "tank" then
            bridge.drawRect(sx + e.x - 14, sy + e.y - 14, 28, 28, 200, 50, 20, 255)
        elseif e.type == "fast" then
            bridge.drawRect(sx + e.x - 6, sy + e.y - 6, 12, 12, 50, 180, 255, 255)
        elseif e.type == "shooter" then
            bridge.drawRect(sx + e.x - 10, sy + e.y - 10, 20, 20, 200, 40, 180, 255)
        end

        for _, b in ipairs(e.bullets) do
            if b.life > 0 then
                bridge.drawRect(sx + b.x - 3, sy + b.y - 3, 6, 6, 255, 80, 80, 255)
            end
        end
    end

    -- Players
    for pid, p in pairs(net.players) do
        if p.alive then
            local visible = true
            if p.invincible > 0 then
                visible = floor(p.invincible * 10) % 2 == 0
            end
            if visible then
                local c = playerColors[p.colorIdx]
                drawShip(sx + p.x, sy + p.y, p.angle, c[1], c[2], c[3], 255)

                if p.thrustOn then
                    local fx = p.x - cos(p.angle) * 14
                    local fy = p.y - sin(p.angle) * 14
                    local flicker = 4 + rand() * 6
                    bridge.drawRect(sx + fx - flicker/2, sy + fy - flicker/2, flicker, flicker, 255, 200, 50, 200)
                end
            end
        end

        -- Bullets
        for _, b in ipairs(p.bullets) do
            if b.life > 0 then
                bridge.drawRect(sx + b.x - 2, sy + b.y - 2, 4, 4, 150, 255, 150, 255)
            end
        end
    end

    -- Particles
    for _, p in ipairs(particles) do
        local alpha = floor(255 * (p.life / p.maxLife))
        if alpha > 0 then
            bridge.drawRect(sx + p.x - p.size/2, sy + p.y - p.size/2, p.size, p.size, p.r, p.g, p.b, alpha)
        end
    end

    -- HUD
    if game.state == "playing" then
        bridge.drawText(string.format("WAVE %d", game.wave), W/2 - 30, 8, 255, 255, 100, 255)
        
        local y = 8
        for pid, p in pairs(net.players) do
            local c = playerColors[p.colorIdx]
            bridge.drawText(string.format("%s: %d", pid, p.score), 10, y, c[1], c[2], c[3], 255)
            
            -- Health bar
            local barW = 80
            local barH = 4
            bridge.drawRect(10, y + 16, barW, barH, 40, 40, 40, 200)
            local hpW = floor(barW * (p.health / p.maxHealth))
            bridge.drawRect(10, y + 16, hpW, barH, c[1], c[2], c[3], 255)
            
            y = y + 30
        end

        if #enemies == 0 and game.waveTimer > 0 then
            local flash = floor(game.waveTimer * 4) % 2 == 0
            if flash then
                bridge.drawText(string.format("WAVE %d INCOMING", game.wave + 1), W/2 - 60, H/2 - 10, 255, 255, 100, 255)
            end
        end
    end

    if game.state == "gameover" then
        bridge.drawRect(W/2 - 120, H/2 - 60, 240, 120, 10, 10, 10, 220)
        bridge.drawText("GAME OVER", W/2 - 40, H/2 - 30, 255, 50, 50, 255)
        
        local y = H/2
        for pid, p in pairs(net.players) do
            local c = playerColors[p.colorIdx]
            bridge.drawText(string.format("%s: %d", pid, p.score), W/2 - 40, y, c[1], c[2], c[3], 255)
            y = y + 20
        end
        
        if net.mode == "host" then
            bridge.drawText("PRESS SPACE TO RESTART", W/2 - 80, H/2 + 40, 150, 150, 150, 255)
        end
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
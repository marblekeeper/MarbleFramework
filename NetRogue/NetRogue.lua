-- NetRogue.lua
-- NETROGUE: Networked ASCII Roguelike
-- Uses MarbleNet TCP protocol for authoritative server input
-- Uses ClayMarble (bridge.*) for rendering
--
-- Architecture:
--   SDL Input -> NetRogue.lua -> TCP packet (MarbleNet protocol) -> server_tcp.lua
--   server_tcp.lua -> authoritative state -> TCP packet -> NetRogue.lua -> bridge.draw*
--
-- This script requires LuaSocket and the MarbleNet protocol.lua in package.path

-- ============================================================
-- FRAMEWORK COMPATIBILITY
-- ============================================================
local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, max, min = math.abs, math.max, math.min

-- ============================================================
-- NETWORK LAYER
-- ============================================================
do
    local msys = "C:/msys64/ucrt64"
    package.path = package.path
        .. ";./?.lua"
        .. ";" .. msys .. "/share/lua/5.4/?.lua"
        .. ";" .. msys .. "/share/lua/5.4/?/init.lua"
        .. ";" .. msys .. "/lib/lua/5.4/?.lua"
    package.cpath = package.cpath
        .. ";" .. msys .. "/lib/lua/5.4/?.dll"
        .. ";" .. msys .. "/lib/lua/5.4/?/core.dll"
end

local socket = require("socket")
local Protocol = require("protocol")

local NET = {
    client = nil,
    connected = false,
    host = "127.0.0.1",
    port = 12345,
    player_id = nil,
    tick = 0,
    recv_buffer = "",
    connect_timer = 0,
    connect_attempts = 0,
    max_connect_attempts = 5,
    status_msg = "Connecting...",
    map_seed = nil,
}

local function net_connect()
    NET.status_msg = "Connecting to " .. NET.host .. ":" .. NET.port .. "..."
    NET.client = socket.tcp()
    NET.client:settimeout(2)
    local ok, err = NET.client:connect(NET.host, NET.port)
    if ok then
        NET.connected = true
        NET.client:settimeout(0)
        NET.status_msg = "Connected! Waiting for auth..."
        print("[NetRogue] Connected to server")
        return true
    else
        NET.connect_attempts = NET.connect_attempts + 1
        NET.status_msg = "Connection failed: " .. tostring(err) ..
            " (attempt " .. NET.connect_attempts .. "/" .. NET.max_connect_attempts .. ")"
        print("[NetRogue] " .. NET.status_msg)
        NET.client:close()
        NET.client = nil
        return false
    end
end

local function net_send(packet)
    if NET.connected and NET.client then
        local ok, err = NET.client:send(packet)
        if not ok then
            print("[NetRogue] Send error: " .. tostring(err))
            if err == "closed" then
                NET.connected = false
                NET.status_msg = "Disconnected from server"
            end
        end
    end
end

local function net_send_move(x, y)
    net_send(Protocol.make_move_packet(x, y))
end

local function net_send_action(action)
    net_send(Protocol.make_action_packet(action))
end

-- ============================================================
-- GAME STATE
-- ============================================================
local TS = 24
local MW, MH = 30, 22

local C = {
    void      = {8, 6, 12},
    wall      = {60, 55, 75},
    wallHi    = {80, 72, 95},
    floor     = {25, 22, 35},
    floorLit  = {40, 35, 55},
    player    = {60, 200, 255},
    other     = {255, 180, 60},
    goblin    = {60, 180, 50},
    goblinHurt= {180, 220, 60},
    goblinDead= {40, 40, 40},
    fog       = {6, 4, 10},
    hud_bg    = {12, 10, 18},
    hud_border= {60, 50, 80},
    net_ok    = {80, 220, 120},
    net_err   = {255, 80, 80},
    net_wait  = {255, 200, 80},
    title_bg  = {10, 8, 16},
    msg       = {180, 170, 200},
    combat_hit= {255, 100, 80},
    combat_miss={120, 110, 140},
    combat_crit={255, 220, 60},
    hp_bar_bg = {40, 10, 15},
    hp_bar    = {50, 200, 80},
    hp_bar_low= {255, 60, 60},
    xp        = {180, 120, 255},
    levelup   = {255, 255, 100},
}

local player = {
    x = 0, y = 0,
    state = "standing",
    connected = false,
    id = nil,
    hp = 20, maxHp = 20,
    attack = 50,
    defense = 30,
    level = 1,
    kills = 0,
    xp = 0,
    xpNext = 20,
    dead = false,
}

local others = {}
local goblins = {}    -- keyed by goblin id
local map = {}
local rooms = {}

local game = {
    state = "connecting",
    pulseTimer = 0,
    shakeTimer = 0,
    shakeIntensity = 0,
    keyWasDown = {},
    turn = 0,
    messages = {},
    maxMessages = 14,
    particles = {},
}

-- ============================================================
-- PARTICLES
-- ============================================================
local function spawnParticles(x, y, count, r, g, b, speed, life)
    for i = 1, count do
        local a = rand() * math.pi * 2
        local s = rand() * speed + speed * 0.2
        game.particles[#game.particles+1] = {
            x = x, y = y,
            vx = cos(a) * s, vy = sin(a) * s,
            life = life * (0.4 + rand() * 0.6),
            maxLife = life,
            r = r, g = g, b = b,
            size = rand() < 0.3 and 3 or 2,
        }
    end
end

local function screenShake(intensity, duration)
    game.shakeTimer = duration
    game.shakeIntensity = intensity
end

-- ============================================================
-- MAP GENERATION (seeded from server)
-- ============================================================
local function carveRoom(rx, ry, rw, rh)
    for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
            if x >= 1 and x <= MW and y >= 1 and y <= MH then
                map[y][x] = 0
            end
        end
    end
    return {x = rx, y = ry, w = rw, h = rh,
            cx = floor(rx + rw/2), cy = floor(ry + rh/2)}
end

local function carveCorridor(x1, y1, x2, y2)
    local x, y = x1, y1
    while x ~= x2 do
        if x >= 1 and x <= MW and y >= 1 and y <= MH then map[y][x] = 0 end
        x = x + (x2 > x and 1 or -1)
    end
    while y ~= y2 do
        if x >= 1 and x <= MW and y >= 1 and y <= MH then map[y][x] = 0 end
        y = y + (y2 > y and 1 or -1)
    end
end

local function generateMap(seed)
    math.randomseed(seed)
    map = {}
    for y = 1, MH do
        map[y] = {}
        for x = 1, MW do map[y][x] = 1 end
    end

    rooms = {}
    local attempts = 0
    local numRooms = rand(7, 12)
    while #rooms < numRooms and attempts < 200 do
        attempts = attempts + 1
        local rw = rand(4, 8)
        local rh = rand(3, 6)
        local rx = rand(2, MW - rw - 1)
        local ry = rand(2, MH - rh - 1)
        local ok = true
        for _, r in ipairs(rooms) do
            if rx < r.x + r.w + 1 and rx + rw + 1 > r.x and
               ry < r.y + r.h + 1 and ry + rh + 1 > r.y then
                ok = false; break
            end
        end
        if ok then
            local room = carveRoom(rx, ry, rw, rh)
            if #rooms > 0 then
                local prev = rooms[#rooms]
                if rand() < 0.5 then
                    carveCorridor(prev.cx, prev.cy, room.cx, prev.cy)
                    carveCorridor(room.cx, prev.cy, room.cx, room.cy)
                else
                    carveCorridor(prev.cx, prev.cy, prev.cx, room.cy)
                    carveCorridor(prev.cx, room.cy, room.cx, room.cy)
                end
            end
            rooms[#rooms+1] = room
        end
    end
    for i = 1, floor(#rooms / 3) do
        local a = rooms[rand(1, #rooms)]
        local b = rooms[rand(1, #rooms)]
        if a ~= b then carveCorridor(a.cx, a.cy, b.cx, b.cy) end
    end

    -- Restore non-deterministic RNG for particles etc
    math.randomseed(os.time() + (player.id or 0))
    print(string.format("[NetRogue] Map generated from seed %d: %d rooms", seed, #rooms))
end

local function tileAt(x, y)
    if x < 1 or x > MW or y < 1 or y > MH then return 1 end
    return map[y][x]
end

-- ============================================================
-- FOV
-- ============================================================
local seen = {}

local function computeFOV()
    for k, v in pairs(seen) do
        if v == 2 then seen[k] = 1 end
    end
    local radius = 7
    for a = 0, 359, 2 do
        local rad = a * math.pi / 180
        local dx = cos(rad)
        local dy = sin(rad)
        local fx, fy = player.x + 0.5, player.y + 0.5
        for d = 0, radius do
            local tx, ty = floor(fx), floor(fy)
            if tx < 1 or tx > MW or ty < 1 or ty > MH then break end
            seen[ty * 1000 + tx] = 2
            if tileAt(tx, ty) == 1 then break end
            fx = fx + dx * 0.5
            fy = fy + dy * 0.5
        end
    end
end

local function isVisible(x, y)
    return (seen[y * 1000 + x] or 0) == 2
end

local function isSeen(x, y)
    return (seen[y * 1000 + x] or 0) >= 1
end

-- ============================================================
-- MESSAGE LOG
-- ============================================================
local function addMessage(text, r, g, b)
    table.insert(game.messages, 1, {
        text = text,
        r = r or C.msg[1], g = g or C.msg[2], b = b or C.msg[3],
        age = 0
    })
    if #game.messages > game.maxMessages then
        table.remove(game.messages)
    end
end

-- ============================================================
-- CLIENT-SIDE GOBLIN LOOKUP
-- ============================================================
local function goblinAt(x, y)
    for _, g in pairs(goblins) do
        if g.alive and g.x == x and g.y == y then return g end
    end
    return nil
end

-- ============================================================
-- NETWORK MESSAGE PROCESSING
-- ============================================================
local function process_server_messages()
    if not NET.connected or not NET.client then return end

    while true do
        local data, err = NET.client:receive("*l")
        if data then
            -- AUTH:OK with map seed
            if data:match("^" .. Protocol.RESPONSE.AUTH_OK) then
                player.id = tonumber(data:match("ID:(%d+)"))
                NET.tick = tonumber(data:match("TICK:(%d+)")) or 0
                NET.map_seed = tonumber(data:match("SEED:(%d+)")) or 42
                NET.player_id = player.id
                player.connected = true
                player.dead = false
                game.state = "playing"
                NET.status_msg = "Player #" .. player.id

                -- Generate map from server seed (deterministic!)
                generateMap(NET.map_seed)

                -- Spawn in room 1
                if #rooms > 0 then
                    player.x = rooms[1].cx
                    player.y = rooms[1].cy
                    net_send_move(player.x, player.y)
                end

                addMessage("Connected as Player #" .. player.id, C.net_ok[1], C.net_ok[2], C.net_ok[3])
                addMessage("WASD: move (bump goblins to fight!)", 160, 150, 180)
                addMessage("Watch out — goblins hit back.", 200, 120, 100)
                computeFOV()

            -- INTENT_ACK
            elseif data:match("^" .. Protocol.RESPONSE.INTENT_ACK) then
                -- acknowledged

            -- POS (our confirmed position)
            elseif data:match("^" .. Protocol.RESPONSE.POS) then
                local x, y, tick = data:match("^POS:([%-]?%d+),([%-]?%d+),TICK:(%d+)$")
                if x and y then
                    player.x = tonumber(x)
                    player.y = tonumber(y)
                    if tick then NET.tick = tonumber(tick) end
                    computeFOV()
                else
                    x, y = data:match("^POS:([%-]?%d+),([%-]?%d+)$")
                    if x and y then
                        player.x = tonumber(x)
                        player.y = tonumber(y)
                        computeFOV()
                    end
                end

            -- STATS (our stats from server)
            elseif data:match("^STATS:") then
                local hp, maxHp, atk, lvl, kills, xp, xpNext =
                    data:match("^STATS:(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
                if hp then
                    player.hp = tonumber(hp)
                    player.maxHp = tonumber(maxHp)
                    player.attack = tonumber(atk)
                    player.level = tonumber(lvl)
                    player.kills = tonumber(kills)
                    player.xp = tonumber(xp)
                    player.xpNext = tonumber(xpNext)
                end

            -- COMBAT (broadcast message)
            elseif data:match("^COMBAT:") then
                local msg = data:match("^COMBAT:(.+)$")
                if msg then
                    local color = C.combat_miss
                    if msg:match("CRITS") then
                        color = C.combat_crit
                        screenShake(5, 0.2)
                    elseif msg:match("hits") then
                        color = C.combat_hit
                        screenShake(3, 0.1)
                    end
                    addMessage(msg, color[1], color[2], color[3])
                end

            -- GOBLIN_SPAWN
            elseif data:match("^GOBLIN_SPAWN:") then
                local id, x, y, hp, maxHp = data:match("^GOBLIN_SPAWN:(%d+),(%d+),(%d+),(%d+),(%d+)$")
                if id then
                    id = tonumber(id)
                    goblins[id] = {
                        id = id,
                        x = tonumber(x), y = tonumber(y),
                        hp = tonumber(hp), maxHp = tonumber(maxHp),
                        alive = true,
                    }
                    addMessage("A goblin appears!", C.goblin[1], C.goblin[2], C.goblin[3])
                    -- Spawn particles at goblin location
                    spawnParticles(tonumber(x) * TS + TS/2, tonumber(y) * TS + TS/2,
                        8, C.goblin[1], C.goblin[2], C.goblin[3], 40, 0.4)
                end

            -- GOBLIN_MOVE
            elseif data:match("^GOBLIN_MOVE:") then
                local id, x, y = data:match("^GOBLIN_MOVE:(%d+),([%-]?%d+),([%-]?%d+)$")
                if id then
                    id = tonumber(id)
                    if goblins[id] then
                        goblins[id].x = tonumber(x)
                        goblins[id].y = tonumber(y)
                    end
                end

            -- GOBLIN_HP
            elseif data:match("^GOBLIN_HP:") then
                local id, hp, maxHp = data:match("^GOBLIN_HP:(%d+),([%-]?%d+),(%d+)$")
                if id then
                    id = tonumber(id)
                    if goblins[id] then
                        goblins[id].hp = tonumber(hp)
                        goblins[id].maxHp = tonumber(maxHp)
                    end
                end

            -- GOBLIN_DEATH
            elseif data:match("^GOBLIN_DEATH:") then
                local id, x, y = data:match("^GOBLIN_DEATH:(%d+),(%d+),(%d+)$")
                if id then
                    id = tonumber(id)
                    if goblins[id] then
                        goblins[id].alive = false
                        addMessage("Goblin #" .. id .. " slain!", C.goblinHurt[1], C.goblinHurt[2], C.goblinHurt[3])
                        spawnParticles(tonumber(x) * TS + TS/2, tonumber(y) * TS + TS/2,
                            15, C.goblin[1], 220, 60, 80, 0.5)
                        screenShake(4, 0.15)
                    end
                end

            -- PLAYER_HP (other player's HP changed)
            elseif data:match("^PLAYER_HP:") then
                -- We get our own HP via STATS, this is for displaying others
                local id, hp, maxHp = data:match("^PLAYER_HP:(%d+),([%-]?%d+),(%d+)$")
                if id then
                    id = tonumber(id)
                    if id == player.id then
                        player.hp = tonumber(hp)
                        if player.hp <= 0 then
                            player.dead = true
                            screenShake(8, 0.4)
                        end
                    end
                end

            -- PLAYER_DEATH
            elseif data:match("^PLAYER_DEATH:") then
                local id = tonumber(data:match("^PLAYER_DEATH:(%d+)$"))
                if id == player.id then
                    player.dead = true
                    addMessage("You have been slain!", 255, 50, 50)
                    screenShake(8, 0.4)
                    spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2,
                        30, 200, 40, 50, 120, 0.8)
                else
                    addMessage("Player #" .. id .. " has fallen!", 200, 100, 100)
                end

            -- PLAYER_RESPAWN (us or others)
            elseif data:match("^PLAYER_RESPAWN:") then
                local id, x, y = data:match("^PLAYER_RESPAWN:(%d+),([%-]?%d+),([%-]?%d+)")
                if id then
                    id = tonumber(id)
                    if id == player.id then
                        player.dead = false
                        player.x = tonumber(x)
                        player.y = tonumber(y)
                        computeFOV()
                        addMessage("You have respawned!", C.net_ok[1], C.net_ok[2], C.net_ok[3])
                        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2,
                            15, 60, 200, 255, 60, 0.5)
                    else
                        -- Other player respawned — update their position
                        if not others[id] then
                            others[id] = {x = 0, y = 0, state = "standing", id = id}
                        end
                        others[id].x = tonumber(x)
                        others[id].y = tonumber(y)
                        addMessage("Player #" .. id .. " respawned!", C.other[1], C.other[2], C.other[3])
                    end
                end

            -- PLAYER_LEVELUP
            elseif data:match("^PLAYER_LEVELUP:") then
                local id, lvl, atk, hp, maxHp =
                    data:match("^PLAYER_LEVELUP:(%d+),(%d+),(%d+),(%d+),(%d+)$")
                if id then
                    id = tonumber(id)
                    if id == player.id then
                        addMessage("LEVEL UP! Lv." .. lvl .. " ATK:" .. atk .. " HP:" .. hp,
                            C.levelup[1], C.levelup[2], C.levelup[3])
                        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2,
                            20, 60, 200, 255, 100, 0.6)
                        screenShake(3, 0.2)
                    else
                        addMessage("Player #" .. id .. " leveled up!", C.xp[1], C.xp[2], C.xp[3])
                    end
                end

            -- PLAYER_ACTION
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_ACTION) then
                local action, tick = data:match("^PLAYER_ACTION:(%w+),TICK:(%d+)$")
                if action then
                    player.state = action:lower()
                    if tick then NET.tick = tonumber(tick) end
                end

            -- PLAYER_JOIN
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_JOIN) then
                local id = tonumber(data:match("^PLAYER_JOIN:(%d+)"))
                if id and id ~= player.id then
                    others[id] = {x = 0, y = 0, state = "standing", id = id}
                    addMessage("Player #" .. id .. " enters!", C.other[1], C.other[2], C.other[3])
                end

            -- PLAYER_MOVE
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_MOVE) then
                local id, x, y = data:match("^PLAYER_MOVE:(%d+),([%-]?%d+),([%-]?%d+)")
                id = tonumber(id)
                if id and id ~= player.id then
                    if not others[id] then
                        others[id] = {x = 0, y = 0, state = "standing", id = id}
                    end
                    others[id].x = tonumber(x)
                    others[id].y = tonumber(y)
                end

            -- PLAYER_LEAVE
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_LEAVE) then
                local id = tonumber(data:match("^PLAYER_LEAVE:(%d+)"))
                if id then
                    others[id] = nil
                    addMessage("Player #" .. id .. " left", 150, 100, 100)
                end

            -- ERROR
            elseif data:match("^" .. Protocol.RESPONSE.ERROR) then
                local errMsg = data:match("^ERROR:(.+)$") or data
                addMessage("Server: " .. errMsg, C.net_err[1], C.net_err[2], C.net_err[3])

            else
                print("[NetRogue] Unknown: " .. data)
            end
        elseif err == "timeout" then
            break
        elseif err == "closed" then
            NET.connected = false
            game.state = "disconnected"
            NET.status_msg = "Server disconnected"
            addMessage("Connection lost!", C.net_err[1], C.net_err[2], C.net_err[3])
            break
        else
            break
        end
    end
end

-- ============================================================
-- INPUT
-- ============================================================
local function keyPressed(key)
    if not bridge.getKeyState then return false end
    local down = bridge.getKeyState(key) == 1
    local was = game.keyWasDown[key] or false
    game.keyWasDown[key] = down
    return down and not was
end

-- ============================================================
-- PLAYER MOVEMENT (bump-to-attack is server-side)
-- ============================================================
local function tryMove(dx, dy)
    if game.state ~= "playing" or player.dead then return end

    local nx, ny = player.x + dx, player.y + dy

    -- Client-side wall check
    if tileAt(nx, ny) == 1 then return end

    -- Check if goblin is there (bump attack — server handles combat)
    local g = goblinAt(nx, ny)
    if g then
        -- Send the move intent; server will resolve it as bump combat
        net_send_move(nx, ny)
        game.turn = game.turn + 1
        return
    end

    -- Normal move (optimistic prediction)
    player.x = nx
    player.y = ny
    net_send_move(nx, ny)
    computeFOV()
    game.turn = game.turn + 1
end

-- ============================================================
-- DRAWING
-- ============================================================
local function drawTile(sx, sy, camOX, camOY, tx, ty, mapAreaH)
    local px = camOX + tx * TS + sx
    local py = camOY + ty * TS + sy
    if px < -TS or px > W + TS or py < -TS or py > mapAreaH + TS then return end

    local vis = isVisible(tx, ty)
    local tile_seen = isSeen(tx, ty)
    local tile = tileAt(tx, ty)

    if not tile_seen then
        bridge.drawRect(px, py, TS, TS, C.void[1], C.void[2], C.void[3], 255)
        return
    end

    local dim = vis and 1.0 or 0.3
    if tile == 1 then
        local cr, cg, cb = C.wall[1], C.wall[2], C.wall[3]
        if (tx + ty) % 3 == 0 then cr, cg, cb = C.wallHi[1], C.wallHi[2], C.wallHi[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if vis and ty > 1 and tileAt(tx, ty-1) == 0 then
            bridge.drawRect(px, py, TS, 2, floor(80*dim), floor(70*dim), floor(100*dim), 255)
        end
    else
        local cr, cg, cb = C.floor[1], C.floor[2], C.floor[3]
        if vis then cr, cg, cb = C.floorLit[1], C.floorLit[2], C.floorLit[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if (tx * 7 + ty * 13) % 11 == 0 then
            bridge.drawRect(px + 4, py + 4, 2, 2,
                floor(cr*dim*0.5), floor(cg*dim*0.5), floor(cb*dim*0.5), 255)
        end
    end
end

local function drawEntity(sx, sy, camOX, camOY, ex, ey, color, hasVisor)
    local px = camOX + ex * TS + sx
    local py = camOY + ey * TS + sy
    bridge.drawRect(px + 2, py + 2, TS - 4, TS - 4, color[1], color[2], color[3], 255)
    bridge.drawRect(px + 5, py + 5, TS - 10, TS - 10,
        min(255, color[1] + 40), min(255, color[2] + 40), min(255, color[3] + 40), 255)
    if hasVisor then
        bridge.drawRect(px + 7, py + 6, 10, 5, 20, 50, 80, 255)
        bridge.drawRect(px + 8, py + 7, 8, 3, 40, 130, 200, 255)
    end
end

local function drawHPBar(sx, sy, camOX, camOY, ex, ey, hp, maxHp)
    if hp >= maxHp then return end
    local px = camOX + ex * TS + sx
    local py = camOY + ey * TS + sy
    local barW = TS - 4
    local hpFrac = max(0, hp / maxHp)
    bridge.drawRect(px + 2, py - 4, barW, 3, C.hp_bar_bg[1], C.hp_bar_bg[2], C.hp_bar_bg[3], 200)
    local barColor = hpFrac > 0.3 and C.hp_bar or C.hp_bar_low
    bridge.drawRect(px + 2, py - 4, floor(barW * hpFrac), 3,
        barColor[1], barColor[2], barColor[3], 255)
end

local function drawGoblin(sx, sy, camOX, camOY, g)
    local px = camOX + g.x * TS + sx
    local py = camOY + g.y * TS + sy

    -- Body — green with pointy ears
    local pulse = sin(game.pulseTimer * 4 + g.id) * 10
    bridge.drawRect(px + 3, py + 4, TS - 6, TS - 6,
        C.goblin[1] + floor(pulse), C.goblin[2], C.goblin[3], 255)
    -- Inner
    bridge.drawRect(px + 6, py + 7, TS - 12, TS - 10,
        min(255, C.goblin[1] + 30), min(255, C.goblin[2] + 30), C.goblin[3] + 20, 255)
    -- Eyes (angry red dots)
    bridge.drawRect(px + 7, py + 8, 3, 3, 255, 60, 40, 255)
    bridge.drawRect(px + 14, py + 8, 3, 3, 255, 60, 40, 255)
    -- Ears
    bridge.drawRect(px + 2, py + 2, 3, 4, C.goblin[1], C.goblin[2], C.goblin[3], 255)
    bridge.drawRect(px + TS - 5, py + 2, 3, 4, C.goblin[1], C.goblin[2], C.goblin[3], 255)

    -- HP bar
    drawHPBar(sx, sy, camOX, camOY, g.x, g.y, g.hp, g.maxHp)
end

local function DrawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = floor((rand() - 0.5) * game.shakeIntensity * 2)
        sy = floor((rand() - 0.5) * game.shakeIntensity * 2)
    end

    local mapAreaH = floor(H * 0.68)
    bridge.drawRect(0, 0, W, H, C.void[1], C.void[2], C.void[3], 255)

    local camOX = floor(W/2 - player.x * TS - TS/2)
    local camOY = floor(mapAreaH * 0.45 - player.y * TS - TS/2)

    -- Tiles
    for ty = 1, MH do
        for tx = 1, MW do
            drawTile(sx, sy, camOX, camOY, tx, ty, mapAreaH)
        end
    end

    -- Goblins
    for _, g in pairs(goblins) do
        if g.alive and isVisible(g.x, g.y) then
            drawGoblin(sx, sy, camOX, camOY, g)
        end
    end

    -- Other players
    for id, other in pairs(others) do
        if isVisible(other.x, other.y) then
            drawEntity(sx, sy, camOX, camOY, other.x, other.y, C.other, false)
            local opx = camOX + other.x * TS + sx
            local opy = camOY + other.y * TS + sy
            bridge.drawText("#" .. id, opx + 2, opy - 10, C.other[1], C.other[2], C.other[3], 200)
        end
    end

    -- Local player
    if not player.dead then
        drawEntity(sx, sy, camOX, camOY, player.x, player.y, C.player, true)
        drawHPBar(sx, sy, camOX, camOY, player.x, player.y, player.hp, player.maxHp)
    end

    -- Particles
    for _, p in ipairs(game.particles) do
        local alpha = floor(255 * (p.life / p.maxLife))
        if alpha > 0 then
            local ppx = camOX + p.x + sx
            local ppy = camOY + p.y + sy
            if ppx > -10 and ppx < W + 10 and ppy > -10 and ppy < mapAreaH + 10 then
                bridge.drawRect(ppx - p.size/2, ppy - p.size/2, p.size, p.size, p.r, p.g, p.b, alpha)
            end
        end
    end

    -- ========== HUD ==========
    local hudY = mapAreaH + 2
    local hudH = H - hudY
    bridge.drawRect(0, hudY, W, hudH, C.hud_bg[1], C.hud_bg[2], C.hud_bg[3], 255)
    bridge.drawRect(0, hudY, W, 2, C.hud_border[1], C.hud_border[2], C.hud_border[3], 255)

    local col1 = 10
    local ly = hudY + 6

    -- Row 1: Title + Net
    bridge.drawText("NETROGUE", col1, ly, 60, 200, 255, 255)
    local netColor = NET.connected and C.net_ok or C.net_err
    bridge.drawRect(col1 + 70, ly + 2, 6, 6, netColor[1], netColor[2], netColor[3], 255)
    bridge.drawText("P#" .. (player.id or "?") .. " Tick:" .. NET.tick,
        col1 + 80, ly, netColor[1], netColor[2], netColor[3], 255)
    ly = ly + 13

    -- Row 2: HP bar
    bridge.drawText("HP:", col1, ly, 200, 200, 200, 255)
    local barX = col1 + 28
    local barW = 90
    local barH = 10
    bridge.drawRect(barX, ly, barW, barH, C.hp_bar_bg[1], C.hp_bar_bg[2], C.hp_bar_bg[3], 255)
    local hpFrac = max(0, player.hp / player.maxHp)
    local hpColor = hpFrac > 0.3 and C.hp_bar or C.hp_bar_low
    bridge.drawRect(barX, ly, floor(barW * hpFrac), barH, hpColor[1], hpColor[2], hpColor[3], 255)
    bridge.drawText(player.hp .. "/" .. player.maxHp, barX + barW + 4, ly, 200, 200, 200, 255)
    ly = ly + 13

    -- Row 3: Stats
    bridge.drawText("ATK:" .. player.attack .. "  LVL:" .. player.level ..
        "  Kills:" .. player.kills, col1, ly, 180, 170, 200, 255)

    -- XP bar
    local xpX = col1 + 220
    bridge.drawText("XP:", xpX, ly, C.xp[1], C.xp[2], C.xp[3], 255)
    bridge.drawRect(xpX + 24, ly, 60, barH, 20, 15, 30, 255)
    local xpFrac = player.xp / max(1, player.xpNext)
    bridge.drawRect(xpX + 24, ly, floor(60 * xpFrac), barH, C.xp[1], C.xp[2], C.xp[3], 255)
    bridge.drawText(player.xp .. "/" .. player.xpNext, xpX + 88, ly, C.xp[1], C.xp[2], C.xp[3], 255)
    ly = ly + 13

    -- Row 4: Controls
    bridge.drawText("WASD:Move/Attack  P:Pray  I:Sit  O:Stand", col1, ly, 110, 100, 130, 255)

    -- Message log (right side)
    local msgX = W/2 + 10
    local msgY = hudY + 6
    bridge.drawText("-- Combat Log --", msgX, msgY, 80, 70, 100, 255)
    for i, msg in ipairs(game.messages) do
        local alpha = max(60, 255 - i * 18)
        bridge.drawText(msg.text, msgX, msgY + i * 12, msg.r, msg.g, msg.b, alpha)
        if msgY + i * 12 > H - 5 then break end
    end

    -- Death overlay
    if player.dead then
        bridge.drawRect(W/4, H/3, W/2, H/5, 25, 5, 8, 230)
        bridge.drawRect(W/4, H/3, W/2, 2, 255, 40, 50, 255)
        bridge.drawText("YOU HAVE FALLEN", W/4 + 40, H/3 + 15, 255, 50, 60, 255)
        bridge.drawText("Kills: " .. player.kills .. "  Level: " .. player.level,
            W/4 + 30, H/3 + 35, 200, 200, 200, 255)
        bridge.drawText("PRESS SPACE TO RESPAWN", W/4 + 20, H/3 + 60, 180, 180, 200, 255)
    end
end

local function DrawConnecting()
    bridge.drawRect(0, 0, W, H, C.title_bg[1], C.title_bg[2], C.title_bg[3], 255)
    bridge.drawText("N E T R O G U E", W/2 - 65, H/4, 60, 200, 255, 255)
    bridge.drawText("MarbleNet + ClayMarble", W/2 - 80, H/4 + 20, 120, 110, 140, 255)

    local statusColor = C.net_wait
    if NET.connect_attempts >= NET.max_connect_attempts then statusColor = C.net_err end
    bridge.drawText(NET.status_msg, W/2 - 120, H/2, statusColor[1], statusColor[2], statusColor[3], 255)

    local dots = string.rep(".", floor(game.pulseTimer * 3) % 4)
    bridge.drawText("Connecting" .. dots, W/2 - 40, H/2 + 25, 140, 130, 160, 255)

    if NET.connect_attempts >= NET.max_connect_attempts then
        bridge.drawText("Could not reach server.", W/2 - 80, H/2 + 50, C.net_err[1], C.net_err[2], C.net_err[3], 255)
        bridge.drawText("Run: build.bat netrogue_server", W/2 - 100, H/2 + 70, 160, 150, 180, 255)
        bridge.drawText("Press SPACE to retry", W/2 - 70, H/2 + 100, 180, 180, 200, 255)
    end
end

local function DrawDisconnected()
    bridge.drawRect(0, 0, W, H, C.title_bg[1], C.title_bg[2], C.title_bg[3], 255)
    bridge.drawText("DISCONNECTED", W/2 - 50, H/2 - 10, C.net_err[1], C.net_err[2], C.net_err[3], 255)
    bridge.drawText(NET.status_msg, W/2 - 100, H/2 + 15, 160, 150, 180, 255)
    bridge.drawText("Press SPACE to reconnect", W/2 - 85, H/2 + 45, 180, 180, 200, 255)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
-- Generate a fallback map (will be replaced when server sends seed)
math.randomseed(os.time())
generateMap(42)
net_connect()

-- ============================================================
-- MAIN CALLBACKS
-- ============================================================
function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    local dt = 0.016

    game.pulseTimer = game.pulseTimer + dt
    if game.shakeTimer > 0 then game.shakeTimer = game.shakeTimer - dt end

    -- Update particles
    for i = #game.particles, 1, -1 do
        local p = game.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        if p.life <= 0 then table.remove(game.particles, i) end
    end

    for _, msg in ipairs(game.messages) do msg.age = msg.age + dt end

    -- === CONNECTING ===
    if game.state == "connecting" then
        NET.connect_timer = NET.connect_timer + dt
        if not NET.connected and NET.connect_timer > 2.0 then
            NET.connect_timer = 0
            if NET.connect_attempts < NET.max_connect_attempts then net_connect() end
        end
        if NET.connect_attempts >= NET.max_connect_attempts then
            if keyPressed("space") then
                NET.connect_attempts = 0
                NET.connect_timer = 0
                net_connect()
            end
        end
        if NET.connected then process_server_messages() end
        return
    end

    -- === DISCONNECTED ===
    if game.state == "disconnected" then
        if keyPressed("space") then
            NET.connect_attempts = 0
            NET.connect_timer = 0
            game.state = "connecting"
            net_connect()
        end
        return
    end

    -- === PLAYING ===
    if game.state == "playing" then
        process_server_messages()

        -- Dead respawn
        if player.dead then
            if keyPressed("space") then
                -- Send RESPAWN command to server (no reconnect needed)
                net_send("RESPAWN:\n")
                addMessage("Requesting respawn...", C.net_wait[1], C.net_wait[2], C.net_wait[3])
            end
            return
        end

        -- Movement
        if keyPressed("W") or keyPressed("w") or keyPressed("up") then tryMove(0, -1)
        elseif keyPressed("S") or keyPressed("s") or keyPressed("down") then tryMove(0, 1)
        elseif keyPressed("A") or keyPressed("a") or keyPressed("left") then tryMove(-1, 0)
        elseif keyPressed("D") or keyPressed("d") or keyPressed("right") then tryMove(1, 0)
        end

        -- Actions
        if keyPressed("P") or keyPressed("p") then
            net_send_action(Protocol.CMD.PRAY)
            player.state = "pray"
        elseif keyPressed("I") or keyPressed("i") then
            net_send_action(Protocol.CMD.SIT)
            player.state = "sit"
        elseif keyPressed("O") or keyPressed("o") then
            net_send_action(Protocol.CMD.STAND)
            player.state = "standing"
        elseif keyPressed("M") or keyPressed("m") then
            net_send_action(Protocol.CMD.MEDITATE)
            player.state = "meditate"
        end
    end
end

function DrawUI()
    if game.state == "connecting" then DrawConnecting()
    elseif game.state == "disconnected" then DrawDisconnected()
    elseif game.state == "playing" then DrawGame()
    end
end
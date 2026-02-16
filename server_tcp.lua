-- server_tcp.lua
-- Tick-based TCP server with command buffer architecture
-- NOW WITH: Goblins, d100 combat, leveling, respawn

local socket = require("socket")
local Protocol = require("protocol")

-- Server configuration
local HOST = "127.0.0.1"
local PORT = 12345
local TICK_RATE = 0.6 -- seconds per tick
local MAX_INTENTS_PER_TICK = 5

-- Shared map seed — clients use this to generate identical maps
local MAP_SEED = 42
local MW, MH = 30, 22

-- Create TCP socket
local server = assert(socket.bind(HOST, PORT))
server:settimeout(0) -- Non-blocking mode

print("=== NETROGUE SERVER ===")
print(string.format("Listening on %s:%d", HOST, PORT))
print(string.format("Tick Rate: %.2f seconds (%.1f ticks/sec)", TICK_RATE, 1/TICK_RATE))
print(string.format("Map Seed: %d (%dx%d)", MAP_SEED, MW, MH))
print("Waiting for clients...\n")

-- ============================================================
-- MAP GENERATION (Server-authoritative)
-- Same algorithm as client, seeded for determinism
-- ============================================================
math.randomseed(MAP_SEED)
local map = {}
local rooms = {}

for y = 1, MH do
    map[y] = {}
    for x = 1, MW do
        map[y][x] = 1
    end
end

local function carveRoom(rx, ry, rw, rh)
    for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
            if x >= 1 and x <= MW and y >= 1 and y <= MH then
                map[y][x] = 0
            end
        end
    end
    return {x = rx, y = ry, w = rw, h = rh,
            cx = math.floor(rx + rw/2), cy = math.floor(ry + rh/2)}
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

local function tileAt(x, y)
    if x < 1 or x > MW or y < 1 or y > MH then return 1 end
    return map[y][x]
end

-- Generate rooms
local attempts = 0
local numRooms = math.random(7, 12)
while #rooms < numRooms and attempts < 200 do
    attempts = attempts + 1
    local rw = math.random(4, 8)
    local rh = math.random(3, 6)
    local rx = math.random(2, MW - rw - 1)
    local ry = math.random(2, MH - rh - 1)
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
            if math.random() < 0.5 then
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
-- Extra connections
for i = 1, math.floor(#rooms / 3) do
    local a = rooms[math.random(1, #rooms)]
    local b = rooms[math.random(1, #rooms)]
    if a ~= b then carveCorridor(a.cx, a.cy, b.cx, b.cy) end
end

-- Re-seed RNG so runtime combat rolls aren't deterministic
math.randomseed(os.time())

print(string.format("Map generated: %d rooms", #rooms))

-- ============================================================
-- GOBLINS (Server-authoritative NPCs)
-- ============================================================
local NUM_GOBLINS = 1
local GOBLIN_RESPAWN_TICKS = 6

local goblins = {}

local function spawnGoblin(id)
    -- Pick a random room (not room 1, that's player spawn)
    local roomIdx = math.random(2, #rooms)
    local room = rooms[roomIdx]
    local gx = math.random(room.x, room.x + room.w - 1)
    local gy = math.random(room.y, room.y + room.h - 1)
    
    goblins[id] = {
        id = id,
        x = gx, y = gy,
        hp = 12, maxHp = 12,
        attack = 15,    -- d100 roll-under to hit
        defense = 25,   -- d100 roll-under to dodge
        dmgMin = 1, dmgMax = 4,
        alive = true,
        deadTicks = 0,  -- counts up when dead, respawn at GOBLIN_RESPAWN_TICKS
        homeRoom = roomIdx,
    }
    print(string.format("  [Goblin #%d] Spawned at (%d,%d) in room %d", id, gx, gy, roomIdx))
end

for i = 1, NUM_GOBLINS do
    spawnGoblin(i)
end

-- ============================================================
-- CLIENT DATA
-- ============================================================
local clients = {}
local client_positions = {}
local client_states = {}
local client_stats = {}     -- HP, attack skill, kills, level
local command_buffers = {}
local intent_counts = {}

-- Tick tracking
local tick_number = 0
local tick_accumulator = 0.0
local last_frame_time = socket.gettime()

-- ============================================================
-- COMBAT SYSTEM (d100 roll-under)
-- ============================================================
local function d100()
    return math.random(1, 100)
end

local function resolveCombat(atk_name, def_name, atk_skill, def_dodge, dmgMin, dmgMax)
    local roll = d100()
    local hit = roll <= atk_skill
    
    if not hit then
        return {
            hit = false,
            roll = roll,
            vs = atk_skill,
            msg = string.format("%s misses %s (d100=%d vs %d)", atk_name, def_name, roll, atk_skill)
        }
    end
    
    -- Check dodge
    local dodgeRoll = d100()
    if dodgeRoll <= def_dodge then
        return {
            hit = false,
            dodged = true,
            roll = roll,
            dodgeRoll = dodgeRoll,
            vs = def_dodge,
            msg = string.format("%s attacks, %s dodges! (d100=%d vs %d)", atk_name, def_name, dodgeRoll, def_dodge)
        }
    end
    
    local dmg = math.random(dmgMin, dmgMax)
    local crit = roll <= 5  -- nat 5 or under = crit
    if crit then dmg = dmg * 2 end
    
    return {
        hit = true,
        crit = crit,
        damage = dmg,
        roll = roll,
        msg = string.format("%s %s %s for %d! (d100=%d)",
            atk_name, crit and "CRITS" or "hits", def_name, dmg, roll)
    }
end

-- ============================================================
-- HELPERS
-- ============================================================
local function broadcast(message, exclude_client)
    for _, client in ipairs(clients) do
        if client ~= exclude_client then
            client:send(message .. "\n")
        end
    end
end

local function broadcast_all(message)
    for _, client in ipairs(clients) do
        client:send(message .. "\n")
    end
end

local function goblinAt(x, y)
    for _, g in ipairs(goblins) do
        if g.alive and g.x == x and g.y == y then return g end
    end
    return nil
end

local function playerAt(x, y)
    for i, client in ipairs(clients) do
        local pos = client_positions[client]
        local stats = client_stats[client]
        if pos and stats and stats.hp > 0 and pos.x == x and pos.y == y then
            return i, client
        end
    end
    return nil, nil
end

local function getClientIndex(client)
    for i, c in ipairs(clients) do
        if c == client then return i end
    end
    return 0
end

-- ============================================================
-- COMMAND HANDLERS
-- ============================================================
local ACTION_HANDLERS = {
    [Protocol.CMD.MOVE] = function(args)
        local x, y = Protocol.parse_move_args(args)
        if x and y then
            return {type = Protocol.CMD.MOVE, x = x, y = y}
        end
        return nil
    end,
    [Protocol.CMD.PRAY] = function(args)
        return {type = Protocol.CMD.PRAY}
    end,
    [Protocol.CMD.SIT] = function(args)
        return {type = Protocol.CMD.SIT}
    end,
    [Protocol.CMD.STAND] = function(args)
        return {type = Protocol.CMD.STAND}
    end,
    [Protocol.CMD.MEDITATE] = function(args)
        return {type = Protocol.CMD.MEDITATE}
    end,
    ["RESPAWN"] = function(args)
        return {type = "RESPAWN"}
    end,
}

local function parse_packet(data)
    local cmd, args = Protocol.parse_packet(data)
    local handler = ACTION_HANDLERS[cmd]
    if handler then return handler(args) end
    return nil
end

local function submit_intent(client, intent)
    if intent_counts[client] >= MAX_INTENTS_PER_TICK then
        client:send(string.format("%s:%s\n", Protocol.RESPONSE.ERROR, Protocol.ERROR.INTENT_LIMIT_EXCEEDED))
        return false
    end
    command_buffers[client] = intent
    intent_counts[client] = intent_counts[client] + 1
    client:send(Protocol.RESPONSE.INTENT_ACK .. "\n")
    return true
end

-- ============================================================
-- PLAYER ATTACKS GOBLIN (bump combat)
-- ============================================================
local function playerAttackGoblin(client, clientIdx, goblin)
    local stats = client_stats[client]
    local result = resolveCombat(
        "Player#" .. clientIdx,
        "Goblin#" .. goblin.id,
        stats.attack,
        goblin.defense,
        stats.dmgMin, stats.dmgMax
    )
    
    -- Broadcast combat message to all
    broadcast_all(string.format("COMBAT:%s", result.msg))
    
    if result.hit then
        goblin.hp = goblin.hp - result.damage
        
        -- Broadcast goblin HP update
        broadcast_all(string.format("GOBLIN_HP:%d,%d,%d", goblin.id, goblin.hp, goblin.maxHp))
        
        if goblin.hp <= 0 then
            goblin.alive = false
            goblin.deadTicks = 0
            broadcast_all(string.format("GOBLIN_DEATH:%d,%d,%d", goblin.id, goblin.x, goblin.y))
            
            -- Player gets XP / level up
            stats.kills = stats.kills + 1
            stats.xp = stats.xp + 10
            
            -- Level up every 20 XP: +3 attack skill, +1 max damage
            if stats.xp >= stats.xpNext then
                stats.level = stats.level + 1
                stats.attack = math.min(90, stats.attack + 3)
                stats.dmgMax = stats.dmgMax + 1
                stats.maxHp = stats.maxHp + 2
                stats.hp = stats.maxHp  -- heal on level up
                stats.xpNext = stats.xpNext + 20
                broadcast_all(string.format("PLAYER_LEVELUP:%d,%d,%d,%d,%d",
                    clientIdx, stats.level, stats.attack, stats.hp, stats.maxHp))
            end
            
            -- Send updated stats
            client:send(string.format("STATS:%d,%d,%d,%d,%d,%d,%d\n",
                stats.hp, stats.maxHp, stats.attack, stats.level, stats.kills, stats.xp, stats.xpNext))
            
            print(string.format("  [Goblin #%d] KILLED by Player #%d (kills: %d, level: %d)",
                goblin.id, clientIdx, stats.kills, stats.level))
        end
    end
end

-- ============================================================
-- GOBLIN ATTACKS PLAYER (auto-retaliation / roam aggro)
-- ============================================================
local function goblinAttackPlayer(goblin, clientIdx, client)
    local stats = client_stats[client]
    if not stats or stats.hp <= 0 then return end
    
    local result = resolveCombat(
        "Goblin#" .. goblin.id,
        "Player#" .. clientIdx,
        goblin.attack,
        stats.defense,
        goblin.dmgMin, goblin.dmgMax
    )
    
    broadcast_all(string.format("COMBAT:%s", result.msg))
    
    if result.hit then
        stats.hp = stats.hp - result.damage
        
        -- Send updated HP to the hit player
        client:send(string.format("STATS:%d,%d,%d,%d,%d,%d,%d\n",
            stats.hp, stats.maxHp, stats.attack, stats.level, stats.kills, stats.xp, stats.xpNext))
        
        -- Broadcast player HP to all
        broadcast_all(string.format("PLAYER_HP:%d,%d,%d", clientIdx, stats.hp, stats.maxHp))
        
        if stats.hp <= 0 then
            broadcast_all(string.format("PLAYER_DEATH:%d", clientIdx))
            print(string.format("  [Player #%d] KILLED by Goblin #%d", clientIdx, goblin.id))
        end
    end
end

-- ============================================================
-- GOBLIN AI (called each tick)
-- ============================================================
local function updateGoblins()
    for _, g in ipairs(goblins) do
        -- Dead goblin respawn counter
        if not g.alive then
            g.deadTicks = g.deadTicks + 1
            if g.deadTicks >= GOBLIN_RESPAWN_TICKS then
                -- Respawn
                local roomIdx = math.random(2, #rooms)
                local room = rooms[roomIdx]
                g.x = math.random(room.x, room.x + room.w - 1)
                g.y = math.random(room.y, room.y + room.h - 1)
                g.hp = g.maxHp
                g.alive = true
                g.deadTicks = 0
                broadcast_all(string.format("GOBLIN_SPAWN:%d,%d,%d,%d,%d",
                    g.id, g.x, g.y, g.hp, g.maxHp))
                print(string.format("  [Goblin #%d] RESPAWNED at (%d,%d)", g.id, g.x, g.y))
            end
            goto continue
        end
        
        -- Find nearest player
        local nearestDist = 999
        local nearestIdx = nil
        local nearestClient = nil
        for i, client in ipairs(clients) do
            local pos = client_positions[client]
            local stats = client_stats[client]
            if pos and stats and stats.hp > 0 then
                local dist = math.abs(pos.x - g.x) + math.abs(pos.y - g.y)
                if dist < nearestDist then
                    nearestDist = dist
                    nearestIdx = i
                    nearestClient = client
                end
            end
        end
        
        -- Only act if a player is within range 8
        if nearestDist <= 8 and nearestClient then
            local pos = client_positions[nearestClient]
            
            if nearestDist == 1 then
                -- Adjacent — ATTACK!
                goblinAttackPlayer(g, nearestIdx, nearestClient)
            else
                -- Move toward nearest player
                local dx = pos.x - g.x
                local dy = pos.y - g.y
                local mx, my = 0, 0
                
                if math.abs(dx) >= math.abs(dy) then
                    mx = dx > 0 and 1 or -1
                else
                    my = dy > 0 and 1 or -1
                end
                
                local nx, ny = g.x + mx, g.y + my
                -- Check wall, other goblin, and player collision
                if tileAt(nx, ny) == 0 and not goblinAt(nx, ny) and not playerAt(nx, ny) then
                    g.x = nx
                    g.y = ny
                else
                    -- Try alternate direction
                    if mx ~= 0 then
                        my = dy > 0 and 1 or (dy < 0 and -1 or 0); mx = 0
                    else
                        mx = dx > 0 and 1 or (dx < 0 and -1 or 0); my = 0
                    end
                    nx, ny = g.x + mx, g.y + my
                    if tileAt(nx, ny) == 0 and not goblinAt(nx, ny) and not playerAt(nx, ny) then
                        g.x = nx
                        g.y = ny
                    end
                end
                
                -- Broadcast goblin position
                broadcast_all(string.format("GOBLIN_MOVE:%d,%d,%d", g.id, g.x, g.y))
            end
        else
            -- Random wander (20% chance per tick)
            if math.random() < 0.2 then
                local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
                local d = dirs[math.random(1, 4)]
                local nx, ny = g.x + d[1], g.y + d[2]
                if tileAt(nx, ny) == 0 and not goblinAt(nx, ny) and not playerAt(nx, ny) then
                    g.x = nx
                    g.y = ny
                    broadcast_all(string.format("GOBLIN_MOVE:%d,%d,%d", g.id, g.x, g.y))
                end
            end
        end
        
        ::continue::
    end
end

-- ============================================================
-- TICK PROCESSING
-- ============================================================
local function process_tick()
    tick_number = tick_number + 1
    print(string.format("\n[TICK #%d] Processing...", tick_number))
    
    for i, client in ipairs(clients) do
        local intent = command_buffers[client]
        
        if intent then
            if intent.type == Protocol.CMD.MOVE then
                local pos = client_positions[client]
                local stats = client_stats[client]
                
                -- Skip if player is dead
                if stats.hp <= 0 then
                    goto next_client
                end
                
                -- Server-side wall check
                if tileAt(intent.x, intent.y) == 1 then
                    -- Reject — send current position back
                    client:send(string.format("%s:%d,%d,TICK:%d\n",
                        Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                    goto next_client
                end
                
                -- Check if bumping into a goblin = attack
                local target_goblin = goblinAt(intent.x, intent.y)
                if target_goblin then
                    -- BUMP COMBAT — don't move, attack instead
                    print(string.format("  [Player #%d] ATTACKS Goblin #%d at (%d,%d)",
                        i, target_goblin.id, intent.x, intent.y))
                    playerAttackGoblin(client, i, target_goblin)
                    
                    -- Send back current position (didn't move)
                    client:send(string.format("%s:%d,%d,TICK:%d\n",
                        Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                    goto next_client
                end
                
                -- Check if another player is there
                local pIdx, pClient = playerAt(intent.x, intent.y)
                if pIdx then
                    -- Can't move into another player
                    client:send(string.format("%s:%d,%d,TICK:%d\n",
                        Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                    goto next_client
                end
                
                -- Valid move
                pos.x = intent.x
                pos.y = intent.y
                print(string.format("  [Player #%d] MOVE -> (%d,%d)", i, pos.x, pos.y))
                client:send(string.format("%s:%d,%d,TICK:%d\n",
                    Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                broadcast(string.format("%s:%d,%d,%d,TICK:%d",
                    Protocol.RESPONSE.PLAYER_MOVE, i, pos.x, pos.y, tick_number), client)
                
            elseif intent.type == Protocol.CMD.PRAY or intent.type == Protocol.CMD.SIT or
                   intent.type == Protocol.CMD.STAND or intent.type == Protocol.CMD.MEDITATE then
                client_states[client] = intent.type
                print(string.format("  [Player #%d] ACTION -> %s", i, intent.type))
                client:send(string.format("%s:%s,TICK:%d\n",
                    Protocol.RESPONSE.PLAYER_ACTION, intent.type, tick_number))
                broadcast(string.format("%s:%d,%s,TICK:%d",
                    Protocol.RESPONSE.PLAYER_ACTION, i, intent.type, tick_number), client)
            
            elseif intent.type == "RESPAWN" then
                local stats = client_stats[client]
                local pos = client_positions[client]
                if stats.hp <= 0 then
                    -- Reset stats (keep level and kills)
                    stats.hp = stats.maxHp
                    stats.xp = 0
                    
                    -- Teleport to room 1
                    pos.x = rooms[1].cx
                    pos.y = rooms[1].cy
                    
                    print(string.format("  [Player #%d] RESPAWNED at (%d,%d)", i, pos.x, pos.y))
                    
                    -- Send respawn confirmation with position and stats
                    client:send(string.format("PLAYER_RESPAWN:%d,%d,%d,TICK:%d\n",
                        i, pos.x, pos.y, tick_number))
                    client:send(string.format("STATS:%d,%d,%d,%d,%d,%d,%d\n",
                        stats.hp, stats.maxHp, stats.attack, stats.level, stats.kills, stats.xp, stats.xpNext))
                    client:send(string.format("%s:%d,%d,TICK:%d\n",
                        Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                    
                    -- Tell everyone else this player is alive and where they are
                    broadcast(string.format("PLAYER_RESPAWN:%d,%d,%d,TICK:%d",
                        i, pos.x, pos.y, tick_number), client)
                end
            end
        end
        
        ::next_client::
    end
    
    -- Update goblins AFTER player moves
    updateGoblins()
    
    -- Clear command buffers
    for _, client in ipairs(clients) do
        command_buffers[client] = nil
        intent_counts[client] = 0
    end
    
    print(string.format("[TICK #%d] Complete.", tick_number))
end

-- ============================================================
-- MAIN SERVER LOOP
-- ============================================================
while true do
    local current_time = socket.gettime()
    local delta_time = current_time - last_frame_time
    last_frame_time = current_time
    
    tick_accumulator = tick_accumulator + delta_time
    
    -- Accept new connections
    local client = server:accept()
    if client then
        client:settimeout(0)
        table.insert(clients, client)
        local client_id = #clients
        
        -- Spawn in room 1
        client_positions[client] = {x = rooms[1].cx, y = rooms[1].cy}
        client_states[client] = Protocol.CMD.STAND
        command_buffers[client] = nil
        intent_counts[client] = 0
        
        -- Player stats
        client_stats[client] = {
            hp = 20, maxHp = 20,
            attack = 50,    -- d100 roll-under
            defense = 30,   -- d100 roll-under dodge
            dmgMin = 2, dmgMax = 5,
            level = 1,
            kills = 0,
            xp = 0,
            xpNext = 20,
        }
        
        print(string.format("[Player #%d] Connected from %s", client_id, client:getpeername()))
        
        -- Send auth + map seed
        client:send(string.format("%s,ID:%d,TICK:%d,SEED:%d\n",
            Protocol.RESPONSE.AUTH_OK, client_id, tick_number, MAP_SEED))
        
        -- Send initial stats
        local s = client_stats[client]
        client:send(string.format("STATS:%d,%d,%d,%d,%d,%d,%d\n",
            s.hp, s.maxHp, s.attack, s.level, s.kills, s.xp, s.xpNext))
        
        -- Send current goblin states
        for _, g in ipairs(goblins) do
            if g.alive then
                client:send(string.format("GOBLIN_SPAWN:%d,%d,%d,%d,%d\n",
                    g.id, g.x, g.y, g.hp, g.maxHp))
            end
        end
        
        -- Broadcast join
        broadcast(string.format("%s:%d,TICK:%d",
            Protocol.RESPONSE.PLAYER_JOIN, client_id, tick_number), client)
    end
    
    -- Handle existing clients
    for i = #clients, 1, -1 do
        local client = clients[i]
        local data, err = client:receive("*l")
        
        if data then
            local packet = parse_packet(data)
            if packet then
                submit_intent(client, packet)
            else
                client:send(string.format("%s:%s\n",
                    Protocol.RESPONSE.ERROR, Protocol.ERROR.INVALID_COMMAND))
            end
        elseif err == "closed" then
            print(string.format("[Player #%d] Disconnected", i))
            broadcast(string.format("%s:%d,TICK:%d",
                Protocol.RESPONSE.PLAYER_LEAVE, i, tick_number), client)
            client:close()
            table.remove(clients, i)
            client_positions[client] = nil
            client_states[client] = nil
            client_stats[client] = nil
            command_buffers[client] = nil
            intent_counts[client] = nil
        end
    end
    
    -- Tick boundary
    if tick_accumulator >= TICK_RATE then
        process_tick()
        tick_accumulator = tick_accumulator - TICK_RATE
    end
    
    socket.sleep(0.01)
end
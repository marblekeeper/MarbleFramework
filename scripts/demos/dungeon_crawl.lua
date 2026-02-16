-- dungeon_crawl.lua
-- D100 Roll-Under Roguelike Dungeon Crawler
-- Arrow keys move, bump-to-attack, collect loot, descend floors
-- All checks are d100 roll-under: roll <= stat = success

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, sqrt, max, min = math.abs, math.sqrt, math.max, math.min

-- Tile size and map dimensions
local TS = 24
local MW, MH = 30, 22

-- Colors
local C = {
    void     = {8, 6, 16},
    wall     = {45, 38, 55},
    wallHi   = {65, 55, 78},
    floor    = {22, 20, 30},
    floorLit = {32, 28, 42},
    player   = {80, 255, 120},
    enemy    = {255, 70, 70},
    gold     = {255, 220, 50},
    potion   = {100, 200, 255},
    stairs   = {255, 180, 50},
    fog      = {12, 10, 20},
    blood    = {120, 20, 20},
    xp       = {180, 130, 255},
    crit     = {255, 255, 80},
    miss     = {120, 120, 120},
    hit      = {255, 100, 80},
    hud_bg   = {15, 12, 25},
    hud_border = {60, 50, 80},
}

-- Game state
local game = {
    state = "title", -- title, playing, dead, levelup, rolling
    floor_num = 1,
    turn = 0,
    messages = {},
    maxMessages = 6,
    shakeTimer = 0,
    shakeIntensity = 0,
    rollAnim = nil,     -- active roll animation
    particles = {},
    camX = 0, camY = 0,
    inputCooldown = 0,
    keyWasDown = {},
}

-- Player
local player = {
    x = 0, y = 0,
    hp = 30, maxHp = 30,
    str = 55,    -- melee hit chance
    def = 40,    -- dodge chance
    dmgMin = 2, dmgMax = 6,
    armor = 0,
    xp = 0,
    xpNext = 20,
    level = 1,
    gold = 0,
    potions = 1,
    kills = 0,
    critBonus = 5,  -- roll under this = crit
    seen = {},      -- fog of war
}

-- Map
local map = {}
local enemies = {}
local items = {}
local stairs = {x = 0, y = 0}

-- Particles
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

local function addMessage(text, r, g, b)
    table.insert(game.messages, 1, {text = text, r = r or 200, g = g or 200, b = b or 200, age = 0})
    if #game.messages > game.maxMessages then
        table.remove(game.messages)
    end
end

-- Roll a d100 (1-100)
local function d100()
    return rand(1, 100)
end

-- Roll with animation
local function rollD100(callback, label)
    game.rollAnim = {
        timer = 0,
        duration = 0.45,
        currentFace = rand(1, 100),
        finalRoll = d100(),
        callback = callback,
        label = label or "d100",
        flickerRate = 0.03,
        flickerTimer = 0,
        done = false,
    }
end

-- Map generation - BSP-ish rooms + corridors
local function tileAt(x, y)
    if x < 1 or x > MW or y < 1 or y > MH then return 1 end
    return map[y][x]
end

local function setTile(x, y, v)
    if x >= 1 and x <= MW and y >= 1 and y <= MH then
        map[y][x] = v
    end
end

local function carveRoom(rx, ry, rw, rh)
    for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
            setTile(x, y, 0)
        end
    end
    return {x = rx, y = ry, w = rw, h = rh,
            cx = floor(rx + rw/2), cy = floor(ry + rh/2)}
end

local function carveCorridor(x1, y1, x2, y2)
    local x, y = x1, y1
    while x ~= x2 do
        setTile(x, y, 0)
        x = x + (x2 > x and 1 or -1)
    end
    while y ~= y2 do
        setTile(x, y, 0)
        y = y + (y2 > y and 1 or -1)
    end
end

local function generateMap()
    -- Init walls
    map = {}
    for y = 1, MH do
        map[y] = {}
        for x = 1, MW do
            map[y][x] = 1
        end
    end

    local rooms = {}
    local attempts = 0
    local numRooms = rand(6, 9) + floor(game.floor_num / 2)

    while #rooms < numRooms and attempts < 200 do
        attempts = attempts + 1
        local rw = rand(3, 7)
        local rh = rand(3, 5)
        local rx = rand(2, MW - rw - 1)
        local ry = rand(2, MH - rh - 1)

        -- Check overlap
        local ok = true
        for _, r in ipairs(rooms) do
            if rx < r.x + r.w + 1 and rx + rw + 1 > r.x and
               ry < r.y + r.h + 1 and ry + rh + 1 > r.y then
                ok = false
                break
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

    -- Extra corridors for loops
    for i = 1, floor(#rooms / 3) do
        local a = rooms[rand(1, #rooms)]
        local b = rooms[rand(1, #rooms)]
        if a ~= b then
            carveCorridor(a.cx, a.cy, b.cx, b.cy)
        end
    end

    return rooms
end

-- Enemy templates scaled by floor
local function enemyTemplate(floor_n)
    local templates = {
        {name="Rat",       glyph="r", hp=6,  str=30, def=15, dmgMin=1, dmgMax=3, xp=5,  color={180,140,100}},
        {name="Skeleton",  glyph="s", hp=10, str=40, def=25, dmgMin=2, dmgMax=5, xp=10, color={220,220,200}},
        {name="Goblin",    glyph="g", hp=8,  str=45, def=30, dmgMin=2, dmgMax=4, xp=8,  color={80,180,60}},
        {name="Orc",       glyph="o", hp=18, str=55, def=20, dmgMin=3, dmgMax=7, xp=18, color={100,160,60}},
        {name="Wraith",    glyph="w", hp=14, str=60, def=50, dmgMin=3, dmgMax=6, xp=22, color={150,120,220}},
        {name="Troll",     glyph="T", hp=30, str=50, def=15, dmgMin=5, dmgMax=10,xp=35, color={80,120,60}},
        {name="Demon",     glyph="D", hp=25, str=70, def=40, dmgMin=4, dmgMax=9, xp=40, color={255,50,80}},
    }

    -- Pick from templates available at this floor depth
    local maxIdx = min(#templates, 2 + floor(floor_n / 2))
    local minIdx = max(1, maxIdx - 3)
    local t = templates[rand(minIdx, maxIdx)]

    -- Scale slightly with floor
    local scale = 1.0 + (floor_n - 1) * 0.12
    return {
        name = t.name,
        glyph = t.glyph,
        hp = floor(t.hp * scale),
        maxHp = floor(t.hp * scale),
        str = min(90, floor(t.str + floor_n * 2)),
        def = min(80, floor(t.def + floor_n)),
        dmgMin = t.dmgMin + floor(floor_n / 3),
        dmgMax = t.dmgMax + floor(floor_n / 3),
        xp = floor(t.xp * scale),
        color = t.color,
        alive = true,
    }
end

local function populateFloor(rooms)
    enemies = {}
    items = {}

    -- Player in first room
    player.x = rooms[1].cx
    player.y = rooms[1].cy

    -- Stairs in last room
    stairs.x = rooms[#rooms].cx
    stairs.y = rooms[#rooms].cy

    -- Enemies in other rooms
    local numEnemies = 4 + game.floor_num * 2 + rand(0, 2)
    for i = 1, numEnemies do
        local room = rooms[rand(2, #rooms)]
        local ex = rand(room.x, room.x + room.w - 1)
        local ey = rand(room.y, room.y + room.h - 1)
        if not (ex == player.x and ey == player.y) and tileAt(ex, ey) == 0 then
            local e = enemyTemplate(game.floor_num)
            e.x = ex
            e.y = ey
            enemies[#enemies+1] = e
        end
    end

    -- Items
    for i = 2, #rooms do
        local room = rooms[i]
        if rand() < 0.4 then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "gold",
                amount = rand(3, 8) + game.floor_num * 2,
            }
        end
        if rand() < 0.25 then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "potion",
            }
        end
    end
end

-- FOV - simple raycasting
local function computeFOV()
    local radius = 6
    for a = 0, 359, 2 do
        local rad = a * math.pi / 180
        local dx = cos(rad)
        local dy = sin(rad)
        local fx, fy = player.x + 0.5, player.y + 0.5
        for d = 0, radius do
            local tx, ty = floor(fx), floor(fy)
            if tx < 1 or tx > MW or ty < 1 or ty > MH then break end
            local key = ty * 1000 + tx
            player.seen[key] = 2 -- 2 = visible now
            if tileAt(tx, ty) == 1 then break end
            fx = fx + dx * 0.5
            fy = fy + dy * 0.5
        end
    end
end

local function dimFOV()
    for k, v in pairs(player.seen) do
        if v == 2 then player.seen[k] = 1 end -- 1 = remembered
    end
end

local function isVisible(x, y)
    return (player.seen[y * 1000 + x] or 0) == 2
end

local function isSeen(x, y)
    return (player.seen[y * 1000 + x] or 0) >= 1
end

-- Enemy at position
local function enemyAt(x, y)
    for _, e in ipairs(enemies) do
        if e.alive and e.x == x and e.y == y then return e end
    end
    return nil
end

-- Combat
local function resolveMelee(attacker, defender, atkName, defName, atkStr, defDef, dmgMin, dmgMax, onDone)
    -- Attack roll
    local roll = d100()
    local hit = roll <= atkStr
    local crit = roll <= player.critBonus

    if attacker == player then crit = roll <= player.critBonus end

    if not hit then
        addMessage(atkName .. " attacks " .. defName .. ": d100=" .. roll .. " vs " .. atkStr .. " MISS!", C.miss[1], C.miss[2], C.miss[3])
        spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 3, 120, 120, 120, 30, 0.3)
    else
        -- Defense roll
        local dRoll = d100()
        local dodged = dRoll <= defDef

        if dodged then
            addMessage(defName .. " dodges! d100=" .. dRoll .. " vs " .. defDef .. " DEF", C.miss[1], C.miss[2], C.miss[3])
            spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 4, 150, 150, 255, 40, 0.3)
        else
            local dmg = rand(dmgMin, dmgMax)
            if crit then
                dmg = dmg * 2
                addMessage(atkName .. " CRITS " .. defName .. "! d100=" .. roll .. " DMG:" .. dmg, C.crit[1], C.crit[2], C.crit[3])
                screenShake(5, 0.2)
                spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 15, 255, 255, 80, 80, 0.5)
            else
                addMessage(atkName .. " hits " .. defName .. " d100=" .. roll .. " DMG:" .. dmg, C.hit[1], C.hit[2], C.hit[3])
                screenShake(3, 0.1)
                spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 8, 255, 80, 60, 60, 0.4)
            end

            -- Apply armor
            if defender == player and player.armor > 0 then
                local reduced = max(1, dmg - player.armor)
                if reduced < dmg then
                    addMessage("  Armor absorbs " .. (dmg - reduced) .. " damage", 160, 160, 180)
                end
                dmg = reduced
            end

            defender.hp = defender.hp - dmg
        end
    end

    if onDone then onDone() end
end

local function checkEnemyDeath(e)
    if e.hp <= 0 then
        e.alive = false
        addMessage(e.name .. " defeated! (+" .. e.xp .. " XP)", C.xp[1], C.xp[2], C.xp[3])
        spawnParticles(e.x * TS + TS/2, e.y * TS + TS/2, 20, e.color[1], e.color[2], e.color[3], 100, 0.6)
        screenShake(4, 0.15)
        player.xp = player.xp + e.xp
        player.kills = player.kills + 1

        -- Drop gold
        if rand() < 0.5 then
            items[#items+1] = {x = e.x, y = e.y, type = "gold", amount = rand(1, 5) + game.floor_num}
        end

        -- Level up check
        if player.xp >= player.xpNext then
            game.state = "levelup"
            player.level = player.level + 1
            player.xpNext = floor(player.xpNext * 1.6)
            addMessage("*** LEVEL UP! Level " .. player.level .. " ***", 255, 255, 100)
            spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 25, 255, 255, 100, 120, 0.8)
            screenShake(3, 0.2)
        end
    end
end

local function checkPlayerDeath()
    if player.hp <= 0 then
        player.hp = 0
        game.state = "dead"
        addMessage("You have perished on floor " .. game.floor_num .. "!", 255, 50, 50)
        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 40, 200, 50, 50, 150, 1.0)
        screenShake(8, 0.4)
    end
end

-- Enemy AI (simple: move toward player if visible)
local function moveEnemies()
    for _, e in ipairs(enemies) do
        if not e.alive then goto continue end

        local dx = player.x - e.x
        local dy = player.y - e.y
        local adist = abs(dx) + abs(dy)

        -- Only act if somewhat close
        if adist > 10 then goto continue end

        -- If adjacent, attack
        if adist == 1 then
            resolveMelee(e, player, e.name, "You", e.str, player.def, e.dmgMin, e.dmgMax)
            checkPlayerDeath()
            goto continue
        end

        -- Move toward player
        local mx, my = 0, 0
        if abs(dx) >= abs(dy) then
            mx = dx > 0 and 1 or -1
        else
            my = dy > 0 and 1 or -1
        end

        local nx, ny = e.x + mx, e.y + my
        if tileAt(nx, ny) == 0 and not enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
            e.x = nx
            e.y = ny
        else
            -- Try other axis
            if mx ~= 0 then
                my = dy > 0 and 1 or (dy < 0 and -1 or 0)
                mx = 0
            else
                mx = dx > 0 and 1 or (dx < 0 and -1 or 0)
                my = 0
            end
            nx, ny = e.x + mx, e.y + my
            if tileAt(nx, ny) == 0 and not enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
                e.x = nx
                e.y = ny
            end
        end

        ::continue::
    end
end

-- Generate a new floor
local function newFloor()
    player.seen = {}
    local rooms = generateMap()
    populateFloor(rooms)
    dimFOV()
    computeFOV()
    addMessage("-- Floor " .. game.floor_num .. " --", 255, 220, 100)
end

-- Level up choices
local levelChoices = {
    {name = "+5 Max HP & heal",   apply = function() player.maxHp = player.maxHp + 5; player.hp = player.maxHp end},
    {name = "+8 STR (hit chance)", apply = function() player.str = min(95, player.str + 8) end},
    {name = "+8 DEF (dodge)",      apply = function() player.def = min(85, player.def + 8) end},
    {name = "+2 Max Damage",       apply = function() player.dmgMax = player.dmgMax + 2 end},
    {name = "+1 Armor",            apply = function() player.armor = player.armor + 1 end},
    {name = "+3 Crit Range",       apply = function() player.critBonus = min(25, player.critBonus + 3) end},
}

local function resetGame()
    game.state = "playing"
    game.floor_num = 1
    game.turn = 0
    game.messages = {}
    game.particles = {}

    player.hp = 30
    player.maxHp = 30
    player.str = 55
    player.def = 40
    player.dmgMin = 2
    player.dmgMax = 6
    player.armor = 0
    player.xp = 0
    player.xpNext = 20
    player.level = 1
    player.gold = 0
    player.potions = 1
    player.kills = 0
    player.critBonus = 5
    player.seen = {}

    addMessage("Arrow keys: move/attack. P: potion. Descend the dungeon!", 180, 180, 220)
    newFloor()
end

-- Player action
local function tryMove(dx, dy)
    if game.state ~= "playing" then return end

    local nx, ny = player.x + dx, player.y + dy

    -- Attack enemy?
    local e = enemyAt(nx, ny)
    if e then
        resolveMelee(player, e, "You", e.name, player.str, e.def, player.dmgMin, player.dmgMax)
        checkEnemyDeath(e)
        if game.state ~= "dead" then
            game.turn = game.turn + 1
            moveEnemies()
        end
        dimFOV()
        computeFOV()
        return
    end

    -- Move
    if tileAt(nx, ny) == 0 then
        player.x = nx
        player.y = ny

        -- Pick up items
        for i = #items, 1, -1 do
            local it = items[i]
            if it.x == nx and it.y == ny then
                if it.type == "gold" then
                    player.gold = player.gold + it.amount
                    addMessage("Picked up " .. it.amount .. " gold!", C.gold[1], C.gold[2], C.gold[3])
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 6, 255, 220, 50, 40, 0.3)
                elseif it.type == "potion" then
                    player.potions = player.potions + 1
                    addMessage("Found a health potion!", C.potion[1], C.potion[2], C.potion[3])
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 6, 100, 200, 255, 40, 0.3)
                end
                table.remove(items, i)
            end
        end

        -- Stairs?
        if nx == stairs.x and ny == stairs.y then
            game.floor_num = game.floor_num + 1
            addMessage("Descending to floor " .. game.floor_num .. "...", 255, 200, 100)
            newFloor()
            return
        end

        game.turn = game.turn + 1
        moveEnemies()
        dimFOV()
        computeFOV()
    end
end

local function usePotion()
    if player.potions > 0 and player.hp < player.maxHp then
        player.potions = player.potions - 1
        local heal = floor(player.maxHp * 0.4) + rand(1, 5)
        player.hp = min(player.maxHp, player.hp + heal)
        addMessage("Drank potion! Healed " .. heal .. " HP", 100, 255, 150)
        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 10, 100, 255, 150, 50, 0.4)
        game.turn = game.turn + 1
        moveEnemies()
        dimFOV()
        computeFOV()
    end
end

-- Input handling with edge detection
local function keyPressed(key)
    if not bridge.getKeyState then return false end
    local down = bridge.getKeyState(key) == 1
    local was = game.keyWasDown[key] or false
    game.keyWasDown[key] = down
    return down and not was
end

-- Drawing
local function drawTile(sx, sy, tx, ty)
    local camOX = floor(W/2 - player.x * TS - TS/2)
    local camOY = floor(H * 0.4 - player.y * TS - TS/2)
    local px = camOX + tx * TS + sx
    local py = camOY + ty * TS + sy

    -- Off screen cull
    if px < -TS or px > W + TS or py < -TS or py > H * 0.65 + TS then return end

    local vis = isVisible(tx, ty)
    local seen = isSeen(tx, ty)
    local tile = tileAt(tx, ty)

    if not seen then
        bridge.drawRect(px, py, TS, TS, C.void[1], C.void[2], C.void[3], 255)
        return
    end

    local dim = vis and 1.0 or 0.35

    if tile == 1 then
        local cr, cg, cb = C.wall[1], C.wall[2], C.wall[3]
        -- Slight variation
        if (tx + ty) % 3 == 0 then cr, cg, cb = C.wallHi[1], C.wallHi[2], C.wallHi[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        -- Wall top highlight
        if vis and ty > 1 and tileAt(tx, ty-1) == 0 then
            bridge.drawRect(px, py, TS, 2, floor(80*dim), floor(70*dim), floor(100*dim), 255)
        end
    else
        local cr, cg, cb = C.floor[1], C.floor[2], C.floor[3]
        if vis then cr, cg, cb = C.floorLit[1], C.floorLit[2], C.floorLit[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        -- Floor detail
        if (tx * 7 + ty * 13) % 11 == 0 then
            bridge.drawRect(px + 4, py + 4, 2, 2, floor(cr*dim*0.7), floor(cg*dim*0.7), floor(cb*dim*0.7), 255)
        end
    end
end

function DrawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = floor((rand() - 0.5) * game.shakeIntensity * 2)
        sy = floor((rand() - 0.5) * game.shakeIntensity * 2)
    end

    -- Clear
    bridge.drawRect(0, 0, W, H, C.void[1], C.void[2], C.void[3], 255)

    if game.state == "title" then
        bridge.drawRect(0, 0, W, H, 8, 6, 16, 255)
        bridge.drawText("DUNGEON OF THE D100", W/2 - 80, H/3 - 20, 255, 220, 100, 255)
        bridge.drawText("A Roll-Under Roguelike", W/2 - 75, H/3 + 5, 180, 160, 200, 255)
        bridge.drawText("Arrow Keys: Move & Attack", W/2 - 85, H/2, 160, 160, 180, 255)
        bridge.drawText("P: Drink Potion", W/2 - 50, H/2 + 20, 160, 160, 180, 255)
        bridge.drawText("Bump enemies to fight", W/2 - 70, H/2 + 40, 160, 160, 180, 255)
        bridge.drawText("Roll d100 <= your stat to succeed", W/2 - 105, H/2 + 60, 140, 140, 160, 255)
        bridge.drawText("PRESS SPACE TO BEGIN", W/2 - 70, H * 0.75, 255, 255, 150, 255)
        return
    end

    local camOX = floor(W/2 - player.x * TS - TS/2)
    local camOY = floor(H * 0.4 - player.y * TS - TS/2)
    local mapAreaH = floor(H * 0.65)

    -- Draw map tiles
    local startTX = max(1, floor(-camOX / TS) - 1)
    local endTX = min(MW, floor((-camOX + W) / TS) + 2)
    local startTY = max(1, floor(-camOY / TS) - 1)
    local endTY = min(MH, floor((-camOY + mapAreaH) / TS) + 2)

    for ty = startTY, endTY do
        for tx = startTX, endTX do
            drawTile(sx, sy, tx, ty)
        end
    end

    -- Draw stairs (if visible)
    if isVisible(stairs.x, stairs.y) then
        local stX = camOX + stairs.x * TS + sx
        local stY = camOY + stairs.y * TS + sy
        bridge.drawRect(stX + 4, stY + 4, TS - 8, TS - 8, C.stairs[1], C.stairs[2], C.stairs[3], 255)
        bridge.drawRect(stX + 7, stY + 7, TS - 14, TS - 14, 180, 120, 30, 255)
        bridge.drawText(">", stX + 8, stY + 5, 255, 240, 180, 255)
    elseif isSeen(stairs.x, stairs.y) then
        local stX = camOX + stairs.x * TS + sx
        local stY = camOY + stairs.y * TS + sy
        bridge.drawRect(stX + 4, stY + 4, TS - 8, TS - 8, 80, 60, 30, 255)
    end

    -- Draw items
    for _, it in ipairs(items) do
        if isVisible(it.x, it.y) then
            local ix = camOX + it.x * TS + sx
            local iy = camOY + it.y * TS + sy
            if it.type == "gold" then
                bridge.drawRect(ix + 8, iy + 8, 8, 8, C.gold[1], C.gold[2], C.gold[3], 255)
                bridge.drawRect(ix + 9, iy + 9, 4, 4, 255, 250, 150, 255)
            elseif it.type == "potion" then
                bridge.drawRect(ix + 7, iy + 5, 10, 14, C.potion[1], C.potion[2], C.potion[3], 255)
                bridge.drawRect(ix + 9, iy + 3, 6, 4, 80, 160, 220, 255)
            end
        end
    end

    -- Draw enemies
    for _, e in ipairs(enemies) do
        if e.alive and isVisible(e.x, e.y) then
            local ex = camOX + e.x * TS + sx
            local ey = camOY + e.y * TS + sy
            -- Body
            bridge.drawRect(ex + 3, ey + 3, TS - 6, TS - 6, e.color[1], e.color[2], e.color[3], 255)
            bridge.drawRect(ex + 5, ey + 5, TS - 10, TS - 10,
                min(255, e.color[1]+30), min(255, e.color[2]+30), min(255, e.color[3]+30), 255)
            -- HP bar if damaged
            if e.hp < e.maxHp then
                local barW = TS - 4
                local hpFrac = e.hp / e.maxHp
                bridge.drawRect(ex + 2, ey - 3, barW, 3, 60, 20, 20, 200)
                bridge.drawRect(ex + 2, ey - 3, floor(barW * hpFrac), 3, 255, 50, 50, 255)
            end
        end
    end

    -- Draw player
    if game.state ~= "dead" then
        local px_draw = camOX + player.x * TS + sx
        local py_draw = camOY + player.y * TS + sy
        bridge.drawRect(px_draw + 2, py_draw + 2, TS - 4, TS - 4, C.player[1], C.player[2], C.player[3], 255)
        bridge.drawRect(px_draw + 5, py_draw + 5, TS - 10, TS - 10, 120, 255, 160, 255)
        -- Eyes
        bridge.drawRect(px_draw + 7, py_draw + 7, 3, 3, 20, 40, 20, 255)
        bridge.drawRect(px_draw + 14, py_draw + 7, 3, 3, 20, 40, 20, 255)
    end

    -- Particles (in map space)
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

    -- HUD panel at bottom
    local hudY = mapAreaH + 2
    local hudH = H - hudY
    bridge.drawRect(0, hudY, W, hudH, C.hud_bg[1], C.hud_bg[2], C.hud_bg[3], 255)
    bridge.drawRect(0, hudY, W, 2, C.hud_border[1], C.hud_border[2], C.hud_border[3], 255)

    -- Stats (left column)
    local col1 = 10
    local ly = hudY + 6
    bridge.drawText("LVL:" .. player.level, col1, ly, 255, 255, 150, 255)
    bridge.drawText("FL:" .. game.floor_num, col1 + 55, ly, 255, 200, 100, 255)

    ly = ly + 14
    -- HP bar
    bridge.drawText("HP:", col1, ly, 200, 200, 200, 255)
    local barX = col1 + 28
    local barW = 90
    local barH = 10
    bridge.drawRect(barX, ly, barW, barH, 40, 15, 15, 255)
    local hpW = floor(barW * (player.hp / player.maxHp))
    local hpR = player.hp <= player.maxHp * 0.3 and 255 or 50
    local hpG = player.hp <= player.maxHp * 0.3 and 50 or 220
    bridge.drawRect(barX, ly, hpW, barH, hpR, hpG, 50, 255)
    bridge.drawText(player.hp .. "/" .. player.maxHp, barX + barW + 5, ly, 200, 200, 200, 255)

    ly = ly + 14
    bridge.drawText("STR:" .. player.str .. " DEF:" .. player.def .. " DMG:" .. player.dmgMin .. "-" .. player.dmgMax, col1, ly, 180, 180, 200, 255)

    ly = ly + 14
    bridge.drawText("ARM:" .. player.armor .. " CRIT:<=" .. player.critBonus, col1, ly, 180, 180, 200, 255)
    bridge.drawText("XP:" .. player.xp .. "/" .. player.xpNext, col1 + 160, ly, C.xp[1], C.xp[2], C.xp[3], 255)

    ly = ly + 14
    bridge.drawText("Gold:" .. player.gold .. "  Potions:" .. player.potions, col1, ly, C.gold[1], C.gold[2], C.gold[3], 255)
    bridge.drawText("Kills:" .. player.kills, col1 + 200, ly, 200, 160, 160, 255)

    -- Message log (right side)
    local msgX = W/2 + 20
    local msgY = hudY + 8
    bridge.drawText("-- Combat Log --", msgX, msgY, 120, 110, 140, 255)
    for i, msg in ipairs(game.messages) do
        local alpha = max(80, 255 - i * 25)
        bridge.drawText(msg.text, msgX, msgY + i * 13, msg.r, msg.g, msg.b, alpha)
        if msgY + i * 13 > H - 5 then break end
    end

    -- Level up overlay
    if game.state == "levelup" then
        bridge.drawRect(W/4, H/4, W/2, H/2, 15, 12, 30, 240)
        bridge.drawRect(W/4, H/4, W/2, 2, 255, 220, 100, 255)
        bridge.drawText("LEVEL UP! Choose a bonus:", W/4 + 20, H/4 + 12, 255, 255, 150, 255)
        for i, choice in ipairs(levelChoices) do
            local y = H/4 + 30 + (i-1) * 22
            local hover = false -- could add mouse later
            bridge.drawRect(W/4 + 15, y, W/2 - 30, 18, 30, 25, 50, 200)
            bridge.drawText(i .. ") " .. choice.name, W/4 + 22, y + 2, 220, 220, 240, 255)
        end
    end

    -- Death overlay
    if game.state == "dead" then
        bridge.drawRect(W/4, H/3, W/2, H/4, 20, 5, 5, 230)
        bridge.drawRect(W/4, H/3, W/2, 2, 255, 50, 50, 255)
        bridge.drawText("YOU HAVE PERISHED", W/4 + 40, H/3 + 15, 255, 60, 60, 255)
        bridge.drawText("Floor: " .. game.floor_num .. "  Level: " .. player.level .. "  Kills: " .. player.kills, W/4 + 15, H/3 + 35, 200, 200, 200, 255)
        bridge.drawText("Gold: " .. player.gold .. "  Score: " .. (player.kills * 10 + player.gold + game.floor_num * 50), W/4 + 15, H/3 + 52, 255, 220, 100, 255)
        bridge.drawText("PRESS SPACE TO TRY AGAIN", W/4 + 25, H/3 + 75, 180, 180, 180, 255)
    end
end

-- Main update
function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    local dt = 0.016

    -- Shake decay
    if game.shakeTimer > 0 then
        game.shakeTimer = game.shakeTimer - dt
    end

    -- Particles
    for i = #game.particles, 1, -1 do
        local p = game.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        if p.life <= 0 then table.remove(game.particles, i) end
    end

    -- Age messages
    for _, msg in ipairs(game.messages) do
        msg.age = msg.age + dt
    end

    -- Input
    if game.state == "title" then
        if keyPressed("space") then
            resetGame()
        end
        return
    end

    if game.state == "dead" then
        if keyPressed("space") then
            resetGame()
        end
        return
    end

    if game.state == "levelup" then
        for i = 1, #levelChoices do
            if keyPressed(tostring(i)) then
                levelChoices[i].apply()
                addMessage("Chose: " .. levelChoices[i].name, 255, 255, 150)
                game.state = "playing"
                break
            end
        end
        return
    end

    -- Movement (turn-based with input cooldown for held keys)
    game.inputCooldown = max(0, game.inputCooldown - dt)

    if game.state == "playing" then
        if keyPressed("up") or keyPressed("w") then tryMove(0, -1)
        elseif keyPressed("down") or keyPressed("s") then tryMove(0, 1)
        elseif keyPressed("left") or keyPressed("a") then tryMove(-1, 0)
        elseif keyPressed("right") or keyPressed("d") then tryMove(1, 0)
        elseif keyPressed("p") then usePotion()
        end
    end
end

function DrawUI()
    DrawGame()
end
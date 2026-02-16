-- MindMarr.lua
-- MINDMARR: Mars Becomes Mind
-- d100 Roll-Under Survival Horror — Escape the sentient planet
-- Arrow keys move, bump-to-attack, collect supplies, reach the shuttle
-- Say "MINDMARR" and it's the last word you ever say

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, sqrt, max, min = math.abs, math.sqrt, math.max, math.min

local TS = 24
local MW, MH = 30, 22

-- Mars palette
local C = {
    void      = {4, 2, 6},
    wall      = {90, 40, 25},
    wallHi    = {120, 55, 35},
    floor     = {35, 18, 14},
    floorLit  = {55, 28, 22},
    player    = {60, 200, 255},
    infected  = {180, 40, 60},
    infGlow   = {220, 60, 80},
    supply    = {100, 220, 140},
    cell      = {180, 60, 200},
    shuttle   = {255, 220, 80},
    fog       = {6, 3, 8},
    blood     = {140, 30, 40},
    xp        = {200, 120, 255},
    crit      = {255, 200, 60},
    miss      = {100, 80, 80},
    hit       = {255, 80, 60},
    hud_bg    = {12, 6, 10},
    hud_border= {80, 35, 50},
    mars      = {200, 60, 40},
    whisper   = {160, 50, 70},
    sanity    = {120, 180, 255},
    oxygen    = {80, 200, 220},
}

-- Infected speech fragments — they only say one word
local MINDMARR_SAYS = {
    "mindmarr...", "MINDMARR!", "mind...marr...", "mindmarr", "MiNdMaRr",
    "m i n d m a r r", "MINDMARR MINDMARR", "...mindmarr...",
    "mindmarr?", "MINDMARR.", "mind...m a r r...", "mindmarrMINDMARR",
}

-- Game state
local game = {
    state = "title",
    sector = 1,         -- floor equivalent
    maxSectors = 7,     -- reach sector 7 shuttle bay to win
    turn = 0,
    messages = {},
    maxMessages = 6,
    shakeTimer = 0,
    shakeIntensity = 0,
    particles = {},
    camX = 0, camY = 0,
    inputCooldown = 0,
    keyWasDown = {},
    marsWhisperTimer = 0,
    pulseTimer = 0,
    won = false,
}

-- Player (survivor)
local player = {
    x = 0, y = 0,
    hp = 30, maxHp = 30,
    str = 55,       -- melee hit
    def = 40,       -- dodge
    dmgMin = 2, dmgMax = 5,
    armor = 0,
    xp = 0,
    xpNext = 20,
    level = 1,
    sanity = 100,   -- max 100, mars drains it
    oxygen = 100,   -- each sector costs O2
    medkits = 1,
    cells = 0,      -- power cells for shuttle
    cellsNeeded = 3,
    kills = 0,
    critBonus = 5,
    seen = {},
}

local map = {}
local enemies = {}
local items = {}
local shuttle = {x = 0, y = 0}

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

local function d100()
    return rand(1, 100)
end

-- Map gen
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
    map = {}
    for y = 1, MH do
        map[y] = {}
        for x = 1, MW do
            map[y][x] = 1
        end
    end

    local rooms = {}
    local attempts = 0
    local numRooms = rand(6, 9) + floor(game.sector / 2)

    while #rooms < numRooms and attempts < 200 do
        attempts = attempts + 1
        local rw = rand(3, 7)
        local rh = rand(3, 5)
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

    return rooms
end

-- Infected templates
local function infectedTemplate(sector)
    local templates = {
        {name="Scientist",    glyph="S", hp=7,  str=30, def=15, dmgMin=1, dmgMax=3, xp=5,  color={180,100,120}},
        {name="Technician",   glyph="T", hp=10, str=40, def=20, dmgMin=2, dmgMax=4, xp=8,  color={160,80,100}},
        {name="Security",     glyph="G", hp=14, str=50, def=25, dmgMin=2, dmgMax=5, xp=12, color={200,70,90}},
        {name="Commander",    glyph="C", hp=20, str=55, def=30, dmgMin=3, dmgMax=7, xp=20, color={220,50,70}},
        {name="MarsSpawn",    glyph="M", hp=16, str=60, def=45, dmgMin=3, dmgMax=6, xp=25, color={200,40,60}},
        {name="Hivemind",     glyph="H", hp=35, str=65, def=30, dmgMin=5, dmgMax=10,xp=40, color={180,30,80}},
        {name="MINDMARR",     glyph="@", hp=50, str=75, def=40, dmgMin=6, dmgMax=12,xp=60, color={255,20,50}},
    }

    local maxIdx = min(#templates, 2 + floor(sector / 2))
    local minIdx = max(1, maxIdx - 3)
    local t = templates[rand(minIdx, maxIdx)]

    local scale = 1.0 + (sector - 1) * 0.12
    return {
        name = t.name,
        glyph = t.glyph,
        hp = floor(t.hp * scale),
        maxHp = floor(t.hp * scale),
        str = min(90, floor(t.str + sector * 2)),
        def = min(80, floor(t.def + sector)),
        dmgMin = t.dmgMin + floor(sector / 3),
        dmgMax = t.dmgMax + floor(sector / 3),
        xp = floor(t.xp * scale),
        color = t.color,
        alive = true,
        sayTimer = 0,
        lastSaid = "",
    }
end

local function populateFloor(rooms)
    enemies = {}
    items = {}

    player.x = rooms[1].cx
    player.y = rooms[1].cy

    -- Shuttle/airlock in last room (only on final sector it's the shuttle)
    shuttle.x = rooms[#rooms].cx
    shuttle.y = rooms[#rooms].cy

    -- Enemies
    local numEnemies = 3 + game.sector * 2 + rand(0, 2)
    for i = 1, numEnemies do
        local room = rooms[rand(2, #rooms)]
        local ex = rand(room.x, room.x + room.w - 1)
        local ey = rand(room.y, room.y + room.h - 1)
        if not (ex == player.x and ey == player.y) and tileAt(ex, ey) == 0 then
            local e = infectedTemplate(game.sector)
            e.x = ex
            e.y = ey
            enemies[#enemies+1] = e
        end
    end

    -- Items
    for i = 2, #rooms do
        local room = rooms[i]
        if rand() < 0.35 then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "supply",
                amount = rand(2, 6) + game.sector,
            }
        end
        if rand() < 0.2 then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "medkit",
            }
        end
        -- Power cells are rare
        if rand() < 0.15 and player.cells < player.cellsNeeded then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "cell",
            }
        end
        -- Oxygen canister
        if rand() < 0.2 then
            items[#items+1] = {
                x = rand(room.x, room.x + room.w - 1),
                y = rand(room.y, room.y + room.h - 1),
                type = "oxygen",
            }
        end
    end
end

-- FOV
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
            player.seen[ty * 1000 + tx] = 2
            if tileAt(tx, ty) == 1 then break end
            fx = fx + dx * 0.5
            fy = fy + dy * 0.5
        end
    end
end

local function dimFOV()
    for k, v in pairs(player.seen) do
        if v == 2 then player.seen[k] = 1 end
    end
end

local function isVisible(x, y)
    return (player.seen[y * 1000 + x] or 0) == 2
end

local function isSeen(x, y)
    return (player.seen[y * 1000 + x] or 0) >= 1
end

local function enemyAt(x, y)
    for _, e in ipairs(enemies) do
        if e.alive and e.x == x and e.y == y then return e end
    end
    return nil
end

-- Mars whisper — sanity drain events
local marsWhispers = {
    "The ground pulses beneath you...",
    "You hear your name spoken from below...",
    "The walls are breathing...",
    "Something remembers you were born...",
    "Mars knows your mother's name...",
    "The red dust rearranges into a face...",
    "You feel the planet thinking...",
    "Your shadow moved on its own...",
    "The air tastes like someone else's memory...",
    "mind...marr... NO. Focus.",
    "A voice in the static: 'Join us.'",
    "Your reflection blinked before you did...",
}

local function marsWhisper()
    if player.sanity > 0 then
        local drain = rand(1, 3)
        player.sanity = max(0, player.sanity - drain)
        local w = marsWhispers[rand(1, #marsWhispers)]
        addMessage(w, C.whisper[1], C.whisper[2], C.whisper[3])
        if player.sanity <= 0 then
            -- sanity gone = you say the word
            game.state = "mindmarr"
            addMessage("Your lips move on their own...", 255, 40, 60)
            addMessage("You whisper: \"mindmarr\"", 255, 20, 40)
            addMessage("It's the last word you ever say.", 255, 0, 0)
            screenShake(10, 0.6)
            spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 50, 200, 30, 60, 150, 1.2)
        end
    end
end

-- Combat
local function resolveMelee(attacker, defender, atkName, defName, atkStr, defDef, dmgMin, dmgMax, onDone)
    local roll = d100()
    local hit = roll <= atkStr
    local crit = false
    if attacker == player then crit = roll <= player.critBonus end

    if not hit then
        addMessage(atkName .. " > " .. defName .. ": d100=" .. roll .. " vs " .. atkStr .. " MISS", C.miss[1], C.miss[2], C.miss[3])
        spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 3, 100, 80, 80, 30, 0.3)
    else
        local dRoll = d100()
        local dodged = dRoll <= defDef

        if dodged then
            addMessage(defName .. " evades! d100=" .. dRoll .. " vs " .. defDef, C.miss[1], C.miss[2], C.miss[3])
            spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 4, 150, 150, 255, 40, 0.3)
        else
            local dmg = rand(dmgMin, dmgMax)
            if crit then
                dmg = dmg * 2
                addMessage(atkName .. " CRITS " .. defName .. "! d100=" .. roll .. " DMG:" .. dmg, C.crit[1], C.crit[2], C.crit[3])
                screenShake(5, 0.2)
                spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 15, 255, 200, 60, 80, 0.5)
            else
                addMessage(atkName .. " hits " .. defName .. " d100=" .. roll .. " DMG:" .. dmg, C.hit[1], C.hit[2], C.hit[3])
                screenShake(3, 0.1)
                spawnParticles(defender.x * TS + TS/2, defender.y * TS + TS/2, 8, 255, 80, 60, 60, 0.4)
            end

            if defender == player and player.armor > 0 then
                local reduced = max(1, dmg - player.armor)
                if reduced < dmg then
                    addMessage("  Suit absorbs " .. (dmg - reduced), 160, 160, 180)
                end
                dmg = reduced
            end

            defender.hp = defender.hp - dmg

            -- Enemy hit drains sanity
            if defender == player and rand() < 0.3 then
                player.sanity = max(0, player.sanity - rand(1, 2))
                addMessage("  Your mind fractures...", C.whisper[1], C.whisper[2], C.whisper[3])
            end
        end
    end

    -- Infected scream mindmarr on attack
    if attacker ~= player then
        local say = MINDMARR_SAYS[rand(1, #MINDMARR_SAYS)]
        addMessage("  " .. atkName .. ": \"" .. say .. "\"", C.infected[1], C.infected[2], C.infected[3])
    end

    if onDone then onDone() end
end

local function checkEnemyDeath(e)
    if e.hp <= 0 then
        e.alive = false
        -- Death cry
        addMessage(e.name .. " collapses: \"mind...marr...\" (+" .. e.xp .. " XP)", C.xp[1], C.xp[2], C.xp[3])
        spawnParticles(e.x * TS + TS/2, e.y * TS + TS/2, 20, e.color[1], e.color[2], e.color[3], 100, 0.6)
        screenShake(4, 0.15)
        player.xp = player.xp + e.xp
        player.kills = player.kills + 1

        if rand() < 0.4 then
            items[#items+1] = {x = e.x, y = e.y, type = "supply", amount = rand(1, 4) + game.sector}
        end

        if player.xp >= player.xpNext then
            game.state = "levelup"
            player.level = player.level + 1
            player.xpNext = floor(player.xpNext * 1.6)
            addMessage("*** ADAPT — Level " .. player.level .. " ***", 255, 255, 100)
            spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 25, 60, 200, 255, 120, 0.8)
            screenShake(3, 0.2)
        end
    end
end

local function checkPlayerDeath()
    if player.hp <= 0 then
        player.hp = 0
        game.state = "dead"
        addMessage("Your body joins the Mindmarr.", 255, 50, 50)
        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 40, 200, 30, 50, 150, 1.0)
        screenShake(8, 0.4)
    end
end

local function checkSanityDeath()
    if player.sanity <= 0 and game.state == "playing" then
        game.state = "mindmarr"
        addMessage("Your lips move: \"mindmarr\"", 255, 20, 40)
        addMessage("The last word you ever say.", 255, 0, 0)
        screenShake(10, 0.6)
        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 50, 200, 30, 60, 150, 1.2)
    end
end

-- Enemy AI
local function moveEnemies()
    for _, e in ipairs(enemies) do
        if not e.alive then goto continue end

        local dx = player.x - e.x
        local dy = player.y - e.y
        local adist = abs(dx) + abs(dy)

        if adist > 10 then goto continue end

        -- Nearby enemies mumble
        if adist <= 6 and rand() < 0.08 then
            local say = MINDMARR_SAYS[rand(1, #MINDMARR_SAYS)]
            addMessage(e.name .. ": \"" .. say .. "\"", C.infected[1], C.infected[2], C.infected[3])
            if rand() < 0.3 then
                player.sanity = max(0, player.sanity - 1)
            end
        end

        if adist == 1 then
            resolveMelee(e, player, e.name, "You", e.str, player.def, e.dmgMin, e.dmgMax)
            checkPlayerDeath()
            checkSanityDeath()
            goto continue
        end

        local mx, my = 0, 0
        if abs(dx) >= abs(dy) then
            mx = dx > 0 and 1 or -1
        else
            my = dy > 0 and 1 or -1
        end

        local nx, ny = e.x + mx, e.y + my
        if tileAt(nx, ny) == 0 and not enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
            e.x = nx; e.y = ny
        else
            if mx ~= 0 then
                my = dy > 0 and 1 or (dy < 0 and -1 or 0); mx = 0
            else
                mx = dx > 0 and 1 or (dx < 0 and -1 or 0); my = 0
            end
            nx, ny = e.x + mx, e.y + my
            if tileAt(nx, ny) == 0 and not enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
                e.x = nx; e.y = ny
            end
        end

        ::continue::
    end
end

local function newFloor()
    player.seen = {}
    local rooms = generateMap()
    populateFloor(rooms)
    dimFOV()
    computeFOV()

    -- O2 cost per sector transition
    if game.sector > 1 then
        local o2cost = rand(5, 12)
        player.oxygen = max(0, player.oxygen - o2cost)
        addMessage("Airlock transit: -" .. o2cost .. " O2", C.oxygen[1], C.oxygen[2], C.oxygen[3])
        if player.oxygen <= 0 then
            game.state = "dead"
            addMessage("Suffocated between sectors.", 255, 50, 50)
            screenShake(6, 0.3)
            return
        end
    end

    if game.sector == game.maxSectors then
        addMessage("== SECTOR " .. game.sector .. ": SHUTTLE BAY ==", 255, 220, 80)
        addMessage("The shuttle is HERE. Reach it!", 255, 255, 150)
    else
        addMessage("-- Sector " .. game.sector .. " / " .. game.maxSectors .. " --", 255, 180, 100)
    end

    -- Mars whispers more in deeper sectors
    if rand(1, 100) <= game.sector * 12 then
        marsWhisper()
    end
end

-- Level up
local levelChoices = {
    {name = "+5 Max HP & heal",      apply = function() player.maxHp = player.maxHp + 5; player.hp = player.maxHp end},
    {name = "+8 STR (hit chance)",    apply = function() player.str = min(95, player.str + 8) end},
    {name = "+8 DEF (dodge)",         apply = function() player.def = min(85, player.def + 8) end},
    {name = "+2 Max Damage",          apply = function() player.dmgMax = player.dmgMax + 2 end},
    {name = "+1 Suit Armor",          apply = function() player.armor = player.armor + 1 end},
    {name = "+15 Sanity restored",    apply = function() player.sanity = min(100, player.sanity + 15) end},
    {name = "+3 Crit Range",          apply = function() player.critBonus = min(25, player.critBonus + 3) end},
}

local function resetGame()
    game.state = "playing"
    game.sector = 1
    game.turn = 0
    game.messages = {}
    game.particles = {}
    game.marsWhisperTimer = 0
    game.won = false

    player.hp = 30; player.maxHp = 30
    player.str = 55; player.def = 40
    player.dmgMin = 2; player.dmgMax = 5
    player.armor = 0
    player.xp = 0; player.xpNext = 20
    player.level = 1
    player.sanity = 100; player.oxygen = 100
    player.medkits = 1; player.cells = 0
    player.cellsNeeded = 3
    player.kills = 0; player.critBonus = 5
    player.seen = {}

    addMessage("Arrows: move/attack. M: medkit. Escape Mars alive.", 180, 180, 220)
    addMessage("Don't lose your mind. Don't say the word.", 200, 60, 80)
    newFloor()
end

-- Player action
local function tryMove(dx, dy)
    if game.state ~= "playing" then return end

    local nx, ny = player.x + dx, player.y + dy

    local e = enemyAt(nx, ny)
    if e then
        resolveMelee(player, e, "You", e.name, player.str, e.def, player.dmgMin, player.dmgMax)
        checkEnemyDeath(e)
        if game.state ~= "dead" and game.state ~= "mindmarr" then
            game.turn = game.turn + 1
            moveEnemies()
            -- Mars whispers every N turns
            game.marsWhisperTimer = game.marsWhisperTimer + 1
            if game.marsWhisperTimer >= (8 - min(5, game.sector)) then
                game.marsWhisperTimer = 0
                marsWhisper()
            end
        end
        dimFOV(); computeFOV()
        checkSanityDeath()
        return
    end

    if tileAt(nx, ny) == 0 then
        player.x = nx; player.y = ny

        -- Items
        for i = #items, 1, -1 do
            local it = items[i]
            if it.x == nx and it.y == ny then
                if it.type == "supply" then
                    player.xp = player.xp + it.amount
                    addMessage("Scavenged supplies (+" .. it.amount .. " XP)", C.supply[1], C.supply[2], C.supply[3])
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 6, 100, 220, 140, 40, 0.3)
                    if player.xp >= player.xpNext then
                        game.state = "levelup"
                        player.level = player.level + 1
                        player.xpNext = floor(player.xpNext * 1.6)
                        addMessage("*** ADAPT — Level " .. player.level .. " ***", 255, 255, 100)
                        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 25, 60, 200, 255, 120, 0.8)
                    end
                elseif it.type == "medkit" then
                    player.medkits = player.medkits + 1
                    addMessage("Found a medkit!", 100, 255, 150)
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 6, 100, 255, 150, 40, 0.3)
                elseif it.type == "cell" then
                    player.cells = player.cells + 1
                    addMessage("POWER CELL acquired! (" .. player.cells .. "/" .. player.cellsNeeded .. ")", C.cell[1], C.cell[2], C.cell[3])
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 12, 180, 60, 200, 60, 0.5)
                    screenShake(2, 0.1)
                elseif it.type == "oxygen" then
                    local o2 = rand(10, 20)
                    player.oxygen = min(100, player.oxygen + o2)
                    addMessage("O2 canister: +" .. o2 .. " oxygen", C.oxygen[1], C.oxygen[2], C.oxygen[3])
                    spawnParticles(nx * TS + TS/2, ny * TS + TS/2, 6, 80, 200, 220, 40, 0.3)
                end
                table.remove(items, i)
            end
        end

        -- Shuttle/airlock
        if nx == shuttle.x and ny == shuttle.y then
            if game.sector == game.maxSectors then
                -- Final escape
                if player.cells >= player.cellsNeeded then
                    game.state = "won"
                    game.won = true
                    addMessage("You ignite the shuttle engines!", 255, 255, 100)
                    addMessage("ESCAPED! Mars screams behind you.", 80, 255, 120)
                    spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 50, 255, 220, 80, 200, 1.5)
                    screenShake(6, 0.5)
                    return
                else
                    addMessage("Shuttle needs " .. (player.cellsNeeded - player.cells) .. " more power cells!", 255, 100, 100)
                end
            else
                game.sector = game.sector + 1
                newFloor()
                return
            end
        end

        game.turn = game.turn + 1
        moveEnemies()

        game.marsWhisperTimer = game.marsWhisperTimer + 1
        if game.marsWhisperTimer >= (8 - min(5, game.sector)) then
            game.marsWhisperTimer = 0
            marsWhisper()
        end

        dimFOV(); computeFOV()
        checkSanityDeath()
    end
end

local function useMedkit()
    if player.medkits > 0 and player.hp < player.maxHp then
        player.medkits = player.medkits - 1
        local heal = floor(player.maxHp * 0.4) + rand(1, 5)
        player.hp = min(player.maxHp, player.hp + heal)
        addMessage("Used medkit: +" .. heal .. " HP", 100, 255, 150)
        spawnParticles(player.x * TS + TS/2, player.y * TS + TS/2, 10, 100, 255, 150, 50, 0.4)
        game.turn = game.turn + 1
        moveEnemies()
        dimFOV(); computeFOV()
    end
end

-- Input
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
    local mapAreaH = floor(H * 0.65)

    if px < -TS or px > W + TS or py < -TS or py > mapAreaH + TS then return end

    local vis = isVisible(tx, ty)
    local seen = isSeen(tx, ty)
    local tile = tileAt(tx, ty)

    if not seen then
        bridge.drawRect(px, py, TS, TS, C.void[1], C.void[2], C.void[3], 255)
        return
    end

    local dim = vis and 1.0 or 0.3

    -- Mars pulse — faint red flicker on walls when deep
    local marsPulse = 0
    if vis and game.sector > 2 then
        marsPulse = sin(game.pulseTimer * 2 + tx * 0.3 + ty * 0.5) * 8 * (game.sector / game.maxSectors)
    end

    if tile == 1 then
        local cr, cg, cb = C.wall[1], C.wall[2], C.wall[3]
        if (tx + ty) % 3 == 0 then cr, cg, cb = C.wallHi[1], C.wallHi[2], C.wallHi[3] end
        cr = min(255, cr + marsPulse)
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if vis and ty > 1 and tileAt(tx, ty-1) == 0 then
            bridge.drawRect(px, py, TS, 2, floor(100*dim), floor(50*dim), floor(40*dim), 255)
        end
    else
        local cr, cg, cb = C.floor[1], C.floor[2], C.floor[3]
        if vis then cr, cg, cb = C.floorLit[1], C.floorLit[2], C.floorLit[3] end
        cr = min(255, cr + marsPulse * 0.5)
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if (tx * 7 + ty * 13) % 11 == 0 then
            bridge.drawRect(px + 4, py + 4, 2, 2, floor(cr*dim*0.6), floor(cg*dim*0.6), floor(cb*dim*0.6), 255)
        end
        -- Mars dust particles on floors in deeper sectors
        if vis and game.sector >= 3 and (tx * 3 + ty * 7) % 17 == 0 then
            bridge.drawRect(px + rand(2, TS-4), py + rand(2, TS-4), 1, 1, 140, 50, 30, 60)
        end
    end
end

function DrawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = floor((rand() - 0.5) * game.shakeIntensity * 2)
        sy = floor((rand() - 0.5) * game.shakeIntensity * 2)
    end

    bridge.drawRect(0, 0, W, H, C.void[1], C.void[2], C.void[3], 255)

    -- TITLE
    if game.state == "title" then
        bridge.drawRect(0, 0, W, H, 8, 3, 6, 255)
        -- Mars surface line
        for x = 0, W, 4 do
            local yy = H * 0.55 + sin(x * 0.02 + game.pulseTimer) * 8
            bridge.drawRect(x, yy, 4, H - yy, 50, 15, 10, 80)
        end

        bridge.drawText("M I N D M A R R", W/2 - 70, H/4 - 10, 255, 40, 50, 255)
        bridge.drawText("Mars is alive. Mars remembers.", W/2 - 105, H/4 + 18, 180, 60, 70, 255)

        bridge.drawText("You are a survivor. The colony is lost.", W/2 - 130, H/2 - 20, 160, 140, 150, 255)
        bridge.drawText("Everyone speaks only one word now.", W/2 - 120, H/2, 160, 140, 150, 255)
        bridge.drawText("If you say it, you join them.", W/2 - 100, H/2 + 20, 200, 60, 70, 255)

        bridge.drawText("Arrow Keys: Move & Fight", W/2 - 85, H/2 + 55, 140, 140, 160, 255)
        bridge.drawText("M: Medkit    Reach the shuttle.", W/2 - 100, H/2 + 75, 140, 140, 160, 255)

        local flicker = sin(game.pulseTimer * 3) > 0 and 255 or 180
        bridge.drawText("PRESS SPACE", W/2 - 40, H * 0.82, flicker, flicker, min(255, flicker + 20), 255)
        return
    end

    -- WON
    if game.state == "won" then
        bridge.drawRect(0, 0, W, H, 4, 8, 15, 255)
        -- Stars
        for i = 1, 60 do
            local sx2 = (i * 137 + floor(game.pulseTimer * 10)) % W
            local sy2 = (i * 211) % H
            bridge.drawRect(sx2, sy2, 1, 1, 255, 255, 255, rand(100, 255))
        end

        bridge.drawText("E S C A P E D", W/2 - 55, H/4, 80, 255, 120, 255)
        bridge.drawText("Mars screams behind you, but you don't look back.", W/2 - 170, H/4 + 30, 160, 200, 180, 255)

        bridge.drawText("Level: " .. player.level .. "  Kills: " .. player.kills, W/2 - 70, H/2, 200, 200, 220, 255)
        bridge.drawText("Sanity: " .. player.sanity .. "%  O2: " .. player.oxygen .. "%", W/2 - 80, H/2 + 20, C.sanity[1], C.sanity[2], C.sanity[3], 255)
        bridge.drawText("Cells: " .. player.cells .. "  Sectors cleared: " .. game.maxSectors, W/2 - 100, H/2 + 40, C.cell[1], C.cell[2], C.cell[3], 255)

        local score = player.kills * 10 + player.sanity * 5 + player.oxygen * 2 + game.maxSectors * 100
        bridge.drawText("Score: " .. score, W/2 - 35, H/2 + 70, 255, 220, 80, 255)

        bridge.drawText("PRESS SPACE TO PLAY AGAIN", W/2 - 90, H * 0.8, 180, 180, 200, 255)
        return
    end

    -- MINDMARR (sanity death)
    if game.state == "mindmarr" then
        local pulse = sin(game.pulseTimer * 4) * 0.3 + 0.7
        bridge.drawRect(0, 0, W, H, floor(30 * pulse), floor(5 * pulse), floor(8 * pulse), 255)

        bridge.drawText("m i n d m a r r", W/2 - 60, H/4, 255, floor(40 * pulse), floor(50 * pulse), 255)
        bridge.drawText("You are one of them now.", W/2 - 80, H/4 + 30, 200, 60, 70, 255)
        bridge.drawText("Your mouth only forms one word.", W/2 - 110, H/4 + 55, 180, 50, 60, 255)

        -- Scrolling mindmarr text
        for i = 0, 12 do
            local yy = H/2 + 10 + i * 16
            local off = floor(game.pulseTimer * 40 + i * 50) % W
            local alpha = max(40, 200 - i * 15)
            bridge.drawText("mindmarr mindmarr mindmarr mindmarr mindmarr", -off + W/2, yy,
                floor(200 * pulse), 30, 40, alpha)
        end

        bridge.drawText("Floor: " .. game.sector .. "  Level: " .. player.level .. "  Kills: " .. player.kills, W/4, H * 0.82, 200, 200, 200, 200)
        bridge.drawText("PRESS SPACE", W/2 - 40, H * 0.9, 180, 100, 110, 255)
        return
    end

    local camOX = floor(W/2 - player.x * TS - TS/2)
    local camOY = floor(H * 0.4 - player.y * TS - TS/2)
    local mapAreaH = floor(H * 0.65)

    -- Map tiles
    local startTX = max(1, floor(-camOX / TS) - 1)
    local endTX = min(MW, floor((-camOX + W) / TS) + 2)
    local startTY = max(1, floor(-camOY / TS) - 1)
    local endTY = min(MH, floor((-camOY + mapAreaH) / TS) + 2)

    for ty = startTY, endTY do
        for tx = startTX, endTX do
            drawTile(sx, sy, tx, ty)
        end
    end

    -- Shuttle/airlock
    if isVisible(shuttle.x, shuttle.y) then
        local stX = camOX + shuttle.x * TS + sx
        local stY = camOY + shuttle.y * TS + sy
        if game.sector == game.maxSectors then
            -- Shuttle glow
            local glow = sin(game.pulseTimer * 3) * 20 + 220
            bridge.drawRect(stX + 2, stY + 2, TS - 4, TS - 4, floor(glow), floor(glow * 0.85), 40, 255)
            bridge.drawRect(stX + 5, stY + 5, TS - 10, TS - 10, 200, 180, 60, 255)
            bridge.drawText("^", stX + 8, stY + 4, 255, 255, 200, 255)
        else
            bridge.drawRect(stX + 4, stY + 4, TS - 8, TS - 8, C.shuttle[1], C.shuttle[2], C.shuttle[3], 255)
            bridge.drawText(">", stX + 8, stY + 5, 255, 240, 180, 255)
        end
    elseif isSeen(shuttle.x, shuttle.y) then
        local stX = camOX + shuttle.x * TS + sx
        local stY = camOY + shuttle.y * TS + sy
        bridge.drawRect(stX + 4, stY + 4, TS - 8, TS - 8, 60, 50, 25, 255)
    end

    -- Items
    for _, it in ipairs(items) do
        if isVisible(it.x, it.y) then
            local ix = camOX + it.x * TS + sx
            local iy = camOY + it.y * TS + sy
            if it.type == "supply" then
                bridge.drawRect(ix + 7, iy + 7, 10, 10, C.supply[1], C.supply[2], C.supply[3], 255)
                bridge.drawRect(ix + 9, iy + 9, 5, 5, 140, 255, 180, 255)
            elseif it.type == "medkit" then
                bridge.drawRect(ix + 6, iy + 6, 12, 12, 255, 80, 80, 255)
                bridge.drawRect(ix + 10, iy + 7, 4, 10, 255, 255, 255, 255)
                bridge.drawRect(ix + 7, iy + 10, 10, 4, 255, 255, 255, 255)
            elseif it.type == "cell" then
                local cg = sin(game.pulseTimer * 4) * 40 + 180
                bridge.drawRect(ix + 5, iy + 4, 14, 16, floor(cg), 50, floor(cg * 1.1), 255)
                bridge.drawRect(ix + 8, iy + 7, 8, 10, 220, 80, 240, 255)
            elseif it.type == "oxygen" then
                bridge.drawRect(ix + 7, iy + 5, 10, 14, C.oxygen[1], C.oxygen[2], C.oxygen[3], 255)
                bridge.drawRect(ix + 9, iy + 3, 6, 4, 60, 160, 180, 255)
            end
        end
    end

    -- Enemies
    for _, e in ipairs(enemies) do
        if e.alive and isVisible(e.x, e.y) then
            local ex = camOX + e.x * TS + sx
            local ey = camOY + e.y * TS + sy
            -- Red pulsing aura
            local aura = sin(game.pulseTimer * 5 + e.x) * 15
            bridge.drawRect(ex + 2, ey + 2, TS - 4, TS - 4,
                min(255, e.color[1] + floor(aura)), min(255, e.color[2]), min(255, e.color[3]), 255)
            bridge.drawRect(ex + 5, ey + 5, TS - 10, TS - 10,
                min(255, e.color[1]+30), min(255, e.color[2]+20), min(255, e.color[3]+20), 255)
            -- HP bar
            if e.hp < e.maxHp then
                local barW = TS - 4
                local hpFrac = e.hp / e.maxHp
                bridge.drawRect(ex + 2, ey - 3, barW, 3, 40, 10, 15, 200)
                bridge.drawRect(ex + 2, ey - 3, floor(barW * hpFrac), 3, 255, 40, 50, 255)
            end
        end
    end

    -- Player
    if game.state ~= "dead" then
        local px_draw = camOX + player.x * TS + sx
        local py_draw = camOY + player.y * TS + sy
        -- Suit
        bridge.drawRect(px_draw + 2, py_draw + 2, TS - 4, TS - 4, C.player[1], C.player[2], C.player[3], 255)
        bridge.drawRect(px_draw + 5, py_draw + 5, TS - 10, TS - 10, 100, 220, 255, 255)
        -- Visor
        bridge.drawRect(px_draw + 7, py_draw + 6, 10, 5, 20, 60, 80, 255)
        bridge.drawRect(px_draw + 8, py_draw + 7, 8, 3, 40, 140, 180, 255)
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

    -- HUD
    local hudY = mapAreaH + 2
    local hudH = H - hudY
    bridge.drawRect(0, hudY, W, hudH, C.hud_bg[1], C.hud_bg[2], C.hud_bg[3], 255)
    bridge.drawRect(0, hudY, W, 2, C.hud_border[1], C.hud_border[2], C.hud_border[3], 255)

    local col1 = 10
    local ly = hudY + 6

    -- Row 1: Level, Sector
    bridge.drawText("LVL:" .. player.level, col1, ly, 255, 255, 150, 255)
    bridge.drawText("SECTOR:" .. game.sector .. "/" .. game.maxSectors, col1 + 55, ly, 255, 180, 100, 255)

    ly = ly + 14

    -- Row 2: HP bar
    bridge.drawText("HP:", col1, ly, 200, 200, 200, 255)
    local barX = col1 + 28
    local barW = 80
    local barH = 10
    bridge.drawRect(barX, ly, barW, barH, 40, 10, 15, 255)
    local hpW = floor(barW * (player.hp / player.maxHp))
    local hpR = player.hp <= player.maxHp * 0.3 and 255 or 50
    local hpG = player.hp <= player.maxHp * 0.3 and 50 or 200
    bridge.drawRect(barX, ly, hpW, barH, hpR, hpG, 50, 255)
    bridge.drawText(player.hp .. "/" .. player.maxHp, barX + barW + 4, ly, 200, 200, 200, 255)

    -- Sanity bar
    local sanX = barX + barW + 55
    bridge.drawText("SAN:", sanX, ly, C.sanity[1], C.sanity[2], C.sanity[3], 255)
    local sanBarX = sanX + 32
    bridge.drawRect(sanBarX, ly, 60, barH, 20, 20, 40, 255)
    local sanW = floor(60 * (player.sanity / 100))
    local sanR = player.sanity <= 25 and 200 or C.sanity[1]
    local sanG = player.sanity <= 25 and 50 or C.sanity[2]
    bridge.drawRect(sanBarX, ly, sanW, barH, sanR, sanG, C.sanity[3], 255)
    bridge.drawText(player.sanity .. "%", sanBarX + 63, ly, C.sanity[1], C.sanity[2], C.sanity[3], 255)

    ly = ly + 14

    -- Row 3: Stats
    bridge.drawText("STR:" .. player.str .. " DEF:" .. player.def .. " DMG:" .. player.dmgMin .. "-" .. player.dmgMax, col1, ly, 180, 160, 170, 255)

    -- O2
    local o2X = 260
    bridge.drawText("O2:", o2X, ly, C.oxygen[1], C.oxygen[2], C.oxygen[3], 255)
    bridge.drawText(player.oxygen .. "%", o2X + 24, ly, C.oxygen[1], C.oxygen[2], C.oxygen[3], 255)

    ly = ly + 14

    -- Row 4: Items
    bridge.drawText("ARM:" .. player.armor .. " CRIT:<=" .. player.critBonus, col1, ly, 160, 150, 170, 255)
    bridge.drawText("XP:" .. player.xp .. "/" .. player.xpNext, col1 + 160, ly, C.xp[1], C.xp[2], C.xp[3], 255)

    ly = ly + 14

    -- Row 5
    bridge.drawText("Medkits:" .. player.medkits, col1, ly, 255, 100, 100, 255)
    bridge.drawText("Cells:" .. player.cells .. "/" .. player.cellsNeeded, col1 + 90, ly, C.cell[1], C.cell[2], C.cell[3], 255)
    bridge.drawText("Kills:" .. player.kills, col1 + 210, ly, 200, 140, 140, 255)

    -- Message log
    local msgX = W/2 + 20
    local msgY = hudY + 8
    bridge.drawText("-- Transmission Log --", msgX, msgY, 100, 70, 90, 255)
    for i, msg in ipairs(game.messages) do
        local alpha = max(80, 255 - i * 25)
        bridge.drawText(msg.text, msgX, msgY + i * 13, msg.r, msg.g, msg.b, alpha)
        if msgY + i * 13 > H - 5 then break end
    end

    -- Level up overlay
    if game.state == "levelup" then
        bridge.drawRect(W/4, H/4, W/2, H/2, 10, 8, 20, 240)
        bridge.drawRect(W/4, H/4, W/2, 2, 60, 200, 255, 255)
        bridge.drawText("ADAPT — Choose an upgrade:", W/4 + 20, H/4 + 12, 100, 230, 255, 255)
        for i, choice in ipairs(levelChoices) do
            local y = H/4 + 30 + (i-1) * 22
            bridge.drawRect(W/4 + 15, y, W/2 - 30, 18, 25, 18, 40, 200)
            bridge.drawText(i .. ") " .. choice.name, W/4 + 22, y + 2, 200, 220, 240, 255)
        end
    end

    -- Death overlay
    if game.state == "dead" then
        bridge.drawRect(W/4, H/3, W/2, H/4, 25, 5, 8, 230)
        bridge.drawRect(W/4, H/3, W/2, 2, 255, 40, 50, 255)
        bridge.drawText("SIGNAL LOST", W/4 + 55, H/3 + 15, 255, 50, 60, 255)
        bridge.drawText("Sector: " .. game.sector .. "  Level: " .. player.level .. "  Kills: " .. player.kills, W/4 + 15, H/3 + 35, 200, 200, 200, 255)
        local score = player.kills * 10 + game.sector * 50
        bridge.drawText("Score: " .. score, W/4 + 60, H/3 + 52, 255, 200, 80, 255)
        bridge.drawText("PRESS SPACE TO TRY AGAIN", W/4 + 25, H/3 + 75, 180, 180, 180, 255)
    end
end

-- Main update
function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    local dt = 0.016

    game.pulseTimer = game.pulseTimer + dt

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

    for _, msg in ipairs(game.messages) do
        msg.age = msg.age + dt
    end

    -- Title
    if game.state == "title" then
        if keyPressed("space") then resetGame() end
        return
    end

    -- Dead / mindmarr / won
    if game.state == "dead" or game.state == "mindmarr" or game.state == "won" then
        if keyPressed("space") then resetGame() end
        return
    end

    -- Level up
    if game.state == "levelup" then
        for i = 1, #levelChoices do
            if keyPressed(tostring(i)) then
                levelChoices[i].apply()
                addMessage("Adapted: " .. levelChoices[i].name, 100, 230, 255)
                game.state = "playing"
                break
            end
        end
        return
    end

    -- Playing
    game.inputCooldown = max(0, game.inputCooldown - dt)

    if game.state == "playing" then
        if keyPressed("up") or keyPressed("w") then tryMove(0, -1)
        elseif keyPressed("down") or keyPressed("s") then tryMove(0, 1)
        elseif keyPressed("left") or keyPressed("a") then tryMove(-1, 0)
        elseif keyPressed("right") or keyPressed("d") then tryMove(1, 0)
        elseif keyPressed("m") then useMedkit()
        end
    end
end

function DrawUI()
    DrawGame()
end
-- netrogue/localgame.lua
-- Client-side singleplayer game logic

local MapGen = require("mapgen")
local Entities = require("entities")
local Config = require("config")
local MessageLog = require("messagelog")
local GameState = require("gamestate")

local LocalGame = { goblins = {}, initialized = false }

local function d100() return math.random(1, 100) end

function LocalGame.init()
    for i = 1, 3 do
        local room = MapGen.rooms[math.random(2, #MapGen.rooms)]
        local gx = math.random(room.x, room.x + room.w - 1)
        local gy = math.random(room.y, room.y + room.h - 1)
        LocalGame.goblins[i] = {
            id = i, x = gx, y = gy, hp = 12, maxHp = 12,
            attack = 15, defense = 25, alive = true
        }
        Entities.updateGoblin(i, gx, gy, 12, 12)
    end
    LocalGame.initialized = true
end

function LocalGame.playerMove(nx, ny)
    if not MapGen.isWalkable(nx, ny) then return false end
    
    -- Check goblin collision
    for _, g in pairs(LocalGame.goblins) do
        if g.alive and g.x == nx and g.y == ny then
            LocalGame.combat(true, g)
            return false
        end
    end
    
    Entities.player.x, Entities.player.y = nx, ny
    require("fov").compute()
    LocalGame.goblinTurn()
    return true
end

function LocalGame.combat(playerAttacking, goblin)
    local p = Entities.player
    local roll = d100()
    
    if playerAttacking then
        if roll <= p.attack then
            local dmg = math.random(2, 5)
            if roll <= 5 then dmg = dmg * 2 end
            goblin.hp = goblin.hp - dmg
            MessageLog.add("You hit Goblin for " .. dmg, Config.C.combat_hit)
            Entities.updateGoblin(goblin.id, goblin.x, goblin.y, goblin.hp, goblin.maxHp)
            
            if goblin.hp <= 0 then
                goblin.alive = false
                Entities.killGoblin(goblin.id)
                p.kills, p.xp = p.kills + 1, p.xp + 10
                MessageLog.add("Goblin slain!", Config.C.goblinHurt)
                
                if p.xp >= p.xpNext then
                    p.level = p.level + 1
                    p.attack = math.min(90, p.attack + 3)
                    p.maxHp, p.hp = p.maxHp + 2, p.maxHp + 2
                    p.xpNext = p.xpNext + 20
                    MessageLog.add("LEVEL UP! Lv." .. p.level, Config.C.levelup)
                end
            end
            GameState.screenShake(3, 0.1)
        else
            MessageLog.add("You miss!", Config.C.combat_miss)
        end
    else
        if roll <= goblin.attack then
            local dmg = math.random(1, 4)
            p.hp = p.hp - dmg
            MessageLog.add("Goblin hits for " .. dmg, Config.C.combat_hit)
            if p.hp <= 0 then
                p.hp, p.dead = 0, true
                MessageLog.add("You died!", {255, 50, 50})
                GameState.screenShake(8, 0.4)
            end
        else
            MessageLog.add("Goblin misses!", Config.C.combat_miss)
        end
    end
end

function LocalGame.goblinTurn()
    local p = Entities.player
    for _, g in pairs(LocalGame.goblins) do
        if g.alive and not p.dead then
            local dist = math.abs(p.x - g.x) + math.abs(p.y - g.y)
            if dist == 1 then
                LocalGame.combat(false, g)
            elseif dist <= 6 then
                local dx = p.x > g.x and 1 or (p.x < g.x and -1 or 0)
                local dy = p.y > g.y and 1 or (p.y < g.y and -1 or 0)
                if math.abs(p.x - g.x) < math.abs(p.y - g.y) then dx = 0 else dy = 0 end
                local nx, ny = g.x + dx, g.y + dy
                if MapGen.isWalkable(nx, ny) and not (p.x == nx and p.y == ny) then
                    g.x, g.y = nx, ny
                    Entities.updateGoblin(g.id, g.x, g.y, g.hp, g.maxHp)
                end
            end
        end
    end
end

function LocalGame.respawn()
    local p = Entities.player
    p.hp, p.dead, p.xp = p.maxHp, false, 0
    p.x, p.y = MapGen.rooms[1].cx, MapGen.rooms[1].cy
    MessageLog.add("Respawned!", Config.C.net_ok)
    require("fov").compute()
end

return LocalGame
-- netrogue/entities.lua
-- Player, other players, and goblins

local Network = require("network")
local MapGen = require("mapgen")

local Entities = {
    player = {
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
    },
    
    others = {},   -- Other players keyed by ID
    goblins = {},  -- Goblins keyed by ID
}

function Entities.tryMove(dx, dy)
    if Entities.player.dead then return end
    
    local nx = Entities.player.x + dx
    local ny = Entities.player.y + dy
    
    -- Client-side prediction - only send if walkable
    if not MapGen.isWalkable(nx, ny) then return end
    
    -- Check if goblin is there (bump attack)
    local g = Entities.getGoblinAt(nx, ny)
    if g then
        -- Send the move intent; server will resolve it as bump combat
        Network.sendMove(nx, ny)
        return
    end
    
    -- Optimistic client-side prediction
    Entities.player.x = nx
    Entities.player.y = ny
    Network.sendMove(nx, ny)
    
    -- Update FOV
    local FOV = require("netrogue.fov")
    FOV.compute()
end

function Entities.getGoblinAt(x, y)
    for _, g in pairs(Entities.goblins) do
        if g.alive and g.x == x and g.y == y then
            return g
        end
    end
    return nil
end

function Entities.setPlayerPosition(x, y)
    Entities.player.x = x
    Entities.player.y = y
end

function Entities.updateOtherPlayer(id, x, y)
    if not Entities.others[id] then
        Entities.others[id] = {}
    end
    Entities.others[id].x = x
    Entities.others[id].y = y
end

function Entities.removeOtherPlayer(id)
    Entities.others[id] = nil
end

function Entities.updateGoblin(id, x, y, hp, maxHp)
    if not Entities.goblins[id] then
        Entities.goblins[id] = {}
    end
    local g = Entities.goblins[id]
    g.x = x
    g.y = y
    g.hp = hp or g.hp
    g.maxHp = maxHp or g.maxHp
    g.alive = true
end

function Entities.killGoblin(id)
    if Entities.goblins[id] then
        Entities.goblins[id].alive = false
    end
end

function Entities.removeGoblin(id)
    Entities.goblins[id] = nil
end

function Entities.updatePlayerStats(hp, maxHp, attack, level, kills, xp, xpNext)
    local p = Entities.player
    p.hp = hp
    p.maxHp = maxHp
    p.attack = attack
    p.level = level
    p.kills = kills
    p.xp = xp
    p.xpNext = xpNext
    p.dead = (hp <= 0)
end

return Entities
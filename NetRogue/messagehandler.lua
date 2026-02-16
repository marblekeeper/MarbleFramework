-- netrogue/protocol.lua
-- Server message processing and protocol handling

local Network = require("network")
local MapGen = require("mapgen")
local Entities = require("entities")
local GameState = require("gamestate")
local MessageLog = require("messagelog")
local Particles = require("particles")
local Config = require("config")
local FOV = require("fov")

local ProtocolModule = require("protocol")

local Protocol = {}

function Protocol.processServerMessages()
    -- Early return in offline mode (WASM doesn't have network)
    if Network.OFFLINE_MODE then
        return
    end
    
    if not Network.connected or not Network.client then return end

    local lines = Network.receive()
    if not lines then return end

    for _, data in ipairs(lines) do
        Protocol.handleMessage(data)
    end
end

function Protocol.handleMessage(data)
    local C = Config.C
    local TS = Config.TS
    
    -- AUTH:OK with map seed
    if data:match("^" .. ProtocolModule.RESPONSE.AUTH_OK) then
        Entities.player.id = tonumber(data:match("ID:(%d+)"))
        Network.tick = tonumber(data:match("TICK:(%d+)")) or 0
        Network.map_seed = tonumber(data:match("SEED:(%d+)")) or 42
        Network.player_id = Entities.player.id
        Entities.player.connected = true
        Entities.player.dead = false
        GameState.state = "playing"
        Network.status_msg = "Player #" .. Entities.player.id

        -- Generate map from server seed (deterministic!)
        MapGen.generate(Network.map_seed)

        -- Spawn in room 1
        if #MapGen.rooms > 0 then
            Entities.player.x = MapGen.rooms[1].cx
            Entities.player.y = MapGen.rooms[1].cy
            Network.sendMove(Entities.player.x, Entities.player.y)
        end

        MessageLog.add("Connected as Player #" .. Entities.player.id, C.net_ok)
        MessageLog.add("WASD: move (bump goblins to fight!)", {160, 150, 180})
        MessageLog.add("Watch out — goblins hit back.", {200, 120, 100})
        FOV.compute()

    -- INTENT_ACK
    elseif data:match("^" .. ProtocolModule.RESPONSE.INTENT_ACK) then
        -- acknowledged

    -- POS (our confirmed position)
    elseif data:match("^" .. ProtocolModule.RESPONSE.POS) then
        local x, y, tick = data:match("^POS:([%-]?%d+),([%-]?%d+),TICK:(%d+)$")
        if x and y then
            Entities.setPlayerPosition(tonumber(x), tonumber(y))
            if tick then Network.tick = tonumber(tick) end
            FOV.compute()
        else
            x, y = data:match("^POS:([%-]?%d+),([%-]?%d+)$")
            if x and y then
                Entities.setPlayerPosition(tonumber(x), tonumber(y))
                FOV.compute()
            end
        end

    -- STATS (our stats from server)
    elseif data:match("^STATS:") then
        local hp, maxHp, atk, lvl, kills, xp, xpNext =
            data:match("^STATS:(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
        if hp then
            Entities.updatePlayerStats(
                tonumber(hp), tonumber(maxHp), tonumber(atk),
                tonumber(lvl), tonumber(kills), tonumber(xp), tonumber(xpNext)
            )
        end

    -- COMBAT (broadcast message)
    elseif data:match("^COMBAT:") then
        local msg = data:match("^COMBAT:(.+)$")
        if msg then
            local color = C.combat_miss
            if msg:match("CRITS") then
                color = C.combat_crit
                GameState.screenShake(5, 0.2)
            elseif msg:match("hits") then
                color = C.combat_hit
                GameState.screenShake(3, 0.1)
            end
            MessageLog.add(msg, color)
        end

    -- GOBLIN_SPAWN
    elseif data:match("^GOBLIN_SPAWN:") then
        local id, x, y, hp, maxHp = data:match("^GOBLIN_SPAWN:(%d+),(%d+),(%d+),(%d+),(%d+)$")
        if id then
            Entities.updateGoblin(tonumber(id), tonumber(x), tonumber(y), tonumber(hp), tonumber(maxHp))
            MessageLog.add("A goblin appears!", C.goblin)
            Particles.spawn(tonumber(x) * TS + TS/2, tonumber(y) * TS + TS/2,
                8, C.goblin[1], C.goblin[2], C.goblin[3], 40, 0.4)
        end

    -- GOBLIN_MOVE
    elseif data:match("^GOBLIN_MOVE:") then
        local id, x, y = data:match("^GOBLIN_MOVE:(%d+),([%-]?%d+),([%-]?%d+)$")
        if id then
            local goblin = Entities.goblins[tonumber(id)]
            if goblin then
                Entities.updateGoblin(tonumber(id), tonumber(x), tonumber(y))
            end
        end

    -- GOBLIN_HP
    elseif data:match("^GOBLIN_HP:") then
        local id, hp, maxHp = data:match("^GOBLIN_HP:(%d+),([%-]?%d+),(%d+)$")
        if id then
            local goblin = Entities.goblins[tonumber(id)]
            if goblin then
                goblin.hp = tonumber(hp)
                goblin.maxHp = tonumber(maxHp)
            end
        end

    -- GOBLIN_DEATH
    elseif data:match("^GOBLIN_DEATH:") then
        local id, x, y = data:match("^GOBLIN_DEATH:(%d+),(%d+),(%d+)$")
        if id then
            Entities.killGoblin(tonumber(id))
            MessageLog.add("Goblin #" .. id .. " slain!", C.goblinHurt)
            Particles.spawn(tonumber(x) * TS + TS/2, tonumber(y) * TS + TS/2,
                15, C.goblin[1], 220, 60, 80, 0.5)
            GameState.screenShake(4, 0.15)
        end

    -- PLAYER_HP (other player's HP changed)
    elseif data:match("^PLAYER_HP:") then
        local id, hp, maxHp = data:match("^PLAYER_HP:(%d+),([%-]?%d+),(%d+)$")
        if id then
            id = tonumber(id)
            if id == Entities.player.id then
                Entities.player.hp = tonumber(hp)
                if Entities.player.hp <= 0 then
                    Entities.player.dead = true
                    GameState.screenShake(8, 0.4)
                end
            end
        end

    -- PLAYER_DEATH
    elseif data:match("^PLAYER_DEATH:") then
        local id = tonumber(data:match("^PLAYER_DEATH:(%d+)$"))
        if id == Entities.player.id then
            Entities.player.dead = true
            MessageLog.add("You have been slain!", {255, 50, 50})
            GameState.screenShake(8, 0.4)
            Particles.spawn(Entities.player.x * TS + TS/2, Entities.player.y * TS + TS/2,
                30, 200, 40, 50, 120, 0.8)
        else
            MessageLog.add("Player #" .. id .. " has fallen!", {200, 100, 100})
        end

    -- PLAYER_RESPAWN (us or others)
    elseif data:match("^PLAYER_RESPAWN:") then
        local id, x, y = data:match("^PLAYER_RESPAWN:(%d+),([%-]?%d+),([%-]?%d+)")
        if id then
            id = tonumber(id)
            if id == Entities.player.id then
                Entities.player.dead = false
                Entities.setPlayerPosition(tonumber(x), tonumber(y))
                FOV.compute()
                MessageLog.add("You have respawned!", C.net_ok)
                Particles.spawn(Entities.player.x * TS + TS/2, Entities.player.y * TS + TS/2,
                    15, 60, 200, 255, 60, 0.5)
            else
                Entities.updateOtherPlayer(id, tonumber(x), tonumber(y))
                MessageLog.add("Player #" .. id .. " respawned!", C.other)
            end
        end

    -- PLAYER_LEVELUP
    elseif data:match("^PLAYER_LEVELUP:") then
        local id, lvl, atk, hp, maxHp =
            data:match("^PLAYER_LEVELUP:(%d+),(%d+),(%d+),(%d+),(%d+)$")
        if id then
            id = tonumber(id)
            if id == Entities.player.id then
                MessageLog.add("LEVEL UP! Lv." .. lvl .. " ATK:" .. atk .. " HP:" .. hp, C.levelup)
                Particles.spawn(Entities.player.x * TS + TS/2, Entities.player.y * TS + TS/2,
                    20, 60, 200, 255, 100, 0.6)
                GameState.screenShake(3, 0.2)
            else
                MessageLog.add("Player #" .. id .. " leveled up!", C.xp)
            end
        end

    -- PLAYER_ACTION
    elseif data:match("^" .. ProtocolModule.RESPONSE.PLAYER_ACTION) then
        local action, tick = data:match("^PLAYER_ACTION:(%w+),TICK:(%d+)$")
        if action then
            Entities.player.state = action:lower()
            if tick then Network.tick = tonumber(tick) end
        end

    -- PLAYER_JOIN
    elseif data:match("^" .. ProtocolModule.RESPONSE.PLAYER_JOIN) then
        local id = tonumber(data:match("^PLAYER_JOIN:(%d+)"))
        if id and id ~= Entities.player.id then
            Entities.updateOtherPlayer(id, 0, 0)
            MessageLog.add("Player #" .. id .. " enters!", C.other)
        end

    -- PLAYER_MOVE
    elseif data:match("^" .. ProtocolModule.RESPONSE.PLAYER_MOVE) then
        local id, x, y = data:match("^PLAYER_MOVE:(%d+),([%-]?%d+),([%-]?%d+)")
        id = tonumber(id)
        if id and id ~= Entities.player.id then
            Entities.updateOtherPlayer(id, tonumber(x), tonumber(y))
        end

    -- PLAYER_LEAVE
    elseif data:match("^" .. ProtocolModule.RESPONSE.PLAYER_LEAVE) then
        local id = tonumber(data:match("^PLAYER_LEAVE:(%d+)"))
        if id then
            Entities.removeOtherPlayer(id)
            MessageLog.add("Player #" .. id .. " left", {150, 100, 100})
        end

    -- ERROR
    elseif data:match("^" .. ProtocolModule.RESPONSE.ERROR) then
        local errMsg = data:match("^ERROR:(.+)$") or data
        MessageLog.add("Server: " .. errMsg, C.net_err)

    else
        print("[NetRogue] Unknown: " .. data)
    end
end

return Protocol
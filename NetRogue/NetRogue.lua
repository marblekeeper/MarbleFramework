-- NetRogue.lua
-- NETROGUE: Networked ASCII Roguelike
-- Component-oriented architecture with server auth framework

-- ============================================================
-- FRAMEWORK COMPATIBILITY
-- ============================================================
local root = UIElement:new({width=800, height=600})

-- ============================================================
-- COMPONENT SYSTEM
-- ============================================================
local Config = require("config")
local Network = require("network")
local MapGen = require("mapgen")
local GameState = require("gamestate")
local Input = require("input")
local Renderer = require("renderer")
local Messages = require("messagehandler")
local Entities = require("entities")
local MessageLog = require("messagelog")
local Particles = require("particles")

-- LocalGame for offline singleplayer
local LocalGame = nil
if Network.OFFLINE_MODE then
    LocalGame = require("localgame")
end

-- ============================================================
-- INITIALIZATION
-- ============================================================
math.randomseed(os.time())
MapGen.generate(42) -- Fallback map
Network.connect()

-- ============================================================
-- MAIN CALLBACKS
-- ============================================================
function UpdateUI(mx, my, down, w, h)
    Config.W, Config.H = w, h
    root.width = w
    root.height = h
    local dt = 0.016

    GameState.updateTimers(dt)
    Particles.update(dt)
    MessageLog.update(dt)

-- State machine
if GameState.state == "connecting" then
    Network.updateConnecting(dt)
    
    -- OFFLINE MODE SHORTCUT
    if Network.OFFLINE_MODE and Network.connected then
        GameState.state = "playing"
        
        -- Initialize local game FIRST
        if LocalGame and not LocalGame.initialized then
            LocalGame.init()
            
            -- Set player starting position
            if #MapGen.rooms > 0 then
                Entities.player.x = MapGen.rooms[1].cx
                Entities.player.y = MapGen.rooms[1].cy
            end
        end
        
        -- THEN compute FOV
        local FOV = require("fov")
        FOV.compute()
        
        MessageLog.add("OFFLINE MODE - Local singleplayer", Config.C.net_wait)
    end
    
    -- ONLINE MODE: Always process server messages while connecting
    if not Network.OFFLINE_MODE then
        Messages.processServerMessages()
    end
    return
end

    if GameState.state == "disconnected" then
        if Input.keyPressed("space") then
            Network.resetAndReconnect()
            GameState.state = "connecting"
        end
        return
    end

    if GameState.state == "playing" then
        -- Process server messages (only in online mode)
        if not Network.OFFLINE_MODE then
            Messages.processServerMessages()
        end
        
        -- Handle respawn
        if Entities.player.dead then
            if Input.keyPressed("space") then
                if Network.OFFLINE_MODE then
                    -- Local respawn
                    LocalGame.respawn()
                else
                    -- Server respawn
                    Network.send("RESPAWN:\n")
                    MessageLog.add("Requesting respawn...", Config.C.net_wait)
                end
            end
            return
        end

        -- Handle movement
        local moved = false
        if Input.keyPressed("W") or Input.keyPressed("w") or Input.keyPressed("up") then
            moved = true
            if Network.OFFLINE_MODE then
                LocalGame.playerMove(Entities.player.x, Entities.player.y - 1)
            else
                Entities.tryMove(0, -1)
            end
        elseif Input.keyPressed("S") or Input.keyPressed("s") or Input.keyPressed("down") then
            moved = true
            if Network.OFFLINE_MODE then
                LocalGame.playerMove(Entities.player.x, Entities.player.y + 1)
            else
                Entities.tryMove(0, 1)
            end
        elseif Input.keyPressed("A") or Input.keyPressed("a") or Input.keyPressed("left") then
            moved = true
            if Network.OFFLINE_MODE then
                LocalGame.playerMove(Entities.player.x - 1, Entities.player.y)
            else
                Entities.tryMove(-1, 0)
            end
        elseif Input.keyPressed("D") or Input.keyPressed("d") or Input.keyPressed("right") then
            moved = true
            if Network.OFFLINE_MODE then
                LocalGame.playerMove(Entities.player.x + 1, Entities.player.y)
            else
                Entities.tryMove(1, 0)
            end
        end

        -- Handle actions (only in online mode)
        if not Network.OFFLINE_MODE then
            local ProtocolModule = require("protocol")
            if Input.keyPressed("P") or Input.keyPressed("p") then
                Network.sendAction(ProtocolModule.CMD.PRAY)
                Entities.player.state = "pray"
            elseif Input.keyPressed("I") or Input.keyPressed("i") then
                Network.sendAction(ProtocolModule.CMD.SIT)
                Entities.player.state = "sit"
            elseif Input.keyPressed("O") or Input.keyPressed("o") then
                Network.sendAction(ProtocolModule.CMD.STAND)
                Entities.player.state = "standing"
            elseif Input.keyPressed("M") or Input.keyPressed("m") then
                Network.sendAction(ProtocolModule.CMD.MEDITATE)
                Entities.player.state = "meditate"
            end
        end
    end
end

function DrawUI()
    if GameState.state == "connecting" then
        Renderer.drawConnecting()
    elseif GameState.state == "disconnected" then
        Renderer.drawDisconnected()
    elseif GameState.state == "playing" then
        Renderer.drawGame()
    end
end
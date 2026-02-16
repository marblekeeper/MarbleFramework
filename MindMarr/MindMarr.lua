-- MindMarr.lua
-- MINDMARR: Mars Becomes Mind
-- d100 Roll-Under Survival Horror — Escape the sentient planet
-- Arrow keys move, bump-to-attack, collect supplies, reach the shuttle
-- Say "MINDMARR" and it's the last word you ever say

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local max = math.max

-- Load modules
local state = require("state")
local K = require("constants")
local util = require("util")
local combat = require("combat")
local actions = require("actions")
local draw = require("draw")

local game = state.game
local player = state.player

-- Input
local function keyPressed(key)
    if not bridge.getKeyState then return false end
    local down = bridge.getKeyState(key) == 1
    local was = game.keyWasDown[key] or false
    game.keyWasDown[key] = down
    return down and not was
end

-- Main update
function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    draw.setSize(w, h)
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

    -- Animate Player
    if player.frameCount > 1 then
        player.animTimer = player.animTimer + dt
        local frameTime = 1.0 / player.animFPS
        if player.animTimer >= frameTime then
            player.animTimer = player.animTimer - frameTime
            player.currentFrame = player.currentFrame + 1
            if player.currentFrame > player.frameCount then
                player.currentFrame = 1
            end
        end
    end

    -- Animate enemies every render frame
    for _, e in ipairs(state.enemies) do
        if e.alive and e.frameCount and e.frameCount > 1 then
            e.animTimer = (e.animTimer or 0) + dt
            local frameTime = 1.0 / (e.animFPS or 5)
            if e.animTimer >= frameTime then
                e.animTimer = e.animTimer - frameTime
                if e.animState == "attack" then
                    e.currentFrame = e.currentFrame + 1
                    if e.currentFrame > e.frameCount then
                        e.animState = "idle"
                        e.currentFrame = 1
                    end
                else
                    -- Idle: alternate frame 1 and 2
                    e.currentFrame = (e.currentFrame == 1) and 2 or 1
                end
            end
        end
    end

    -- Title
    if game.state == "title" then
        if keyPressed("space") then actions.resetGame() end
        return
    end

    -- Dead / mindmarr / won
    if game.state == "dead" or game.state == "mindmarr" or game.state == "won" then
        if keyPressed("space") then actions.resetGame() end
        return
    end

    -- Level up
    if game.state == "levelup" then
        for i = 1, #K.levelChoices do
            if keyPressed(tostring(i)) then
                actions.applyLevelChoice(i)
                break
            end
        end
        return
    end

    -- Interaction Menu (Document/Terminal)
    if game.state == "interacting" then
        if keyPressed("1") then
            actions.resolveInteraction(1)
        elseif keyPressed("2") then
            actions.resolveInteraction(2)
        end
        return
    end
    
    -- Interaction Menu (Scrap)
    if game.state == "interacting_scrap" then
        local opts = game.interaction.options or {}
        for i = 1, #opts do
            if keyPressed(tostring(i)) then
                actions.resolveScrapInteraction(i)
                break
            end
        end
        return
    end

    -- Playing
    game.inputCooldown = max(0, game.inputCooldown - dt)

    if game.state == "playing" then
        if keyPressed("up") or keyPressed("w") then actions.tryMove(0, -1)
        elseif keyPressed("down") or keyPressed("s") then actions.tryMove(0, 1)
        elseif keyPressed("left") or keyPressed("a") then actions.tryMove(-1, 0)
        elseif keyPressed("right") or keyPressed("d") then actions.tryMove(1, 0)
        elseif keyPressed("m") then actions.useMedkit()
        end
    end
end

function DrawUI()
    draw.drawGame()
end 

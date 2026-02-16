-- util.lua
-- MINDMARR: Utility functions

local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, sqrt, max, min = math.abs, math.sqrt, math.max, math.min

local state = require("state")
local K = require("constants")

local game = state.game
local player = state.player

local M = {}

function M.spawnParticles(x, y, count, r, g, b, speed, life)
    for i = 1, count do
        local a = rand() * math.pi * 2
        local s = rand() * speed + speed * 0.2
        game.particles[#game.particles+1] = {
            x = x, y = y,
            vx = cos(a) * s, vy = sin(a) * s,
            life = life * (0.4 + rand() * 0.6),
            maxLife = life,
            r = r, g = g, b = b,
            -- UPDATED: Scale particles based on Tile Size (approx 10-15% of a tile)
            size = rand() < 0.3 and (K.TS * 0.15) or (K.TS * 0.1),
        }
    end
end

function M.screenShake(intensity, duration)
    game.shakeTimer = duration
    game.shakeIntensity = intensity
end

function M.addMessage(text, r, g, b)
    table.insert(game.messages, 1, {text = text, r = r or 200, g = g or 200, b = b or 200, age = 0})
    if #game.messages > game.maxMessages then
        table.remove(game.messages)
    end
end

function M.d100()
    return rand(1, 100)
end

-- FOV
function M.computeFOV()
    local radius = 6
    for a = 0, 359, 2 do
        local rad = a * math.pi / 180
        local dx = cos(rad)
        local dy = sin(rad)
        local fx, fy = player.x + 0.5, player.y + 0.5
        for d = 0, radius do
            local tx, ty = floor(fx), floor(fy)
            if tx < 1 or tx > K.MW or ty < 1 or ty > K.MH then break end
            player.seen[ty * 1000 + tx] = 2
            if M.tileAt(tx, ty) == 1 then break end
            fx = fx + dx * 0.5
            fy = fy + dy * 0.5
        end
    end
end

function M.dimFOV()
    for k, v in pairs(player.seen) do
        if v == 2 then player.seen[k] = 1 end
    end
end

function M.isVisible(x, y)
    return (player.seen[y * 1000 + x] or 0) == 2
end

function M.isSeen(x, y)
    return (player.seen[y * 1000 + x] or 0) >= 1
end

-- Tile helpers (need map access)
function M.tileAt(x, y)
    if x < 1 or x > K.MW or y < 1 or y > K.MH then return 1 end
    return state.map[y][x]
end

function M.setTile(x, y, v)
    if x >= 1 and x <= K.MW and y >= 1 and y <= K.MH then
        state.map[y][x] = v
    end
end

function M.enemyAt(x, y)
    for _, e in ipairs(state.enemies) do
        if e.alive and e.x == x and e.y == y then return e end
    end
    return nil
end

-- Mars whisper
function M.marsWhisper()
    if player.sanity > 0 then
        local drain = rand(1, 3)
        player.sanity = max(0, player.sanity - drain)
        local w = K.marsWhispers[rand(1, #K.marsWhispers)]
        M.addMessage(w, K.C.whisper[1], K.C.whisper[2], K.C.whisper[3])
        if player.sanity <= 0 then
            game.state = "mindmarr"
            M.addMessage("Your lips move on their own...", 255, 40, 60)
            M.addMessage("You whisper: \"mindmarr\"", 255, 20, 40)
            M.addMessage("It's the last word you ever say.", 255, 0, 0)
            M.screenShake(10, 0.6)
            M.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 50, 200, 30, 60, 150, 1.2)
        end
    end
end

return M
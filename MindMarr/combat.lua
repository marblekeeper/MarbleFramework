-- combat.lua
-- MINDMARR: Combat resolution, death checks, enemy AI

local rand, floor = math.random, math.floor
local abs, max, min = math.abs, math.max, math.min

local state = require("state")
local K = require("constants")
local util = require("util")

-- Attempt to load the audio module safely
local audioLoaded, audio = pcall(require, "audio")
if not audioLoaded then audio = nil end

local game = state.game
local player = state.player

local M = {}

function M.resolveMelee(attacker, defender, atkName, defName, atkStr, defDef, dmgMin, dmgMax, onDone)
    local roll = util.d100()
    local hit = roll <= atkStr
    local crit = false
    if attacker == player then crit = roll <= player.critBonus end

    -- Trigger attack animation for attacking enemy
    if attacker ~= player and attacker.frameCount and attacker.frameCount > 1 then
        attacker.animState = "attack"
        attacker.currentFrame = 2  -- Start attack anim at frame 2
        attacker.animTimer = 0
    end

    if not hit then
        util.addMessage(atkName .. " > " .. defName .. ": d100=" .. roll .. " vs " .. atkStr .. " MISS", K.C.miss[1], K.C.miss[2], K.C.miss[3])
        util.spawnParticles(defender.x * K.TS + K.TS/2, defender.y * K.TS + K.TS/2, 3, 100, 80, 80, 30, 0.3)
    else
        local dRoll = util.d100()
        local dodged = dRoll <= defDef

        if dodged then
            util.addMessage(defName .. " evades! d100=" .. dRoll .. " vs " .. defDef, K.C.miss[1], K.C.miss[2], K.C.miss[3])
            util.spawnParticles(defender.x * K.TS + K.TS/2, defender.y * K.TS + K.TS/2, 4, 150, 150, 255, 40, 0.3)
        else
            local dmg = rand(dmgMin, dmgMax)
            if crit then
                dmg = dmg * 2
                util.addMessage(atkName .. " CRITS " .. defName .. "! d100=" .. roll .. " DMG:" .. dmg, K.C.crit[1], K.C.crit[2], K.C.crit[3])
                util.screenShake(5, 0.2)
                util.spawnParticles(defender.x * K.TS + K.TS/2, defender.y * K.TS + K.TS/2, 15, 255, 200, 60, 80, 0.5)
            else
                util.addMessage(atkName .. " hits " .. defName .. " d100=" .. roll .. " DMG:" .. dmg, K.C.hit[1], K.C.hit[2], K.C.hit[3])
                util.screenShake(3, 0.1)
                util.spawnParticles(defender.x * K.TS + K.TS/2, defender.y * K.TS + K.TS/2, 8, 255, 80, 60, 60, 0.4)
            end

            if defender == player and player.armor > 0 then
                local reduced = max(1, dmg - player.armor)
                if reduced < dmg then
                    util.addMessage("  Suit absorbs " .. (dmg - reduced), 160, 160, 180)
                end
                dmg = reduced
            end

            defender.hp = defender.hp - dmg

            if defender == player and rand() < 0.3 then
                player.sanity = max(0, player.sanity - rand(1, 2))
                util.addMessage("  Your mind fractures...", K.C.whisper[1], K.C.whisper[2], K.C.whisper[3])
            end
        end
    end

    -- Infected scream mindmarr on attack
    if attacker ~= player then
        local say = K.MINDMARR_SAYS[rand(1, #K.MINDMARR_SAYS)]
        util.addMessage("  " .. atkName .. ": \"" .. say .. "\"", K.C.infected[1], K.C.infected[2], K.C.infected[3])
    end

    if onDone then onDone() end
end

function M.checkEnemyDeath(e)
    if e.hp <= 0 then
        e.alive = false
        util.addMessage(e.name .. " collapses: \"mind...marr...\" (+" .. e.xp .. " XP)", K.C.xp[1], K.C.xp[2], K.C.xp[3])
        util.spawnParticles(e.x * K.TS + K.TS/2, e.y * K.TS + K.TS/2, 20, e.color[1], e.color[2], e.color[3], 100, 0.6)
        util.screenShake(4, 0.15)
        player.xp = player.xp + e.xp
        player.kills = player.kills + 1

        if rand() < 0.4 then
            state.items[#state.items+1] = {x = e.x, y = e.y, type = "supply", amount = rand(1, 4) + game.sector}
        end

        if player.xp >= player.xpNext then
            game.state = "levelup"
            player.level = player.level + 1
            player.xpNext = floor(player.xpNext * 1.6)
            util.addMessage("*** ADAPT — Level " .. player.level .. " ***", 255, 255, 100)
            util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 25, 60, 200, 255, 120, 0.8)
            util.screenShake(3, 0.2)
        end
    end
end

function M.checkPlayerDeath()
    if player.hp <= 0 then
        player.hp = 0
        game.state = "dead"
        
        -- Play Audio
        if K.assets.audio and K.assets.audio.death then
            if audio and audio.play then
                audio.play(K.assets.audio.death)
            elseif bridge and bridge.playSound then
                -- Direct bridge fallback
                bridge.playSound(K.assets.audio.death)
            end
        end

        util.addMessage("Your body joins the Mindmarr.", 255, 50, 50)
        util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 40, 200, 30, 50, 150, 1.0)
        util.screenShake(8, 0.4)
    end
end

function M.checkSanityDeath()
    if player.sanity <= 0 and game.state == "playing" then
        game.state = "mindmarr"
        util.addMessage("Your lips move: \"mindmarr\"", 255, 20, 40)
        util.addMessage("The last word you ever say.", 255, 0, 0)
        util.screenShake(10, 0.6)
        util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 50, 200, 30, 60, 150, 1.2)
    end
end

function M.moveEnemies()
    for _, e in ipairs(state.enemies) do
        if not e.alive then goto continue end

        local dx = player.x - e.x
        local dy = player.y - e.y
        local adist = abs(dx) + abs(dy)

        if adist > 10 then goto continue end

        -- Nearby enemies mumble
        if adist <= 6 and rand() < 0.08 then
            local say = K.MINDMARR_SAYS[rand(1, #K.MINDMARR_SAYS)]
            util.addMessage(e.name .. ": \"" .. say .. "\"", K.C.infected[1], K.C.infected[2], K.C.infected[3])
            if rand() < 0.3 then
                player.sanity = max(0, player.sanity - 1)
            end
        end

        if adist == 1 then
            M.resolveMelee(e, player, e.name, "You", e.str, player.def, e.dmgMin, e.dmgMax)
            M.checkPlayerDeath()
            M.checkSanityDeath()
            goto continue
        end

        local mx, my = 0, 0
        if abs(dx) >= abs(dy) then
            mx = dx > 0 and 1 or -1
        else
            my = dy > 0 and 1 or -1
        end

        local nx, ny = e.x + mx, e.y + my
        if util.tileAt(nx, ny) == 0 and not util.enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
            e.x = nx; e.y = ny
        else
            if mx ~= 0 then
                my = dy > 0 and 1 or (dy < 0 and -1 or 0); mx = 0
            else
                mx = dx > 0 and 1 or (dx < 0 and -1 or 0); my = 0
            end
            nx, ny = e.x + mx, e.y + my
            if util.tileAt(nx, ny) == 0 and not util.enemyAt(nx, ny) and not (nx == player.x and ny == player.y) then
                e.x = nx; e.y = ny
            end
        end

        ::continue::
    end
end

return M
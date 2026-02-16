-- draw.lua
-- MINDMARR: All rendering

local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, max, min = math.abs, math.max, math.min

local state = require("state")
local K = require("constants")
local util = require("util")
local assets = require("assets")

local game = state.game
local player = state.player

local W, H = 800, 600

local M = {}

function M.setSize(w, h)
    W, H = w, h
end

local function drawTile(sx, sy, tx, ty)
    local camOX = floor(W/2 - player.x * K.TS - K.TS/2)
    local camOY = floor(H * 0.4 - player.y * K.TS - K.TS/2)
    local px = camOX + tx * K.TS + sx
    local py = camOY + ty * K.TS + sy
    local mapAreaH = floor(H * 0.65)

    if px < -K.TS or px > W + K.TS or py < -K.TS or py > mapAreaH + K.TS then return end

    local vis = util.isVisible(tx, ty)
    local seen = util.isSeen(tx, ty)
    local tile = util.tileAt(tx, ty)

    if not seen then
        bridge.drawRect(px, py, K.TS, K.TS, K.C.void[1], K.C.void[2], K.C.void[3], 255)
        return
    end

    local dim = vis and 1.0 or 0.3

    local marsPulse = 0
    if vis and game.sector > 2 then
        marsPulse = sin(game.pulseTimer * 2 + tx * 0.3 + ty * 0.5) * 8 * (game.sector / game.maxSectors)
    end

    if tile == 1 then
        local cr, cg, cb = K.C.wall[1], K.C.wall[2], K.C.wall[3]
        if (tx + ty) % 3 == 0 then cr, cg, cb = K.C.wallHi[1], K.C.wallHi[2], K.C.wallHi[3] end
        cr = min(255, cr + marsPulse)
        bridge.drawRect(px, py, K.TS, K.TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if vis and ty > 1 and util.tileAt(tx, ty-1) == 0 then
            bridge.drawRect(px, py, K.TS, 2, floor(100*dim), floor(50*dim), floor(40*dim), 255)
        end
    else
        local cr, cg, cb = K.C.floor[1], K.C.floor[2], K.C.floor[3]
        if vis then cr, cg, cb = K.C.floorLit[1], K.C.floorLit[2], K.C.floorLit[3] end
        cr = min(255, cr + marsPulse * 0.5)
        bridge.drawRect(px, py, K.TS, K.TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if (tx * 7 + ty * 13) % 11 == 0 then
            bridge.drawRect(px + 4, py + 4, 2, 2, floor(cr*dim*0.6), floor(cg*dim*0.6), floor(cb*dim*0.6), 255)
        end
        if vis and game.sector >= 3 and (tx * 3 + ty * 7) % 17 == 0 then
            bridge.drawRect(px + rand(2, K.TS-4), py + rand(2, K.TS-4), 1, 1, 140, 50, 30, 60)
        end
    end
end

local function drawTitle()
    bridge.drawRect(0, 0, W, H, 8, 3, 6, 255)
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
end

local function drawWon()
    bridge.drawRect(0, 0, W, H, 4, 8, 15, 255)
    for i = 1, 60 do
        local sx2 = (i * 137 + floor(game.pulseTimer * 10)) % W
        local sy2 = (i * 211) % H
        bridge.drawRect(sx2, sy2, 1, 1, 255, 255, 255, rand(100, 255))
    end

    bridge.drawText("E S C A P E D", W/2 - 55, H/4, 80, 255, 120, 255)
    bridge.drawText("Mars screams behind you, but you don't look back.", W/2 - 170, H/4 + 30, 160, 200, 180, 255)

    bridge.drawText("Level: " .. player.level .. "  Kills: " .. player.kills, W/2 - 70, H/2, 200, 200, 220, 255)
    bridge.drawText("Sanity: " .. player.sanity .. "%  O2: " .. player.oxygen .. "%", W/2 - 80, H/2 + 20, K.C.sanity[1], K.C.sanity[2], K.C.sanity[3], 255)
    bridge.drawText("Cells: " .. player.cells .. "  Sectors cleared: " .. game.maxSectors, W/2 - 100, H/2 + 40, K.C.cell[1], K.C.cell[2], K.C.cell[3], 255)

    local score = player.kills * 10 + player.sanity * 5 + player.oxygen * 2 + game.maxSectors * 100
    bridge.drawText("Score: " .. score, W/2 - 35, H/2 + 70, 255, 220, 80, 255)

    bridge.drawText("PRESS SPACE TO PLAY AGAIN", W/2 - 90, H * 0.8, 180, 180, 200, 255)
end

local function drawMindmarr()
    local pulse = sin(game.pulseTimer * 4) * 0.3 + 0.7
    bridge.drawRect(0, 0, W, H, floor(30 * pulse), floor(5 * pulse), floor(8 * pulse), 255)

    bridge.drawText("m i n d m a r r", W/2 - 60, H/4, 255, floor(40 * pulse), floor(50 * pulse), 255)
    bridge.drawText("You are one of them now.", W/2 - 80, H/4 + 30, 200, 60, 70, 255)
    bridge.drawText("Your mouth only forms one word.", W/2 - 110, H/4 + 55, 180, 50, 60, 255)

    for i = 0, 12 do
        local yy = H/2 + 10 + i * 16
        local off = floor(game.pulseTimer * 40 + i * 50) % W
        local alpha = max(40, 200 - i * 15)
        bridge.drawText("mindmarr mindmarr mindmarr mindmarr mindmarr", -off + W/2, yy,
            floor(200 * pulse), 30, 40, alpha)
    end

    bridge.drawText("Floor: " .. game.sector .. "  Level: " .. player.level .. "  Kills: " .. player.kills, W/4, H * 0.82, 200, 200, 200, 200)
    bridge.drawText("PRESS SPACE", W/2 - 40, H * 0.9, 180, 100, 110, 255)
end

local function drawHUD(mapAreaH)
    local hudY = mapAreaH + 2
    local hudH = H - hudY
    bridge.drawRect(0, hudY, W, hudH, K.C.hud_bg[1], K.C.hud_bg[2], K.C.hud_bg[3], 255)
    bridge.drawRect(0, hudY, W, 2, K.C.hud_border[1], K.C.hud_border[2], K.C.hud_border[3], 255)

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
    bridge.drawText("SAN:", sanX, ly, K.C.sanity[1], K.C.sanity[2], K.C.sanity[3], 255)
    local sanBarX = sanX + 32
    bridge.drawRect(sanBarX, ly, 60, barH, 20, 20, 40, 255)
    local sanW = floor(60 * (player.sanity / 100))
    local sanR = player.sanity <= 25 and 200 or K.C.sanity[1]
    local sanG = player.sanity <= 25 and 50 or K.C.sanity[2]
    bridge.drawRect(sanBarX, ly, sanW, barH, sanR, sanG, K.C.sanity[3], 255)
    bridge.drawText(player.sanity .. "%", sanBarX + 63, ly, K.C.sanity[1], K.C.sanity[2], K.C.sanity[3], 255)

    ly = ly + 14

    -- Row 3: Stats
    bridge.drawText("STR:" .. player.str .. " DEF:" .. player.def .. " DMG:" .. player.dmgMin .. "-" .. player.dmgMax, col1, ly, 180, 160, 170, 255)

    local o2X = 260
    bridge.drawText("O2:", o2X, ly, K.C.oxygen[1], K.C.oxygen[2], K.C.oxygen[3], 255)
    bridge.drawText(player.oxygen .. "%", o2X + 24, ly, K.C.oxygen[1], K.C.oxygen[2], K.C.oxygen[3], 255)

    ly = ly + 14

    -- Row 4: Items
    bridge.drawText("ARM:" .. player.armor .. " CRIT:<=" .. player.critBonus, col1, ly, 160, 150, 170, 255)
    bridge.drawText("XP:" .. player.xp .. "/" .. player.xpNext, col1 + 160, ly, K.C.xp[1], K.C.xp[2], K.C.xp[3], 255)

    ly = ly + 14

    -- Row 5
    bridge.drawText("Medkits:" .. player.medkits, col1, ly, 255, 100, 100, 255)
    bridge.drawText("Keys:" .. player.keycards, col1 + 80, ly, K.C.keycard[1], K.C.keycard[2], K.C.keycard[3], 255)
    bridge.drawText("Cells:" .. player.cells .. "/" .. player.cellsNeeded, col1 + 140, ly, K.C.cell[1], K.C.cell[2], K.C.cell[3], 255)
    bridge.drawText("Kills:" .. player.kills, col1 + 260, ly, 200, 140, 140, 255)
    
    if player.hasBackpack then
        bridge.drawText("Scrap:" .. player.scrapCount, col1 + 340, ly, 200, 200, 200, 255)
    end

    -- Message log
    local msgX = W/2 + 20
    local msgY = hudY + 8
    bridge.drawText("-- Transmission Log --", msgX, msgY, 100, 70, 90, 255)
    for i, msg in ipairs(game.messages) do
        local alpha = max(80, 255 - i * 25)
        bridge.drawText(msg.text, msgX, msgY + i * 13, msg.r, msg.g, msg.b, alpha)
        if msgY + i * 13 > H - 5 then break end
    end
end

function M.drawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = floor((rand() - 0.5) * game.shakeIntensity * 2)
        sy = floor((rand() - 0.5) * game.shakeIntensity * 2)
    end

    bridge.drawRect(0, 0, W, H, K.C.void[1], K.C.void[2], K.C.void[3], 255)

    if game.state == "title" then drawTitle(); return end
    if game.state == "won" then drawWon(); return end
    if game.state == "mindmarr" then drawMindmarr(); return end

    local camOX = floor(W/2 - player.x * K.TS - K.TS/2)
    local camOY = floor(H * 0.4 - player.y * K.TS - K.TS/2)
    local mapAreaH = floor(H * 0.65)

    -- Map tiles
    local startTX = max(1, floor(-camOX / K.TS) - 1)
    local endTX = min(K.MW, floor((-camOX + W) / K.TS) + 2)
    local startTY = max(1, floor(-camOY / K.TS) - 1)
    local endTY = min(K.MH, floor((-camOY + mapAreaH) / K.TS) + 2)

    for ty = startTY, endTY do
        for tx = startTX, endTX do
            drawTile(sx, sy, tx, ty)
        end
    end

    -- Shuttle/airlock
    if util.isVisible(state.shuttle.x, state.shuttle.y) then
        local stX = camOX + state.shuttle.x * K.TS + sx
        local stY = camOY + state.shuttle.y * K.TS + sy
        local drewShuttle = assets.tryDrawSprite("shuttle", stX, stY, K.TS, K.TS)
        if not drewShuttle then
            if game.sector == game.maxSectors then
                local glow = sin(game.pulseTimer * 3) * 20 + 220
                bridge.drawRect(stX + 2, stY + 2, K.TS - 4, K.TS - 4, floor(glow), floor(glow * 0.85), 40, 255)
                bridge.drawRect(stX + 5, stY + 5, K.TS - 10, K.TS - 10, 200, 180, 60, 255)
                bridge.drawText("^", stX + 8, stY + 4, 255, 255, 200, 255)
            else
                bridge.drawRect(stX + 4, stY + 4, K.TS - 8, K.TS - 8, K.C.shuttle[1], K.C.shuttle[2], K.C.shuttle[3], 255)
                bridge.drawText(">", stX + 8, stY + 5, 255, 240, 180, 255)
            end
        end
    elseif util.isSeen(state.shuttle.x, state.shuttle.y) then
        local stX = camOX + state.shuttle.x * K.TS + sx
        local stY = camOY + state.shuttle.y * K.TS + sy
        bridge.drawRect(stX + 4, stY + 4, K.TS - 8, K.TS - 8, 60, 50, 25, 255)
    end

    -- Elevator
    if state.elevator.revealed and util.isVisible(state.elevator.x, state.elevator.y) then
        local ex = camOX + state.elevator.x * K.TS + sx
        local ey = camOY + state.elevator.y * K.TS + sy
        local drewElevator = assets.tryDrawSprite("elevator", ex, ey, K.TS, K.TS)
        if not drewElevator then
            local pulse = sin(game.pulseTimer * 3) * 15 + 100
            bridge.drawRect(ex + 3, ey + 3, K.TS - 6, K.TS - 6, floor(pulse), floor(pulse * 2.2), 255, 255)
            bridge.drawRect(ex + 6, ey + 6, K.TS - 12, K.TS - 12, K.C.elevator[1], K.C.elevator[2], K.C.elevator[3], 255)
            bridge.drawText("E", ex + 8, ey + 6, 255, 255, 255, 255)
        end
    elseif state.elevator.revealed and util.isSeen(state.elevator.x, state.elevator.y) then
        local ex = camOX + state.elevator.x * K.TS + sx
        local ey = camOY + state.elevator.y * K.TS + sy
        bridge.drawRect(ex + 6, ey + 6, K.TS - 12, K.TS - 12, 40, 80, 100, 255)
    end

    -- Items
    for _, it in ipairs(state.items) do
        if util.isVisible(it.x, it.y) then
            local ix = camOX + it.x * K.TS + sx
            local iy = camOY + it.y * K.TS + sy
            local spriteKey = it.spriteKey or it.type
            local drewSprite = assets.tryDrawSprite(spriteKey, ix, iy, K.TS, K.TS)

            if not drewSprite then
                -- Fallback procedural item rendering
                if it.type == "supply" then
                    bridge.drawRect(ix + 7, iy + 7, 10, 10, K.C.supply[1], K.C.supply[2], K.C.supply[3], 255)
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
                    bridge.drawRect(ix + 7, iy + 5, 10, 14, K.C.oxygen[1], K.C.oxygen[2], K.C.oxygen[3], 255)
                    bridge.drawRect(ix + 9, iy + 3, 6, 4, 60, 160, 180, 255)
                elseif it.type == "keycard" then
                    local glow = sin(game.pulseTimer * 4) * 20 + 220
                    bridge.drawRect(ix + 4, iy + 5, 16, 14, floor(glow), floor(glow * 0.8), 50, 255)
                    bridge.drawRect(ix + 6, iy + 7, 12, 10, K.C.keycard[1], K.C.keycard[2], K.C.keycard[3], 255)
                    bridge.drawRect(ix + 8, iy + 11, 3, 3, 80, 60, 20, 255)
                elseif it.type == "scattered_document" then
                    bridge.drawRect(ix + 8, iy + 8, 14, 18, K.C.document[1], K.C.document[2], K.C.document[3], 255)
                    bridge.drawRect(ix + 10, iy + 10, 10, 2, 50, 50, 50, 200)
                    bridge.drawRect(ix + 10, iy + 14, 10, 2, 50, 50, 50, 200)
                elseif it.type == "terminal" then
                    bridge.drawRect(ix + 6, iy + 6, 20, 18, 50, 50, 50, 255) -- Case
                    local scrG = sin(game.pulseTimer * 5) * 30 + 100
                    bridge.drawRect(ix + 8, iy + 8, 16, 12, 10, floor(scrG), 30, 255) -- Screen
                    bridge.drawRect(ix + 8, iy + 22, 20, 4, 40, 40, 40, 255) -- Keyboard
                elseif it.type == "scrap" then
                    bridge.drawRect(ix + 6, iy + 10, 8, 8, K.C.scrap[1], K.C.scrap[2], K.C.scrap[3], 255)
                    bridge.drawRect(ix + 14, iy + 8, 6, 6, 100, 100, 110, 255)
                    bridge.drawRect(ix + 10, iy + 16, 10, 4, 80, 80, 90, 255)
                end
            end
        end
    end

    -- Enemies
    for _, e in ipairs(state.enemies) do
        if e.alive and util.isVisible(e.x, e.y) then
            local ex = camOX + e.x * K.TS + sx
            local ey = camOY + e.y * K.TS + sy
            local drewSprite = false
            if e.spriteKey then
                if e.frameCount and e.frameCount > 1 then
                    drewSprite = assets.tryDrawSprite(e.spriteKey, ex, ey, K.TS, K.TS,
                        e.currentFrame, e.frameCols, e.frameRows, e.frameWidth, e.frameHeight)
                else
                    drewSprite = assets.tryDrawSprite(e.spriteKey, ex, ey, K.TS, K.TS)
                end
            end
            
            if not drewSprite then
                local aura = sin(game.pulseTimer * 5 + e.x) * 15
                bridge.drawRect(ex + 2, ey + 2, K.TS - 4, K.TS - 4,
                    min(255, e.color[1] + floor(aura)), min(255, e.color[2]), min(255, e.color[3]), 255)
                bridge.drawRect(ex + 5, ey + 5, K.TS - 10, K.TS - 10,
                    min(255, e.color[1]+30), min(255, e.color[2]+20), min(255, e.color[3]+20), 255)
            end
            
            if e.hp < e.maxHp then
                local bW = K.TS - 4
                local hpFrac = e.hp / e.maxHp
                bridge.drawRect(ex + 2, ey - 3, bW, 3, 40, 10, 15, 200)
                bridge.drawRect(ex + 2, ey - 3, floor(bW * hpFrac), 3, 255, 40, 50, 255)
            end
        end
    end

    -- Player
    if game.state ~= "dead" then
        local px_draw = camOX + player.x * K.TS + sx
        local py_draw = camOY + player.y * K.TS + sy
        local drewSprite = assets.tryDrawSprite("player", px_draw, py_draw, K.TS, K.TS, 
                                              player.currentFrame, player.frameCols, player.frameRows, 
                                              player.frameWidth, player.frameHeight)
        
        if not drewSprite then
            bridge.drawRect(px_draw + 2, py_draw + 2, K.TS - 4, K.TS - 4, K.C.player[1], K.C.player[2], K.C.player[3], 255)
            bridge.drawRect(px_draw + 5, py_draw + 5, K.TS - 10, K.TS - 10, 100, 220, 255, 255)
            bridge.drawRect(px_draw + 7, py_draw + 6, 10, 5, 20, 60, 80, 255)
            bridge.drawRect(px_draw + 8, py_draw + 7, 8, 3, 40, 140, 180, 255)
        end
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

    drawHUD(mapAreaH)

    -- Interaction Overlay (Documents/Terminals)
    if game.state == "interacting" then
        bridge.drawRect(W/4, H/3, W/2, 200, 15, 15, 20, 240)
        bridge.drawRect(W/4, H/3, W/2, 2, 100, 200, 255, 255)
        
        local typeName = (game.interaction.type == "terminal") and "TERMINAL FOUND" or "SCATTERED DOCUMENT"
        bridge.drawText(typeName, W/4 + 20, H/3 + 20, 100, 230, 255, 255)
        
        bridge.drawText("1. Read", W/4 + 40, H/3 + 60, 255, 255, 255, 255)
        bridge.drawText("2. Leave", W/4 + 40, H/3 + 90, 200, 200, 200, 255)
        
        if game.interaction.type == "terminal" then
             bridge.drawText("(Only on North Walls)", W/4 + 20, H/3 + 150, 100, 100, 100, 255)
        end
    end
    
    -- Interaction Overlay (Scrap)
    if game.state == "interacting_scrap" then
        local opts = game.interaction.options or {}
        local menuH = 40 + #opts * 30
        
        bridge.drawRect(W/4, H/3, W/2, menuH, 15, 15, 25, 245)
        bridge.drawRect(W/4, H/3, W/2, 2, 160, 160, 170, 255)
        
        bridge.drawText("SCRAP PILE", W/4 + 20, H/3 + 15, 200, 200, 220, 255)
        
        for i, opt in ipairs(opts) do
            local y = H/3 + 40 + (i-1) * 30
            local color = (opt.action == "leave") and {180, 180, 180} or {255, 255, 255}
            bridge.drawText(i .. ". " .. opt.label, W/4 + 40, y, color[1], color[2], color[3], 255)
        end
    end

    -- Level up overlay
    if game.state == "levelup" then
        bridge.drawRect(W/4, H/4, W/2, H/2, 10, 8, 20, 240)
        bridge.drawRect(W/4, H/4, W/2, 2, 60, 200, 255, 255)
        bridge.drawText("ADAPT — Choose an upgrade:", W/4 + 20, H/4 + 12, 100, 230, 255, 255)
        for i, choice in ipairs(K.levelChoices) do
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

return M 

-- netrogue/renderer.lua
-- All rendering logic

local Config = require("config")
local Network = require("network")
local MapGen = require("mapgen")
local Entities = require("entities")
local GameState = require("gamestate")
local MessageLog = require("messagelog")
local Particles = require("particles")
local FOV = require("fov")

local Renderer = {}

local floor, min, max = math.floor, math.min, math.max
local sin, cos = math.sin, math.cos

-- ============================================================
-- TILE RENDERING
-- ============================================================
local function drawTile(sx, sy, camOX, camOY, tx, ty, mapAreaH)
    local C = Config.C
    local TS = Config.TS
    local W = Config.W
    
    local px = camOX + tx * TS + sx
    local py = camOY + ty * TS + sy
    if px < -TS or px > W + TS or py < -TS or py > mapAreaH + TS then return end

    local vis = FOV.isVisible(tx, ty)
    local tile_seen = FOV.isSeen(tx, ty)
    local tile = MapGen.getTile(tx, ty)

    if not tile_seen then
        bridge.drawRect(px, py, TS, TS, C.void[1], C.void[2], C.void[3], 255)
        return
    end

    local dim = vis and 1.0 or 0.3
    if tile == 1 then
        local cr, cg, cb = C.wall[1], C.wall[2], C.wall[3]
        if (tx + ty) % 3 == 0 then cr, cg, cb = C.wallHi[1], C.wallHi[2], C.wallHi[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if vis and ty > 1 and MapGen.getTile(tx, ty-1) == 0 then
            bridge.drawRect(px, py, TS, 2, floor(80*dim), floor(70*dim), floor(100*dim), 255)
        end
    else
        local cr, cg, cb = C.floor[1], C.floor[2], C.floor[3]
        if vis then cr, cg, cb = C.floorLit[1], C.floorLit[2], C.floorLit[3] end
        bridge.drawRect(px, py, TS, TS, floor(cr*dim), floor(cg*dim), floor(cb*dim), 255)
        if (tx * 7 + ty * 13) % 11 == 0 then
            bridge.drawRect(px + 4, py + 4, 2, 2,
                floor(cr*dim*0.5), floor(cg*dim*0.5), floor(cb*dim*0.5), 255)
        end
    end
end

-- ============================================================
-- ENTITY RENDERING
-- ============================================================
local function drawEntity(sx, sy, camOX, camOY, ex, ey, color, hasVisor)
    local TS = Config.TS
    local px = camOX + ex * TS + sx
    local py = camOY + ey * TS + sy
    bridge.drawRect(px + 2, py + 2, TS - 4, TS - 4, color[1], color[2], color[3], 255)
    bridge.drawRect(px + 5, py + 5, TS - 10, TS - 10,
        min(255, color[1] + 40), min(255, color[2] + 40), min(255, color[3] + 40), 255)
    if hasVisor then
        bridge.drawRect(px + 7, py + 6, 10, 5, 20, 50, 80, 255)
        bridge.drawRect(px + 8, py + 7, 8, 3, 40, 130, 200, 255)
    end
end

local function drawHPBar(sx, sy, camOX, camOY, ex, ey, hp, maxHp)
    local C = Config.C
    local TS = Config.TS
    if hp >= maxHp then return end
    local px = camOX + ex * TS + sx
    local py = camOY + ey * TS + sy
    local barW = TS - 4
    local hpFrac = max(0, hp / maxHp)
    bridge.drawRect(px + 2, py - 4, barW, 3, C.hp_bar_bg[1], C.hp_bar_bg[2], C.hp_bar_bg[3], 200)
    local barColor = hpFrac > 0.3 and C.hp_bar or C.hp_bar_low
    bridge.drawRect(px + 2, py - 4, floor(barW * hpFrac), 3,
        barColor[1], barColor[2], barColor[3], 255)
end

local function drawGoblin(sx, sy, camOX, camOY, g)
    local C = Config.C
    local TS = Config.TS
    local px = camOX + g.x * TS + sx
    local py = camOY + g.y * TS + sy

    -- Body — green with pointy ears
    -- FIX: added (g.id or 0) to prevent crash if id is nil
    local pulse = sin(GameState.pulseTimer * 4 + (g.id or 0)) * 10
    
    bridge.drawRect(px + 3, py + 4, TS - 6, TS - 6,
        C.goblin[1] + floor(pulse), C.goblin[2], C.goblin[3], 255)
    -- Inner
    bridge.drawRect(px + 6, py + 7, TS - 12, TS - 10,
        min(255, C.goblin[1] + 30), min(255, C.goblin[2] + 30), C.goblin[3] + 20, 255)
    -- Eyes (angry red dots)
    bridge.drawRect(px + 7, py + 8, 3, 3, 255, 60, 40, 255)
    bridge.drawRect(px + 14, py + 8, 3, 3, 255, 60, 40, 255)
    -- Ears
    bridge.drawRect(px + 2, py + 2, 3, 4, C.goblin[1], C.goblin[2], C.goblin[3], 255)
    bridge.drawRect(px + TS - 5, py + 2, 3, 4, C.goblin[1], C.goblin[2], C.goblin[3], 255)

    -- HP bar
    drawHPBar(sx, sy, camOX, camOY, g.x, g.y, g.hp, g.maxHp)
end

-- ============================================================
-- MAIN GAME SCREEN
-- ============================================================
function Renderer.drawGame()
    local C = Config.C
    local W, H = Config.W, Config.H
    local TS = Config.TS
    local MW, MH = Config.MW, Config.MH
    local player = Entities.player
    
    -- Screen shake
    local sx, sy = GameState.getShake()
    
    local mapAreaH = floor(H * 0.68)
    bridge.drawRect(0, 0, W, H, C.void[1], C.void[2], C.void[3], 255)

    local camOX = floor(W/2 - player.x * TS - TS/2)
    local camOY = floor(mapAreaH * 0.45 - player.y * TS - TS/2)

    -- Tiles
    for ty = 1, MH do
        for tx = 1, MW do
            drawTile(sx, sy, camOX, camOY, tx, ty, mapAreaH)
        end
    end

    -- Goblins
    for _, g in pairs(Entities.goblins) do
        if g.alive and FOV.isVisible(g.x, g.y) then
            drawGoblin(sx, sy, camOX, camOY, g)
        end
    end

    -- Other players
    for id, other in pairs(Entities.others) do
        if FOV.isVisible(other.x, other.y) then
            drawEntity(sx, sy, camOX, camOY, other.x, other.y, C.other, false)
            local opx = camOX + other.x * TS + sx
            local opy = camOY + other.y * TS + sy
            bridge.drawText("#" .. id, opx + 2, opy - 10, C.other[1], C.other[2], C.other[3], 200)
        end
    end

    -- Local player
    if not player.dead then
        drawEntity(sx, sy, camOX, camOY, player.x, player.y, C.player, true)
        drawHPBar(sx, sy, camOX, camOY, player.x, player.y, player.hp, player.maxHp)
    end

    -- Particles
    for _, p in ipairs(Particles.particles) do
        local alpha = floor(255 * (p.life / p.maxLife))
        if alpha > 0 then
            local ppx = camOX + p.x + sx
            local ppy = camOY + p.y + sy
            if ppx > -10 and ppx < W + 10 and ppy > -10 and ppy < mapAreaH + 10 then
                bridge.drawRect(ppx - p.size/2, ppy - p.size/2, p.size, p.size, p.r, p.g, p.b, alpha)
            end
        end
    end

    -- ========== HUD ==========
    Renderer.drawHUD(mapAreaH)

    -- Death overlay
    if player.dead then
        bridge.drawRect(W/4, H/3, W/2, H/5, 25, 5, 8, 230)
        bridge.drawRect(W/4, H/3, W/2, 2, 255, 40, 50, 255)
        bridge.drawText("YOU HAVE FALLEN", W/4 + 40, H/3 + 15, 255, 50, 60, 255)
        bridge.drawText("Kills: " .. player.kills .. "  Level: " .. player.level,
            W/4 + 30, H/3 + 35, 200, 200, 200, 255)
        bridge.drawText("PRESS SPACE TO RESPAWN", W/4 + 20, H/3 + 60, 180, 180, 200, 255)
    end
end

-- ============================================================
-- HUD RENDERING
-- ============================================================
function Renderer.drawHUD(mapAreaH)
    local C = Config.C
    local W, H = Config.W, Config.H
    local player = Entities.player
    
    local hudY = mapAreaH + 2
    local hudH = H - hudY
    bridge.drawRect(0, hudY, W, hudH, C.hud_bg[1], C.hud_bg[2], C.hud_bg[3], 255)
    bridge.drawRect(0, hudY, W, 2, C.hud_border[1], C.hud_border[2], C.hud_border[3], 255)

    local col1 = 10
    local ly = hudY + 6

    -- Row 1: Title + Net
    bridge.drawText("NETROGUE", col1, ly, 60, 200, 255, 255)
    local netColor = Network.connected and C.net_ok or C.net_err
    bridge.drawRect(col1 + 70, ly + 2, 6, 6, netColor[1], netColor[2], netColor[3], 255)
    bridge.drawText("P#" .. (player.id or "?") .. " Tick:" .. Network.tick,
        col1 + 80, ly, netColor[1], netColor[2], netColor[3], 255)
    ly = ly + 13

    -- Row 2: HP bar
    bridge.drawText("HP:", col1, ly, 200, 200, 200, 255)
    local barX = col1 + 28
    local barW = 90
    local barH = 10
    bridge.drawRect(barX, ly, barW, barH, C.hp_bar_bg[1], C.hp_bar_bg[2], C.hp_bar_bg[3], 255)
    local hpFrac = max(0, player.hp / player.maxHp)
    local hpColor = hpFrac > 0.3 and C.hp_bar or C.hp_bar_low
    bridge.drawRect(barX, ly, floor(barW * hpFrac), barH, hpColor[1], hpColor[2], hpColor[3], 255)
    bridge.drawText(player.hp .. "/" .. player.maxHp, barX + barW + 4, ly, 200, 200, 200, 255)
    ly = ly + 13

    -- Row 3: Stats
    bridge.drawText("ATK:" .. player.attack .. "  LVL:" .. player.level ..
        "  Kills:" .. player.kills, col1, ly, 180, 170, 200, 255)

    -- XP bar
    local xpX = col1 + 220
    bridge.drawText("XP:", xpX, ly, C.xp[1], C.xp[2], C.xp[3], 255)
    bridge.drawRect(xpX + 24, ly, 60, barH, 20, 15, 30, 255)
    local xpFrac = player.xp / max(1, player.xpNext)
    bridge.drawRect(xpX + 24, ly, floor(60 * xpFrac), barH, C.xp[1], C.xp[2], C.xp[3], 255)
    bridge.drawText(player.xp .. "/" .. player.xpNext, xpX + 88, ly, C.xp[1], C.xp[2], C.xp[3], 255)
    ly = ly + 13

    -- Row 4: Controls
    bridge.drawText("WASD:Move/Attack  P:Pray  I:Sit  O:Stand", col1, ly, 110, 100, 130, 255)

    -- Message log (right side)
    local msgX = W/2 + 10
    local msgY = hudY + 6
    bridge.drawText("-- Combat Log --", msgX, msgY, 80, 70, 100, 255)
    for i, msg in ipairs(MessageLog.messages) do
        local alpha = max(60, 255 - i * 18)
        bridge.drawText(msg.text, msgX, msgY + i * 12, msg.r, msg.g, msg.b, alpha)
        if msgY + i * 12 > H - 5 then break end
    end
end

-- ============================================================
-- CONNECTION SCREENS
-- ============================================================
function Renderer.drawConnecting()
    local C = Config.C
    local W, H = Config.W, Config.H
    
    bridge.drawRect(0, 0, W, H, C.title_bg[1], C.title_bg[2], C.title_bg[3], 255)
    bridge.drawText("N E T R O G U E", W/2 - 65, H/4, 60, 200, 255, 255)
    bridge.drawText("MarbleNet + ClayMarble", W/2 - 80, H/4 + 20, 120, 110, 140, 255)

    local statusColor = C.net_wait
    if Network.connect_attempts >= Network.max_connect_attempts then statusColor = C.net_err end
    bridge.drawText(Network.status_msg, W/2 - 120, H/2, statusColor[1], statusColor[2], statusColor[3], 255)

    local dots = string.rep(".", floor(GameState.pulseTimer * 3) % 4)
    bridge.drawText("Connecting" .. dots, W/2 - 40, H/2 + 25, 140, 130, 160, 255)

    if Network.connect_attempts >= Network.max_connect_attempts then
        bridge.drawText("Could not reach server.", W/2 - 80, H/2 + 50, C.net_err[1], C.net_err[2], C.net_err[3], 255)
        bridge.drawText("Run: build.bat netrogue_server", W/2 - 100, H/2 + 70, 160, 150, 180, 255)
        bridge.drawText("Press SPACE to retry", W/2 - 70, H/2 + 100, 180, 180, 200, 255)
    end
end

function Renderer.drawDisconnected()
    local C = Config.C
    local W, H = Config.W, Config.H
    
    bridge.drawRect(0, 0, W, H, C.title_bg[1], C.title_bg[2], C.title_bg[3], 255)
    bridge.drawText("DISCONNECTED", W/2 - 50, H/2 - 10, C.net_err[1], C.net_err[2], C.net_err[3], 255)
    bridge.drawText(Network.status_msg, W/2 - 100, H/2 + 15, 160, 150, 180, 255)
    bridge.drawText("Press SPACE to reconnect", W/2 - 85, H/2 + 45, 180, 180, 200, 255)
end

return Renderer
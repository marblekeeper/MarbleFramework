-- space_shooter.lua
-- Retro Asteroids-style shooter: Left/Right rotate, Up thrust, Space shoot
-- Player vs waves of enemies, screen wrap, particles, score

local root = UIElement:new({width=800, height=600})

local W, H = 800, 600
local TAU = math.pi * 2
local sin, cos, rand, floor = math.sin, math.cos, math.random, math.floor
local abs, sqrt, max, min = math.abs, math.sqrt, math.max, math.min
local atan2 = atan2 or math.atan

local game = {
    state = "playing",
    score = 0,
    lives = 3,
    wave = 1,
    waveTimer = 0,
    shakeTimer = 0,
    shakeIntensity = 0,
    spawnTimer = 0,
    dt = 0.016,
}

local player = {
    x = 400, y = 300,
    vx = 0, vy = 0,
    angle = -math.pi/2,
    rotSpeed = 4.5,
    thrust = 320,
    drag = 0.985,
    radius = 12,
    health = 3,
    maxHealth = 3,
    bullets = {},
    fireRate = 0.12,
    fireCooldown = 0,
    invincible = 0,
    thrustOn = false,
    alive = true,
    respawnTimer = 0,
    shieldTime = 0,
    shieldRadius = 40,
}

local enemies = {}
local particles = {}
local stars = {}
local pickups = {}

for i = 1, 120 do
    stars[i] = {
        x = rand(0, W),
        y = rand(0, H),
        brightness = rand(30, 100),
        size = rand() < 0.3 and 2 or 1,
        speed = rand(5, 30),
    }
end

local function wrap(x, y)
    if x < -20 then x = x + W + 40 end
    if x > W + 20 then x = x - W - 40 end
    if y < -20 then y = y + H + 40 end
    if y > H + 20 then y = y - H - 40 end
    return x, y
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx*dx + dy*dy)
end

local function spawnParticles(x, y, count, r, g, b, speed, life)
    for i = 1, count do
        local a = rand() * TAU
        local s = rand() * speed + speed * 0.3
        particles[#particles+1] = {
            x = x, y = y,
            vx = cos(a) * s,
            vy = sin(a) * s,
            life = life * (0.5 + rand() * 0.5),
            maxLife = life,
            r = r, g = g, b = b,
            size = rand() < 0.4 and 3 or 2,
        }
    end
end

local function screenShake(intensity, duration)
    game.shakeTimer = duration
    game.shakeIntensity = intensity
end

local function spawnEnemy(etype)
    local side = rand(1, 4)
    local x, y
    if side == 1 then x, y = rand(0, W), -20
    elseif side == 2 then x, y = rand(0, W), H + 20
    elseif side == 3 then x, y = -20, rand(0, H)
    else x, y = W + 20, rand(0, H) end

    local e = {
        x = x, y = y, vx = 0, vy = 0,
        angle = rand() * TAU,
        rotSpeed = (rand() - 0.5) * 3,
        radius = 10,
        health = 1,
        type = etype or "grunt",
        fireTimer = rand() * 2,
        bullets = {},
        alive = true,
    }

    if e.type == "grunt" then
        local spd = 60 + game.wave * 8
        local a = atan2(player.y - y, player.x - x) + (rand() - 0.5) * 0.8
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 10
        e.health = 1
        e.score = 100
    elseif e.type == "tank" then
        local spd = 35 + game.wave * 4
        local a = atan2(player.y - y, player.x - x)
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 16
        e.health = 3
        e.score = 300
    elseif e.type == "fast" then
        local spd = 140 + game.wave * 10
        local a = atan2(player.y - y, player.x - x) + (rand() - 0.5) * 0.3
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 8
        e.health = 1
        e.score = 200
    elseif e.type == "shooter" then
        local spd = 50 + game.wave * 5
        local a = atan2(player.y - y, player.x - x) + (rand() - 0.5) * 1.0
        e.vx = cos(a) * spd
        e.vy = sin(a) * spd
        e.radius = 12
        e.health = 2
        e.fireRate = max(0.8, 2.0 - game.wave * 0.1)
        e.score = 250
    end

    enemies[#enemies+1] = e
end

local function spawnWave()
    local w = game.wave
    local grunts = 3 + w * 2
    local tanks = floor(w / 2)
    local fasts = floor(w / 3) + (w > 2 and 1 or 0)
    local shooters = floor(w / 4) + (w > 3 and 1 or 0)

    for i = 1, grunts do spawnEnemy("grunt") end
    for i = 1, tanks do spawnEnemy("tank") end
    for i = 1, fasts do spawnEnemy("fast") end
    for i = 1, shooters do spawnEnemy("shooter") end
end

local function spawnPickup(x, y)
    if rand() < 0.25 then
        pickups[#pickups+1] = {
            x = x, y = y,
            type = rand() < 0.5 and "health" or "shield",
            life = 8,
            radius = 8,
            pulse = 0,
        }
    end
end

local function fireBullet(e, angle, speed, isEnemy)
    local bx = e.x + cos(angle) * (e.radius + 4)
    local by = e.y + sin(angle) * (e.radius + 4)
    local list = isEnemy and e.bullets or player.bullets
    list[#list+1] = {
        x = bx, y = by,
        vx = cos(angle) * speed,
        vy = sin(angle) * speed,
        alive = true,
        life = 2.5,
        isEnemy = isEnemy,
    }
end

local function resetPlayer()
    player.x = W / 2
    player.y = H / 2
    player.vx = 0
    player.vy = 0
    player.angle = -math.pi / 2
    player.alive = true
    player.invincible = 2.0
    player.health = player.maxHealth
    player.bullets = {}
    player.fireCooldown = 0
    player.shieldTime = 0
end

local function resetGame()
    game.score = 0
    game.lives = 3
    game.wave = 1
    game.waveTimer = 0
    game.state = "playing"
    enemies = {}
    particles = {}
    pickups = {}
    resetPlayer()
    spawnWave()
end

local function pollKeys()
    if not bridge.getKeyState then return end
    game.keys = {
        left = bridge.getKeyState("left") == 1 or bridge.getKeyState("a") == 1,
        right = bridge.getKeyState("right") == 1 or bridge.getKeyState("d") == 1,
        up = bridge.getKeyState("up") == 1 or bridge.getKeyState("w") == 1,
        space = bridge.getKeyState("space") == 1,
    }
end

function UpdateGame(dt)
    game.dt = dt
    pollKeys()
    local keys = game.keys or {}

    if game.shakeTimer > 0 then
        game.shakeTimer = game.shakeTimer - dt
    end

    if game.state == "gameover" then
        if keys.space then resetGame() end
        for i = #particles, 1, -1 do
            local p = particles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            p.vx = p.vx * 0.97
            p.vy = p.vy * 0.97
            if p.life <= 0 then table.remove(particles, i) end
        end
        return
    end

    if player.alive then
        if keys.left then player.angle = player.angle - player.rotSpeed * dt end
        if keys.right then player.angle = player.angle + player.rotSpeed * dt end

        player.thrustOn = keys.up
        if keys.up then
            player.vx = player.vx + cos(player.angle) * player.thrust * dt
            player.vy = player.vy + sin(player.angle) * player.thrust * dt
            if rand() < 0.7 then
                local ba = player.angle + math.pi + (rand() - 0.5) * 0.8
                spawnParticles(
                    player.x - cos(player.angle) * 12,
                    player.y - sin(player.angle) * 12,
                    1, 255, rand(100, 200), 30,
                    40 + rand() * 30, 0.3
                )
            end
        end

        player.vx = player.vx * player.drag
        player.vy = player.vy * player.drag
        player.x = player.x + player.vx * dt
        player.y = player.y + player.vy * dt
        player.x, player.y = wrap(player.x, player.y)

        player.invincible = max(0, player.invincible - dt)
        player.shieldTime = max(0, player.shieldTime - dt)
        player.fireCooldown = max(0, player.fireCooldown - dt)

        if keys.space and player.fireCooldown <= 0 then
            fireBullet(player, player.angle, 500, false)
            player.fireCooldown = player.fireRate
            spawnParticles(
                player.x + cos(player.angle) * 16,
                player.y + sin(player.angle) * 16,
                3, 255, 255, 150, 60, 0.15
            )
        end
    else
        player.respawnTimer = player.respawnTimer - dt
        if player.respawnTimer <= 0 then
            if game.lives > 0 then
                resetPlayer()
            else
                game.state = "gameover"
            end
        end
    end

    for i = #player.bullets, 1, -1 do
        local b = player.bullets[i]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.life = b.life - dt
        b.x, b.y = wrap(b.x, b.y)
        if b.life <= 0 then
            table.remove(player.bullets, i)
        end
    end

    for ei = #enemies, 1, -1 do
        local e = enemies[ei]
        e.x = e.x + e.vx * dt
        e.y = e.y + e.vy * dt
        e.x, e.y = wrap(e.x, e.y)
        e.angle = e.angle + e.rotSpeed * dt

        if e.type == "shooter" and e.fireRate and player.alive then
            e.fireTimer = e.fireTimer - dt
            if e.fireTimer <= 0 then
                local a = atan2(player.y - e.y, player.x - e.x)
                fireBullet(e, a, 200 + game.wave * 10, true)
                e.fireTimer = e.fireRate
                spawnParticles(e.x, e.y, 2, 255, 80, 80, 30, 0.15)
            end
        end

        for bi = #e.bullets, 1, -1 do
            local b = e.bullets[bi]
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.life = b.life - dt
            b.x, b.y = wrap(b.x, b.y)

            if player.alive and player.invincible <= 0 and player.shieldTime <= 0 and b.life > 0 then
                if dist(b.x, b.y, player.x, player.y) < player.radius then
                    b.life = 0
                    player.health = player.health - 1
                    screenShake(4, 0.15)
                    spawnParticles(player.x, player.y, 8, 255, 200, 50, 80, 0.4)
                    if player.health <= 0 then
                        player.alive = false
                        player.respawnTimer = 2.0
                        game.lives = game.lives - 1
                        spawnParticles(player.x, player.y, 30, 50, 255, 50, 150, 0.8)
                        spawnParticles(player.x, player.y, 15, 255, 255, 100, 100, 0.5)
                        screenShake(8, 0.3)
                    end
                end
            elseif player.alive and player.shieldTime > 0 and b.life > 0 then
                if dist(b.x, b.y, player.x, player.y) < player.shieldRadius then
                    b.life = 0
                    spawnParticles(b.x, b.y, 8, 50, 150, 255, 60, 0.3)
                    screenShake(2, 0.08)
                end
            end

            if b.life <= 0 then table.remove(e.bullets, bi) end
        end

        for bi = #player.bullets, 1, -1 do
            local b = player.bullets[bi]
            if b.life > 0 and dist(b.x, b.y, e.x, e.y) < e.radius + 3 then
                b.life = 0
                table.remove(player.bullets, bi)
                e.health = e.health - 1
                spawnParticles(b.x, b.y, 5, 255, 200, 100, 60, 0.3)
                screenShake(2, 0.08)
                if e.health <= 0 then
                    game.score = game.score + (e.score or 100)
                    local cr, cg, cb = 255, 100, 50
                    if e.type == "tank" then cr, cg, cb = 255, 150, 50
                    elseif e.type == "fast" then cr, cg, cb = 50, 200, 255
                    elseif e.type == "shooter" then cr, cg, cb = 255, 50, 200 end
                    spawnParticles(e.x, e.y, 20, cr, cg, cb, 120, 0.6)
                    spawnParticles(e.x, e.y, 10, 255, 255, 200, 80, 0.3)
                    screenShake(5, 0.15)
                    spawnPickup(e.x, e.y)
                    table.remove(enemies, ei)
                    break
                end
            end
        end

        if e.alive ~= false and player.alive and player.invincible <= 0 and player.shieldTime <= 0 then
            if dist(e.x, e.y, player.x, player.y) < e.radius + player.radius then
                player.health = player.health - 2
                e.health = e.health - 2
                screenShake(6, 0.2)
                spawnParticles(player.x, player.y, 12, 255, 150, 50, 100, 0.5)
                if player.health <= 0 then
                    player.alive = false
                    player.respawnTimer = 2.0
                    game.lives = game.lives - 1
                    spawnParticles(player.x, player.y, 30, 50, 255, 50, 150, 0.8)
                    screenShake(8, 0.3)
                end
                if e.health <= 0 then
                    game.score = game.score + (e.score or 100)
                    spawnParticles(e.x, e.y, 15, 255, 100, 50, 100, 0.5)
                    table.remove(enemies, ei)
                end
            end
        elseif e.alive ~= false and player.alive and player.shieldTime > 0 then
            if dist(e.x, e.y, player.x, player.y) < e.radius + player.shieldRadius then
                e.health = e.health - 3
                screenShake(4, 0.15)
                spawnParticles(e.x, e.y, 15, 50, 150, 255, 100, 0.5)
                if e.health <= 0 then
                    game.score = game.score + (e.score or 100)
                    spawnParticles(e.x, e.y, 20, 100, 200, 255, 120, 0.6)
                    table.remove(enemies, ei)
                end
            end
        end
    end

    for i = #pickups, 1, -1 do
        local p = pickups[i]
        p.life = p.life - dt
        p.pulse = p.pulse + dt * 5
        if p.life <= 0 then
            table.remove(pickups, i)
        elseif player.alive and dist(p.x, p.y, player.x, player.y) < p.radius + player.radius then
            if p.type == "health" then
                player.health = min(player.maxHealth, player.health + 1)
                spawnParticles(p.x, p.y, 10, 50, 255, 50, 60, 0.4)
            elseif p.type == "shield" then
                player.shieldTime = 30.0
                spawnParticles(p.x, p.y, 20, 50, 150, 255, 80, 0.5)
            end
            table.remove(pickups, i)
        end
    end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        p.vx = p.vx * 0.97
        p.vy = p.vy * 0.97
        if p.life <= 0 then table.remove(particles, i) end
    end

    for _, s in ipairs(stars) do
        s.y = s.y + s.speed * dt
        if s.y > H then s.y = 0; s.x = rand(0, W) end
    end

    if #enemies == 0 then
        game.waveTimer = game.waveTimer + dt
        if game.waveTimer > 2.0 then
            game.wave = game.wave + 1
            game.waveTimer = 0
            spawnWave()
        end
    end
end

local function drawPoly(cx, cy, angle, points, r, g, b, a)
    for i = 1, #points - 1 do
        local x1 = cx + cos(angle + points[i][1]) * points[i][2]
        local y1 = cy + sin(angle + points[i][1]) * points[i][2]
        local x2 = cx + cos(angle + points[i+1][1]) * points[i+1][2]
        local y2 = cy + sin(angle + points[i+1][1]) * points[i+1][2]
        local dx, dy = x2 - x1, y2 - y1
        local len = sqrt(dx*dx + dy*dy)
        if len > 0.5 then
            local mx, my = (x1+x2)/2, (y1+y2)/2
            bridge.drawRect(mx - len/2, my - 1, len, 2, r, g, b, a)
        end
    end
    if #points > 1 then
        local last = points[#points]
        local first = points[1]
        local x1 = cx + cos(angle + last[1]) * last[2]
        local y1 = cy + sin(angle + last[1]) * last[2]
        local x2 = cx + cos(angle + first[1]) * first[2]
        local y2 = cy + sin(angle + first[1]) * first[2]
        local dx, dy = x2 - x1, y2 - y1
        local len = sqrt(dx*dx + dy*dy)
        if len > 0.5 then
            local mx, my = (x1+x2)/2, (y1+y2)/2
            bridge.drawRect(mx - len/2, my - 1, len, 2, r, g, b, a)
        end
    end
end

local function drawShip(x, y, angle, r, g, b, a, scale)
    scale = scale or 1.0
    local nx, ny = cos(angle), sin(angle)
    local px, py = -ny, nx

    local tipX, tipY = x + nx * 14 * scale, y + ny * 14 * scale
    local lx, ly = x - nx * 10 * scale + px * 8 * scale, y - ny * 10 * scale + py * 8 * scale
    local rx, ry = x - nx * 10 * scale - px * 8 * scale, y - ny * 10 * scale - py * 8 * scale

    for t = 0, 1, 0.08 do
        local ax = lx + (tipX - lx) * t
        local ay = ly + (tipY - ly) * t
        local bx = rx + (tipX - rx) * t
        local by = ry + (tipY - ry) * t
        local minx = min(ax, bx)
        local maxx = max(ax, bx)
        local miny = min(ay, by)
        local maxy = max(ay, by)
        local w = max(2, maxx - minx)
        local h = max(2, maxy - miny)
        bridge.drawRect(minx, miny, w, h, r, g, b, a)
    end

    local ex, ey = x - nx * 6 * scale, y - ny * 6 * scale
    bridge.drawRect(ex - 3*scale, ey - 3*scale, 6*scale, 6*scale, floor(r*0.5), floor(g*0.5), floor(b*0.5), a)
end

function DrawGame()
    local sx, sy = 0, 0
    if game.shakeTimer > 0 then
        sx = (rand() - 0.5) * game.shakeIntensity * 2
        sy = (rand() - 0.5) * game.shakeIntensity * 2
    end

    bridge.drawRect(sx, sy, W, H, 5, 5, 12, 255)

    for _, s in ipairs(stars) do
        local br = s.brightness
        bridge.drawRect(sx + s.x, sy + s.y, s.size, s.size, br, br, floor(br * 1.2), 255)
    end

    for _, p in ipairs(pickups) do
        local pulse = 0.6 + sin(p.pulse) * 0.4
        local sz = p.radius * pulse * 2
        if p.type == "health" then
            bridge.drawRect(sx + p.x - sz/2, sy + p.y - 2, sz, 4, 50, 255, 50, 200)
            bridge.drawRect(sx + p.x - 2, sy + p.y - sz/2, 4, sz, 50, 255, 50, 200)
        else
            bridge.drawRect(sx + p.x - sz/2, sy + p.y - sz/2, sz, sz, 50, 150, 255, 200)
            bridge.drawRect(sx + p.x - sz/4, sy + p.y - sz/4, sz/2, sz/2, 100, 200, 255, 255)
        end
    end

    for _, e in ipairs(enemies) do
        if e.type == "grunt" then
            bridge.drawRect(sx + e.x - 8, sy + e.y - 8, 16, 16, 255, 60, 30, 255)
            bridge.drawRect(sx + e.x - 5, sy + e.y - 5, 10, 10, 255, 100, 50, 255)
        elseif e.type == "tank" then
            bridge.drawRect(sx + e.x - 14, sy + e.y - 14, 28, 28, 200, 50, 20, 255)
            bridge.drawRect(sx + e.x - 10, sy + e.y - 10, 20, 20, 255, 80, 30, 255)
            bridge.drawRect(sx + e.x - 6, sy + e.y - 6, 12, 12, 180, 40, 15, 255)
        elseif e.type == "fast" then
            bridge.drawRect(sx + e.x - 6, sy + e.y - 6, 12, 12, 50, 180, 255, 255)
            bridge.drawRect(sx + e.x - 3, sy + e.y - 3, 6, 6, 100, 220, 255, 255)
        elseif e.type == "shooter" then
            bridge.drawRect(sx + e.x - 10, sy + e.y - 10, 20, 20, 200, 40, 180, 255)
            bridge.drawRect(sx + e.x - 6, sy + e.y - 6, 12, 12, 255, 80, 220, 255)
            bridge.drawRect(sx + e.x - 2, sy + e.y - 2, 4, 4, 255, 180, 255, 255)
        end

        for _, b in ipairs(e.bullets) do
            if b.life > 0 then
                bridge.drawRect(sx + b.x - 3, sy + b.y - 3, 6, 6, 255, 80, 80, 255)
                bridge.drawRect(sx + b.x - 1, sy + b.y - 1, 2, 2, 255, 200, 200, 255)
            end
        end
    end

    if player.alive then
        if player.shieldTime > 0 then
            local shieldPulse = sin(player.shieldTime * 8) * 0.3 + 0.7
            local shieldAlpha = floor(160 * shieldPulse)
            local rad = player.shieldRadius
            
            -- Draw concentric shield circles
            for layer = 0, 3 do
                local r = rad - layer * 2
                local numSegs = 48
                for i = 0, numSegs - 1 do
                    local a = (i / numSegs) * TAU
                    local x = player.x + cos(a) * r
                    local y = player.y + sin(a) * r
                    local size = 3 + layer
                    bridge.drawRect(sx + x - size/2, sy + y - size/2, size, size, 50, 150, 255, floor(shieldAlpha * (1 - layer * 0.15)))
                end
            end
            
            -- Fill interior with translucent blue
            local fillRad = rad - 8
            for dy = -fillRad, fillRad, 4 do
                for dx = -fillRad, fillRad, 4 do
                    if dx*dx + dy*dy < fillRad*fillRad then
                        bridge.drawRect(sx + player.x + dx, sy + player.y + dy, 4, 4, 30, 100, 200, floor(shieldAlpha * 0.3))
                    end
                end
            end
        end

        local visible = true
        if player.invincible > 0 then
            visible = floor(player.invincible * 10) % 2 == 0
        end
        if visible then
            drawShip(sx + player.x, sy + player.y, player.angle, 50, 255, 80, 255)

            if player.thrustOn then
                local fx = player.x - cos(player.angle) * 14
                local fy = player.y - sin(player.angle) * 14
                local flicker = 4 + rand() * 6
                bridge.drawRect(sx + fx - flicker/2, sy + fy - flicker/2, flicker, flicker, 255, 200, 50, 200)
                bridge.drawRect(sx + fx - flicker/4, sy + fy - flicker/4, flicker/2, flicker/2, 255, 255, 150, 255)
            end
        end
    end

    for _, b in ipairs(player.bullets) do
        if b.life > 0 then
            bridge.drawRect(sx + b.x - 2, sy + b.y - 2, 4, 4, 150, 255, 150, 255)
            bridge.drawRect(sx + b.x - 1, sy + b.y - 1, 2, 2, 220, 255, 220, 255)
        end
    end

    for _, p in ipairs(particles) do
        local alpha = floor(255 * (p.life / p.maxLife))
        if alpha > 0 then
            bridge.drawRect(sx + p.x - p.size/2, sy + p.y - p.size/2, p.size, p.size, p.r, p.g, p.b, alpha)
        end
    end

    bridge.drawText(string.format("SCORE %07d", game.score), 10, 8, 200, 255, 200, 255)
    bridge.drawText(string.format("WAVE %d", game.wave), W/2 - 30, 8, 255, 255, 100, 255)

    for i = 1, game.lives do
        local lx = W - 30 * i
        drawShip(lx, 18, -math.pi/2, 50, 255, 80, 180, 0.6)
    end

    local barW = 80
    local barH = 6
    local barX = 10
    local barY = 26
    bridge.drawRect(barX, barY, barW, barH, 40, 40, 40, 200)
    local hpW = floor(barW * (player.health / player.maxHealth))
    local hpR = player.health <= 1 and 255 or 50
    local hpG = player.health <= 1 and 50 or 255
    bridge.drawRect(barX, barY, hpW, barH, hpR, hpG, 50, 255)

    if player.shieldTime > 0 then
        local shieldBarW = 80
        local shieldBarH = 6
        local shieldBarX = 10
        local shieldBarY = 36
        bridge.drawRect(shieldBarX, shieldBarY, shieldBarW, shieldBarH, 20, 20, 40, 200)
        local shieldW = floor(shieldBarW * (player.shieldTime / 3.0))
        bridge.drawRect(shieldBarX, shieldBarY, shieldW, shieldBarH, 50, 150, 255, 255)
    end

    if #enemies == 0 and game.waveTimer > 0 then
        local flash = floor(game.waveTimer * 4) % 2 == 0
        if flash then
            bridge.drawText(string.format("WAVE %d INCOMING", game.wave + 1), W/2 - 60, H/2 - 10, 255, 255, 100, 255)
        end
    end

    if game.state == "gameover" then
        bridge.drawRect(W/2 - 120, H/2 - 40, 240, 80, 10, 10, 10, 220)
        bridge.drawText("GAME OVER", W/2 - 40, H/2 - 20, 255, 50, 50, 255)
        bridge.drawText(string.format("FINAL SCORE: %d", game.score), W/2 - 55, H/2, 200, 200, 200, 255)
        bridge.drawText("PRESS SPACE TO RESTART", W/2 - 80, H/2 + 18, 150, 150, 150, 255)
    end
end

resetGame()

function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width = w
    root.height = h
    UpdateGame(0.016)
end

function DrawUI()
    DrawGame()
end
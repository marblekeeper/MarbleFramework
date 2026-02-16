-- netrogue/particles.lua
-- Particle system for combat effects

local Particles = {
    particles = {},
}

function Particles.spawn(x, y, count, r, g, b, speed, life)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local s = math.random() * speed + speed * 0.2
        table.insert(Particles.particles, {
            x = x, y = y,
            vx = math.cos(angle) * s,
            vy = math.sin(angle) * s,
            life = life * (0.4 + math.random() * 0.6),
            maxLife = life,
            r = r, g = g, b = b,
            size = math.random() < 0.3 and 3 or 2,
        })
    end
end

function Particles.update(dt)
    for i = #Particles.particles, 1, -1 do
        local p = Particles.particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        p.vx = p.vx * 0.95
        p.vy = p.vy * 0.95
        
        if p.life <= 0 then
            table.remove(Particles.particles, i)
        end
    end
end

function Particles.clear()
    Particles.particles = {}
end

return Particles
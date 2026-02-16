-- ohko.lua
-- TACTICAL 1-HIT KILL
-- Mechanics: High/Mid/Low attacks, Stamina, Counter-attacks, Bursty Movement

local root = UIElement:new({width=800, height=600})

-- CONFIG
local DEBUG_MODE = true -- Set to true to see Hitboxes (Red) and Hurtboxes (Green/Blue)
local W, H = 800, 600
local FLOOR_Y = 450

-- ASSETS
local TEXTURE_PATH = "assets/Content/textures/kung_fu_idle.png"
local texID = nil

-- CONSTANTS
local STAMINA_MAX = 100
local STAMINA_REGEN = 0.5
local COST_ATTACK = 25
local COST_BLOCK_PER_FRAME = 0.2
local FRICTION = 0.85      -- Lower = slippery, Higher = snappy (0.85 = heavy steps)
local ACCEL = 3.0          -- How fast we burst into speed
local MAX_SPEED = 12.0

-- ATTACK DEFINITIONS
local ATTACKS = {
    HIGH = { id="high", windup=15, active=5, recover=20, y_off=-25, range=70, w=50, h=30, damage=100 },
    MID  = { id="mid",  windup=10, active=5, recover=15, y_off=0,   range=60, w=60, h=30, damage=100 },
    LOW  = { id="low",  windup=12, active=5, recover=18, y_off=30,  range=60, w=60, h=25, damage=100 }
}

-- STATE
local game = {
    over = false,
    winner = "",
    slowMoTimer = 0,
    resetTimer = 0
}

-- UTILS
local function checkRect(r1, r2)
    return r1.x < r2.x + r2.w and
           r1.x + r1.w > r2.x and
           r1.y < r2.y + r2.h and
           r1.y + r1.h > r2.y
end

local function isKeyDown(key)
    if not bridge.getKeyState then return false end
    return bridge.getKeyState(key) == 1
end

-- ENTITY FACTORY
local function createFighter(x, color, isPlayer)
    return {
        -- Physics
        x = x, y = FLOOR_Y,
        vx = 0,
        w = 50, h = 90, -- Hurtbox dimensions
        facing = isPlayer and 1 or -1,
        
        -- Gameplay Stats
        isPlayer = isPlayer,
        color = color,
        hp = 1,
        stamina = STAMINA_MAX,
        
        -- State Machine
        state = "idle", -- idle, move, crouch, windup, active, recover, block, counter, stun, dead
        frame = 1,      -- 1:Idle, 2:Move/Crouch, 3:Windup, 4:Strike
        
        -- Combat Data
        currentAttack = nil, -- Reference to ATTACKS table
        timer = 0,           -- General purpose timer for states
        blockHeight = "mid", -- mid (covers high/mid), low (covers mid/low)
        
        hitbox = nil -- {x,y,w,h} when active
    }
end

local p1 = createFighter(200, {100, 200, 255}, true)
local ai = createFighter(600, {255, 80, 80}, false)

-- LOGIC
local function updateFighter(e, target, dt)
    -- 1. Physics (Bursty Movement)
    e.x = e.x + e.vx
    e.vx = e.vx * FRICTION -- Apply friction every frame
    if math.abs(e.vx) < 0.1 then e.vx = 0 end
    
    -- Keep in bounds
    if e.x < 0 then e.x = 0; e.vx = 0 end
    if e.x > W - e.w then e.x = W - e.w; e.vx = 0 end

    -- 2. Stamina Regen
    if e.state ~= "block" and e.state ~= "windup" and e.state ~= "active" then
        e.stamina = math.min(STAMINA_MAX, e.stamina + STAMINA_REGEN)
    end

    -- 3. State Management
    if e.state == "dead" then
        e.frame = 2 -- Collapse frame
        return
    end

    -- Hitbox Cleanup
    e.hitbox = nil 

    -- COUNTER STATE (High Risk)
    if e.state == "counter" then
        e.timer = e.timer - 1
        e.vx = 0
        e.frame = 3
        -- If hit during this, logic handled in collision
        if e.timer <= 0 then e.state = "idle" end
        return
    end

    -- STUN STATE
    if e.state == "stun" then
        e.timer = e.timer - 1
        e.frame = 2
        if e.timer <= 0 then e.state = "idle" end
        return
    end

    -- ATTACK CYCLE
    if e.state == "windup" then
        e.vx = e.vx * 0.5 -- Slow down significantly
        e.timer = e.timer - 1
        e.frame = 3
        if e.timer <= 0 then
            e.state = "active"
            e.timer = e.currentAttack.active
            -- Play sound here if possible
        end
        return
    elseif e.state == "active" then
        e.frame = 4
        e.timer = e.timer - 1
        
        -- Create Hitbox
        local atk = e.currentAttack
        local hx = e.x + (e.facing * 30) + (e.facing == 1 and e.w or -atk.w)
        local hy = e.y + 30 + atk.y_off 
        e.hitbox = { x = hx, y = hy, w = atk.w, h = atk.h, type = atk.id }
        
        -- Slight Lunge
        e.vx = e.facing * 2

        if e.timer <= 0 then
            e.state = "recover"
            e.timer = atk.recover
        end
        return
    elseif e.state == "recover" then
        e.frame = 3
        e.timer = e.timer - 1
        if e.timer <= 0 then e.state = "idle" end
        return
    end

    -- NEUTRAL STATES (Input Allowed)
    
    -- Reset vars
    local moveDir = 0
    local crouch = false
    local attackInput = nil -- "high", "mid", "low"
    local counterInput = false
    local blockInput = false

    -- PLAYER INPUT
    if e.isPlayer then
        -- Movement
        if isKeyDown("left") or isKeyDown("a") then moveDir = -1 end
        if isKeyDown("right") or isKeyDown("d") then moveDir = 1 end
        if isKeyDown("down") or isKeyDown("s") then crouch = true end
        
        -- Modifiers
        local shift = (isKeyDown("shift") or isKeyDown("rshift"))

        -- Combat Inputs
        if isKeyDown("space") then
            if shift then attackInput = "HIGH"
            elseif crouch then attackInput = "LOW"
            else attackInput = "MID"
            end
        elseif isKeyDown("f") then -- 'F' to Counter
            counterInput = true
        elseif isKeyDown("b") or (e.facing == 1 and moveDir == -1) or (e.facing == -1 and moveDir == 1) then
            -- Walking backwards counts as blocking
            blockInput = true
        end
    else
        -- AI LOGIC
        local dx = target.x - e.x
        local dist = math.abs(dx)
        
        -- Face player
        if dx > 0 then e.facing = 1 else e.facing = -1 end

        if dist > 120 then
            moveDir = (dx > 0) and 1 or -1
        elseif dist < 80 then
            moveDir = (dx > 0) and -1 or 1 -- Back off
            blockInput = true
        else
            -- In range logic
            local roll = math.random()
            if roll < 0.02 and e.stamina > 30 then attackInput = "MID"
            elseif roll < 0.04 and e.stamina > 30 then attackInput = "LOW"
            elseif roll < 0.05 and e.stamina > 30 then attackInput = "HIGH"
            elseif roll < 0.06 then counterInput = true
            elseif roll < 0.1 then crouch = true
            end
        end
    end

    -- EXECUTE ACTIONS
    
    -- 1. Counter (Highest Priority)
    if counterInput and e.stamina > 10 then
        e.state = "counter"
        e.timer = 15 -- 15 frames (0.25s) window
        e.stamina = e.stamina - 10
        return
    end

    -- 2. Attack
    if attackInput and e.stamina >= COST_ATTACK then
        e.state = "windup"
        e.currentAttack = ATTACKS[attackInput]
        e.timer = e.currentAttack.windup
        e.stamina = e.stamina - COST_ATTACK
        return
    end

    -- 3. Movement / Block / Crouch
    if crouch then
        e.state = "crouch"
        e.h = 60 -- Shrink hurtbox
        e.y = FLOOR_Y + 30 -- Visually lower
        e.vx = 0 -- Cannot move while crouching (or make it very slow)
        e.frame = 2
        
        if blockInput then 
            e.state = "block"
            e.blockHeight = "low" 
            e.stamina = e.stamina - COST_BLOCK_PER_FRAME
        end
    else
        e.h = 90
        e.y = FLOOR_Y
        
        if blockInput then
            e.state = "block"
            e.blockHeight = "mid"
            e.stamina = e.stamina - COST_BLOCK_PER_FRAME
            e.vx = moveDir * ACCEL * 0.5 -- Walk slower while blocking
            e.frame = 2
        elseif moveDir ~= 0 then
            e.state = "move"
            e.vx = e.vx + (moveDir * ACCEL)
            e.vx = math.max(math.min(e.vx, MAX_SPEED), -MAX_SPEED)
            e.frame = (math.floor(os.clock() * 8) % 2) + 1 -- Animate walk
        else
            e.state = "idle"
            e.frame = 1
        end
    end
end

local function resolveCombat(attacker, defender)
    if not attacker.hitbox then return end
    if defender.state == "dead" then return end

    -- Calculate Defender Hurtbox
    -- Note: We modified defender.y and defender.h in updateFighter based on crouch
    local hurtbox = { x = defender.x, y = defender.y, w = defender.w, h = defender.h }

    if checkRect(attacker.hitbox, hurtbox) then
        
        -- HIT DETECTED
        local hitType = attacker.hitbox.type -- high, mid, low
        local blocked = false
        local countered = (defender.state == "counter")

        if countered then
            -- INSTANT REVERSAL
            attacker.state = "dead"
            game.winner = defender.isPlayer and "PLAYER 1" or "CPU"
            game.over = true
            game.slowMoTimer = 60
            return
        end

        if defender.state == "block" and defender.stamina > 0 then
            -- Block Logic
            if hitType == "high" and defender.blockHeight == "mid" then blocked = true end
            if hitType == "mid" then blocked = true end -- Blocked by standing or crouching
            if hitType == "low" and defender.blockHeight == "low" then blocked = true end
        end

        if blocked then
            -- Pushback
            defender.vx = attacker.facing * 10
            attacker.vx = -attacker.facing * 5
            defender.stamina = math.max(0, defender.stamina - 15)
            attacker.state = "recover" -- Force attacker into recovery
            attacker.hitbox = nil -- Disable hitbox immediately
        else
            -- CLEAN HIT
            defender.state = "dead"
            game.winner = attacker.isPlayer and "PLAYER 1" or "CPU"
            game.over = true
            game.slowMoTimer = 60 -- 1 second of slowmo
        end
    end
end

------------------------------------------------------------------------
-- MAIN LOOPS
------------------------------------------------------------------------

function UpdateUI(mx, my, down, w, h)
    W, H = w, h
    root.width, root.height = w, h

    -- Load Texture Once
    if not texID and bridge.loadTexture then
        texID = bridge.loadTexture(TEXTURE_PATH)
    end

    -- Reset Handling
    if game.over and game.slowMoTimer <= 0 then
        if isKeyDown("space") then
            -- Reset
            p1 = createFighter(200, {100, 200, 255}, true)
            ai = createFighter(600, {255, 80, 80}, false)
            game.over = false
        end
        return
    end

    local dt = 1
    if game.slowMoTimer > 0 then
        game.slowMoTimer = game.slowMoTimer - 1
        dt = 0.1 -- Slow motion factor
    end

    if not game.over then
        updateFighter(p1, ai, dt)
        updateFighter(ai, p1, dt)
        resolveCombat(p1, ai)
        resolveCombat(ai, p1)
    end
end

function DrawUI()
    -- 1. Background
    bridge.drawRect(0, 0, W, H, 30, 30, 35, 255) -- Dark Grey BG
    bridge.drawRect(0, FLOOR_Y + 90, W, H - (FLOOR_Y + 90), 15, 15, 20, 255) -- Floor

    -- 2. Helpers
    local function drawFighter(e)
        -- Shadow
        bridge.drawRect(e.x + 5, FLOOR_Y + 85, e.w - 10, 6, 0, 0, 0, 100)

        -- Sprite Calculation
        -- Sheet is 64x64. Frame 1 (0,0), Frame 2 (64,0), etc.
        local sx = (e.frame - 1) * 64
        local sy = 0
        local sw, sh = 64, 64
        
        -- If counter state, tint gold
        local r, g, b = e.color[1], e.color[2], e.color[3]
        if e.state == "counter" then r,g,b = 255, 255, 0 end
        if e.state == "block" then r,g,b = 150, 150, 150 end

        if texID and bridge.drawTexture then
            -- Determine UVs based on facing
            -- Standard drawTexture usually doesn't support UVs in basic bridge, 
            -- assuming standard draw: drawTexture(id, x, y, w, h, r, g, b, a)
            -- If we can't do UVs, we just draw the whole thing, but let's assume 
            -- we fallback to Rects if UV not supported, or just draw the texture.
            -- Since the prompt implies basic "render with a texture", we will just draw it.
            
            -- Simple bobbing for breathing
            local breathe = (e.state == "idle") and math.sin(os.clock()*5)*2 or 0
            
            bridge.drawTexture(texID, e.x - 7, e.y - 10 + breathe, 64*1.5, 64*1.5, r, g, b, 255)
            
            -- Facing Indicator (Small eye dot)
            if e.facing == 1 then
                bridge.drawRect(e.x + 40, e.y + 10, 4, 4, 255, 255, 255, 255)
            else
                bridge.drawRect(e.x + 10, e.y + 10, 4, 4, 255, 255, 255, 255)
            end
        else
            -- Fallback Rect
            local h = e.h
            if e.state == "crouch" then h = 60 end
            bridge.drawRect(e.x, e.y, e.w, h, r, g, b, 255)
            
            -- Eye
            local ex = (e.facing == 1) and (e.x + e.w - 10) or (e.x + 2)
            bridge.drawRect(ex, e.y + 10, 8, 8, 255, 255, 255, 255)
        end

        -- DEBUG HITBOXES
        if DEBUG_MODE then
            -- Hurtbox (Green = Safe, Yellow = Blocking, Blue = Vulnerable)
            local hr, hg, hb = 0, 255, 0
            if e.state == "block" then hr, hg, hb = 255, 255, 0 
            else hr, hg, hb = 0, 100, 255 end
            
            -- Draw wireframe hurtbox
            bridge.drawRect(e.x, e.y, e.w, 2, hr, hg, hb, 200)
            bridge.drawRect(e.x, e.y + e.h, e.w, 2, hr, hg, hb, 200)
            bridge.drawRect(e.x, e.y, 2, e.h, hr, hg, hb, 200)
            bridge.drawRect(e.x + e.w, e.y, 2, e.h, hr, hg, hb, 200)

            -- Attack Hitbox (Red filled)
            if e.hitbox then
                bridge.drawRect(e.hitbox.x, e.hitbox.y, e.hitbox.w, e.hitbox.h, 255, 0, 0, 150)
            end
        end

        -- STAMINA BAR
        local barW = 50
        bridge.drawRect(e.x, e.y - 15, barW, 6, 50, 50, 50, 255)
        local stW = (e.stamina / STAMINA_MAX) * barW
        local stC = (e.stamina < COST_ATTACK) and {150, 150, 150} or {0, 255, 100}
        bridge.drawRect(e.x, e.y - 15, stW, 6, stC[1], stC[2], stC[3], 255)
    end

    drawFighter(p1)
    drawFighter(ai)

    -- 3. UI Overlay
    if game.over then
        local cx, cy = W/2, H/2
        bridge.drawRect(0, cy - 80, W, 160, 0, 0, 0, 220)
        bridge.drawText("FATAL HIT", cx - 60, cy - 30, 255, 50, 50, 255)
        bridge.drawText(game.winner .. " WINS", cx - 50, cy, 255, 255, 255, 255)
        
        if game.slowMoTimer <= 0 then
            bridge.drawText("PRESS SPACE TO REMATCH", cx - 90, cy + 40, 200, 200, 200, 255)
        end
    else
        bridge.drawText("CONTROLS:", 10, 10, 150, 150, 150, 255)
        bridge.drawText("WASD: Move  S: Crouch  F: Counter", 10, 30, 200, 200, 200, 255)
        bridge.drawText("SPACE: Mid Attack", 10, 50, 200, 200, 200, 255)
        bridge.drawText("CROUCH + SPACE: Low Attack", 10, 70, 200, 200, 200, 255)
        bridge.drawText("SHIFT + SPACE: High Attack", 10, 90, 200, 200, 200, 255)
        bridge.drawText("HOLD BACK: Block (Costs Stamina)", 10, 110, 200, 200, 200, 255)
    end
end
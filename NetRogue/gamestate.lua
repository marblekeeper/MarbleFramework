-- netrogue/gamestate.lua
-- Central game state management

local GameState = {
    state = "connecting",  -- "connecting", "playing", "disconnected"
    pulseTimer = 0,
    shakeTimer = 0,
    shakeIntensity = 0,
}

function GameState.updateTimers(dt)
    GameState.pulseTimer = GameState.pulseTimer + dt
    if GameState.shakeTimer > 0 then
        GameState.shakeTimer = GameState.shakeTimer - dt
    end
end

function GameState.screenShake(intensity, duration)
    GameState.shakeTimer = duration
    GameState.shakeIntensity = intensity
end

function GameState.getShake()
    if GameState.shakeTimer <= 0 then
        return 0, 0
    end
    local t = GameState.shakeTimer
    local intensity = GameState.shakeIntensity
    return math.sin(t * 80) * intensity, math.cos(t * 100) * intensity
end

return GameState
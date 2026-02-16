-- netrogue/input.lua
-- Input handling and key state tracking

local Input = {
    keyWasDown = {},
}

function Input.keyPressed(key)
    if not bridge.getKeyState then return false end
    local down = bridge.getKeyState(key) == 1
    local wasDown = Input.keyWasDown[key] or false
    Input.keyWasDown[key] = down
    return down and not wasDown
end

return Input
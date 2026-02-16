-- netrogue/messagelog.lua
-- Combat and event message logging

local MessageLog = {
    messages = {},
    maxMessages = 14,
}

function MessageLog.add(text, color)
    table.insert(MessageLog.messages, 1, {
        text = text,
        r = color[1],
        g = color[2],
        b = color[3],
        age = 0,
    })
    
    -- Trim excess messages
    while #MessageLog.messages > MessageLog.maxMessages do
        table.remove(MessageLog.messages)
    end
end

function MessageLog.update(dt)
    for _, msg in ipairs(MessageLog.messages) do
        msg.age = msg.age + dt
    end
end

function MessageLog.clear()
    MessageLog.messages = {}
end

return MessageLog
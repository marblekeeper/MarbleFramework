-- protocol.lua
-- Shared network protocol definitions for Marble Roguelike
-- Include this file in both client and server

local Protocol = {}

-- Command definitions (string-based for now, easy to migrate to binary later)
Protocol.CMD = {
    -- Movement
    MOVE = "MOVE",
    
    -- Actions
    PRAY = "PRAY",
    SIT = "SIT",
    STAND = "STAND",
    MEDITATE = "MEDITATE",
    
    -- Future expansion
    -- ATTACK = "ATTACK",
    -- USE_ITEM = "USE_ITEM",
    -- CHAT = "CHAT",
}

-- Server responses
Protocol.RESPONSE = {
    AUTH_OK = "AUTH:OK",
    INTENT_ACK = "INTENT_ACK",
    POS = "POS",
    PLAYER_JOIN = "PLAYER_JOIN",
    PLAYER_MOVE = "PLAYER_MOVE",
    PLAYER_LEAVE = "PLAYER_LEAVE",
    PLAYER_ACTION = "PLAYER_ACTION",
    ERROR = "ERROR",
}

-- Error codes
Protocol.ERROR = {
    INTENT_LIMIT_EXCEEDED = "INTENT_LIMIT_EXCEEDED",
    INVALID_COMMAND = "INVALID_COMMAND",
    INVALID_POSITION = "INVALID_POSITION",
}

-- Packet construction helpers
function Protocol.make_move_packet(x, y)
    return string.format("%s:%d,%d\n", Protocol.CMD.MOVE, x, y)
end

function Protocol.make_action_packet(action, arg)
    if arg then
        return string.format("%s:%s\n", action, arg)
    else
        return string.format("%s:\n", action)
    end
end

-- Packet parsing helpers
function Protocol.parse_packet(data)
    local cmd, args = data:match("^(%w+):(.*)$")
    return cmd, args
end

function Protocol.parse_move_args(args)
    local x, y = args:match("^([%-]?%d+),([%-]?%d+)$")
    if x and y then
        return tonumber(x), tonumber(y)
    end
    return nil, nil
end

function Protocol.parse_response(data)
    -- Extract response type and data
    local resp_type, rest = data:match("^([%w_:]+):?(.*)$")
    return resp_type, rest
end

return Protocol
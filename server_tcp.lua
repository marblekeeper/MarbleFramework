-- server_tcp.lua
-- Pure TCP server for desktop offline/LAN mode
-- This is your original server.lua - unchanged and working

local socket = require("socket")
local Protocol = require("protocol")

-- Server configuration
local HOST = "127.0.0.1"
local PORT = 12345
local TICK_RATE = 0.6 -- seconds per tick
local MAX_INTENTS_PER_TICK = 5

-- Create TCP socket
local server = assert(socket.bind(HOST, PORT))
server:settimeout(0) -- Non-blocking mode

print("=== MARBLE ROGUELIKE SERVER (TCP) ===")
print(string.format("Listening on %s:%d", HOST, PORT))
print(string.format("Tick Rate: %.2f seconds (%.1f ticks/sec)", TICK_RATE, 1/TICK_RATE))
print(string.format("Max Intents: %d per client per tick", MAX_INTENTS_PER_TICK))
print("Waiting for clients...\n")

-- Client data structures
local clients = {}
local client_positions = {} -- Immutable state (updated only on tick)
local client_states = {} -- Track action states (sitting, praying, etc)
local command_buffers = {} -- Intent queue per client
local intent_counts = {} -- Track intents submitted this tick

-- Tick tracking
local tick_number = 0
local tick_accumulator = 0.0
local last_frame_time = socket.gettime()

-- Command handlers (using shared protocol)
local ACTION_HANDLERS = {
    [Protocol.CMD.MOVE] = function(args)
        local x, y = Protocol.parse_move_args(args)
        if x and y then
            return {type = Protocol.CMD.MOVE, x = x, y = y}
        end
        return nil
    end,
    
    [Protocol.CMD.PRAY] = function(args)
        return {type = Protocol.CMD.PRAY}
    end,
    
    [Protocol.CMD.SIT] = function(args)
        return {type = Protocol.CMD.SIT}
    end,
    
    [Protocol.CMD.STAND] = function(args)
        return {type = Protocol.CMD.STAND}
    end,
    
    [Protocol.CMD.MEDITATE] = function(args)
        local duration = tonumber(args) or 60
        return {type = Protocol.CMD.MEDITATE, duration = duration}
    end,
}

local function parse_packet(data)
    local cmd, args = Protocol.parse_packet(data)
    local handler = ACTION_HANDLERS[cmd]
    if handler then
        return handler(args)
    end
    return nil
end

local function broadcast(message, exclude_client)
    for _, client in ipairs(clients) do
        if client ~= exclude_client then
            client:send(message .. "\n")
        end
    end
end

-- Process intent submission (does NOT execute yet)
local function submit_intent(client, intent)
    -- Check intent limit
    if intent_counts[client] >= MAX_INTENTS_PER_TICK then
        client:send(string.format("%s:%s\n", Protocol.RESPONSE.ERROR, Protocol.ERROR.INTENT_LIMIT_EXCEEDED))
        return false
    end
    
    -- "Last one in" - overwrite previous intent for this tick
    command_buffers[client] = intent
    intent_counts[client] = intent_counts[client] + 1
    
    -- Acknowledge intent received (not processed yet)
    client:send(Protocol.RESPONSE.INTENT_ACK .. "\n")
    return true
end

-- Process all command buffers at tick boundary
local function process_tick()
    tick_number = tick_number + 1
    print(string.format("\n[TICK #%d] Processing commands...", tick_number))
    
    -- Process each client's buffered command
    for i, client in ipairs(clients) do
        local intent = command_buffers[client]
        
        if intent then
            if intent.type == Protocol.CMD.MOVE then
                -- Update immutable state
                local pos = client_positions[client]
                pos.x = intent.x
                pos.y = intent.y
                
                print(string.format("  [Client #%d] MOVE -> (%d, %d)", i, pos.x, pos.y))
                
                -- Confirm movement to client
                client:send(string.format("%s:%d,%d,TICK:%d\n", Protocol.RESPONSE.POS, pos.x, pos.y, tick_number))
                
                -- Broadcast to other clients
                broadcast(string.format("%s:%d,%d,%d,TICK:%d\n", Protocol.RESPONSE.PLAYER_MOVE, i, pos.x, pos.y, tick_number), client)
            
            elseif intent.type == Protocol.CMD.PRAY or intent.type == Protocol.CMD.SIT or 
                   intent.type == Protocol.CMD.STAND or intent.type == Protocol.CMD.MEDITATE then
                -- Update client state
                client_states[client] = intent.type
                
                print(string.format("  [Client #%d] ACTION -> %s", i, intent.type))
                
                -- Confirm action
                client:send(string.format("%s:%s,TICK:%d\n", Protocol.RESPONSE.PLAYER_ACTION, intent.type, tick_number))
                
                -- Broadcast to other clients
                broadcast(string.format("%s:%d,%s,TICK:%d\n", Protocol.RESPONSE.PLAYER_ACTION, i, intent.type, tick_number), client)
            end
        end
    end
    
    -- Clear command buffers for next tick
    for _, client in ipairs(clients) do
        command_buffers[client] = nil
        intent_counts[client] = 0
    end
    
    print(string.format("[TICK #%d] Complete. State is now immutable.\n", tick_number))
end

-- Main server loop
while true do
    local current_time = socket.gettime()
    local delta_time = current_time - last_frame_time
    last_frame_time = current_time
    
    tick_accumulator = tick_accumulator + delta_time
    
    -- Accept new connections
    local client = server:accept()
    if client then
        client:settimeout(0)
        table.insert(clients, client)
        local client_id = #clients
        client_positions[client] = {x = 0, y = 0} -- Spawn at origin
        client_states[client] = Protocol.CMD.STAND -- Default state
        command_buffers[client] = nil
        intent_counts[client] = 0
        
        print(string.format("[Client #%d] Connected from %s", client_id, client:getpeername()))
        client:send(string.format("%s,ID:%d,TICK:%d\n", Protocol.RESPONSE.AUTH_OK, client_id, tick_number))
        broadcast(string.format("%s:%d,TICK:%d\n", Protocol.RESPONSE.PLAYER_JOIN, client_id, tick_number), client)
    end
    
    -- Handle existing clients (receive intents)
    for i = #clients, 1, -1 do
        local client = clients[i]
        local data, err = client:receive("*l") -- Line-based protocol
        
        if data then
            local packet = parse_packet(data)
            if packet then
                -- Submit intent (will be processed on next tick)
                submit_intent(client, packet)
            else
                client:send(string.format("%s:%s\n", Protocol.RESPONSE.ERROR, Protocol.ERROR.INVALID_COMMAND))
            end
        elseif err == "closed" then
            print(string.format("[Client #%d] Disconnected", i))
            broadcast(string.format("%s:%d,TICK:%d\n", Protocol.RESPONSE.PLAYER_LEAVE, i, tick_number), client)
            client:close()
            table.remove(clients, i)
            client_positions[client] = nil
            client_states[client] = nil
            command_buffers[client] = nil
            intent_counts[client] = nil
        end
        -- "timeout" error is expected in non-blocking mode
    end
    
    -- Tick boundary: process all buffered commands
    if tick_accumulator >= TICK_RATE then
        process_tick()
        tick_accumulator = tick_accumulator - TICK_RATE
    end
    
    -- Prevent CPU spinning
    socket.sleep(0.01)
end
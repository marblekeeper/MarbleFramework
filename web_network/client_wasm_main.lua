-- client_wasm_main.lua
-- WASM entry point using JavaScript WebSocket bridge

local ws = require("websocket")
local Protocol = require("protocol")
local NetworkConfig = require("network_config")

print("=== MARBLE ROGUELIKE CLIENT (WASM) ===")
print("Initializing WebSocket connection...")

-- Get endpoint
local endpoint = NetworkConfig.get_endpoint(false) -- Offline mode

print(string.format("Connecting to: %s:%d", endpoint.host, endpoint.port))

-- Connect via JavaScript WebSocket
local success = ws.connect(endpoint.host, endpoint.port)

if success then
    print("Connection initiated!")
else
    print("Failed to initiate connection!")
    return
end

-- Global state
_G.ws = ws
_G.player_id = nil
_G.pos_x = 0
_G.pos_y = 0
_G.frame_count = 0
_G.connection_state = "connecting"

-- Process messages
function process_messages()
    while true do
        local msg = _G.ws.receive()
        if not msg then break end
        
        print("← Server: " .. msg)
        
        -- Parse responses
        if msg:match("^AUTH:OK") then
            _G.player_id = tonumber(msg:match("ID:(%d+)"))
            print(string.format("[OK] Authenticated as Player #%d", _G.player_id))
        elseif msg:match("^POS:") then
            local x, y = msg:match("^POS:([%-]?%d+),([%-]?%d+)")
            if x and y then
                _G.pos_x, _G.pos_y = tonumber(x), tonumber(y)
                print(string.format("Position: (%d, %d)", _G.pos_x, _G.pos_y))
            end
        elseif msg:match("^INTENT_ACK") then
            print("[OK] Server acknowledged intent")
        elseif msg:match("^PLAYER_JOIN") then
            local id = tonumber(msg:match("^PLAYER_JOIN:(%d+)"))
            print(string.format("→ Player #%d joined", id))
        elseif msg:match("^PLAYER_MOVE") then
            local id, x, y = msg:match("^PLAYER_MOVE:(%d+),([%-]?%d+),([%-]?%d+)")
            print(string.format("→ Player #%s moved to (%s, %s)", id, x, y))
        elseif msg:match("^PLAYER_LEAVE") then
            local id = tonumber(msg:match("^PLAYER_LEAVE:(%d+)"))
            print(string.format("← Player #%d left", id))
        end
    end
end

-- Main update loop (called by Emscripten at 60 FPS)
function update()
    _G.frame_count = _G.frame_count + 1
    
    -- Log status every second
    if _G.frame_count % 60 == 1 then
        local connected = _G.ws.is_connected()
        print(string.format("[Frame %d] State: %s, Connected: %s", 
            _G.frame_count, _G.connection_state, tostring(connected)))
    end
    
    -- Check for connection
    if _G.connection_state == "connecting" and _G.ws.is_connected() then
        _G.connection_state = "connected"
        print("[OK] WebSocket connected!")
    end
    
    -- Process messages
    if _G.connection_state == "connected" then
        process_messages()
        
        -- Send test movement every 5 seconds
        if _G.frame_count % 300 == 150 then
            local move_packet = Protocol.make_move_packet(1, 0)
            _G.ws.send(move_packet)
            print("→ Sent test movement")
        end
    end
end

print("WASM client initialized")
print("Waiting for WebSocket connection...")
print("update() function registered for Emscripten main loop")
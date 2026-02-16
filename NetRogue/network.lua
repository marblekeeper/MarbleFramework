-- netrogue/network.lua
-- Network layer: TCP connection and communication
-- WASM-READY VERSION with platform detection

-- Platform detection: LuaSocket won't be available in WASM
local IS_WASM = false
local socket = nil
local pcall_success, socket_module = pcall(require, "socket")
if pcall_success then
    socket = socket_module
    print("[Network] Desktop mode: Using LuaSocket")
else
    IS_WASM = true
    print("[Network] WASM mode: Using JavaScript WebSocket bridge")
end

local ProtocolModule = require("protocol")

local Network = {
    client = nil,
    connected = false,
    host = "127.0.0.1",
    port = 12345,
    player_id = nil,
    tick = 0,
    recv_buffer = "",
    connect_timer = 0,
    connect_attempts = 0,
    max_connect_attempts = 5,
    status_msg = "Connecting...",
    map_seed = nil,
    
    -- Platform flags
    IS_WASM = IS_WASM,
    OFFLINE_MODE = false,  -- Set to true for Phase 1 offline testing
}

-- ============================================================
-- WASM WEBSOCKET TRANSPORT (Phase 2)
-- ============================================================
if IS_WASM then
    function Network.connect()
        if Network.OFFLINE_MODE then
            -- PHASE 1: Simulate connection for offline testing
            Network.connected = true
            Network.player_id = 1
            Network.map_seed = 42
            Network.status_msg = "OFFLINE MODE (PHASE 1)"
            print("[Network] WASM OFFLINE MODE: Simulated connection")
            return true
        end
        
        -- PHASE 2: Real WebSocket connection via JavaScript bridge
        Network.status_msg = "Connecting via WebSocket..."
        
        if not bridge or not bridge.callJS then
            print("[Network] ERROR: bridge.callJS not available")
            Network.status_msg = "WebSocket bridge unavailable"
            return false
        end
        
        -- Call JavaScript to initiate WebSocket connection
        local wsUrl = "ws://localhost:8080"  -- websockify proxy
        bridge.callJS("wsConnect('" .. wsUrl .. "')")
        
        -- Poll for connection (non-blocking)
        Network.connect_timer = 0
        print("[Network] WebSocket connection initiated to " .. wsUrl)
        return false  -- Will become true when wsIsConnected() returns 1
    end
    
    function Network.send(packet)
        if Network.OFFLINE_MODE then
            print("[Network] OFFLINE: Would send: " .. packet)
            return
        end
        
        if not Network.connected then return end
        
        if bridge and bridge.callJS then
            -- Remove newline for JavaScript, we'll add it on the JS side
            local msg = packet:gsub("\n", "")
            bridge.callJS("wsSendMessage('" .. msg:gsub("'", "\\'") .. "')")
        end
    end
    
    function Network.receive()
        if Network.OFFLINE_MODE then
            return nil  -- No server messages in offline mode
        end
        
        if not Network.connected then return nil end
        
        if not bridge or not bridge.callJS then return nil end
        
        -- Get message from JavaScript WebSocket
        local data = bridge.callJS("wsGetMessage()")
        
        if not data or data == "" then
            return nil
        end
        
        -- Return as single-item array (messagehandler expects array)
        return {data}
    end
    
    function Network.updateConnecting(dt)
        if Network.OFFLINE_MODE then return end
        
        Network.connect_timer = Network.connect_timer + dt
        
        -- Check if WebSocket is connected
        if not Network.connected and bridge and bridge.callJS then
            local wsStatus = bridge.callJS("wsIsConnected()")
            if wsStatus == "1" or tonumber(wsStatus) == 1 then
                Network.connected = true
                Network.status_msg = "Connected via WebSocket!"
                print("[Network] WebSocket connected!")
            end
        end
        
        -- Retry connection if not connected after timeout
        if not Network.connected and Network.connect_timer > 2.0 then
            Network.connect_timer = 0
            if Network.connect_attempts < Network.max_connect_attempts then
                Network.connect_attempts = Network.connect_attempts + 1
                Network.connect()
            else
                Network.status_msg = "Connection failed (WebSocket)"
            end
        end
    end

-- ============================================================
-- DESKTOP TCP TRANSPORT (Original LuaSocket)
-- ============================================================
else
    function Network.connect()
        if Network.OFFLINE_MODE then
            -- Desktop can also run offline for testing
            Network.connected = true
            Network.player_id = 1
            Network.map_seed = 42
            Network.status_msg = "OFFLINE MODE"
            print("[Network] Desktop OFFLINE MODE: Simulated connection")
            return true
        end
        
        Network.status_msg = "Connecting to " .. Network.host .. ":" .. Network.port .. "..."
        Network.client = socket.tcp()
        Network.client:settimeout(2)
        local ok, err = Network.client:connect(Network.host, Network.port)
        if ok then
            Network.connected = true
            Network.client:settimeout(0)
            Network.status_msg = "Connected! Waiting for auth..."
            print("[NetRogue] Connected to server")
            return true
        else
            Network.connect_attempts = Network.connect_attempts + 1
            Network.status_msg = "Connection failed: " .. tostring(err) ..
                " (attempt " .. Network.connect_attempts .. "/" .. Network.max_connect_attempts .. ")"
            print("[NetRogue] " .. Network.status_msg)
            Network.client:close()
            Network.client = nil
            return false
        end
    end
    
    function Network.send(packet)
        if Network.OFFLINE_MODE then
            print("[Network] OFFLINE: Would send: " .. packet)
            return
        end
        
        if Network.connected and Network.client then
            local ok, err = Network.client:send(packet)
            if not ok then
                print("[NetRogue] Send error: " .. tostring(err))
                if err == "closed" then
                    Network.connected = false
                    Network.status_msg = "Disconnected from server"
                end
            end
        end
    end
    
    function Network.receive()
        if Network.OFFLINE_MODE then
            return nil
        end
        
        if not Network.connected or not Network.client then
            return nil
        end
        
        local data, err, partial = Network.client:receive("*a")
        if err == "closed" then
            Network.connected = false
            Network.status_msg = "Disconnected from server"
            return nil
        end
        
        if data then
            Network.recv_buffer = Network.recv_buffer .. data
        elseif partial then
            Network.recv_buffer = Network.recv_buffer .. partial
        end
        
        local lines = {}
        while true do
            local pos = Network.recv_buffer:find("\n")
            if not pos then break end
            local line = Network.recv_buffer:sub(1, pos - 1)
            Network.recv_buffer = Network.recv_buffer:sub(pos + 1)
            if #line > 0 then
                table.insert(lines, line)
            end
        end
        
        return #lines > 0 and lines or nil
    end
    
    function Network.updateConnecting(dt)
        if Network.OFFLINE_MODE then return end
        
        Network.connect_timer = Network.connect_timer + dt
        if not Network.connected and Network.connect_timer > 2.0 then
            Network.connect_timer = 0
            if Network.connect_attempts < Network.max_connect_attempts then
                Network.connect()
            end
        end
    end
end

-- ============================================================
-- SHARED FUNCTIONS (same for both platforms)
-- ============================================================
function Network.sendMove(x, y)
    Network.send(ProtocolModule.make_move_packet(x, y))
end

function Network.sendAction(action)
    Network.send(ProtocolModule.make_action_packet(action))
end

function Network.resetAndReconnect()
    Network.connect_attempts = 0
    Network.connect_timer = 0
    Network.connect()
end

return Network
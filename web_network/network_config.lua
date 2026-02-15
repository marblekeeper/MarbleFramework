-- network_config.lua
-- Platform detection and connection routing for cross-platform deployment

local NetworkConfig = {}

-- Platform detection
-- For WASM builds, we always run in browser
-- Desktop builds will have this set to false
NetworkConfig.IS_BROWSER = true  -- WASM builds are always browser
NetworkConfig.IS_WINDOWS = false
NetworkConfig.IS_LINUX = false

-- Server endpoints
NetworkConfig.ENDPOINTS = {
    -- Local TCP (Desktop offline mode)
    LOCAL_TCP = {
        host = "127.0.0.1",
        port = 12345,
        protocol = "tcp"
    },
    
    -- Local WebSocket (Browser offline mode)
    LOCAL_WS = {
        host = "127.0.0.1",
        port = 8080,
        protocol = "websocket"
    },
    
    -- Online WebSocket (Both platforms online mode)
    ONLINE_WS = {
        host = "yourgame.com",  -- CHANGE THIS to your actual domain
        port = 8080,
        protocol = "websocket",
        secure = true  -- Use wss:// in production
    }
}

-- Get appropriate endpoint based on platform and mode
function NetworkConfig.get_endpoint(online_mode)
    if NetworkConfig.IS_BROWSER then
        -- Browser can only use WebSocket
        if online_mode then
            return NetworkConfig.ENDPOINTS.ONLINE_WS
        else
            return NetworkConfig.ENDPOINTS.LOCAL_WS
        end
    else
        -- Desktop
        if online_mode then
            return NetworkConfig.ENDPOINTS.ONLINE_WS
        else
            return NetworkConfig.ENDPOINTS.LOCAL_TCP
        end
    end
end

-- Format connection string for display
function NetworkConfig.format_endpoint(endpoint)
    local protocol_str = endpoint.protocol == "websocket" and 
                        (endpoint.secure and "wss://" or "ws://") or "tcp://"
    return string.format("%s%s:%d", protocol_str, endpoint.host, endpoint.port)
end

-- Check if we need to start integrated server
function NetworkConfig.should_start_integrated_server(online_mode)
    -- Only start integrated server for offline mode
    return not online_mode
end

-- Get server type to start
function NetworkConfig.get_server_type(online_mode)
    if online_mode then
        return nil  -- Don't start server in online mode
    end
    
    if NetworkConfig.IS_BROWSER then
        return "websocket"  -- WASM needs WebSocket server
    else
        return "tcp"  -- Desktop uses TCP server
    end
end

return NetworkConfig
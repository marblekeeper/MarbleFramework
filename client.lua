-- client.lua
-- Basic TCP client with keyboard movement

local socket = require("socket")
local Protocol = require("protocol")

-- Server configuration
local HOST = "127.0.0.1"
local PORT = 12345

-- Connect to server
local client = assert(socket.tcp())
client:settimeout(5) -- 5 second timeout for initial connection
print("Connecting to server...")

local success, err = client:connect(HOST, PORT)
if not success then
    print("Failed to connect: " .. tostring(err))
    os.exit(1)
end

print("Connected to server!")
client:settimeout(0) -- Non-blocking after connection

-- Player state
local player_id = nil
local pos_x, pos_y = 0, 0

-- Process server messages
local function process_server_messages()
    while true do
        local data, err = client:receive("*l")
        if data then
            -- Parse server responses using protocol
            if data:match("^" .. Protocol.RESPONSE.AUTH_OK) then
                player_id = tonumber(data:match("ID:(%d+)"))
                local tick = tonumber(data:match("TICK:(%d+)"))
                print(string.format("[OK] Authenticated as Player #%d (Server Tick: %d)", player_id, tick or 0))
            elseif data:match("^" .. Protocol.RESPONSE.INTENT_ACK) then
                -- Server acknowledged our intent submission
                -- Action will happen on next tick
            elseif data:match("^" .. Protocol.RESPONSE.POS) then
                local x, y, tick = data:match("^POS:([%-]?%d+),([%-]?%d+),TICK:(%d+)$")
                if x and y and tick then
                    pos_x, pos_y = tonumber(x), tonumber(y)
                    print(string.format("Server confirmed position: (%d, %d) [Tick #%s]", pos_x, pos_y, tick))
                else
                    -- Fallback for old format
                    x, y = data:match("^POS:([%-]?%d+),([%-]?%d+)$")
                    if x and y then
                        pos_x, pos_y = tonumber(x), tonumber(y)
                        print(string.format("Server confirmed position: (%d, %d)", pos_x, pos_y))
                    end
                end
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_ACTION) then
                -- Parse: PLAYER_ACTION:ACTION_TYPE,TICK:N
                local action, tick = data:match("^PLAYER_ACTION:(%w+),TICK:(%d+)$")
                if action and tick then
                    print(string.format("[OK] Action processed: %s [Tick #%s]", action, tick))
                else
                    -- Fallback
                    local parts = data:match("^PLAYER_ACTION:(.+)$")
                    print(string.format("Action confirmed: %s", parts))
                end
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_JOIN) then
                local id = tonumber(data:match("^PLAYER_JOIN:(%d+)"))
                print(string.format("→ Player #%d joined the game", id))
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_MOVE) then
                local id, x, y = data:match("^PLAYER_MOVE:(%d+),([%-]?%d+),([%-]?%d+)")
                print(string.format("→ Player #%s moved to (%s, %s)", id, x, y))
            elseif data:match("^" .. Protocol.RESPONSE.PLAYER_LEAVE) then
                local id = tonumber(data:match("^PLAYER_LEAVE:(%d+)"))
                print(string.format("← Player #%d left the game", id))
            elseif data:match("^" .. Protocol.RESPONSE.ERROR) then
                print("Server Error: " .. data)
            else
                print("Server: " .. data)
            end
        elseif err ~= "timeout" then
            print("Connection error: " .. tostring(err))
            break
        else
            break -- Timeout is normal in non-blocking mode
        end
    end
end

-- Send movement packet using protocol
local function send_move(x, y)
    local packet = Protocol.make_move_packet(x, y)
    client:send(packet)
end

-- Send action packet using protocol
local function send_action(action)
    local packet = Protocol.make_action_packet(action)
    client:send(packet)
end

-- Demo: automated movement pattern
print("\n=== MARBLE ROGUELIKE CLIENT ===")
print("Tick-based command buffer system:")
print("  - Commands are INTENTS (queued)")
print("  - Server processes at tick boundaries (0.6s)")
print("  - Max 5 intents per tick (last one wins)")
print("")
print("Starting automated movement demo...\n")

-- Auto-demo: move in a square pattern
local demo_moves = {
    {1, 0},  -- right
    {2, 0},
    {2, 1},  -- down
    {2, 2},
    {1, 2},  -- left
    {0, 2},
    {0, 1},  -- up
    {0, 0},
}

for step, move in ipairs(demo_moves) do
    process_server_messages()
    send_move(move[1], move[2])
    print(string.format("[Step %d] Sending MOVE -> (%d, %d)", step, move[1], move[2]))
    socket.sleep(0.5) -- Wait between moves
end

-- Wait for final server confirmations
socket.sleep(0.5)
process_server_messages()

-- Interactive mode
print("\n" .. string.rep("=", 50))
print("Demo complete. Entering interactive mode...")
print(string.rep("=", 50))
print("Movement: w (up) | a (left) | s (down) | d (right)")
print("Actions:  p (pray) | m (meditate) | i (sit) | o (stand)")
print("Quit:     q")
print(string.rep("=", 50))
print("")

local running = true
while running do
    io.write("> ")
    io.flush()
    local input = io.read("*l")
    
    if not input then break end
    
    input = input:lower():gsub("^%s*(.-)%s*$", "%1") -- Trim and lowercase
    
    -- Quit
    if input == "q" or input == "quit" then
        running = false
    
    -- Movement
    elseif input == "w" or input == "up" then
        pos_y = pos_y - 1
        send_move(pos_x, pos_y)
        print(string.format("Intent: MOVE UP to (%d, %d) (waiting...)", pos_x, pos_y))
    elseif input == "s" or input == "down" then
        pos_y = pos_y + 1
        send_move(pos_x, pos_y)
        print(string.format("Intent: MOVE DOWN to (%d, %d) (waiting...)", pos_x, pos_y))
    elseif input == "a" or input == "left" then
        pos_x = pos_x - 1
        send_move(pos_x, pos_y)
        print(string.format("Intent: MOVE LEFT to (%d, %d) (waiting...)", pos_x, pos_y))
    elseif input == "d" or input == "right" then
        pos_x = pos_x + 1
        send_move(pos_x, pos_y)
        print(string.format("Intent: MOVE RIGHT to (%d, %d) (waiting...)", pos_x, pos_y))
    
    -- Actions
    elseif input == "p" or input == "pray" then
        send_action(Protocol.CMD.PRAY)
        print("Intent: PRAY (waiting for server...)")
    elseif input == "m" or input == "meditate" then
        send_action(Protocol.CMD.MEDITATE)
        print("Intent: MEDITATE (waiting for server...)")
    elseif input == "i" or input == "sit" then
        send_action(Protocol.CMD.SIT)
        print("Intent: SIT (waiting for server...)")
    elseif input == "o" or input == "stand" then
        send_action(Protocol.CMD.STAND)
        print("Intent: STAND (waiting for server...)")
    
    elseif input == "" then
        -- Ignore empty input
    else
        print("Unknown command. Use: w/a/s/d (move), p/m/i/o (actions), q (quit)")
    end
    
    -- Wait for server confirmation (up to 1 second)
    local wait_start = socket.gettime()
    while socket.gettime() - wait_start < 1.0 do
        socket.sleep(0.05)
        process_server_messages()
    end
end

client:close()
print("Disconnected from server.")
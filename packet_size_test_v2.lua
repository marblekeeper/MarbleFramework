-- packet_size_test_v3.lua
-- Robust Binary Protocol Test for MarbleNet
local Protocol = require("protocol")

-- Simple XOR Checksum for Layer 1 Security
local function calculate_checksum(data)
    local ck = 0
    for i = 1, #data do
        ck = (ck ~ string.byte(data, i)) % 256
    end
    return ck
end

-- Simulation Data
local x, y = 125, -42
local tick = 1024
local seq_id = 42 

-- Format Strings:
-- B: Unsigned Char (1 byte, 0-255) - Perfect for IDs and Checksums
-- i4: Signed 32-bit Integer (4 bytes) - For Coordinates
-- I4: Unsigned 32-bit Integer (4 bytes) - For Tick counters
local FMT_MOVE = "B i4 i4 B" -- CMD, X, Y, SEQ (Checksum appended after)
local FMT_POS  = "B i4 i4 I4 B" -- CMD, X, Y, TICK, SEQ

print("--- MarbleNet Robust Packet Size Comparison ---\n")

---------------------------------------------------------
-- 1. CLIENT INTENT: MOVE
---------------------------------------------------------
-- Current Text Approach
local text_move = Protocol.make_move_packet(x, y)

-- Robust Binary: Pack data, calculate checksum, then append it
local move_payload = string.pack(FMT_MOVE, 1, x, y, seq_id)
local move_checksum = calculate_checksum(move_payload)
local bin_move = move_payload .. string.pack("B", move_checksum)

---------------------------------------------------------
-- 2. SERVER RESPONSE: POS UPDATE
---------------------------------------------------------
-- Current Text Approach
local text_pos = string.format("POS:%d,%d,TICK:%d\n", x, y, tick)

-- Robust Binary
local pos_payload = string.pack(FMT_POS, 2, x, y, tick, seq_id)
local pos_checksum = calculate_checksum(pos_payload)
local bin_pos = pos_payload .. string.pack("B", pos_checksum)

---------------------------------------------------------
-- 3. RESULTS DISPLAY
---------------------------------------------------------
print(string.format("%-25s | %-10s | %s", "Packet Type", "Size (B)", "Security Features"))
print(string.rep("-", 75))
print(string.format("%-25s | %-10s | %s", "Text MOVE", #text_move, "None (Fragile)"))
print(string.format("%-25s | %-10s | %s", "Binary MOVE (Robust)", #bin_move, "SEQ + XOR Checksum"))
print(string.format("%-25s | %-10s | %s", "Text POS Update", #text_pos, "None"))
print(string.format("%-25s | %-10s | %s", "Binary POS (Robust)", #bin_pos, "SEQ + XOR Checksum"))

---------------------------------------------------------
-- 4. 1,000 PLAYER SCALE ANALYSIS
---------------------------------------------------------
local tick_rate = 0.6
local players = 1000
local total_bytes = (#bin_move + #bin_pos) * players
local kbps = total_bytes / tick_rate / 1024

print("\n--- Efficiency & Scalability Metrics ---")
print(string.format("Binary Bandwidth (1k Players): %.2f KB/s", kbps))
print("Packet Stability: Fixed-length (Reliable for C Command Buffer)")
print("CPU Impact: O(1) Struct Casting in C vs. Regex/String parsing")
-- packet_size_test.lua
local Protocol = require("protocol")

-- Simulation Data
local x, y = 125, -42
local tick = 1024
local player_id = 7

print("--- MarbleNet Packet Size Comparison ---\n")

---------------------------------------------------------
-- 1. MOVEMENT COMMAND (Client -> Server)
---------------------------------------------------------
local text_move = Protocol.make_move_packet(x, y)

-- Binary: [CMD_ID: 1 byte] [X: 4 bytes] [Y: 4 bytes]
local bin_move = string.pack("b i4 i4", 1, x, y) 

print(string.format("%-20s | %-10s | %s", "Packet Type", "Size (B)", "Raw Representation"))
print(string.rep("-", 60))
print(string.format("%-20s | %-10s | %s", "Text MOVE", #text_move, text_move:gsub("\n", "\\n")))
print(string.format("%-20s | %-10s | %s", "Binary MOVE", #bin_move, "Binary Data"))

---------------------------------------------------------
-- 2. POSITION UPDATE (Server -> Client)
---------------------------------------------------------
-- Text: POS:125,-42,TICK:1024\n
local text_pos = string.format("POS:%d,%d,TICK:%d\n", x, y, tick)

-- Binary: [MSG_ID: 1 byte] [X: i4] [Y: i4] [TICK: I4]
local bin_pos = string.pack("b i4 i4 I4", 2, x, y, tick)

print(string.format("%-20s | %-10s | %s", "Text POS Update", #text_pos, text_pos:gsub("\n", "\\n")))
print(string.format("%-20s | %-10s | %s", "Binary POS Update", #bin_pos, "Binary Data"))

---------------------------------------------------------
-- 3. SUMMARY ANALYSIS
---------------------------------------------------------
local text_total = #text_move + #text_pos
local bin_total = #bin_move + #bin_pos
local savings = ((text_total - bin_total) / text_total) * 100

print("\n--- Efficiency Metrics ---")
print(string.format("Average Text Packet:   %.1f bytes", text_total / 2))
print(string.format("Average Binary Packet: %.1f bytes", bin_total / 2))
print(string.format("Bandwidth Reduction:   %.1f%%", savings))

-- 1000 Player Projection
local tick_rate = 0.6 -- seconds
local players = 1000
local text_kbps = (text_total * players) / tick_rate / 1024
local bin_kbps = (bin_total * players) / tick_rate / 1024

print(string.format("\n1,000 Player Bandwidth (at %.1fs tick):", tick_rate))
print(string.format("Text Protocol:   %.2f KB/s", text_kbps))
print(string.format("Binary Protocol: %.2f KB/s", bin_kbps))
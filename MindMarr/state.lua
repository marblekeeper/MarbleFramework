-- state.lua
-- MINDMARR: Shared mutable game state

local game = {
    state = "title",
    sector = 1,
    maxSectors = 7,
    turn = 0,
    messages = {},
    maxMessages = 6,
    shakeTimer = 0,
    shakeIntensity = 0,
    particles = {},
    camX = 0, camY = 0,
    inputCooldown = 0,
    keyWasDown = {},
    marsWhisperTimer = 0,
    pulseTimer = 0,
    won = false,
    
    -- New: Tracks the item the player is currently deciding on
    interaction = {
        active = false,
        type = nil,       -- "scattered_document", "terminal", "scrap"
        itemIndex = nil,  -- Index in items table
        content = "",     -- Text to display if read
        isCorrupted = false,
        options = {}      -- For scrap menu options
    }
}

local player = {
    x = 0, y = 0,
    hp = 30, maxHp = 30,
    str = 55,
    def = 40,
    dmgMin = 2, dmgMax = 5,
    armor = 0,
    xp = 0,
    xpNext = 20,
    level = 1,
    sanity = 100,
    oxygen = 100,
    medkits = 1,
    cells = 0,
    cellsNeeded = 3,
    kills = 0,
    critBonus = 5,
    seen = {},
    keycards = 0,
    
    -- Inventory / Crafting
    hasBackpack = false,
    hasSword = false,
    hasScrapArmor = false,
    scrapCount = 0,

    -- Animation State
    -- Assuming 64x64 sprite sheet with 4 frames (2x2 grid, 32x32 frames)
    frameCount = 4,
    frameCols = 2,
    frameRows = 2,
    frameWidth = 32,
    frameHeight = 32,
    currentFrame = 1,
    animTimer = 0,
    animFPS = 5
}

local map = {}
local enemies = {}
local items = {}
local shuttle = {x = 0, y = 0}
local elevator = {x = 0, y = 0, revealed = false}

return {
    game = game,
    player = player,
    map = map,
    enemies = enemies,
    items = items,
    shuttle = shuttle,
    elevator = elevator,
} 

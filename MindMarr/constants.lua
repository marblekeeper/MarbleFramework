-- constants.lua
-- MINDMARR: Shared constants, palette, config

local TS = 80
local MW, MH = 30, 22

local C = {
    void      = {4, 2, 6},
    wall      = {90, 40, 25},
    wallHi    = {120, 55, 35},
    floor     = {35, 18, 14},
    floorLit  = {55, 28, 22},
    player    = {60, 200, 255},
    infected  = {180, 40, 60},
    infGlow   = {220, 60, 80},
    supply    = {100, 220, 140},
    cell      = {180, 60, 200},
    shuttle   = {255, 220, 80},
    fog       = {6, 3, 8},
    blood     = {140, 30, 40},
    xp        = {200, 120, 255},
    crit      = {255, 200, 60},
    miss      = {100, 80, 80},
    hit       = {255, 80, 60},
    hud_bg    = {12, 6, 10},
    hud_border= {80, 35, 50},
    mars      = {200, 60, 40},
    whisper   = {160, 50, 70},
    sanity    = {120, 180, 255},
    oxygen    = {80, 200, 220},
    keycard   = {255, 200, 50},
    elevator  = {100, 220, 255},
    -- New Item Colors
    document  = {240, 240, 220},
    terminal  = {50, 200, 100},
    corrupted = {200, 50, 50},
    scrap     = {160, 160, 170},
}

local MINDMARR_SAYS = {
    "mindmarr...", "MINDMARR!", "mind...marr...", "mindmarr", "MiNdMaRr",
    "m i n d m a r r", "MINDMARR MINDMARR", "...mindmarr...",
    "mindmarr?", "MINDMARR.", "mind...m a r r...", "mindmarrMINDMARR",
}

local marsWhispers = {
    "The ground pulses beneath you...",
    "You hear your name spoken from below...",
    "The walls are breathing...",
    "Something remembers you were born...",
    "Mars knows your mother's name...",
    "The red dust rearranges into a face...",
    "You feel the planet thinking...",
    "Your shadow moved on its own...",
    "The air tastes like someone else's memory...",
    "mind...marr... NO. Focus.",
    "A voice in the static: 'Join us.'",
    "Your reflection blinked before you did...",
}

local levelChoices = {
    {name = "+5 Max HP & heal"},
    {name = "+8 STR (hit chance)"},
    {name = "+8 DEF (dodge)"},
    {name = "+2 Max Damage"},
    {name = "+1 Suit Armor"},
    {name = "+15 Sanity restored"},
    {name = "+3 Crit Range"},
}

-- Lore Database
local lore = {
    clean = {
        "LAB_LOG_01: Subject reports vibrations. Not seismic. A heartbeat.",
        "RECOVERY_PLAN: Shuttle fueled. Don't listen to the wind.",
        "MEMO: The filters are failing. The dust... it tastes like iron.",
        "DIARY: Day 40. They stopped talking. They just stare at the walls.",
        "TECH_NOTE: The terminals are rewriting themselves. Code I didn't write.",
    },
    corrupted = {
        "SECURITY_FEED: Everyone is red. MINDMARR MINDMARR.",
        "CAPTAIN'S LOG: 404... miiinnnddddmmaaarrrr...",
        "ERROR: JOIN US. FLESH IS WEAK. MARS IS ETERNAL.",
        "01001... MIND... MARR... SUFFOCATE... BREATHE...",
        "DONT LOOK BEHIND YOU DONT LOOK BEHIND YOU",
    }
}

-- Optional sprite assets (if nil/missing, falls back to procedural rendering)
local assets = {
    sprites = {
        -- Characters
        player = "assets/Content/textures/player_idle.png",
        enemy_scientist = "assets/Content/textures/scientist_mindmarr.png",
        enemy_mindcrab = "assets/Content/textures/mind_crab.png",
        Technician = "assets/Content/textures/scientist_001.png",
        
        -- Items & Objects
        medkit = "assets/Content/textures/medkit.png",
        supply = "assets/Content/textures/supply.png",
        cell = "assets/Content/textures/power_cell.png",
        oxygen = "assets/Content/textures/oxygen_tank.png",
        keycard = "assets/Content/textures/elevator_keycard.png",
        shuttle = "assets/Content/textures/shuttle.png",
        elevator = "assets/Content/textures/elevator.png",
        
        -- New Items
        scattered_document = "assets/Content/textures/handwritten_document.png",
        terminal = "assets/Content/textures/terminal_001.png",
        scrap = "assets/Content/textures/scrap.png",
    },
    audio = {
        death = "assets/Content/audio/demo.mp3",
        sector_theme = "assets/Content/audio/TG_8.mp3"
    }
}

return {
    TS = TS,
    MW = MW,
    MH = MH,
    C = C,
    MINDMARR_SAYS = MINDMARR_SAYS,
    marsWhispers = marsWhispers,
    levelChoices = levelChoices,
    assets = assets,
    lore = lore
} 

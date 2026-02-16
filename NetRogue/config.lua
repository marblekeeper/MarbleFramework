-- netrogue/config.lua
-- Global configuration and constants

local Config = {}

-- Display settings
Config.W = 800
Config.H = 600
Config.TS = 24  -- Tile size
Config.MW = 30  -- Map width
Config.MH = 22  -- Map height

-- Color palette
Config.C = {
    void      = {8, 6, 12},
    wall      = {60, 55, 75},
    wallHi    = {80, 72, 95},
    floor     = {25, 22, 35},
    floorLit  = {40, 35, 55},
    player    = {60, 200, 255},
    other     = {255, 180, 60},
    goblin    = {60, 180, 50},
    goblinHurt= {180, 220, 60},
    goblinDead= {40, 40, 40},
    fog       = {6, 4, 10},
    hud_bg    = {12, 10, 18},
    hud_border= {60, 50, 80},
    net_ok    = {80, 220, 120},
    net_err   = {255, 80, 80},
    net_wait  = {255, 200, 80},
    title_bg  = {10, 8, 16},
    msg       = {180, 170, 200},
    combat_hit= {255, 100, 80},
    combat_miss={120, 110, 140},
    combat_crit={255, 220, 60},
    hp_bar_bg = {40, 10, 15},
    hp_bar    = {50, 200, 80},
    hp_bar_low= {255, 60, 60},
    xp        = {180, 120, 255},
    levelup   = {255, 255, 100},
}

-- Visibility settings
Config.VISION_RADIUS = 8

return Config
-- actions.lua
-- MINDMARR: Player actions - movement, items, floor transitions

local rand, floor = math.random, math.floor
local max, min = math.max, math.min

local state = require("state")
local K = require("constants")
local util = require("util")
local combat = require("combat")
local mapgen = require("mapgen")

local game = state.game
local player = state.player

local M = {}

function M.newFloor()
    player.seen = {}
    local rooms = mapgen.generateMap()
    mapgen.populateFloor(rooms)
    util.dimFOV()
    util.computeFOV()

    -- O2 cost per sector transition
    if game.sector > 1 then
        local o2cost = rand(5, 12)
        player.oxygen = max(0, player.oxygen - o2cost)
        util.addMessage("Airlock transit: -" .. o2cost .. " O2", K.C.oxygen[1], K.C.oxygen[2], K.C.oxygen[3])
        if player.oxygen <= 0 then
            game.state = "dead"
            util.addMessage("Suffocated between sectors.", 255, 50, 50)
            util.screenShake(6, 0.3)
            return
        end
    end

    if game.sector == game.maxSectors then
        util.addMessage("== SECTOR " .. game.sector .. ": SHUTTLE BAY ==", 255, 220, 80)
        util.addMessage("The shuttle is HERE. Reach it!", 255, 255, 150)
    else
        util.addMessage("-- Sector " .. game.sector .. " / " .. game.maxSectors .. " --", 255, 180, 100)
    end

    if rand(1, 100) <= game.sector * 12 then
        util.marsWhisper()
    end
end

local function endOfTurn()
    game.turn = game.turn + 1
    combat.moveEnemies()

    game.marsWhisperTimer = game.marsWhisperTimer + 1
    if game.marsWhisperTimer >= (8 - min(5, game.sector)) then
        game.marsWhisperTimer = 0
        util.marsWhisper()
    end

    util.dimFOV()
    util.computeFOV()
    combat.checkSanityDeath()
end

function M.resolveInteraction(choice)
    local it = game.interaction
    if choice == 1 then
        -- Read
        local items = state.items
        if items[it.itemIndex] then
            if it.isCorrupted then
                local loss = rand(10, 20)
                player.sanity = max(0, player.sanity - loss)
                util.addMessage("CORRUPTED! Your mind fractures... (-" .. loss .. " Sanity)", 255, 50, 50)
                util.screenShake(4, 0.2)
                combat.checkSanityDeath()
            else
                local gain = rand(10, 20)
                player.sanity = min(100, player.sanity + gain)
                util.addMessage("Data integrity verified. (+ " .. gain .. " Sanity)", 100, 255, 100)
            end
            util.addMessage("LOG: " .. it.content, 200, 200, 220)
            table.remove(items, it.itemIndex)
        end
    else
        -- Leave
        util.addMessage("You step away from the " .. (it.type == "terminal" and "terminal." or "paper."), 150, 150, 150)
    end
    
    game.interaction = {active = false}
    game.state = "playing"
end

function M.generateScrapOptions()
    local opts = {}
    if not player.hasBackpack then
        table.insert(opts, {label="Craft Backpack (Allows Storing Scrap)", action="backpack"})
    end
    if not player.hasSword then
        table.insert(opts, {label="Makeshift Sword (+2 Min/Max DMG)", action="sword"})
    end
    if not player.hasScrapArmor then
        table.insert(opts, {label="Makeshift Armor (+1 Armor)", action="armor"})
    end
    if player.hasBackpack then
        table.insert(opts, {label="Stash in Backpack", action="stash"})
    end
    table.insert(opts, {label="Leave", action="leave"})
    return opts
end

function M.resolveScrapInteraction(choiceIndex)
    local it = game.interaction
    local opts = it.options
    
    if choiceIndex > #opts then return end
    
    local opt = opts[choiceIndex]
    local items = state.items
    
    if opt.action == "leave" then
        util.addMessage("You leave the scrap pile.", 150, 150, 150)
        game.interaction = {active=false}
        game.state = "playing"
        return
    end

    if items[it.itemIndex] then
        if opt.action == "backpack" then
            player.hasBackpack = true
            util.addMessage("Crafted Backpack! You can now carry scrap.", 100, 255, 150)
            util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 10, 200, 200, 200, 50, 0.5)
            table.remove(items, it.itemIndex)
        elseif opt.action == "sword" then
            player.hasSword = true
            player.dmgMin = player.dmgMin + 2
            player.dmgMax = player.dmgMax + 2
            util.addMessage("Crafted Makeshift Sword! Damage increased.", 255, 100, 100)
            util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 10, 200, 50, 50, 50, 0.5)
            table.remove(items, it.itemIndex)
        elseif opt.action == "armor" then
            player.hasScrapArmor = true
            player.armor = player.armor + 1
            util.addMessage("Crafted Makeshift Armor! +1 Armor.", 100, 100, 255)
            util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 10, 50, 50, 200, 50, 0.5)
            table.remove(items, it.itemIndex)
        elseif opt.action == "stash" then
            player.scrapCount = player.scrapCount + 1
            util.addMessage("Scrap stashed in backpack.", 200, 200, 200)
            table.remove(items, it.itemIndex)
        end
    end
    
    game.interaction = {active=false}
    game.state = "playing"
end

function M.tryMove(dx, dy)
    if game.state ~= "playing" then return end

    local nx, ny = player.x + dx, player.y + dy

    local e = util.enemyAt(nx, ny)
    if e then
        combat.resolveMelee(player, e, "You", e.name, player.str, e.def, player.dmgMin, player.dmgMax)
        combat.checkEnemyDeath(e)
        if game.state ~= "dead" and game.state ~= "mindmarr" then
            endOfTurn()
        end
        return
    end

    if util.tileAt(nx, ny) == 0 then
        -- CHECK FOR INTERACTIVE ITEMS
        local items = state.items
        for i, it in ipairs(items) do
            if it.x == nx and it.y == ny then
                if it.type == "scattered_document" or it.type == "terminal" then
                    game.state = "interacting"
                    game.interaction = {
                        active = true,
                        type = it.type,
                        itemIndex = i,
                        content = it.content,
                        isCorrupted = it.isCorrupted
                    }
                    return 
                elseif it.type == "scrap" then
                    game.state = "interacting_scrap"
                    game.interaction = {
                        active = true,
                        type = "scrap",
                        itemIndex = i,
                        options = M.generateScrapOptions()
                    }
                    return
                end
            end
        end

        player.x = nx; player.y = ny

        -- Instant Pickup Items
        for i = #items, 1, -1 do
            local it = items[i]
            if it.x == nx and it.y == ny then
                if it.type == "supply" then
                    player.xp = player.xp + it.amount
                    util.addMessage("Scavenged supplies (+" .. it.amount .. " XP)", K.C.supply[1], K.C.supply[2], K.C.supply[3])
                    util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 6, 100, 220, 140, 40, 0.3)
                    if player.xp >= player.xpNext then
                        game.state = "levelup"
                        player.level = player.level + 1
                        player.xpNext = floor(player.xpNext * 1.6)
                        util.addMessage("*** ADAPT — Level " .. player.level .. " ***", 255, 255, 100)
                        util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 25, 60, 200, 255, 120, 0.8)
                    end
                    table.remove(items, i)
                elseif it.type == "medkit" then
                    player.medkits = player.medkits + 1
                    util.addMessage("Found a medkit!", 100, 255, 150)
                    util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 6, 100, 255, 150, 40, 0.3)
                    table.remove(items, i)
                elseif it.type == "cell" then
                    player.cells = player.cells + 1
                    util.addMessage("POWER CELL acquired! (" .. player.cells .. "/" .. player.cellsNeeded .. ")", K.C.cell[1], K.C.cell[2], K.C.cell[3])
                    util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 12, 180, 60, 200, 60, 0.5)
                    util.screenShake(2, 0.1)
                    table.remove(items, i)
                elseif it.type == "oxygen" then
                    local o2 = rand(10, 20)
                    player.oxygen = min(100, player.oxygen + o2)
                    util.addMessage("O2 canister: +" .. o2 .. " oxygen", K.C.oxygen[1], K.C.oxygen[2], K.C.oxygen[3])
                    util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 6, 80, 200, 220, 40, 0.3)
                    table.remove(items, i)
                elseif it.type == "keycard" then
                    player.keycards = player.keycards + 1
                    util.addMessage("KEYCARD found! Can skip a sector via elevator.", K.C.keycard[1], K.C.keycard[2], K.C.keycard[3])
                    util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 10, K.C.keycard[1], K.C.keycard[2], K.C.keycard[3], 50, 0.4)
                    util.screenShake(2, 0.15)
                    state.elevator.revealed = true
                    table.remove(items, i)
                end
            end
        end

        -- Elevator (skip sector if player has keycard)
        if state.elevator.revealed and nx == state.elevator.x and ny == state.elevator.y then
            if player.keycards > 0 then
                local skipTo = min(game.maxSectors, game.sector + 2)
                player.keycards = player.keycards - 1
                util.addMessage("Elevator activated! Skipping to sector " .. skipTo .. "...", K.C.elevator[1], K.C.elevator[2], K.C.elevator[3])
                util.screenShake(4, 0.3)
                util.spawnParticles(nx * K.TS + K.TS/2, ny * K.TS + K.TS/2, 20, K.C.elevator[1], K.C.elevator[2], K.C.elevator[3], 80, 0.6)
                game.sector = skipTo
                M.newFloor()
                return
            else
                util.addMessage("Elevator locked. Need a keycard!", 200, 100, 100)
            end
        end

        -- Shuttle/airlock
        if nx == state.shuttle.x and ny == state.shuttle.y then
            if game.sector == game.maxSectors then
                if player.cells >= player.cellsNeeded then
                    game.state = "won"
                    game.won = true
                    util.addMessage("You ignite the shuttle engines!", 255, 255, 100)
                    util.addMessage("ESCAPED! Mars screams behind you.", 80, 255, 120)
                    util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 50, 255, 220, 80, 200, 1.5)
                    util.screenShake(6, 0.5)
                    return
                else
                    util.addMessage("Shuttle needs " .. (player.cellsNeeded - player.cells) .. " more power cells!", 255, 100, 100)
                end
            else
                game.sector = game.sector + 1
                M.newFloor()
                return
            end
        end

        endOfTurn()
    end
end

function M.useMedkit()
    if player.medkits > 0 and player.hp < player.maxHp then
        player.medkits = player.medkits - 1
        local heal = floor(player.maxHp * 0.4) + rand(1, 5)
        player.hp = min(player.maxHp, player.hp + heal)
        util.addMessage("Used medkit: +" .. heal .. " HP", 100, 255, 150)
        util.spawnParticles(player.x * K.TS + K.TS/2, player.y * K.TS + K.TS/2, 10, 100, 255, 150, 50, 0.4)
        game.turn = game.turn + 1
        combat.moveEnemies()
        util.dimFOV(); util.computeFOV()
    end
end

-- Level up choices (apply functions need player reference)
function M.applyLevelChoice(index)
    local applies = {
        function() player.maxHp = player.maxHp + 5; player.hp = player.maxHp end,
        function() player.str = min(95, player.str + 8) end,
        function() player.def = min(85, player.def + 8) end,
        function() player.dmgMax = player.dmgMax + 2 end,
        function() player.armor = player.armor + 1 end,
        function() player.sanity = min(100, player.sanity + 15) end,
        function() player.critBonus = min(25, player.critBonus + 3) end,
    }
    if applies[index] then
        applies[index]()
        util.addMessage("Adapted: " .. K.levelChoices[index].name, 100, 230, 255)
        game.state = "playing"
    end
end

function M.resetGame()
    game.state = "playing"
    game.sector = 1
    game.turn = 0
    game.messages = {}
    game.particles = {}
    game.marsWhisperTimer = 0
    game.won = false
    game.interaction = {active=false}

    player.hp = 30; player.maxHp = 30
    player.str = 55; player.def = 40
    player.dmgMin = 2; player.dmgMax = 5
    player.armor = 0
    player.xp = 0; player.xpNext = 20
    player.level = 1
    player.sanity = 100; player.oxygen = 100
    player.medkits = 1; player.cells = 0
    player.cellsNeeded = 3
    player.kills = 0; player.critBonus = 5
    player.seen = {}
    player.keycards = 0
    
    player.hasBackpack = false
    player.hasSword = false
    player.hasScrapArmor = false
    player.scrapCount = 0

    util.addMessage("Arrows: move/attack. M: medkit. Escape Mars alive.", 180, 180, 220)
    util.addMessage("Don't lose your mind. Don't say the word.", 200, 60, 80)
    M.newFloor()
end

return M 

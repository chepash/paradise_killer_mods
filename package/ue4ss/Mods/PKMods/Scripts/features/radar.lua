-- Radar: one feature (Ctrl+B) with a menu filter per item category.
local Radar = require("core.radar")
local S     = require("core.settings")

-- Settings from before the radars were merged (crystal_radar / crest_radar).
if S.get("radar.enabled") == nil then
    local crystals, crests = S.get("crystal_radar.enabled"), S.get("crest_radar.enabled")
    if crystals ~= nil or crests ~= nil then
        S.set("radar.enabled", crystals == true or crests == true)
        if crystals ~= nil then S.set("radar.crystal", crystals == true or crests ~= true) end
        if crests ~= nil then S.set("radar.crest", crests == true or crystals ~= true) end
    end
end

-- Collected items stay in the world. Picking one up sets bHasBeenRemoved
-- (until the next load) and destroys its "Pickup_Glitch" component (for
-- good): an item without Pickup_Glitch was collected before the save was
-- loaded. Seen in pkmods.log component sets: the Crystallised Tear Necklace
-- the user had picked up, Islands 001-003, ... had only [SpawnScale].
-- Music is the exception so far: a collected song still showed while every
-- music pickup had Pickup_Glitch (under research: player Inventory/Collection).

-- Blood Crystals are "GoldCoin" internally: each one is its own Blueprint
-- (Blueprint_Pickup_GoldCoin_001.._159 + a few named ones) derived from
-- Blueprint_Pickup_Parent. Uncollected: 2 components (Pickup_Glitch, SpawnScale).
local CRYSTALS = {
    tag            = "crystal",
    label          = "Blood Crystals",
    parents        = { "Blueprint_Pickup_Parent_C" },
    match          = function(cls) return cls:find("GoldCoin", 1, true) ~= nil end,
    icon           = "/Game/Assets/2D_Assets/Textures/Inventory/GoldCoins/GoldCoin.GoldCoin",
    fullComponents = 2,
    color          = { R = 1.0, G = 0.25, B = 0.35, A = 1.0 },
    colorNearest   = { R = 1.0, G = 0.85, B = 0.25, A = 1.0 },
}

-- Crests: puzzle key items, all derived from Blueprint_Pickup_Parent_Crest.
-- Unlike crystals one class is placed several times:
--   Blueprint_Pickup_SyndicateCrest        Syndicate HQ crests (e.g. Red Crest), 10
--   Blueprint_Pickup_SuburbCrest           3
--   Blueprint_Pickup_DanchiCrest           2
--   Blueprint_Pickup_ApartmentStatusCrest  2
--   Blueprint_Pickup_Farm_Valve            farm valves, 3
local KEY_ITEM_ICONS = "/Game/Assets/2D_Assets/Textures/Inventory/KeyItems/"
local CREST_ICONS = {
    Blueprint_Pickup_SyndicateCrest_C       = "HQ_Crest.HQ_Crest",
    Blueprint_Pickup_SuburbCrest_C          = "Suburb_Crest.Suburb_Crest",
    Blueprint_Pickup_DanchiCrest_C          = "Danchi_Crest.Danchi_Crest",
    Blueprint_Pickup_ApartmentStatusCrest_C = "Apartment_Crest.Apartment_Crest",
    Blueprint_Pickup_Farm_Valve_C           = "valve.valve",
}

local CRESTS = {
    tag            = "crest",
    label          = "Crests",
    parents        = { "Blueprint_Pickup_Parent_Crest_C", "Blueprint_Pickup_Parent_C" },
    match          = function(cls) return CREST_ICONS[cls] ~= nil end,
    icon           = function(cls) return KEY_ITEM_ICONS .. (CREST_ICONS[cls] or "HQ_Crest.HQ_Crest") end,
    icons          = (function()
        local list = {}
        for _, file in pairs(CREST_ICONS) do list[#list + 1] = KEY_ITEM_ICONS .. file end
        return list
    end)(),
    aliveComponent = "Pickup_Glitch",
    color          = { R = 0.3, G = 0.9, B = 1.0, A = 1.0 },
    colorNearest   = { R = 1.0, G = 0.85, B = 0.25, A = 1.0 },
}

-- Relics ("RELIC OBTAINED"): ordinary pickups (Blueprint_Pickup_Parent) whose
-- InventoryItemData sits directly in ItemData/Collectables/ (74) or in
-- Collectables/Update_NewCollectables/ (6). The other Collectables subfolders
-- (Drinks, Islands, ShrineCarvings, Transmissions) are different collectibles.
-- In the world relics show as a heart, so the marker uses the game's heart icon.
local RELIC_DATA = "/Game/Assets/Inventory/ItemData/Collectables/"

local RELICS = {
    tag            = "relic",
    label          = "Relics",
    parents        = { "Blueprint_Pickup_Parent_C" },
    match          = function(_, actor)
        local path = Radar.itemDataPath(actor)
        if not path or path:sub(1, #RELIC_DATA) ~= RELIC_DATA then return false end
        local rest = path:sub(#RELIC_DATA + 1)
        return not rest:find("/", 1, true) or rest:sub(1, 23) == "Update_NewCollectables/"
    end,
    icon           = "/Game/Assets/2D_Assets/Heart/heart-128.heart-128",
    aliveComponent = "Pickup_Glitch",
    color          = { R = 1.0, G = 0.45, B = 0.85, A = 1.0 },
    colorNearest   = { R = 1.0, G = 0.85, B = 0.25, A = 1.0 },
}

-- The other collectibles that lie in the world as pickups, matched by class
-- name (from the Blueprints_Pickups/<folder> asset names). Their parent class
-- is a guess; the radar finds the real one if the guess is wrong. Drinks and
-- ancient symbols aren't world pickups (vending machines / sights), so they
-- have no category.
local TEX = "/Game/Assets/2D_Assets/Textures/Inventory/"
local PICKUP_PARENT = { "Blueprint_Pickup_Parent_C" }
local GOLD = { R = 1.0, G = 0.85, B = 0.25, A = 1.0 }

local function prefix(p)
    return function(cls) return cls:sub(1, #p) == p end
end

local ISLANDS = {
    tag = "island", label = "Islands",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Island"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/collectables.collectables",
    color = { R = 0.4, G = 1.0, B = 0.5, A = 1.0 }, colorNearest = GOLD,
}

local SHRINES = {
    tag = "shrine", label = "Shrine Carvings",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_ShrineCarving_"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/collectables.collectables",
    color = { R = 0.75, G = 0.55, B = 1.0, A = 1.0 }, colorNearest = GOLD,
}

local MUSIC = {
    tag = "music", label = "Music",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Music_"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/music_pickup_in_world.music_pickup_in_world",
    color = { R = 1.0, G = 0.6, B = 0.2, A = 1.0 }, colorNearest = GOLD,
}

local WHISKY = {
    tag = "whisky", label = "Whisky",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Whisky_"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/Whisky.Whisky",
    color = { R = 0.95, G = 0.75, B = 0.45, A = 1.0 }, colorNearest = GOLD,
}

local TRANSMISSIONS = {
    tag = "transmission", label = "Transmissions",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Transmission"),
    aliveComponent = "Pickup_Glitch",
    icon = "/Game/Assets/2D_Assets/UI/Icons/Starlight/icon-starlight-broadcast.icon-starlight-broadcast",
    color = { R = 0.45, G = 0.65, B = 1.0, A = 1.0 }, colorNearest = GOLD,
}

local GHOSTS = {
    tag = "ghost", label = "Ghost Items",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Ghost_"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "KeyItems/Ghost_PowerStation_Item.Ghost_PowerStation_Item",  -- Pickups/ghost isn't a Texture2D
    color = { R = 0.85, G = 0.85, B = 0.95, A = 1.0 }, colorNearest = GOLD,
}

local SKINS = {
    tag = "skin", label = "Starlight Skins",
    parents = PICKUP_PARENT, match = prefix("Blueprint_Pickup_Update_StarlightSkin_"),
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/starlight_upgrade_pickup.starlight_upgrade_pickup",
    color = { R = 0.8, G = 1.0, B = 0.3, A = 1.0 }, colorNearest = GOLD,
}

-- ---------------------------------------------------------------------------
-- Player progress (read from the player's own components, so it survives
-- save loads and updates the moment something is bought / donated / met):
--   * pawn.Inventory.OwnedItems: map, key = item name (e.g. Collectable_Drink_Pillar)
--   * pawn.Collection.CollectionData: map, key = collection category
--     (ShrineCollection, FoxMessengerCollection = Shinji, DrinkCollection, ...),
--     value = HeldCollectionCategoryData struct. Its fields aren't known by name,
--     so every item name found in any of its fields (arrays, maps, objects) is
--     taken as collected.
-- UE4SS maps here have ForEach/Find/Contains but no Num.

local U = require("core.util")

-- "Collectable_Drink_Pillar" from an FName / object / path string.
local function nameOf(x)
    if x == nil then return nil end
    if type(x) == "string" then return x:match("([^%./%s]+)$") end
    if type(x) ~= "userdata" then return tostring(x) end
    local okT, t = pcall(function() return x:ToString() end)
    if okT and type(t) == "string" and t ~= "" then return t:match("([^%./%s]+)$") end
    local okN, n = pcall(function() return x:GetFullName() end)
    if okN and type(n) == "string" then return n:match("([^%./%s]+)$") end
    return nil
end

-- Every item name inside value (an object, array or map), into set.
local function collectNames(value, set)
    local okA, num = pcall(function() return value:GetArrayNum() end)
    if okA and type(num) == "number" then
        pcall(function()
            value:ForEach(function(_, e)
                local okE, ev = pcall(function() return e:get() end)
                local n = okE and nameOf(ev)
                if n then set[n] = true end
            end)
        end)
        return
    end
    local okM = pcall(function()
        value:ForEach(function(k, v)
            local okK, kv = pcall(function() return k:get() end)
            local n1 = okK and nameOf(kv)
            if n1 then set[n1] = true end
            local okV, vv = pcall(function() return v:get() end)
            local n2 = okV and nameOf(vv)
            if n2 then set[n2] = true end
        end)
    end)
    if okM then return end
    local n = nameOf(value)
    if n then set[n] = true end
end

local HELD_STRUCT = "/Script/ParadiseKiller.HeldCollectionCategoryData"
local progress = { t = -math.huge, owned = {}, collected = {}, logged = false }

local function playerProgress()
    if U.nowMs() - progress.t < 2000 then return progress end
    progress.t = U.nowMs()
    local pawn = U.getPawn()
    if not pawn then return progress end
    local owned, collected, fields = {}, {}, {}
    pcall(function()
        pawn.Inventory.OwnedItems:ForEach(function(k, _)
            local okK, kv = pcall(function() return k:get() end)
            local n = okK and nameOf(kv)
            if n then owned[n] = true end
        end)
    end)
    local def = U.findPermanent(HELD_STRUCT)
    pcall(function()
        pawn.Collection.CollectionData:ForEach(function(_, v)
            local okS, st = pcall(function() return v:get() end)
            if not (okS and st and U.valid(def)) then return end
            def:ForEachProperty(function(prop)
                local field = prop:GetFName():ToString()
                fields[field] = true
                local okF, fv = pcall(function() return st[field] end)
                if okF and fv ~= nil then collectNames(fv, collected) end
            end)
        end)
    end)
    progress.owned, progress.collected = owned, collected
    if not progress.logged then  -- once per session: what was found (research)
        progress.logged = true
        local fl, sample = {}, {}
        for k in pairs(fields) do fl[#fl + 1] = k end
        for k in pairs(collected) do
            if #sample < 40 then sample[#sample + 1] = k end
        end
        local no = 0
        for _ in pairs(owned) do no = no + 1 end
        U.log("Progress: %d owned items; collection struct fields: %s", no, table.concat(fl, ", "))
        U.log("Progress: collected names (sample): %s", table.concat(sample, ", "))
    end
    return progress
end

-- The CollectionItem (e.g. Shrine_BloodDancer, FoxItem_22) of an actor's
-- Collection component, cached per actor.
local itemOfActor = {}
local function collectionItem(a)
    local addr = a:GetAddress()
    local item = itemOfActor[addr]
    if item == nil then
        local ok, ref = pcall(function() return a.Collection.CollectionItem end)
        item = (ok and nameOf(ref)) or false
        itemOfActor[addr] = item
    end
    return item or nil
end

local function collectedByPlayer(a)
    local item = collectionItem(a)
    return item ~= nil and playerProgress().collected[item] == true
end

-- Pickups: the item a pickup gives is its ItemData (e.g. GoldCoin_017,
-- SoundTrack_BreezeWithU, Collectable_wellreadbook), and every item the player
-- has picked up is a key of the player's Inventory.OwnedItems. So "already in
-- the inventory" marks a collected pickup after a load too. This fixed music,
-- whose collected pickups looked exactly like uncollected ones (all keep
-- Pickup_Glitch). Runs next to the per-category component checks.
local itemOfPickup = {}
local function ownedPickup(a)
    local addr = a:GetAddress()
    local item = itemOfPickup[addr]
    if item == nil then
        item = (Radar.itemDataPath(a) or ""):match("([^%./]+)$") or false
        itemOfPickup[addr] = item
    end
    return item ~= false and playerProgress().owned[item] == true
end

-- Key Items: story / puzzle items (ItemData/KeyItems: Factory_EmployeeCard,
-- Corridor_Key, Dog_treat, Gun_Love_Dies, LD_BloodVial, LD_Space_Helmet).
local KEY_ITEM_DATA = "/Game/Assets/Inventory/ItemData/KeyItems/"
local KEY_ITEMS = {
    tag = "keyitem", label = "Key Items",
    parents = PICKUP_PARENT,
    match = function(_, actor)
        local path = Radar.itemDataPath(actor)
        return path ~= nil and path:sub(1, #KEY_ITEM_DATA) == KEY_ITEM_DATA
    end,
    aliveComponent = "Pickup_Glitch",
    icon = TEX .. "Pickups/key_item_pickup.key_item_pickup",
    color = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }, colorNearest = GOLD,
}

for _, c in ipairs({ CRYSTALS, CRESTS, RELICS, ISLANDS, SHRINES, MUSIC, WHISKY,
                     TRANSMISSIONS, GHOSTS, SKINS, KEY_ITEMS }) do
    c.doneScan = ownedPickup
end

-- Shinji: an NPC met in unexpected places. In the data he's the Fox Messenger
-- collection (FoxMessengerCollection, items FoxItem_NN, 50 actors NPC_Shinji).
-- After the talk he explodes and the game turns his collision off (state
-- watcher: bActorEnableCollision true -> false); met ones are also in the
-- player's collection. match must not be match-all: the full-scan fallback
-- would take every actor.
local SHINJI = {
    tag = "shinji", label = "Shinji",
    parents = { "NPC_Shinji_C" },
    match = function(cls) return cls == "NPC_Shinji_C" end,
    alive = function(a) return a.bActorEnableCollision == true end,
    doneScan = collectedByPlayer,
    icon = "/Game/Assets/2D_Assets/Characters/Avatars/shinji_avatar.shinji_avatar",
    color = { R = 0.95, G = 0.35, B = 1.0, A = 1.0 }, colorNearest = GOLD,
}

-- Blood Shrines: pyramid shrines where Lady Love Dies (the player) lets blood
-- and donates a Blood Crystal. Class Temple_Shrine_Blueprint; each has a
-- Collection component with category ShrineCollection and item
-- Shrine_<God> (the same 17 gods as the Shrine Carvings). Donating changes
-- nothing on the shrine itself (state watcher saw nothing); it's recorded in
-- the player's collection.
local BLOOD_SHRINES = {
    tag = "bloodshrine", label = "Blood Shrines",
    parents = { "Temple_Shrine_Blueprint_C" },
    match = function(cls) return cls == "Temple_Shrine_Blueprint_C" end,
    doneScan = collectedByPlayer,
    icon = "/Game/Assets/2D_Assets/UI/Pyramid.Pyramid",
    color = { R = 1.0, G = 0.3, B = 0.3, A = 1.0 }, colorNearest = GOLD,
}

-- Vending machines: each sells one drink of the Drinks collection
-- (ItemData/Collectables/Drinks); drinks aren't world pickups, the machines are
-- what you look for. The machine's drink is the key of its
-- Inventory.StartingItems (e.g. VendingMachine_BizzareLychee ->
-- Collectable_Drink_BizzareLychee_2); sold out = that drink is in the player's
-- Inventory.OwnedItems. Store.NumItemsPurchased (1 right after a purchase) is
-- a second signal. (CachedHasItems was unreliable right after a load.)
local drinkOfMachine = {}
local function machineDrink(a)
    local addr = a:GetAddress()
    local d = drinkOfMachine[addr]
    if d == nil then
        d = false
        pcall(function()
            a.Inventory.StartingItems:ForEach(function(k, _)
                local okK, kv = pcall(function() return k:get() end)
                d = (okK and nameOf(kv)) or false
                return true
            end)
        end)
        drinkOfMachine[addr] = d
    end
    return d or nil
end

local VENDING = {
    tag = "vending", label = "Vending Machines",
    parents = { "VendingMachine_Blueprint_C", "VendingMachine_Broken_Blueprint_C" },
    match = function(cls) return cls:sub(1, 15) == "VendingMachine_" end,
    icon = TEX .. "Collectables/Drink_Coffee.Drink_Coffee",
    doneScan = function(a)
        local okP, bought = pcall(function() return a.Store.NumItemsPurchased end)
        if okP and type(bought) == "number" and bought > 0 then return true end
        local drink = machineDrink(a)
        return drink ~= nil and playerProgress().owned[drink] == true
    end,
    -- Logged for the 5 nearest machines once per level (research).
    debug = function(a)
        local drink = machineDrink(a)
        return string.format("drink=%s  owned=%s", tostring(drink),
            tostring(drink ~= nil and playerProgress().owned[drink] == true))
    end,
    color = { R = 0.35, G = 0.95, B = 0.95, A = 1.0 }, colorNearest = GOLD,
}

return Radar.new({
    id         = "radar",
    name       = "Radar",
    default    = false,
    toggleKey  = { key = "B", ctrl = true },
    categories = { CRYSTALS, CRESTS, RELICS, ISLANDS, SHRINES, MUSIC, WHISKY, TRANSMISSIONS, GHOSTS, SKINS, KEY_ITEMS,
                   SHINJI, BLOOD_SHRINES, VENDING },
    -- Written automatically once per level (no Ctrl+F9 needed).
    autoResearch = { vendingcomp = true, player = true, collection = true, playermaps = true },
    -- Find what marks a sold-out machine / donated shrine / met Shinji.
    compare    = {
        { tag = "vending", component = "Inventory" },
        { tag = "vending", component = "Store" },
        { tag = "bloodshrine", component = "Collection" },
        { tag = "shinji", component = "Collection" },
    },
    -- Log what changes on a shrine when blood is donated / on Shinji when met.
    watch      = { tags = { bloodshrine = true, shinji = true, vending = true }, radiusM = 12, components = { "Collection", "Inventory", "Store" } },
    -- Containers (cupboards, bins, gashapon...) spawn their item only when
    -- opened. Dumped on Ctrl+F9 to find which property says what's inside.
    research   = {
        -- Where the game remembers collected items (music in particular).
        { tag = "player", maxElems = 400, get = function()
            local U = require("core.util")
            local pawn = U.getPawn()
            if not pawn then return {} end
            local out = {}
            for _, name in ipairs({ "Inventory", "Collection", "ItemMonitor" }) do
                local ok, comp = pcall(function() return pawn[name] end)
                if ok and comp then out[#out + 1] = comp end
            end
            return out
        end },
        -- Shinji and the Blood Shrines carry a "Collection" component: likely
        -- where the game remembers "met" / "donated".
        { tag = "collection", maxElems = 50, get = function()
            local out = {}
            for _, cls in ipairs({ "NPC_Shinji_C", "Temple_Shrine_Blueprint_C" }) do
                for _, a in ipairs(FindAllOf(cls) or {}) do
                    local ok, comp = pcall(function() return a.Collection end)
                    if ok and comp then out[#out + 1] = comp end
                end
            end
            return out
        end },
        -- Vending machines: where "already bought everything" lives. The three
        -- nearest machines' Inventory and Store components.
        { tag = "vendingcomp", maxElems = 30, get = function()
            local U = require("core.util")
            local pawn = U.getPawn()
            if not pawn then return {} end
            local o = pawn:K2_GetActorLocation()
            local machines = {}
            for _, cls in ipairs({ "VendingMachine_Blueprint_C", "VendingMachine_Broken_Blueprint_C" }) do
                for _, a in ipairs(FindAllOf(cls) or {}) do
                    if U.valid(a) then
                        local l = a:K2_GetActorLocation()
                        local d = math.sqrt((l.X - o.X) ^ 2 + (l.Y - o.Y) ^ 2 + (l.Z - o.Z) ^ 2)
                        machines[#machines + 1] = { a = a, d = d }
                    end
                end
            end
            table.sort(machines, function(x, y) return x.d < y.d end)
            local out = {}
            for i = 1, math.min(3, #machines) do
                for _, name in ipairs({ "Inventory", "Store" }) do
                    local ok, comp = pcall(function() return machines[i].a[name] end)
                    if ok and comp then out[#out + 1] = comp end
                end
            end
            return out
        end },
        -- Keys (and simple values) of the player's maps: where donated shrines,
        -- met Shinjis and bought drinks are remembered. Read with TMap:ForEach
        -- (UE4SS maps have Find/Contains/ForEach, but no Num).
        { tag = "playermaps", run = function(reason)
            local U = require("core.util")
            local S = require("core.settings")
            local pawn = U.getPawn()
            if not pawn then return end
            local path = string.format("%splayermaps_%s.txt", S.dir(), os.date("%Y%m%d_%H%M%S"))
            local f = io.open(path, "w")
            if not f then return end
            f:write("-- " .. reason .. ", " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
            -- Best-effort text for a map key/value: object name, FName/FString
            -- text, or a struct's fields (one level, arrays up to 40 elements).
            local function desc(v, depth)
                if type(v) ~= "userdata" then return tostring(v) end
                local okN, name = pcall(function() return v:GetFullName() end)
                if okN and type(name) == "string" then return name end
                local okT, text = pcall(function() return v:ToString() end)
                if okT and type(text) == "string" then return text end
                local okA, num = pcall(function() return v:GetArrayNum() end)
                if okA and type(num) == "number" then
                    local elems = {}
                    pcall(function()
                        v:ForEach(function(i, e)
                            if i > 40 then return true end
                            local okE, ev = pcall(function() return e:get() end)
                            elems[#elems + 1] = okE and desc(ev, depth + 1) or "?"
                        end)
                    end)
                    return "[" .. num .. "] " .. table.concat(elems, " | ")
                end
                if depth < 1 then
                    local okS, st = pcall(function() return v:GetStruct() end)
                    if okS and st then
                        local parts = {}
                        pcall(function()
                            st:ForEachProperty(function(prop)
                                local field = prop:GetFName():ToString()
                                local okF, fv = pcall(function() return v[field] end)
                                parts[#parts + 1] = field .. "=" .. (okF and desc(fv, depth + 1) or "?")
                            end)
                        end)
                        return "{" .. table.concat(parts, ", ") .. "}"
                    end
                end
                return "<" .. tostring(v) .. ">"
            end
            local function describe(param)
                local okV, v = pcall(function() return param:get() end)
                if not okV then v = param end
                return desc(v, 0)
            end
            -- Key/value property types of a map, from the owning class's reflection.
            local function mapTypes(obj, mapName)
                local out = "?"
                pcall(function()
                    obj:GetClass():ForEachProperty(function(prop)
                        if prop:GetFName():ToString() == mapName then
                            local okK, k = pcall(function() return prop:GetKeyProp():GetClass():GetFName():ToString() end)
                            local okV, v = pcall(function() return prop:GetValueProp():GetClass():GetFName():ToString() end)
                            out = (okK and k or "?") .. " -> " .. (okV and v or "?")
                        end
                    end)
                end)
                return out
            end
            for _, spec in ipairs({ { "Collection", "CollectionData" }, { "Inventory", "OwnedItems" },
                                    { "Inventory", "OwnedCurrency" } }) do
                local okO, owner = pcall(function() return pawn[spec[1]] end)
                f:write(string.format("\n== %s.%s  (%s)\n", spec[1], spec[2],
                    okO and mapTypes(owner, spec[2]) or "?"))
                local n = 0
                pcall(function()
                    owner[spec[2]]:ForEach(function(k, v)
                        n = n + 1
                        if n > 600 then return true end
                        f:write(string.format("  %s = %s\n", describe(k), describe(v)))
                    end)
                end)
                f:write(string.format("  (%d entries)\n", n))
            end
            -- The stock maps of the 3 nearest vending machines: machine -> drink.
            local o = pawn:K2_GetActorLocation()
            local machines = {}
            for _, cls in ipairs({ "VendingMachine_Blueprint_C", "VendingMachine_Broken_Blueprint_C" }) do
                for _, a in ipairs(FindAllOf(cls) or {}) do
                    if U.valid(a) then
                        local l = a:K2_GetActorLocation()
                        machines[#machines + 1] = { a = a, d = math.sqrt((l.X - o.X) ^ 2 + (l.Y - o.Y) ^ 2 + (l.Z - o.Z) ^ 2) / 100 }
                    end
                end
            end
            table.sort(machines, function(x, y) return x.d < y.d end)
            for i = 1, math.min(3, #machines) do
                local a = machines[i].a
                for _, mapName in ipairs({ "OwnedItems", "StartingItems" }) do
                    f:write(string.format("\n== %.0fm %s Inventory.%s\n", machines[i].d, a:GetFName():ToString(), mapName))
                    local n = 0
                    pcall(function()
                        a.Inventory[mapName]:ForEach(function(k, v)
                            n = n + 1
                            if n > 20 then return true end
                            f:write(string.format("  %s = %s\n", describe(k), describe(v)))
                        end)
                    end)
                    f:write(string.format("  (%d entries)\n", n))
                end
            end
            f:close()
            U.log("Radar[playermaps]: wrote %s", path)
        end },
        { tag = "container", parents = {
            "BP_crate_cupboard_master_C", "BP_crate_cupboard_locked_hinged_C",
            "BP_crate_cupboard_hinged_bloodChiller_C", "BP_crate_gashapon_master_C",
            "BP_crate_open_bin_master_C", "BP_crate_collectable_pyramid_master_C",
            "BP_locked_crate_no_computer_C", "Blueprint_EzraLocker_C",
        } },
    },
})

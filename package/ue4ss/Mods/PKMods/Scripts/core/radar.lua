-- Pickup radar: Radar.new(cfg) returns one feature that, while enabled,
-- marks pickups still lying in the loaded world: an icon with the distance on
-- the item when it's on screen, an arrow at the screen edge (compass-style)
-- when it's not. Items come from categories, each with an ON/OFF filter in
-- the menu; the nearest item of each category is highlighted.
--
-- cfg = { id, name, default, toggleKey,   feature fields (see main.lua)
--         categories = { category, ... },
--         research = { { tag, parents | get, maxElems } | { tag, run = fn(reason) }, ... },
--         watch = { tags = { [tag] = true }, radiusM, components = { name } },
--         compare = { { tag, component }, ... } }
--                    logs which component properties differ across a category
--                    logs state changes of nearby items (research)
--                    extra Ctrl+F9 dumps without markers: actors of the parent
--                    classes, or the objects get() returns
-- category = {
--   tag            short name for settings, logs, dump files ("crystal")
--   label          menu filter text ("Blood Crystals")
--   default        filter state before the user changes it (default true)
--   parents        classes passed to FindAllOf (subclasses are included). A
--                  guess is fine: if nothing is found, one full actor scan per
--                  level finds the real parent classes
--   match          fn(className, actor) -> bool, picks the wanted pickups
--                  (Radar.itemDataPath(actor) helps: items are told apart by
--                  the folder of their InventoryItemData asset)
--   icon           texture path, or fn(className) -> texture path
--   icons          with a function icon: every path it can return (preloaded;
--                  textures are never loaded during gameplay)
--   aliveComponent name of a Blueprint-created component every uncollected item
--                  has and a collected one lacks ("Pickup_Glitch"); this is how
--                  items collected before the save was loaded are recognized
--   doneScan       fn(actor) -> bool, "already done" check run once per scan
--                  (every 3 s) for checks too slow for every frame
--   alive          fn(actor) -> bool, extra per-frame check for things that
--                  aren't pickups (Shinji: still has collision); keep it cheap
--   fullComponents older variant: uncollected items have this many components
--                  nil for both = only bHasBeenRemoved (this session) is used
--   color, colorNearest   label colors
-- }
local U  = require("core.util")
local S  = require("core.settings")
local UI = require("core.ui")

local Radar = {}

local MAX_MARKERS = 24
local RESCAN_MS   = 3000
local EDGE_MARGIN = 48
local ICON_SIZE   = 32
local FONT_SIZE   = 16

-- Icon textures.
--   * Loaded (LoadAsset) only by preloadIcons() right after a level load, never
--     in the middle of gameplay.
--   * Unreal's GC doesn't see Lua references: a texture cached without
--     anything else holding it was freed (e.g. by a level load) and the next
--     SetBrushFromTexture read freed memory (two EXCEPTION_ACCESS_VIOLATION
--     crashes). Hidden "keeper" Images in our UI hold each icon in their brush,
--     a real UPROPERTY reference, so the GC keeps the textures alive.
--   * Textures are remembered at preload and checked with U.valid before every
--     use. They are NOT looked up again with StaticFindObject during gameplay:
--     that's fatal while the engine collects garbage (crashed once).
local textures = {}  -- path -> Texture2D object, or false (missing)

-- The live Texture2D at path, or nil.
local function liveTexture(path)
    if not path then return nil end
    local t = StaticFindObject(path)
    if U.valid(t) and U.className(t) == "Texture2D" then return t end
    return nil
end

local function loadTexture(path)
    local t = liveTexture(path)
    if t then return t end
    pcall(function() LoadAsset(path) end)
    t = liveTexture(path)
    if not t then U.log("Radar: icon texture missing or not a Texture2D: %s", path) end
    return t
end

local function texture(path)
    local t = textures[path]
    if t and U.valid(t) then return t end
    return nil
end

-- Names of the components the item's Blueprint created. (K2_GetComponentsByClass
-- returned nothing on these actors, so the array is read directly.)
local function createdComponents(actor)
    local names = {}
    pcall(function()
        actor.BlueprintCreatedComponents:ForEach(function(_, elem)
            local c = elem:get()
            if U.valid(c) then names[#names + 1] = c:GetFName():ToString() end
        end)
    end)
    return names
end

local function createdCount(actor)
    local ok, n = pcall(function() return actor.BlueprintCreatedComponents:GetArrayNum() end)
    return ok and n or nil
end

-- Path of the pickup's InventoryItemData asset, e.g.
-- "/Game/Assets/Inventory/ItemData/Collectables/Collectable_CrystallizedTears.Collectable_CrystallizedTears",
-- or nil. (GetFullName is "<Class> <path>"; UE4SS has no GetPathName.)
function Radar.itemDataPath(actor)
    local ok, full = pcall(function()
        local d = actor.ItemData
        if not U.valid(d) then return nil end
        return d:GetFullName()
    end)
    if ok and type(full) == "string" then return full:match("^%S+%s+(.+)$") end
    return nil
end

local function distM(actor, o)
    local l = actor:K2_GetActorLocation()
    local dx, dy, dz = l.X - o.X, l.Y - o.Y, l.Z - o.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100
end

-- Readable property values of obj's whole class chain: scalars, object names,
-- array lengths ("[n]"), plus the names of Blueprint-created components.
-- Property types a snapshot reads. Everything else (structs, maps, sets,
-- delegates, text, interfaces) is skipped: reading the whole state of a
-- vending machine, arrays of structs included, hung the game.
local SIMPLE_TYPES = {
    BoolProperty = true, ByteProperty = true, EnumProperty = true,
    IntProperty = true, Int64Property = true, UInt32Property = true,
    FloatProperty = true, DoubleProperty = true,
    NameProperty = true, StrProperty = true,
    ObjectProperty = true, ClassProperty = true,
}

local function propType(prop)
    local ok, t = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and t or "?"
end

-- Array of objects? Only those get their elements listed.
local function objectArray(prop)
    local ok, t = pcall(function() return prop:GetInner():GetClass():GetFName():ToString() end)
    return ok and (t == "ObjectProperty" or t == "ClassProperty")
end

local function snapshot(obj, maxElems)
    maxElems = maxElems or 6
    local snap = {}
    local cls = obj:GetClass()
    while U.valid(cls) and cls:GetFName():ToString() ~= "Object" do
        pcall(function()
            cls:ForEachProperty(function(prop)
                local name = prop:GetFName():ToString()
                local ptype = propType(prop)
                if ptype == "ArrayProperty" then
                    local listElems = objectArray(prop)
                    local okI, inner = pcall(function() return prop:GetInner():GetClass():GetFName():ToString() end)
                    local innerType = okI and inner or "?"
                    pcall(function()
                        local arr = obj[name]
                        local num = arr:GetArrayNum()
                        local elems = {}
                        if listElems then
                            arr:ForEach(function(i, elem)
                                if i > maxElems then return true end  -- stop
                                local okE, s = pcall(function() return elem:get():GetFullName() end)
                                elems[#elems + 1] = (okE and type(s) == "string") and s or "?"
                            end)
                        end
                        snap[name] = "[" .. num .. " x " .. innerType .. "]" .. (#elems > 0 and (" " .. table.concat(elems, " | ")) or "")
                    end)
                    return
                end
                if not SIMPLE_TYPES[ptype] then
                    snap[name] = "<" .. ptype .. ", not read>"
                    return
                end
                local ok, v = pcall(function() return obj[name] end)
                if not ok then return end
                local tv = type(v)
                if tv == "boolean" or tv == "number" or tv == "string" then
                    snap[name] = tostring(v)
                elseif tv == "userdata" then
                    local ok2, full = pcall(function() return v:GetFullName() end)
                    if ok2 and type(full) == "string" then snap[name] = full end
                end
            end)
        end)
        cls = cls:GetSuperStruct()
    end
    snap["created components"] = table.concat(createdComponents(obj), ", ")
    return snap
end

-- ---------------------------------------------------------------------------
-- Projection (pure math, no out-params)

local function camBasis(rot)
    local p, y = math.rad(rot.Pitch), math.rad(rot.Yaw)
    local cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    return { cp * cy, cp * sy, sp }, { -sy, cy, 0 }, { -sp * cy, -sp * sy, cp }
end

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Returns x, y (widget units), onScreen, edge arrow
local function project(world, cam, W, H)
    local d = { world.X - cam.loc.X, world.Y - cam.loc.Y, world.Z - cam.loc.Z }
    local x, y, z = dot(d, cam.fwd), dot(d, cam.right), dot(d, cam.up)
    local cx, cy, m = W / 2, H / 2, EDGE_MARGIN

    if x > 1 then
        local sx, sy = cx + y / x * cam.focal, cy - z / x * cam.focal
        if sx >= m and sx <= W - m and sy >= m and sy <= H - m then
            return sx, sy, true, nil
        end
    end

    local dx, dy = y, -z
    if x <= 1 and math.abs(dx) < 1 and math.abs(dy) < 1 then dy = 1 end  -- straight behind
    local len = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / len, dy / len
    local hw, hh = cx - m, cy - m
    local t = math.min(dx ~= 0 and hw / math.abs(dx) or math.huge, dy ~= 0 and hh / math.abs(dy) or math.huge)
    local sx, sy = cx + dx * t, cy + dy * t
    local arrow
    if math.abs(sx - m) < 1 then arrow = "<"
    elseif math.abs(sx - (W - m)) < 1 then arrow = ">"
    elseif sy < cy then arrow = "^"
    else arrow = "v" end
    return sx, sy, false, arrow
end

-- ---------------------------------------------------------------------------

function Radar.new(cfg)
    local F = {
        id        = cfg.id,
        name      = cfg.name,
        default   = cfg.default,
        toggleKey = cfg.toggleKey,
    }

    local pool     = {}   -- { icon, iconSlot, iconPath, hasIcon, label, labelSlot }
    local getOpacity      -- defined with the opacity hotkeys below
    local runResearch     -- defined after F.diag
    local autoResearchDone = false
    local lastScan = -math.huge

    -- Per-category state.
    for _, c in ipairs(cfg.categories) do
        c.items, c.componentsLogged, c.fallbackDone = {}, false, false
    end

    local function catOn(c)
        return S.get(cfg.id .. "." .. c.tag, c.default ~= false)
    end

    local function iconPath(c, className)
        if type(c.icon) == "function" then return c.icon(className) end
        return c.icon
    end

    -- Every icon a category can use: its icon string, or its `icons` list when
    -- icon is a function.
    local preloaded = false
    local iconPaths = {}
    for _, c in ipairs(cfg.categories) do
        if type(c.icon) == "string" then iconPaths[#iconPaths + 1] = c.icon end
        for _, p in ipairs(c.icons or {}) do iconPaths[#iconPaths + 1] = p end
    end

    local keepersGen = -1
    local function preloadIcons()
        if not preloaded then
            preloaded = true
            for _, path in ipairs(iconPaths) do
                textures[path] = loadTexture(path) or false
            end
        end
        -- One hidden Image per icon in the current UI build keeps it alive.
        if keepersGen ~= UI.generation then
            keepersGen = UI.generation
            for _, path in ipairs(iconPaths) do
                local tex = texture(path)
                if tex then
                    local img = UI.add("/Script/UMG.Image", "IconKeeper", 0)
                    img:SetBrushFromTexture(tex, false)
                end
            end
            for _, m in ipairs(pool) do m.iconPath = nil end  -- re-set brushes from live textures
        end
    end

    -- Collected items stay in the world.
    --  * picked up this session: the game sets bHasBeenRemoved (and destroys a component);
    --  * collected before the save was loaded: bHasBeenRemoved is false again,
    --    but the component is still missing (verified for Blood Crystals).
    -- Collected before the save was loaded: decided once per scan (component
    -- arrays are too slow to walk every frame), kept in c.gone by address.
    local function collectedBefore(c, actor)
        if c.doneScan then
            local ok, done = pcall(c.doneScan, actor)
            if ok and done == true then return true end
        end
        if c.aliveComponent then
            for _, name in ipairs(createdComponents(actor)) do
                if name == c.aliveComponent then return false end
            end
            return true
        end
        if c.fullComponents then
            local n = createdCount(actor)
            return n ~= nil and n < c.fullComponents
        end
        return false
    end

    local function isAlive(c, actor)
        if not U.valid(actor) then return false end
        if c.gone and c.gone[actor:GetAddress()] then return false end
        local ok, removed = pcall(function() return actor.bHasBeenRemoved end)
        -- Strict == true: on actors without the property (NPCs, shrines) UE4SS
        -- returns a placeholder object, which Lua treats as true.
        if ok and removed == true then return false end
        local okH, hidden = pcall(function() return actor.bHidden end)
        if okH and hidden == true then return false end
        if c.alive then
            local okA, alive = pcall(c.alive, actor)
            if okA and not alive then return false end
        end
        return true
    end

    -- Once per level: which component sets the items have (research for
    -- fullComponents / a check for a specific component).
    -- Research: compare a component across all items of a category and log only
    -- the properties whose values differ, with the distance of the nearest item
    -- per value. Standing next to a "done" item (sold-out machine, donated
    -- shrine) shows which value marks it. Runs once per level and on Ctrl+F9.
    local function compareComponent(c, compName)
        local pawn = U.getPawn()
        local o = pawn and pawn:K2_GetActorLocation()
        local values = {}  -- key -> value -> { n, nearest }
        local total = 0
        for _, a in ipairs(c.items) do
            local ok, comp = pcall(function() return a[compName] end)
            if U.valid(a) and ok and comp and U.valid(comp) then
                total = total + 1
                local okD, d = pcall(distM, a, o)
                d = (o and okD) and d or -1
                for k, v in pairs(snapshot(comp, 20)) do
                    values[k] = values[k] or {}
                    local e = values[k][v] or { n = 0, nearest = math.huge }
                    e.n = e.n + 1
                    if d >= 0 and d < e.nearest then e.nearest = d end
                    values[k][v] = e
                end
            end
        end
        local keys = {}
        for k in pairs(values) do keys[#keys + 1] = k end
        table.sort(keys)
        local lines = 0
        for _, k in ipairs(keys) do
            local distinct = {}
            for v, e in pairs(values[k]) do distinct[#distinct + 1] = { v = v, e = e } end
            if #distinct > 1 and #distinct <= 8 then
                table.sort(distinct, function(x, y) return x.e.n < y.e.n end)
                local parts = {}
                for _, d in ipairs(distinct) do
                    parts[#parts + 1] = string.format("%s x%d (nearest %.0fm)", d.v:sub(1, 120), d.e.n, d.e.nearest)
                end
                U.log("Radar[%s] %s.%s differs: %s", c.tag, compName, k, table.concat(parts, "  |  "))
                lines = lines + 1
            end
        end
        U.log("Radar[%s] compared %s on %d items, %d differing properties", c.tag, compName, total, lines)
    end

    local function runCompares()
        for _, cmp in ipairs(cfg.compare or {}) do
            for _, c in ipairs(cfg.categories) do
                if c.tag == cmp.tag and #c.items > 0 then pcall(compareComponent, c, cmp.component) end
            end
        end
    end

    local function logComponentSets(c)
        if c.componentsLogged or #c.items == 0 then return end
        c.componentsLogged = true
        local sets = {}
        for _, a in ipairs(c.items) do
            if U.valid(a) then
                local key = table.concat(createdComponents(a), ", ")
                local e = sets[key] or { n = 0, removed = 0, classes = {} }
                e.n = e.n + 1
                local ok, removed = pcall(function() return a.bHasBeenRemoved end)
                if ok and removed == true then e.removed = e.removed + 1 end
                if #e.classes < 4 then e.classes[#e.classes + 1] = U.className(a) end
                sets[key] = e
            end
        end
        for key, e in pairs(sets) do
            U.log("Radar[%s]: %d with components [%s], %d with bHasBeenRemoved (e.g. %s)",
                c.tag, e.n, key, e.removed, table.concat(e.classes, ", "))
        end
    end

    local function filter(list, c)
        local found = {}
        for _, a in ipairs(list) do
            if U.valid(a) and c.match(U.className(a), a) then found[#found + 1] = a end
        end
        return found
    end

    -- One scan for all enabled categories: FindAllOf walks every object in the
    -- game, so each parent class is searched once, not once per category.
    -- A category that finds nothing through its parents gets one full actor scan
    -- per level; the real parent classes of what it finds replace the guess.
    local function scanAll(all)
        local byParent, actors = {}, nil
        for _, c in ipairs(cfg.categories) do
            if all or catOn(c) then
                local found = {}
                for _, p in ipairs(c.parents) do
                    byParent[p] = byParent[p] or FindAllOf(p) or {}
                    for _, a in ipairs(filter(byParent[p], c)) do found[#found + 1] = a end
                end
                if #found == 0 and not c.fallbackDone then
                    c.fallbackDone = true
                    actors = actors or FindAllOf("Actor") or {}
                    found = filter(actors, c)
                    if #found > 0 then
                        local seen, parents = {}, {}
                        for _, a in ipairs(found) do
                            local ok, super = pcall(function()
                                return a:GetClass():GetSuperStruct():GetFName():ToString()
                            end)
                            if ok and super and not seen[super] then
                                seen[super] = true
                                parents[#parents + 1] = super
                            end
                        end
                        c.parents = parents
                        U.log("Radar[%s]: found via full scan; parents now %s", c.tag, table.concat(parents, ", "))
                    end
                end
                c.items = found
                c.gone = {}
                for _, a in ipairs(found) do
                    if collectedBefore(c, a) then c.gone[a:GetAddress()] = true end
                end
                local firstTime = not c.componentsLogged
                if firstTime and c.doneScan and #found > 0 then
                    local n = 0
                    for _ in pairs(c.gone) do n = n + 1 end
                    U.log("Radar[%s]: %d of %d counted as done", c.tag, n, #found)
                    if c.debug then
                        local pawn = U.getPawn()
                        local o = pawn and pawn:K2_GetActorLocation()
                        local rows = {}
                        for _, a in ipairs(found) do
                            local okD, d = pcall(distM, a, o)
                            rows[#rows + 1] = { a = a, d = (o and okD) and d or 1e9 }
                        end
                        table.sort(rows, function(x, y) return x.d < y.d end)
                        for i = 1, math.min(5, #rows) do
                            local okS, info = pcall(c.debug, rows[i].a)
                            U.log("Radar[%s]   %.0fm %s: %s", c.tag, rows[i].d,
                                rows[i].a:GetFName():ToString(), okS and tostring(info) or ("debug error: " .. tostring(info)))
                        end
                    end
                end
                logComponentSets(c)
                if firstTime and c.componentsLogged then
                    for _, cmp in ipairs(cfg.compare or {}) do
                        if cmp.tag == c.tag then pcall(compareComponent, c, cmp.component) end
                    end
                end
            end
        end
        lastScan = U.nowMs()
        local anyItems = false
        for _, c in ipairs(cfg.categories) do
            if #(c.items or {}) > 0 then anyItems = true break end
        end
        -- Only in the game world: in the main menu there's nothing to dump.
        if cfg.autoResearch and not autoResearchDone and anyItems and U.getPawn() then
            autoResearchDone = true
            U.gameDelay(3000, function() pcall(runResearch, cfg.autoResearch, "auto research after level load") end)
        end
    end

    local function dumpAll(tag, items, reason, maxElems)
        local path = string.format("%s%s_states_%s.txt", S.dir(), tag, os.date("%Y%m%d_%H%M%S"))
        local f = io.open(path, "w")
        if not f then U.log("Radar[%s]: can't write %s", tag, path) return end
        f:write(string.format("-- %s, %s, %d items\n", reason, os.date("%Y-%m-%d %H:%M:%S"), #items))
        local pawn = U.getPawn()
        local o = pawn and pawn:K2_GetActorLocation()
        for _, a in ipairs(items) do
            if U.valid(a) then
                local okD, d = pcall(distM, a, o)
                local okN, objName = pcall(function() return a:GetFName():ToString() end)
                f:write(string.format("\n== %s (%s)  dist=%s\n", U.className(a), okN and objName or "?",
                    (o and okD) and string.format("%.1fm", d) or "?"))
                local snap = snapshot(a, maxElems)
                local keys = {}
                for k in pairs(snap) do keys[#keys + 1] = k end
                table.sort(keys)
                for _, k in ipairs(keys) do f:write(string.format("  %s = %s\n", k, snap[k])) end
            end
        end
        f:close()
        U.log("Radar[%s]: wrote %d states to %s", tag, #items, path)
    end

    UI.onBuild(function()
        pool = {}
        for i = 1, MAX_MARKERS do
            local m = {}
            m.icon, m.iconSlot = UI.add("/Script/UMG.Image", "RadarIcon", 10000)
            m.iconSlot:SetAutoSize(false)
            m.iconSlot:SetAlignment({ X = 0.5, Y = 0.5 })
            m.label, m.labelSlot = UI.add("/Script/UMG.TextBlock", "RadarLabel", 10001)
            UI.styleText(m.label, FONT_SIZE)
            m.labelSlot:SetAutoSize(true)
            m.labelSlot:SetAlignment({ X = 0.5, Y = 0.0 })
            pool[i] = m
        end
    end)

    local function hideAll()
        for _, m in ipairs(pool) do
            pcall(function()
                UI.setVisible(m.icon, false)
                UI.setVisible(m.label, false)
            end)
        end
    end

    -- Items of every enabled category. The nearest of each category is always
    -- shown (and highlighted); the remaining markers go to the nearest overall.
    local function visibleItems(origin)
        local all, nearestOf = {}, {}
        for _, c in ipairs(cfg.categories) do
            if catOn(c) then
                for _, a in ipairs(c.items) do
                    if isAlive(c, a) then
                        local l = a:K2_GetActorLocation()
                        local dx, dy, dz = l.X - origin.X, l.Y - origin.Y, l.Z - origin.Z
                        local e = {
                            loc  = { X = l.X, Y = l.Y, Z = l.Z },
                            dist = math.sqrt(dx * dx + dy * dy + dz * dz) / 100,
                            cls  = U.className(a),
                            cat  = c,
                        }
                        all[#all + 1] = e
                        local n = nearestOf[c]
                        if not n or e.dist < n.dist then nearestOf[c] = e end
                    end
                end
            end
        end
        table.sort(all, function(a, b) return a.dist < b.dist end)
        local out = {}
        for _, e in pairs(nearestOf) do
            e.nearest = true
            out[#out + 1] = e
        end
        for _, e in ipairs(all) do
            if #out >= MAX_MARKERS then break end
            if not e.nearest then out[#out + 1] = e end
        end
        return out
    end


    -- State watcher (research): items of the cfg.watch categories near the
    -- player are snapshotted every WATCH_MS, together with the listed
    -- components; values that change get logged. Keys that keep changing
    -- (timers, animation) are muted after a few changes. This is how
    -- "donated" / "met" can be found without the user pressing anything.
    local WATCH_MS = 2000
    local watchPrev, watchCount, lastWatch = {}, {}, -math.huge

    local function watchSnapshot(a, components)
        local snap = snapshot(a, 10)
        for _, name in ipairs(components or {}) do
            local ok, comp = pcall(function() return a[name] end)
            if ok and comp and U.valid(comp) then
                for k, v in pairs(snapshot(comp, 10)) do snap[name .. "." .. k] = v end
            end
        end
        return snap
    end

    local function watchTick(origin)
        local w = cfg.watch
        if not w or U.nowMs() - lastWatch < WATCH_MS then return end
        lastWatch = U.nowMs()
        for _, c in ipairs(cfg.categories) do
            if w.tags[c.tag] then
                for _, a in ipairs(c.items) do
                    if U.valid(a) then
                        local okD, d = pcall(distM, a, origin)
                        if okD and d <= w.radiusM then
                            local addr = a:GetAddress()
                            local snap = watchSnapshot(a, w.components)
                            local prev = watchPrev[addr]
                            if prev then
                                for k, v in pairs(snap) do
                                    if prev[k] ~= nil and prev[k] ~= v then
                                        local n = (watchCount[k] or 0) + 1
                                        watchCount[k] = n
                                        if n <= 3 then
                                            U.log("Radar[%s] state change on %s (%.1fm): %s: %s -> %s%s", c.tag,
                                                U.className(a), d, k, prev[k], v, n == 3 and "  (muted from now on)" or "")
                                        end
                                    end
                                end
                            end
                            watchPrev[addr] = snap
                        end
                    end
                end
            end
        end
    end

    function F.tick()
        local pc = U.getPC()
        if not pc then return end
        if not UI.ensure() or #pool == 0 then return end
        preloadIcons()
        if U.nowMs() - lastScan > RESCAN_MS then scanAll(false) end

        local cm = pc.PlayerCameraManager
        if not U.valid(cm) then return end
        local W, H = UI.viewport(pc)
        if not W or W < 1 or H < 1 then return end

        local cam = { loc = cm:GetCameraLocation() }
        cam.fwd, cam.right, cam.up = camBasis(cm:GetCameraRotation())
        cam.focal = (W / 2) / math.tan(math.rad(cm:GetFOVAngle()) / 2)

        local origin = cam.loc
        local pawn = U.getPawn()
        if pawn then origin = pawn:K2_GetActorLocation() end

        pcall(watchTick, origin)
        local list = visibleItems(origin)
        local opacity = getOpacity()
        for i, m in ipairs(pool) do
            local e = list[i]
            if not (e and U.valid(m.label) and U.valid(m.icon)) then
                UI.setVisible(m.icon, false)
                UI.setVisible(m.label, false)
            else
                local sx, sy, onScreen, arrow = project(e.loc, cam, W, H)
                local color = e.nearest and e.cat.colorNearest or e.cat.color
                local size = e.nearest and ICON_SIZE * 1.4 or ICON_SIZE
                local text = string.format("%dm", math.floor(e.dist + 0.5))
                if arrow then text = arrow .. " " .. text end

                local path = iconPath(e.cat, e.cls)
                if path ~= m.iconPath then
                    local tex = texture(path)
                    if tex then m.icon:SetBrushFromTexture(tex, false) end
                    m.iconPath, m.hasIcon = path, tex ~= nil
                end
                if m.hasIcon then
                    m.iconSlot:SetSize({ X = size, Y = size })
                    m.iconSlot:SetPosition({ X = sx, Y = sy })
                    m.icon:SetOpacity(1.0)
                    m.icon:SetRenderOpacity(opacity * (onScreen and 1.0 or 0.75))
                    UI.setVisible(m.icon, true)
                else
                    text = "* " .. text
                    UI.setVisible(m.icon, false)
                end
                UI.setText(m.label, text)
                UI.setColor(m.label, color)
                m.labelSlot:SetPosition({ X = sx, Y = sy + (m.hasIcon and size / 2 + 2 or 0) })
                m.label:SetRenderOpacity(opacity)
                UI.setVisible(m.label, true)
            end
        end
    end

    function F.onEnable() end

    function F.onDisable()
        hideAll()
    end

    function F.onRestart()
        lastScan = -math.huge
        autoResearchDone = false
        preloaded = false
        watchPrev = {}
        for _, c in ipairs(cfg.categories) do
            c.items, c.componentsLogged, c.fallbackDone = {}, false, false
        end
    end

    -- Marker opacity, 10..100 % in 10 % steps (Ctrl+= / Ctrl+-).
    local OPACITY_KEY = cfg.id .. ".opacity"

    function getOpacity()
        return S.get(OPACITY_KEY, 1.0)
    end

    local function changeOpacity(delta)
        local v = math.floor(getOpacity() * 10 + delta + 0.5) / 10
        v = math.max(0.1, math.min(1.0, v))
        S.set(OPACITY_KEY, v)
        UI.toast(string.format("%s opacity: %d%%", cfg.name, math.floor(v * 100 + 0.5)))
    end

    local function more() changeOpacity(1) end
    local function less() changeOpacity(-1) end
    F.hotkeys = {
        { key = "Equals",   ctrl = true, fn = more, desc = "radar markers more visible" },
        { key = "Hyphen",   ctrl = true, fn = less, desc = "radar markers more transparent" },
        { key = "Add",      ctrl = true, fn = more, hidden = true },  -- numpad + / -
        { key = "Subtract", ctrl = true, fn = less, hidden = true },
    }

    -- Menu: opacity (cycles 100 -> 80 -> ... -> 20 -> 100), then one filter per category.
    F.options = {
        {
            label = function() return string.format("Opacity: %d%%", math.floor(getOpacity() * 100 + 0.5)) end,
            activate = function()
                local v = getOpacity() - 0.2
                if v < 0.15 then v = 1.0 end
                S.set(OPACITY_KEY, math.floor(v * 10 + 0.5) / 10)
            end,
        },
    }
    for _, c in ipairs(cfg.categories) do
        F.options[#F.options + 1] = {
            label = function() return string.format("%s: %s", c.label, catOn(c) and "ON" or "OFF") end,
            activate = function()
                S.set(cfg.id .. "." .. c.tag, not catOn(c))
                lastScan = -math.huge  -- a category just turned on needs its items
            end,
        }
    end

    -- Short list in the log; every property of every item goes to a file.
    function F.diag()
        runCompares()
        scanAll(true)
        local pawn = U.getPawn()
        local o = pawn and pawn:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
        for _, c in ipairs(cfg.categories) do
            dumpAll(c.tag, c.items, "Ctrl+F9")
            local rows, gone = {}, 0
            for _, a in ipairs(c.items) do
                if U.valid(a) then
                    if not isAlive(c, a) then gone = gone + 1 end
                    rows[#rows + 1] = { a = a, d = distM(a, o) }
                end
            end
            table.sort(rows, function(x, y) return x.d < y.d end)
            U.log("Radar[%s]: %d loaded, %d collected, filter %s, parents %s", c.tag, #rows, gone,
                catOn(c) and "ON" or "OFF", table.concat(c.parents, ", "))
            for i = 1, math.min(5, #rows) do
                U.log("  %2d. %-45s %7.1fm  alive=%s components=%s", i, U.className(rows[i].a), rows[i].d,
                    tostring(isAlive(c, rows[i].a)), tostring(createdCount(rows[i].a)))
            end
        end
        runResearch(nil, "Ctrl+F9 research")
    end

    -- Research dumps (cfg.research). only = set of tags, or nil for all.
    function runResearch(only, reason)
        for _, r in ipairs(cfg.research or {}) do
            if (not only or only[r.tag]) and r.run then
                local ok, err = pcall(r.run, reason)
                if not ok then U.log("Radar[%s]: research failed: %s", r.tag, tostring(err)) end
            elseif not only or only[r.tag] then
                local seen, items = {}, {}
                if r.get then
                    local ok, list = pcall(r.get)
                    for _, o in ipairs(ok and list or {}) do
                        if U.valid(o) then items[#items + 1] = o end
                    end
                end
                for _, p in ipairs(r.parents or {}) do
                    for _, a in ipairs(FindAllOf(p) or {}) do
                        if U.valid(a) and not seen[a:GetAddress()] then
                            seen[a:GetAddress()] = true
                            items[#items + 1] = a
                        end
                    end
                end
                dumpAll(r.tag, items, reason, r.maxElems)
            end
        end
    end

    return F
end

-- Shared with other research code (features/meditation.lua).
Radar.snapshot = snapshot

return Radar

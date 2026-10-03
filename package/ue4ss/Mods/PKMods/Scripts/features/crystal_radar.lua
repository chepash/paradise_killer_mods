-- Blood Crystal Radar: while enabled (F1 menu) marks every
-- Blood Crystal loaded in the world — on the crystal when it's on screen, at
-- the screen edge with an arrow (compass-style) when it's not.
--
-- Internally Blood Crystals are "GoldCoin": each one is its own Blueprint
-- (Blueprint_Pickup_GoldCoin_001.._159 + a few named ones) derived from
-- Blueprint_Pickup_Parent.
local U  = require("core.util")
local S  = require("core.settings")
local UI = require("core.ui")

local F = {
    id        = "crystal_radar",
    name      = "Blood Crystal Radar",
    default   = false,
    toggleKey = { key = "B", ctrl = true },
}

local CFG = {
    CLASS_PATTERN  = "GoldCoin",
    PARENT_CLASSES = { "Blueprint_Pickup_Parent_C" },
    MAX_MARKERS    = 12,
    RESCAN_MS      = 3000,
    EDGE_MARGIN    = 48,
    ICON_SIZE      = 32,
    ICON_TEXTURE   = "/Game/Assets/2D_Assets/Textures/Inventory/GoldCoins/GoldCoin.GoldCoin",
    FONT_SIZE      = 16,
    COLOR          = { R = 1.0, G = 0.25, B = 0.35, A = 1.0 },
    COLOR_NEAREST  = { R = 1.0, G = 0.85, B = 0.25, A = 1.0 },
}

local crystals  = {}
local lastScan  = -math.huge
local pool      = {}   -- { icon, iconSlot, label, labelSlot }
local iconTex   = nil
local iconTried = false


-- ---------------------------------------------------------------------------
-- Crystal discovery

local function isCrystal(actor)
    return U.className(actor):find(CFG.CLASS_PATTERN, 1, true) ~= nil
end

-- Names of the components the crystal's Blueprint created. A lying crystal
-- has 2; picking it up destroys one. (K2_GetComponentsByClass returned nothing
-- here, so the array is read directly.)
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

-- Collected crystals stay in the world.
--  * picked up this session: the game sets bHasBeenRemoved and destroys a component;
--  * collected before the save was loaded: the component is gone, but
--    bHasBeenRemoved is false again.
-- So a crystal counts as collected if the flag is set or a component is missing.
local FULL_COMPONENTS = 2

local function isAlive(actor)
    if not U.valid(actor) then return false end
    local ok, removed = pcall(function() return actor.bHasBeenRemoved end)
    if ok and removed then return false end
    local n = createdCount(actor)
    if n and n < FULL_COMPONENTS then return false end
    local okH, hidden = pcall(function() return actor.bHidden end)
    return not (okH and hidden)
end

-- Once per level: which components a normal vs a "collected" crystal has,
-- to replace the count check with a check for a specific component.
local componentsLogged = false

local function logComponentSets()
    if componentsLogged or #crystals == 0 then return end
    componentsLogged = true
    local sets = {}
    for _, a in ipairs(crystals) do
        if U.valid(a) then
            local key = table.concat(createdComponents(a), ", ")
            local e = sets[key] or { n = 0, example = U.className(a), removed = 0 }
            e.n = e.n + 1
            local ok, removed = pcall(function() return a.bHasBeenRemoved end)
            if ok and removed then e.removed = e.removed + 1 end
            sets[key] = e
        end
    end
    for key, e in pairs(sets) do
        U.log("Radar: %d crystal(s) with components [%s], %d with bHasBeenRemoved (e.g. %s)",
            e.n, key, e.removed, e.example)
    end
end

local function scan()
    local found = {}
    for _, parent in ipairs(CFG.PARENT_CLASSES) do
        for _, a in ipairs(FindAllOf(parent) or {}) do
            if U.valid(a) and isCrystal(a) then found[#found + 1] = a end
        end
    end
    if #found == 0 then
        -- Parent class guess was wrong: scan every actor.
        for _, a in ipairs(FindAllOf("Actor") or {}) do
            if U.valid(a) and isCrystal(a) then found[#found + 1] = a end
        end
    end
    crystals = found
    lastScan = U.nowMs()
    logComponentSets()
end

local function distM(actor, o)
    local l = actor:K2_GetActorLocation()
    local dx, dy, dz = l.X - o.X, l.Y - o.Y, l.Z - o.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 100
end

-- ---------------------------------------------------------------------------
-- Research dump (Ctrl+F9)

-- Readable property values of obj's whole class chain: scalars, object names,
-- array lengths ("[n]"), plus the names of Blueprint-created components.
local function snapshot(obj)
    local snap = {}
    local cls = obj:GetClass()
    while U.valid(cls) and cls:GetFName():ToString() ~= "Object" do
        pcall(function()
            cls:ForEachProperty(function(prop)
                local name = prop:GetFName():ToString()
                local ok, v = pcall(function() return obj[name] end)
                if not ok then return end
                local tv = type(v)
                if tv == "boolean" or tv == "number" or tv == "string" then
                    snap[name] = tostring(v)
                elseif tv == "userdata" then
                    local ok2, full = pcall(function() return v:GetFullName() end)
                    if ok2 and type(full) == "string" then
                        snap[name] = full
                    else
                        local ok3, num = pcall(function() return v:GetArrayNum() end)
                        if ok3 and type(num) == "number" then snap[name] = "[" .. num .. "]" end
                    end
                end
            end)
        end)
        cls = cls:GetSuperStruct()
    end
    snap["created components"] = table.concat(createdComponents(obj), ", ")
    return snap
end

-- Full state of every crystal -> crystal_states_<date>_<time>.txt in the mod folder.
local function dumpAllCrystals(reason)
    scan()
    local path = string.format("%scrystal_states_%s.txt", S.dir(), os.date("%Y%m%d_%H%M%S"))
    local f = io.open(path, "w")
    if not f then U.log("Radar: can't write %s", path) return end
    f:write(string.format("-- %s, %s, %d crystals\n", reason, os.date("%Y-%m-%d %H:%M:%S"), #crystals))
    local pawn = U.getPawn()
    local o = pawn and pawn:K2_GetActorLocation()
    for _, a in ipairs(crystals) do
        if U.valid(a) then
            f:write(string.format("\n== %s  dist=%s\n", U.className(a), o and string.format("%.1fm", distM(a, o)) or "?"))
            local snap = snapshot(a)
            local keys = {}
            for k in pairs(snap) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do f:write(string.format("  %s = %s\n", k, snap[k])) end
        end
    end
    f:close()
    U.log("Radar: wrote %d crystal states to %s", #crystals, path)
end

-- ---------------------------------------------------------------------------
-- Markers

local function loadIcon()
    if iconTried then return iconTex end
    iconTried = true
    pcall(function() iconTex = LoadAsset(CFG.ICON_TEXTURE) end)
    if not U.valid(iconTex) then iconTex = StaticFindObject(CFG.ICON_TEXTURE) end
    if not U.valid(iconTex) then
        iconTex = nil
        U.log("Radar: icon texture not found, using text markers")
    end
    return iconTex
end

UI.onBuild(function()
    pool = {}
    local tex = loadIcon()
    for i = 1, CFG.MAX_MARKERS do
        local m = {}
        if tex then
            m.icon, m.iconSlot = UI.add("/Script/UMG.Image", "RadarIcon", 10000)
            m.icon:SetBrushFromTexture(tex, false)
            m.iconSlot:SetAutoSize(false)
            m.iconSlot:SetAlignment({ X = 0.5, Y = 0.5 })
        end
        m.label, m.labelSlot = UI.add("/Script/UMG.TextBlock", "RadarLabel", 10001)
        UI.styleText(m.label, CFG.FONT_SIZE)
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
    local cx, cy, m = W / 2, H / 2, CFG.EDGE_MARGIN

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
-- Feature hooks

function F.tick()
    local pc = U.getPC()
    if not pc then return end

    if not UI.ensure() or #pool == 0 then return end
    if U.nowMs() - lastScan > CFG.RESCAN_MS then scan() end

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

    local list = {}
    for _, a in ipairs(crystals) do
        if isAlive(a) then
            local l = a:K2_GetActorLocation()
            local dx, dy, dz = l.X - origin.X, l.Y - origin.Y, l.Z - origin.Z
            list[#list + 1] = { loc = { X = l.X, Y = l.Y, Z = l.Z }, dist = math.sqrt(dx * dx + dy * dy + dz * dz) / 100 }
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)

    for i, m in ipairs(pool) do
        local c = list[i]
        if not (c and U.valid(m.label)) then
            UI.setVisible(m.icon, false)
            UI.setVisible(m.label, false)
        else
            local sx, sy, onScreen, arrow = project(c.loc, cam, W, H)
            local color = (i == 1) and CFG.COLOR_NEAREST or CFG.COLOR
            local size = (i == 1) and CFG.ICON_SIZE * 1.4 or CFG.ICON_SIZE
            local text = string.format("%dm", math.floor(c.dist + 0.5))
            if arrow then text = arrow .. " " .. text end
            if not m.icon then text = "* " .. text end

            if m.icon then
                m.iconSlot:SetSize({ X = size, Y = size })
                m.iconSlot:SetPosition({ X = sx, Y = sy })
                m.icon:SetOpacity(onScreen and 1.0 or 0.75)
                UI.setVisible(m.icon, true)
            end
            UI.setText(m.label, text)
            UI.setColor(m.label, color)
            m.labelSlot:SetPosition({ X = sx, Y = sy + (m.icon and size / 2 + 2 or 0) })
            UI.setVisible(m.label, true)
        end
    end
end

function F.onEnable() end

function F.onDisable()
    hideAll()
end

function F.onRestart()
    crystals, lastScan = {}, -math.huge
    componentsLogged = false
end

-- Short list in the log; every property of every crystal goes to a file.
function F.diag()
    dumpAllCrystals("Ctrl+F9")
    local pawn = U.getPawn()
    local o = pawn and pawn:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
    local rows, removed = {}, 0
    for _, a in ipairs(crystals) do
        if U.valid(a) then
            if not isAlive(a) then removed = removed + 1 end
            rows[#rows + 1] = { a = a, d = distM(a, o) }
        end
    end
    table.sort(rows, function(x, y) return x.d < y.d end)
    U.log("Radar: %d crystals loaded, %d picked up this session", #rows, removed)
    for i = 1, math.min(10, #rows) do
        U.log("  %2d. %-45s %7.1fm  alive=%s", i, U.className(rows[i].a), rows[i].d, tostring(isAlive(rows[i].a)))
    end
end

return F

-- PKMods — all Paradise Killer mods in one UE4SS package.
--
--   F1          open / close the mod menu (number keys switch items, 0 = next page)
--   Ctrl + J    Air Control on/off
--   Ctrl + B    Radar on/off (what it shows: filters in the menu)
--   Ctrl + F    Fly Mode on/off (Space up, Left Alt down)
--   Ctrl + F9   diagnostics to the UE4SS console / UE4SS.log / pkmods.log
-- Ctrl alone is left to the game's own AR view.
--
-- Adding a feature: create Scripts\features\<name>.lua returning a table
-- { id, name, default, toggleKey?, hotkeys?, options?, onEnable, onDisable,
--   tick?, onRestart?, diag? } and list it in FEATURES below.
-- Keys use Unreal key names: toggleKey = { key = "J", ctrl = true },
-- hotkeys = { { key = "B", ctrl = true, fn = function() ... end } }.

local scriptDir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
package.path = scriptDir .. "?.lua;" .. package.path

local U    = require("core.util")
local S    = require("core.settings")
-- Working directory is Binaries\Win64, so the relative path is a safe fallback.
local modDir = scriptDir ~= "" and (scriptDir .. "..\\") or "ue4ss\\Mods\\PKMods\\"
S.init(modDir)
U.setLogFile(modDir .. "pkmods.log")
U.log("===== PKMods start =====")
U.log("settings: %ssettings.txt", modDir)
local UI   = require("core.ui")
local Menu = require("core.menu")
local Input = require("core.input")

-- Parentheses matter: in Lua 5.4 require() returns (module, filepath), and the
-- last call in a table constructor would add the filepath as an extra entry.
local FEATURES = {
    (require("features.air_control")),
    (require("features.radar")),
    (require("features.fly")),
    (require("features.meditation")),
}

local MENU_KEY = S.get("menu.key", "F1")  -- Unreal key name
local DIGITS   = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }

local GREEN = { R = 0.3, G = 1.0, B = 0.4, A = 1 }
local RED   = { R = 1.0, G = 0.4, B = 0.4, A = 1 }

-- ---------------------------------------------------------------------------
-- Feature state

local function safe(fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok then U.log("error: %s", tostring(err)) end
end

local function setEnabled(f, on, quiet)
    f.enabled = on
    S.set(f.id .. ".enabled", on)
    safe(on and f.onEnable or f.onDisable)
    if not quiet then UI.toast(f.name .. ": " .. (on and "ON" or "OFF"), on and GREEN or RED) end
end

for _, f in ipairs(FEATURES) do
    f.enabled = S.get(f.id .. ".enabled", f.default)
end

-- ---------------------------------------------------------------------------
-- Menu items: one toggle per feature, followed by its options.

for _, f in ipairs(FEATURES) do
    Menu.add({
        label = function() return string.format("[%s]  %s", f.enabled and "ON " or "OFF", f.name) end,
        activate = function() setEnabled(f, not f.enabled) end,
        -- f.hint: how to use it, shown instead of the bare toggle key
        hint = f.hint or (f.toggleKey and Input.label(f.toggleKey.key, f.toggleKey.ctrl)) or nil,
    })
    for _, opt in ipairs(f.options or {}) do
        Menu.add({ label = opt.label, activate = opt.activate, indent = true })
    end
end

-- ---------------------------------------------------------------------------
-- Keys: polled on the game thread (see core/input.lua for why not RegisterKeyBind).

Input.bind(MENU_KEY, false, Menu.toggle)
for i, k in ipairs(DIGITS) do
    Input.bind(k, false, function() Menu.press(i) end)
end
Input.bind("Zero", false, Menu.nextPage)

for _, f in ipairs(FEATURES) do
    if f.toggleKey then
        Input.bind(f.toggleKey.key, f.toggleKey.ctrl, function() setEnabled(f, not f.enabled) end)
    end
    for _, hk in ipairs(f.hotkeys or {}) do
        Input.bind(hk.key, hk.ctrl, function()
            if f.enabled then hk.fn() end
        end)
        if not hk.hidden then
            Menu.addHotkey(Input.label(hk.key, hk.ctrl), (hk.desc or "?") .. " (" .. f.name .. ")")
        end
    end
end

-- What's around the player: every actor within NEARBY_M, nearest first, with
-- its item data if it has one. Answers "what is this thing in front of me?"
-- before picking it up. One full actor scan, only on Ctrl+F9.
local NEARBY_M = 8

local function nearby(pawn)
    local o = pawn:K2_GetActorLocation()
    local rows = {}
    for _, a in ipairs(FindAllOf("Actor") or {}) do
        if U.valid(a) then
            local ok, l = pcall(function() return a:K2_GetActorLocation() end)
            if ok and l then
                local d = math.sqrt((l.X - o.X) ^ 2 + (l.Y - o.Y) ^ 2 + (l.Z - o.Z) ^ 2) / 100
                if d <= NEARBY_M and a:GetAddress() ~= pawn:GetAddress() then
                    rows[#rows + 1] = { a = a, d = d }
                end
            end
        end
    end
    table.sort(rows, function(x, y) return x.d < y.d end)
    U.log("-- Actors within %dm: %d", NEARBY_M, #rows)
    for _, r in ipairs(rows) do
        local okI, item = pcall(function()
            local data = r.a.ItemData
            if data and data:IsValid() then return data:GetFullName():match("([^%.]+)$") end
            local coll = r.a.Collection
            if coll and coll:IsValid() then
                local ci = coll.CollectionItem
                if ci and ci:IsValid() then return "collection " .. ci:GetFullName():match("([^%.]+)$") end
            end
            return nil
        end)
        U.log("  %5.1fm  %-45s %-40s %s", r.d, U.className(r.a), r.a:GetFName():ToString(),
            (okI and item) and ("item " .. item) or "")
    end
end

local function diag()
    U.log("===== DIAGNOSTICS =====")
    local pc = U.getPC()
    U.log("PlayerController: %s", pc and pc:GetFullName() or "none")
    local pawn = U.getPawn()
    U.log("Pawn: %s", pawn and pawn:GetFullName() or "none")
    if pawn then safe(nearby, pawn) end
    for _, f in ipairs(FEATURES) do
        U.log("-- %s (%s)", f.name, f.enabled and "ON" or "OFF")
        safe(f.diag)
    end
    U.log("-- UserWidgets in viewport:")
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        local ok, inVp = pcall(function() return w:IsInViewport() end)
        if ok and inVp then
            local info = select(2, pcall(function()
                return string.format("visible=%s opacity=%.2f root=%s", tostring(w:IsVisible()),
                    w:GetRenderOpacity(), U.className(w.WidgetTree.RootWidget))
            end))
            U.log("  %s  %s", U.className(w), tostring(info))
        end
    end
    U.log("UI host: %s", UI.ensure() and "attached" or "none")
    U.log("===== END =====")
end
Input.bind("F9", true, diag)
Menu.addHotkey(Input.label("F9", true), "diagnostics -> pkmods.log")

-- ---------------------------------------------------------------------------
-- Level change / respawn

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    U.gameDelay(500, function()
        UI.reset()
        for _, f in ipairs(FEATURES) do
            safe(f.onRestart)
            if f.enabled then safe(f.onEnable) end
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Main loop (~30 fps, on the game thread)

local lastErr = nil

-- One timer only. Keys used to be polled by a second, per-frame timer
-- (LoopInGameThreadAfterFrames); twice a Ctrl+R hot reload then hung the game
-- right after "All mods re-installed", most likely the reload racing a
-- callback that ran every frame. 33 ms is fast enough for key presses.
local function tick()
    Input.poll()
    UI.tick()
    Menu.tick(MENU_KEY)
    for _, f in ipairs(FEATURES) do
        if f.enabled and f.tick then f.tick() end
    end
end

U.gameLoop(33, function()
    local ok, err = pcall(tick)
    if not ok and tostring(err) ~= lastErr then
        lastErr = tostring(err)
        U.log("tick error: %s", lastErr)
    end
end)

U.gameDelay(3000, function()
    for _, f in ipairs(FEATURES) do
        if f.enabled then safe(f.onEnable) end
    end
end)

U.log("Loaded %d features (%s timers). Press %s for the mod menu.", #FEATURES,
    LoopInGameThreadWithDelay and "game-thread" or "async", MENU_KEY)

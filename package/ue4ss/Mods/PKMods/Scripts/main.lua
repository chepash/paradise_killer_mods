-- PKMods — all Paradise Killer mods in one UE4SS package.
--
--   F1          open / close the mod menu (number keys switch items)
--   Ctrl + J    Air Control on/off
--   Ctrl + B    Blood Crystal Radar on/off
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
    (require("features.crystal_radar")),
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
        hint = f.toggleKey and Input.label(f.toggleKey.key, f.toggleKey.ctrl) or nil,
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

for _, f in ipairs(FEATURES) do
    if f.toggleKey then
        Input.bind(f.toggleKey.key, f.toggleKey.ctrl, function() setEnabled(f, not f.enabled) end)
    end
    for _, hk in ipairs(f.hotkeys or {}) do
        Input.bind(hk.key, hk.ctrl, function()
            if f.enabled then hk.fn() end
        end)
        Menu.addHotkey(Input.label(hk.key, hk.ctrl), (hk.desc or "?") .. " (" .. f.name .. ")")
    end
end

local function diag()
    U.log("===== DIAGNOSTICS =====")
    local pc = U.getPC()
    U.log("PlayerController: %s", pc and pc:GetFullName() or "none")
    local pawn = U.getPawn()
    U.log("Pawn: %s", pawn and pawn:GetFullName() or "none")
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
Menu.addHotkey("Ctrl+R", "reload all mods (UE4SS)")

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

-- Keys are polled every frame when UE4SS supports frame timers, so short
-- presses aren't missed; otherwise together with the 33 ms tick.
local perFrameInput = LoopInGameThreadAfterFrames ~= nil
if perFrameInput then
    LoopInGameThreadAfterFrames(1, function() safe(Input.poll) end)
end

local function tick()
    if not perFrameInput then Input.poll() end
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

U.log("Loaded %d features (%s timers, keys polled %s). Press %s for the mod menu.", #FEATURES,
    LoopInGameThreadWithDelay and "game-thread" or "async",
    perFrameInput and "every frame" or "every 33 ms", MENU_KEY)

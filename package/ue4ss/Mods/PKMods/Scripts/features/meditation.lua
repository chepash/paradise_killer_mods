-- Meditation Markers: keeps the game's meditation hearts on until toggled off.
--
-- The game's meditation (hold Q): the screen darkens, then hearts
-- (BP_MeditationMarker, a pool of 500 actors) mark every place not visited /
-- activated yet within MeditationDistanceFromPlayer (300 m), and they hide again
-- after MeditationItemRevealTime (20 s). All of it lives in the player's native
-- MeditationComponent (pawn.Meditation); it has no UFunction to reveal markers,
-- the reveal happens when a meditation finishes (watched: RevealTimeRemaining
-- jumps to 20 and the markers' bHidden turns false; at 0 they hide).
--
-- While this feature is on (use: Ctrl+M once, then tap Q whenever hearts are wanted):
--   * RevealTime is practically infinite, so hearts from a meditation stay;
--     hearts already showing are extended right away;
--   * holding Q needs 0.15 s instead of 0.7 s, and the darkening timelines
--     (MeditationEffect, MeditationEffect_Finished) play 5x faster.
-- Setting the timer without a meditation (tried) only re-shows the previous
-- meditation's markers at their old places: choosing and placing markers
-- happens in native code at the end of a meditation, so Q is still needed.
-- Off: RevealTimeRemaining goes to almost 0 (the game hides the hearts) and the
-- original values come back. The darkening animation itself is the game's.
local U     = require("core.util")
local S     = require("core.settings")
local Radar = require("core.radar")

local F = {
    id        = "meditation",
    name      = "Meditation Markers",
    default   = false,
    toggleKey = { key = "M", ctrl = true },
    hint      = "Ctrl+M, then tap Q",
}

local FOREVER  = 1.0e7     -- seconds
local QUICK_Q  = 0.15      -- TimeButtonHoldRequiredForMeditation while on
local FAST     = 5.0       -- play rate of the darkening timelines while on
local TIMELINES = { "MeditationEffect", "MeditationEffect_Finished" }

local original = nil       -- { revealTime, hold }
local lastShown = nil

local function comp()
    local pawn = U.getPawn()
    if not pawn then return nil end
    local ok, m = pcall(function() return pawn.Meditation end)
    if ok and m and U.valid(m) then return m end
    return nil
end

local function num(m, prop)
    local ok, v = pcall(function() return m[prop] end)
    return (ok and type(v) == "number") and v or nil
end

local function apply(m)
    if not original then
        original = {
            revealTime = num(m, "MeditationItemRevealTime") or 20.0,
            hold = num(m, "TimeButtonHoldRequiredForMeditation") or 0.7,
        }
    end
    m.MeditationItemRevealTime = FOREVER
    m.TimeButtonHoldRequiredForMeditation = QUICK_Q
    -- Only extend hearts that are showing: setting the timer with nothing
    -- revealed shows the previous meditation's markers at their old places.
    local remaining = num(m, "MeditationItemRevealTimeRemaining") or 0
    if remaining > 0 and remaining < FOREVER / 2 then m.MeditationItemRevealTimeRemaining = FOREVER end
end

-- The darkening is two timelines on the pawn; their play rate speeds it up.
local function setPlayRate(rate)
    local pawn = U.getPawn()
    if not pawn then return end
    for _, name in ipairs(TIMELINES) do
        pcall(function()
            local t = pawn[name]
            if t and U.valid(t) then t:SetPlayRate(rate) end
        end)
    end
end

-- Whether the first pool marker is visible (cheap: one array element).
local function markersShown(m)
    local ok, shown = pcall(function()
        local first = nil
        m.MeditationMarkerActorPool:ForEach(function(_, e)
            first = e:get()
            return true
        end)
        return first ~= nil and first.bHidden == false
    end)
    return ok and shown
end

function F.onEnable()
    lastShown = nil
    local m = comp()
    if m then apply(m) end
    setPlayRate(FAST)
end

function F.onDisable()
    setPlayRate(1.0)
    local m = comp()
    if not m then return end
    if original then
        m.MeditationItemRevealTime = original.revealTime
        m.TimeButtonHoldRequiredForMeditation = original.hold
    end
    m.MeditationItemRevealTimeRemaining = 0.05
end

-- Re-apply (new pawn after a load, or the game resetting values) and log
-- whether markers show, to learn if a timer alone reveals them.
local lastCheck = -math.huge
function F.tick()
    if U.nowMs() - lastCheck < 500 then return end
    lastCheck = U.nowMs()
    local m = comp()
    if not m then return end
    -- Floats come back as float32 (0.15 -> 0.150000006): compare with a tolerance.
    local function off(prop, want) return math.abs((num(m, prop) or -1) - want) > 0.001 end
    local remaining = num(m, "MeditationItemRevealTimeRemaining") or 0
    if off("MeditationItemRevealTime", FOREVER) or off("TimeButtonHoldRequiredForMeditation", QUICK_Q)
        or (remaining > 0 and remaining < FOREVER / 2) then
        apply(m)
    end
    setPlayRate(FAST)  -- cheap; also covers a new pawn after a load
    local shown = markersShown(m)
    if shown ~= lastShown then
        U.log("Meditation: markers %s", shown and "shown" or "hidden")
        lastShown = shown
    end
end

function F.onRestart()
    lastShown = nil
end

-- Ctrl+F9: properties and UFunctions of the meditation pieces (research).
function F.diag()
    local m = comp()
    if not m then return end
    local path = string.format("%smeditation_%s.txt", S.dir(), os.date("%Y%m%d_%H%M%S"))
    local f = io.open(path, "w")
    if not f then return end
    local snap = Radar.snapshot(m, 5)
    local keys = {}
    for k in pairs(snap) do keys[#keys + 1] = k end
    table.sort(keys)
    f:write("== " .. m:GetFullName() .. "\n")
    for _, k in ipairs(keys) do f:write(string.format("  %s = %s\n", k, snap[k])) end
    f:close()
    U.log("Meditation: wrote %s", path)
end

return F

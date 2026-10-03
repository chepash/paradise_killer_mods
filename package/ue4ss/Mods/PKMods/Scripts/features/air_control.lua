-- Air Control: lets you steer while in the air (the game locks it by default).
-- Based on the original AirControlMod; raises CharacterMovement.AirControl.
local U = require("core.util")
local S = require("core.settings")

local F = {
    id        = "air_control",
    name      = "Air Control",
    default   = true,
    toggleKey = { key = "J", ctrl = true },
}

local STRENGTHS = { 0.35, 0.5, 0.75, 1.0 }  -- 0.35 = UE default, 1.0 = arcade
local REAPPLY_MS = 2000

local original = {}  -- movement component address -> values before we touched it
local lastApply = -math.huge

local function strength()
    return S.get("air_control.strength", 1.0)
end

local function moveComp()
    local pawn = U.getPawn()
    if not pawn then return nil end
    local mc = pawn.CharacterMovement
    if U.valid(mc) then return mc end
    mc = pawn.MovementComponent
    if U.valid(mc) then return mc end
    return nil
end

local function apply()
    lastApply = U.nowMs()
    local mc = moveComp()
    if not mc then return false end
    local addr = mc:GetAddress()
    if not original[addr] then
        original[addr] = {
            air  = mc.AirControl,
            mult = mc.AirControlBoostMultiplier,
            thr  = mc.AirControlBoostVelocityThreshold,
        }
    end
    if F.enabled then
        mc.AirControl = strength()
        mc.AirControlBoostMultiplier = 1.0
        mc.AirControlBoostVelocityThreshold = 0.0
    else
        local o = original[addr]
        mc.AirControl = o.air
        mc.AirControlBoostMultiplier = o.mult
        mc.AirControlBoostVelocityThreshold = o.thr
    end
    return true
end

function F.onEnable()  apply() end
function F.onDisable() apply() end

-- The game may reset movement values (respawn, cutscenes); re-apply periodically.
function F.tick()
    if U.nowMs() - lastApply > REAPPLY_MS then apply() end
end

function F.onRestart()
    lastApply = -math.huge
end

F.options = {
    {
        label = function() return string.format("Air Control strength: %.2f", strength()) end,
        activate = function()
            local cur, nextVal = strength(), STRENGTHS[1]
            for i, v in ipairs(STRENGTHS) do
                if math.abs(v - cur) < 0.001 then nextVal = STRENGTHS[i % #STRENGTHS + 1] end
            end
            S.set("air_control.strength", nextVal)
            if F.enabled then apply() end
        end,
    },
}

function F.diag()
    local mc = moveComp()
    if not mc then U.log("AirControl: no movement component"); return end
    U.log("AirControl: %s  AirControl=%s", mc:GetFullName(), tostring(mc.AirControl))
end

return F

-- Fly Mode: switches the player's CharacterMovement into Unreal's built-in
-- flying mode (no gravity). W/S fly where the camera looks (pitch included),
-- A/D strafe, Space goes up, Left Alt down. Collision stays on (no noclip).
-- Turning it off drops the player into the normal falling mode.
--
-- How: the game moves the pawn horizontally from native code (a hook on
-- Pawn:AddMovementInput only ever saw our own calls), so the vertical part is
-- added by us: AddMovementInput(Z) every frame while W/S/Space/Alt are held,
-- Z for W/S = tan(camera pitch), which together with the game's horizontal
-- input points along the view. Input added less often than every frame made
-- climbing very slow (braking kicked in on the frames in between), so a
-- per-frame timer runs while flying, and only then: per-frame callbacks are
-- suspected in the Ctrl+R hangs.
local U     = require("core.util")
local S     = require("core.settings")
local Input = require("core.input")

local F = {
    id        = "fly",
    name      = "Fly Mode",
    default   = false,
    toggleKey = { key = "F", ctrl = true },
    hint      = "Ctrl+F; Space up, Alt down",
}

local MOVE_FALLING, MOVE_FLYING = 3, 5   -- EMovementMode
local SPEEDS   = { 1000, 1500, 2000, 3000 }  -- MaxFlySpeed, cm/s
local DEFAULT_SPEED = 2000
local VERTICAL = 0.5                     -- Space / Alt climb at half the flying speed
local KEY_UP, KEY_DOWN = "SpaceBar", "LeftAlt"
local MAX_TAN  = 8                       -- caps the vertical share when looking straight up/down

local original = {}  -- movement component address -> values before flying
local frameLoop = nil
local flying = false

-- A saved speed that's no longer offered (e.g. the old 4000) falls back to the default.
local function speed()
    local v = S.get("fly.speed", DEFAULT_SPEED)
    for _, allowed in ipairs(SPEEDS) do
        if v == allowed then return v end
    end
    return DEFAULT_SPEED
end

local function moveComp()
    local pawn = U.getPawn()
    if not pawn then return nil, nil end
    local mc = pawn.CharacterMovement
    if U.valid(mc) then return mc, pawn end
    return nil, pawn
end

local function startFlying(mc)
    local addr = mc:GetAddress()
    if not original[addr] then
        original[addr] = {
            fly = mc.MaxFlySpeed, brake = mc.BrakingDecelerationFlying, accel = mc.MaxAcceleration,
        }
    end
    mc.MaxFlySpeed = speed()
    mc.MaxAcceleration = speed() * 4             -- full speed in ~0.25 s
    mc.BrakingDecelerationFlying = speed() * 2   -- stop quickly when keys are released
    mc:SetMovementMode(MOVE_FLYING, 0)
end

-- Every frame while flying: the vertical part of the movement.
local function frame()
    if not flying then return end
    local mc, pawn = moveComp()
    if not mc then return end
    local z = 0
    local w, s = Input.held("W"), Input.held("S")
    if w ~= s then
        local pc = U.getPC()
        local okR, rot = pcall(function() return pc:GetControlRotation() end)
        if okR and rot then
            local pitch = rot.Pitch
            if pitch > 180 then pitch = pitch - 360 end
            local t = math.tan(math.rad(pitch))
            t = math.max(-MAX_TAN, math.min(MAX_TAN, t))
            z = z + (w and t or -t)
        end
    end
    if Input.held(KEY_UP) then z = z + VERTICAL end
    if Input.held(KEY_DOWN) then z = z - VERTICAL end
    if z ~= 0 then
        pcall(function() pawn:AddMovementInput({ X = 0, Y = 0, Z = z }, 1.0, true) end)
    end
end

local function loopOn()
    if frameLoop ~= nil then return end
    if LoopInGameThreadAfterFrames then
        frameLoop = LoopInGameThreadAfterFrames(1, function()
            local ok, err = pcall(frame)
            if not ok then U.log("Fly: %s", tostring(err)) end
        end) or true
    else
        frameLoop = true  -- older UE4SS: F.tick (30 Hz) does it instead
    end
end

local function loopOff()
    if frameLoop ~= nil and frameLoop ~= true and CancelDelayedAction then
        pcall(CancelDelayedAction, frameLoop)
    end
    frameLoop = nil
end

function F.onEnable()
    flying = true
    local mc = moveComp()
    if mc then startFlying(mc) end
    loopOn()
end

function F.onDisable()
    flying = false
    loopOff()
    local mc = moveComp()
    if not mc then return end
    local o = original[mc:GetAddress()]
    if o then
        mc.MaxFlySpeed = o.fly
        mc.BrakingDecelerationFlying = o.brake
        mc.MaxAcceleration = o.accel
    end
    mc:SetMovementMode(MOVE_FALLING, 0)
end

-- The game's AR view (hold Ctrl) slows the player; that's left as the game
-- does it. On release the game restores its own movement values, which wiped
-- ours (flying stayed very slow), so for 2 s after Ctrl is released the fly
-- speed / acceleration are checked and re-applied. Otherwise only the
-- movement mode is checked.
local AFTER_CTRL_MS = 2000
local ctrlWasHeld, recheckUntil = false, -math.huge
local reportedReset = false

function F.tick()
    local mc = moveComp()
    if not mc then return end
    local ctrl = Input.held("LeftControl") or Input.held("RightControl")
    if ctrlWasHeld and not ctrl then recheckUntil = U.nowMs() + AFTER_CTRL_MS end
    ctrlWasHeld = ctrl

    local okM, mode = pcall(function() return mc.MovementMode end)
    if not (okM and mode == MOVE_FLYING) then
        startFlying(mc)
    elseif not ctrl and U.nowMs() < recheckUntil then
        local okF, fly = pcall(function() return mc.MaxFlySpeed end)
        local okA, accel = pcall(function() return mc.MaxAcceleration end)
        if (okF and math.abs(fly - speed()) > 1) or (okA and math.abs(accel - speed() * 4) > 1) then
            if not reportedReset then
                reportedReset = true
                U.log("Fly: after the AR view the game left MaxFlySpeed=%s, MaxAcceleration=%s; restoring",
                    tostring(fly), tostring(accel))
            end
            startFlying(mc)
        end
    end
    if not LoopInGameThreadAfterFrames then frame() end
end

F.options = {
    {
        label = function() return string.format("Fly speed: %d m/s", math.floor(speed() / 100)) end,
        activate = function()
            local cur, nextVal = speed(), SPEEDS[1]
            for i, v in ipairs(SPEEDS) do
                if v == cur then nextVal = SPEEDS[i % #SPEEDS + 1] end
            end
            S.set("fly.speed", nextVal)
            if F.enabled then
                local mc = moveComp()
                if mc then startFlying(mc) end
            end
        end,
    },
}

function F.diag()
    local mc = moveComp()
    if not mc then U.log("Fly: no movement component") return end
    U.log("Fly: MovementMode=%s MaxFlySpeed=%s MaxAcceleration=%s loop=%s", tostring(mc.MovementMode),
        tostring(mc.MaxFlySpeed), tostring(mc.MaxAcceleration), tostring(frameLoop))
end

return F

-- Hotkeys polled on the game thread.
--
-- UE4SS RegisterKeyBind callbacks run on a separate UE4SS thread. Pressing keys
-- quickly while our game-thread loop was running corrupted the Lua state
-- ("No overload found for FText" on a plain string, "Ref was not function")
-- and crashed the game. Polling PlayerController:IsInputKeyDown from the game
-- thread keeps all of PKMods' Lua on one thread.
--
-- Key names are Unreal FKey names: "F1", "J", "B", "F9", "One" .. "Nine", ...
local U = require("core.util")

local I = {}

local binds = {}   -- { key, ctrl, fn }
local names = {}   -- key -> FName (created once)
local prev  = {}   -- key -> was down at the previous poll

local function fname(k)
    local n = names[k]
    if not n then
        n = FName(k)
        names[k] = n
    end
    return n
end

local function isDown(pc, k)
    local ok, down = pcall(function() return pc:IsInputKeyDown({ KeyName = fname(k) }) end)
    return ok and down == true
end

-- Is the key held right now (for continuous actions, e.g. flying up/down).
function I.held(key)
    local pc = U.getPC()
    return pc ~= nil and isDown(pc, key)
end

-- fn runs on the press edge. ctrl = true requires Ctrl held, false/nil requires it released.
function I.bind(key, ctrl, fn)
    binds[#binds + 1] = { key = key, ctrl = ctrl and true or false, fn = fn }
end

-- Human-readable key combo for menus: ("J", true) -> "Ctrl+J".
local KEY_NAMES = { Equals = "=", Hyphen = "-", Add = "Num+", Subtract = "Num-", Zero = "0" }

function I.label(key, ctrl)
    return (ctrl and "Ctrl+" or "") .. (KEY_NAMES[key] or key)
end

function I.ctrlDown(pc)
    return isDown(pc, "LeftControl") or isDown(pc, "RightControl")
end

-- Call every frame (or as often as possible) from the game thread.
function I.poll()
    local pc = U.getPC()
    if not pc then return end
    local ctrl = I.ctrlDown(pc)
    local now = {}
    for _, b in ipairs(binds) do
        if now[b.key] == nil then now[b.key] = isDown(pc, b.key) end
    end
    for _, b in ipairs(binds) do
        if now[b.key] and not prev[b.key] and b.ctrl == ctrl then
            local ok, err = pcall(b.fn)
            if not ok then U.log("key %s: %s", b.key, tostring(err)) end
        end
    end
    prev = now
end

return I

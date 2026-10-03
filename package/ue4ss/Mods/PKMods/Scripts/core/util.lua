-- Small helpers shared by all PKMods modules.
local UEHelpers = require("UEHelpers")

local U = {}

-- UE4SS.log is recreated on every game start, so PKMods also appends its own
-- lines to pkmods.log in the mod folder (kept across sessions).
local logPath = nil

function U.setLogFile(path)
    logPath = path
end

function U.log(fmt, ...)
    local line = string.format(fmt, ...)
    print("[PKMods] " .. line .. "\n")
    if logPath then
        local f = io.open(logPath, "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] "), line, "\n")
            f:close()
        end
    end
end

function U.valid(o)
    return o ~= nil and o:IsValid()
end

-- Wall-clock milliseconds (os.clock is wall time on Windows).
function U.nowMs()
    return os.clock() * 1000
end

function U.className(o)
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

function U.cdo(path)
    local o = StaticFindObject(path)
    if U.valid(o) then return o end
    return nil
end

-- PlayerController lookup scans the whole object array, so failures are
-- retried at most once per second (main menu / loading screens).
local pcCache, pcRetryAt = nil, 0
function U.getPC()
    if U.valid(pcCache) then return pcCache end
    local t = U.nowMs()
    if t < pcRetryAt then return nil end
    pcRetryAt = t + 1000
    local ok, pc = pcall(UEHelpers.GetPlayerController)
    if ok and U.valid(pc) then
        pcCache = pc
        return pc
    end
    return nil
end

-- Game-thread timers. UE4SS 3.0.1 only had LoopAsync + ExecuteInGameThread,
-- which crashed the game (0xC0000264, lock released by the wrong thread) when
-- used ~30 times a second. Newer UE4SS runs timers on the game thread itself.
function U.gameLoop(ms, fn)
    if LoopInGameThreadWithDelay then
        LoopInGameThreadWithDelay(ms, fn)
        return
    end
    local busy = false
    LoopAsync(ms, function()
        if busy then return false end
        busy = true
        ExecuteInGameThread(function()
            fn()
            busy = false
        end)
        return false
    end)
end

function U.gameDelay(ms, fn)
    if ExecuteInGameThreadWithDelay then
        ExecuteInGameThreadWithDelay(ms, fn)
        return
    end
    ExecuteWithDelay(ms, function() ExecuteInGameThread(fn) end)
end

function U.getPawn()
    local pc = U.getPC()
    if not pc then return nil end
    local pawn = pc.Pawn
    if U.valid(pawn) then return pawn end
    return nil
end

return U

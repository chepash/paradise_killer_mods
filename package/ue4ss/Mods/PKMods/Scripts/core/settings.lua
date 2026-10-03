-- Persistent settings: Mods\PKMods\settings.txt, one "key = value" per line.
local S = {}

local values = {}
local path = nil
local dir = ""

-- Mod folder (ends with a separator); other files the mod writes go here too.
function S.dir() return dir end

local function parse(v)
    if v == "true" then return true end
    if v == "false" then return false end
    return tonumber(v) or v
end

function S.init(modDir)
    dir = modDir
    path = modDir .. "settings.txt"
    local f = io.open(path, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
        if k then values[k] = parse(v) end
    end
    f:close()
end

function S.save()
    if not path then return end
    local f = io.open(path, "w")
    if not f then return end
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        f:write(string.format("%s = %s\n", k, tostring(values[k])))
    end
    f:close()
end

function S.get(key, default)
    local v = values[key]
    if v == nil then return default end
    return v
end

function S.set(key, value)
    values[key] = value
    S.save()
end

return S

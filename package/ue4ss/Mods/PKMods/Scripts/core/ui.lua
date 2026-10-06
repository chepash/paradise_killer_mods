-- On-screen UI without a widget Blueprint of our own.
--
-- UUserWidget is abstract, so a mod can't create a fresh one from Lua. Instead
-- we attach our widgets to the root CanvasPanel of a game widget that is already
-- in the viewport (its root canvas is full screen). When that host disappears
-- (level change, HUD hidden) a new one is picked and every registered builder
-- runs again to recreate its widgets there.
local U = require("core.util")

local UI = {}

local PREFIX         = "PKM_"
local STRAY_PREFIXES = { "PKM_", "BCR_" }  -- BCR_ = old standalone radar
local PREFERRED      = { "YMKHUDBP_C", "HUD_TopCorner_C", "ARViewHud_BP_C" }
local CHECK_MS       = 1000

UI.generation = 0  -- bumped on every rebuild; widgets of older generations are gone

UI.VISIBLE   = 3  -- ESlateVisibility::HitTestInvisible
UI.COLLAPSED = 1

local host      = nil  -- { widget, canvas }
local lastCheck = -math.huge
local uid       = 0
local builders  = {}
local live      = {}   -- address -> true for widgets of the current build

-- Widget names must be unique across script reloads: constructing an object
-- with the name of an existing one in the same outer overwrites it in place,
-- which left frozen "ghost" markers on screen after Ctrl+R.
math.randomseed(os.time())
local RUN_TOKEN = string.format("%06x", math.random(0, 0xFFFFFF))

-- fn(host) is called every time a new host is attached.
function UI.onBuild(fn)
    builders[#builders + 1] = fn
    if host then
        local ok, err = pcall(fn, host)
        if not ok then U.log("ui build failed: %s", tostring(err)) end
    end
end

local function rootCanvas(w)
    local ok, canvas = pcall(function()
        if not w:IsInViewport() then return nil end
        local root = w.WidgetTree.RootWidget
        if U.valid(root) and U.className(root) == "CanvasPanel" then return root end
        return nil
    end)
    return ok and canvas or nil
end

-- Our widgets inherit the host's opacity, so a fully opaque host is preferred
-- (a notification popup that fades in and out made the menu see-through).
local OPAQUE = 0.99
local MIN_OPACITY = 0.5

local function opacity(w)
    local ok, v = pcall(function()
        if not w:IsVisible() then return 0 end
        return w:GetRenderOpacity()
    end)
    return ok and v or 0
end

-- Removes every PKMods widget in the game that isn't part of the current build
-- (left by an earlier host, an earlier build or a script reload). Searches by
-- name instead of walking the host's children, which didn't catch them.
local SWEEP_CLASSES = { "Image", "TextBlock", "Border" }

local function sweepOrphans()
    local removed = 0
    for _, cls in ipairs(SWEEP_CLASSES) do
        for _, w in ipairs(FindAllOf(cls) or {}) do
            if U.valid(w) and not live[w:GetAddress()] then
                local name = w:GetFName():ToString()
                for _, p in ipairs(STRAY_PREFIXES) do
                    if name:sub(1, #p) == p then
                        pcall(function()
                            w:SetVisibility(UI.COLLAPSED)
                            w:RemoveFromParent()
                        end)
                        removed = removed + 1
                        break
                    end
                end
            end
        end
    end
    if removed > 0 then U.log("UI: removed %d leftover widget(s)", removed) end
end

local function candidates()
    local list = {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if U.valid(w) then
            local canvas = rootCanvas(w)
            if canvas then list[#list + 1] = { widget = w, canvas = canvas, opacity = opacity(w) } end
        end
    end
    return list
end

-- Opaque hosts first (preferred classes, then any); otherwise the most opaque one.
local function pick(list)
    for _, cls in ipairs(PREFERRED) do
        for _, c in ipairs(list) do
            if c.opacity >= OPAQUE and U.className(c.widget) == cls then return c end
        end
    end
    local best = nil
    for _, c in ipairs(list) do
        if c.opacity >= MIN_OPACITY and (not best or c.opacity > best.opacity) then best = c end
    end
    return best
end

local function sameWidget(a, b)
    return a and b and a.widget:GetAddress() == b.widget:GetAddress()
end

-- Returns the current host, re-checking it at most once per CHECK_MS.
function UI.ensure()
    local t = U.nowMs()
    if t - lastCheck < CHECK_MS then return host end
    lastCheck = t
    if host and U.valid(host.widget) and rootCanvas(host.widget) and opacity(host.widget) >= OPAQUE then
        return host
    end

    local list = candidates()
    local new = pick(list)
    if not new then
        host = nil
        return nil
    end
    if sameWidget(new, host) then return host end

    host = new
    U.log("UI attached to %s (opacity %.2f)", U.className(host.widget), host.opacity)
    live = {}
    UI.generation = UI.generation + 1
    for _, fn in ipairs(builders) do
        local ok, err = pcall(fn, host)
        if not ok then U.log("ui build failed: %s", tostring(err)) end
    end
    sweepOrphans()
    return host
end

-- Forget the host (new level); the next ensure() picks a fresh one.
function UI.reset()
    host, lastCheck = nil, -math.huge
end

-- Creates a widget owned by the host's WidgetTree (not yet parented).
function UI.construct(classPath, short)
    uid = uid + 1
    local w = StaticConstructObject(U.findPermanent(classPath), host.widget.WidgetTree,
        FName(string.format("%s%s_%s_%d", PREFIX, short, RUN_TOKEN, uid)))
    live[w:GetAddress()] = true
    return w
end

-- Creates a widget and puts it on the host canvas. Returns widget, slot.
function UI.add(classPath, short, zOrder)
    local w = UI.construct(classPath, short)
    local slot = host.canvas:AddChildToCanvas(w)
    slot:SetZOrder(zOrder or 10000)
    w:SetVisibility(UI.COLLAPSED)
    return w, slot
end

function UI.setVisible(w, on)
    if U.valid(w) then w:SetVisibility(on and UI.VISIBLE or UI.COLLAPSED) end
end

function UI.styleText(tb, size, color)
    pcall(function()
        local font = tb.Font
        font.Size = size
        tb:SetFont(font)
    end)
    pcall(function()
        tb:SetShadowOffset({ X = 1.5, Y = 1.5 })
        tb:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 })
    end)
    if color then UI.setColor(tb, color) end
end

function UI.setText(tb, text)
    tb:SetText(FText(tostring(text)))
end

function UI.setColor(tb, color)
    tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
end

-- Viewport size in widget (DPI-scaled) units.
function UI.viewport(pc)
    local wl = U.cdo("/Script/UMG.Default__WidgetLayoutLibrary")
    if not wl then return nil end
    local vp, scale = wl:GetViewportSize(pc), wl:GetViewportScale(pc)
    if scale <= 0 then scale = 1 end
    return vp.X / scale, vp.Y / scale
end

-- ---------------------------------------------------------------------------
-- Toast: short message at the top of the screen.

local toast = { tb = nil, slot = nil, text = nil, color = nil, untilMs = 0 }

UI.onBuild(function()
    toast.tb, toast.slot = UI.add("/Script/UMG.TextBlock", "Toast", 30000)
    toast.slot:SetAutoSize(true)
    toast.slot:SetAlignment({ X = 0.5, Y = 0.0 })
    UI.styleText(toast.tb, 22)
    toast.shownText = nil
end)

function UI.toast(text, color, seconds)
    U.log("%s", text)
    toast.text = text
    toast.color = color or { R = 1, G = 1, B = 1, A = 1 }
    toast.untilMs = U.nowMs() + (seconds or 2) * 1000
    toast.shownText = nil
end

function UI.tick()
    if not toast.text then return end
    if U.nowMs() > toast.untilMs then
        toast.text = nil
        UI.setVisible(toast.tb, false)
        return
    end
    if not UI.ensure() or not U.valid(toast.tb) then return end
    if toast.shownText ~= toast.text then
        local pc = U.getPC()
        local W = pc and UI.viewport(pc) or 1920
        UI.setText(toast.tb, toast.text)
        UI.setColor(toast.tb, toast.color)
        toast.slot:SetPosition({ X = W / 2, Y = 90 })
        toast.shownText = toast.text
    end
    UI.setVisible(toast.tb, true)
end

return UI

-- In-game mod menu: a panel listing numbered items; the number key activates one.
local U  = require("core.util")
local UI = require("core.ui")

local M = {}

M.open = false
local items = {}        -- { label = fn() -> string, activate = fn(), indent = bool, hint = string? }
local hotkeys = {}      -- { keys = "Ctrl+F9", text = "diagnostics" }: listed at the bottom
local panel = {}        -- border, slot, text
local shownText = nil

local MAX_ITEMS = 9

-- item.label() returns the current text, item.activate() runs on key press,
-- item.hint (e.g. "Ctrl+J") is shown next to the label.
function M.add(item)
    if #items >= MAX_ITEMS then
        U.log("menu full, item ignored")
        return
    end
    items[#items + 1] = item
end

-- Hotkeys that work without the menu, listed at its bottom so they're not forgotten.
function M.addHotkey(keys, text)
    hotkeys[#hotkeys + 1] = { keys = keys, text = text }
end

UI.onBuild(function(host)
    panel.border = UI.construct("/Script/UMG.Border", "MenuBg")
    panel.border:SetBrushColor({ R = 0.06, G = 0.07, B = 0.12, A = 0.92 })
    panel.border:SetPadding({ Left = 24, Top = 18, Right = 28, Bottom = 18 })
    panel.text = UI.construct("/Script/UMG.TextBlock", "MenuText")
    -- No explicit color: SetColorAndOpacity turned this text black once; the
    -- TextBlock default (white) is what was readable in-game.
    UI.styleText(panel.text, 20)
    pcall(function()
        local c = panel.text.ColorAndOpacity.SpecifiedColor
        U.log("menu text color: R=%.2f G=%.2f B=%.2f A=%.2f", c.R, c.G, c.B, c.A)
    end)
    panel.border:SetContent(panel.text)
    panel.slot = host.canvas:AddChildToCanvas(panel.border)
    panel.slot:SetZOrder(20000)
    panel.slot:SetAutoSize(true)
    panel.slot:SetPosition({ X = 40, Y = 240 })  -- below the area-name banner
    UI.setVisible(panel.border, false)
    shownText = nil
end)

local function render(keyName)
    local lines = { string.format("PK MODS                        [%s] close", keyName), "" }
    for i, it in ipairs(items) do
        local ok, label = pcall(it.label)
        if not ok then label = "?" end
        local hint = it.hint and ("      " .. it.hint) or ""
        lines[#lines + 1] = string.format("%d   %s%s%s", i, it.indent and "      " or "", label, hint)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "press a number to switch"
    if #hotkeys > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "HOTKEYS"
        for _, h in ipairs(hotkeys) do
            lines[#lines + 1] = string.format("%-12s %s", h.keys, h.text)
        end
    end
    return table.concat(lines, "\n")
end

function M.toggle()
    M.open = not M.open
end

function M.press(n)
    if not M.open then return end
    local it = items[n]
    if it then it.activate() end
end

function M.tick(keyName)
    if not M.open then
        if U.valid(panel.border) then UI.setVisible(panel.border, false) end
        return
    end
    if not UI.ensure() or not U.valid(panel.text) then return end
    local text = render(keyName)
    if text ~= shownText then
        UI.setText(panel.text, text)
        shownText = text
    end
    UI.setVisible(panel.border, true)
end

return M

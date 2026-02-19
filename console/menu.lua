----------------------------------------------------------------
-- console/menu.lua
-- Nested menu stack (DOS/Win92 style) for Pause / Tools / Settings
----------------------------------------------------------------
local menu = {}

local stack = {}
local sel = 1

local gfx, theme

function menu.init(console)
    gfx   = console.gfx
    theme = console.theme or require("console.theme")
end

function menu.push(m)
    stack[#stack + 1] = m
    sel = 1
end

function menu.pop()
    if #stack > 0 then
        stack[#stack] = nil
        sel = 1
    end
end

function menu.top()
    return stack[#stack]
end

function menu.isOpen()
    return #stack > 0
end

function menu.closeAll()
    while #stack > 0 do stack[#stack] = nil end
    sel = 1
end

-- Navigate to a valid item (skip headers)
local function ensureValid(m)
    local items = m and m.items or {}
    local n = #items
    if n == 0 then return end
    while items[sel] and items[sel].type == "header" do
        sel = sel + 1
        if sel > n then sel = 1 end
    end
    if sel < 1 then sel = 1 end
    if sel > n then sel = n end
end

-- Returns: "resume", "quit", "reset", "settings", or nil (still open)
function menu.update(input)
    local m = menu.top()
    if not m then return nil end

    local items = m.items or {}
    local n = #items
    if n == 0 then return nil end

    ensureValid(m)

    -- ESC / B: back or close
    if input.justPressed.B or input.justPressed.START then
        if #stack > 1 then
            menu.pop()
            return nil
        end
        -- Root menu: START/B = resume
        return "resume"
    end

    -- Navigate
    if input.justPressed.UP then
        repeat
            sel = sel - 1
            if sel < 1 then sel = n end
        until items[sel].type ~= "header"
        return nil
    end
    if input.justPressed.DOWN then
        repeat
            sel = sel + 1
            if sel > n then sel = 1 end
        until items[sel].type ~= "header"
        return nil
    end

    -- A: select
    if input.justPressed.A then
        local it = items[sel]
        if it.type == "action" and it.onSelect then
            it.onSelect()
            return it.result  -- optional: "resume", "quit", "reset", "settings"
        elseif it.type == "submenu" and it.submenu then
            menu.push(it.submenu)
            return nil
        elseif it.type == "toggle" and it.get and it.set then
            it.set(not it.get())
            return nil
        end
    end

    return nil
end

function menu.draw()
    local m = menu.top()
    if not m then return end

    local items = m.items or {}
    ensureValid(m)

    local pw, ph = 180, 120
    local px = math.floor((gfx.VIRT_W - pw) / 2)
    local py = math.floor((gfx.VIRT_H - ph) / 2)

    local bx, by, bw, bh = theme.window(gfx, px, py, pw, ph, m.title or "MENU")

    local btnH = 14
    for i, it in ipairs(items) do
        local ry = by + (i - 1) * (btnH + 2)
        local selected = (i == sel)
        if it.type == "header" then
            gfx.print(it.label, bx + 4, ry + 2, theme.C.disabled)
        else
            if selected then
                gfx.rect(bx, ry, bw, btnH, theme.C.highlight)
            end
            local textCol = selected and theme.C.highText or theme.C.winText
            local label = it.label
            if it.type == "toggle" and it.get and it.get() then
                label = label .. "  [ON]"
            elseif it.type == "toggle" and it.get and not it.get() then
                label = label .. "  [OFF]"
            end
            gfx.print(label, bx + 4, ry + 2, textCol)
        end
    end

    gfx.print("ESC/B:BACK  A:SELECT", px + 4, py + ph - 12, theme.C.disabled)
end

return menu

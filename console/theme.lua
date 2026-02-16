----------------------------------------------------------------
-- console/theme.lua
-- Windows 3.1 / "Program Manager" style drawing helpers
-- Uses ONLY the gfx module palette + primitives
----------------------------------------------------------------
local theme = {}

-- Win3.1 color mapping to our CGA/EGA palette
theme.C = {
    desktop   = 1,   -- dark blue desktop background
    titlebar  = 1,   -- dark blue title bar
    titleText = 15,  -- white title text
    winBg     = 7,   -- light gray window body
    winText   = 0,   -- black text
    highlight = 9,   -- blue (selected item bg)
    highText  = 15,  -- white (selected item text)
    bevelLt   = 15,  -- white bevel highlight (top-left)
    bevelDk   = 8,   -- dark gray bevel shadow (bottom-right)
    bevelBlk  = 0,   -- black outermost edge
    btnFace   = 7,   -- light gray button face
    btnText   = 0,   -- black button text
    disabled  = 8,   -- dark gray disabled text
    taskbar   = 7,   -- light gray taskbar background
    taskText  = 0,   -- black taskbar text
    progress  = 1,   -- dark blue progress bar fill
    listBg    = 15,  -- white list background
    scrollBg  = 7,   -- scrollbar background
}

----------------------------------------------------------------
-- Beveled rectangle (Win3.1 raised / sunken)
--   raised: top-left = white, bottom-right = dark
--   sunken: top-left = dark, bottom-right = white
----------------------------------------------------------------
function theme.bevelRect(gfx, x, y, w, h, raised)
    local lt = raised and theme.C.bevelLt or theme.C.bevelDk
    local dk = raised and theme.C.bevelDk or theme.C.bevelLt

    -- fill
    gfx.rect(x, y, w, h, theme.C.winBg)

    -- outer black border
    gfx.rectLine(x, y, w, h, theme.C.bevelBlk)

    -- inner bevel: top + left highlight
    gfx.line(x + 1, y + 1, x + w - 2, y + 1, lt)     -- top
    gfx.line(x + 1, y + 1, x + 1,     y + h - 2, lt)  -- left

    -- inner bevel: bottom + right shadow
    gfx.line(x + 1,     y + h - 2, x + w - 2, y + h - 2, dk)  -- bottom
    gfx.line(x + w - 2, y + 1,     x + w - 2, y + h - 2, dk)  -- right
end

----------------------------------------------------------------
-- Window frame with title bar
--   returns body area {bx, by, bw, bh} for content layout
----------------------------------------------------------------
function theme.window(gfx, x, y, w, h, title)
    local TITLE_H = 12

    -- outer raised bevel
    theme.bevelRect(gfx, x, y, w, h, true)

    -- title bar (dark blue filled)
    gfx.rect(x + 2, y + 2, w - 4, TITLE_H, theme.C.titlebar)

    -- title text (centered)
    local tw = gfx.textWidth(title or "")
    local tx = x + math.floor((w - tw) / 2)
    gfx.print(title or "", tx, y + 4, theme.C.titleText)

    -- body area
    local bx = x + 3
    local by = y + 2 + TITLE_H + 1
    local bw = w - 6
    local bh = h - TITLE_H - 6
    return bx, by, bw, bh
end

----------------------------------------------------------------
-- Button (raised bevel with centered text)
--   pressed = true draws sunken style
----------------------------------------------------------------
function theme.button(gfx, x, y, w, h, label, pressed)
    theme.bevelRect(gfx, x, y, w, h, not pressed)
    local tw = gfx.textWidth(label)
    local tx = x + math.floor((w - tw) / 2)
    local ty = y + math.floor((h - gfx.CHAR_H) / 2)
    if pressed then tx = tx + 1; ty = ty + 1 end
    gfx.print(label, tx, ty, theme.C.btnText)
end

----------------------------------------------------------------
-- Listbox (sunken bevel, items, optional selected index)
--   returns nothing; items = { {text=, ...}, ... }
----------------------------------------------------------------
function theme.listbox(gfx, x, y, w, h, items, selected, itemH)
    itemH = itemH or 12

    -- sunken frame
    theme.bevelRect(gfx, x, y, w, h, false)

    -- white interior
    gfx.rect(x + 2, y + 2, w - 4, h - 4, theme.C.listBg)

    -- items
    local maxVisible = math.floor((h - 4) / itemH)
    for i = 1, math.min(#items, maxVisible) do
        local iy = y + 2 + (i - 1) * itemH
        local sel = (i == selected)
        if sel then
            gfx.rect(x + 2, iy, w - 4, itemH, theme.C.highlight)
        end
        local text = items[i].text or items[i].title or tostring(items[i])
        gfx.print(text, x + 5, iy + 2, sel and theme.C.highText or theme.C.winText)
        if items[i].sub then
            gfx.print(items[i].sub, x + 5, iy + 2 + (itemH > 10 and 8 or 0), sel and theme.C.highText or theme.C.disabled)
        end
    end
end

----------------------------------------------------------------
-- Taskbar (bottom strip, raised bevel)
----------------------------------------------------------------
function theme.taskbar(gfx, y, w, h, leftText, rightText)
    theme.bevelRect(gfx, 0, y, w, h, true)
    if leftText then
        gfx.print(leftText, 4, y + math.floor((h - gfx.CHAR_H) / 2), theme.C.taskText)
    end
    if rightText then
        local rw = gfx.textWidth(rightText)
        gfx.print(rightText, w - rw - 4, y + math.floor((h - gfx.CHAR_H) / 2), theme.C.taskText)
    end
end

----------------------------------------------------------------
-- Progress bar (sunken bevel + filled portion)
--   frac = 0..1
----------------------------------------------------------------
function theme.progressBar(gfx, x, y, w, h, frac)
    -- sunken frame
    theme.bevelRect(gfx, x, y, w, h, false)
    -- fill
    local inner = math.floor((w - 4) * math.max(0, math.min(1, frac)))
    if inner > 0 then
        gfx.rect(x + 2, y + 2, inner, h - 4, theme.C.progress)
    end
end

----------------------------------------------------------------
-- Desktop background (tiled blue pattern)
----------------------------------------------------------------
function theme.desktop(gfx, w, h)
    gfx.rect(0, 0, w, h, theme.C.desktop)
    -- subtle dither pattern (every other 2px)
    for py = 0, h - 1, 4 do
        for px = 0, w - 1, 4 do
            gfx.pixel(px, py, 9)
        end
    end
end

----------------------------------------------------------------
-- Procedural mouse cursor (11x16ish arrow)
-- Returns an ImageData-based image, built once
----------------------------------------------------------------
local cursorImage
function theme.getCursor()
    if cursorImage then return cursorImage end

    -- 11x16 cursor bitmap: 1=white, 2=black, 0=transparent
    local ROWS = {
        {2},
        {2,2},
        {2,1,2},
        {2,1,1,2},
        {2,1,1,1,2},
        {2,1,1,1,1,2},
        {2,1,1,1,1,1,2},
        {2,1,1,1,1,1,1,2},
        {2,1,1,1,1,1,1,1,2},
        {2,1,1,1,1,1,1,1,1,2},
        {2,1,1,1,1,1,2,2,2,2},
        {2,1,1,2,1,1,2},
        {2,1,2,0,2,1,1,2},
        {2,2,0,0,2,1,1,2},
        {2,0,0,0,0,2,1,1,2},
        {0,0,0,0,0,2,2,2},
    }
    local cw, ch = 10, #ROWS
    local id = love.image.newImageData(cw, ch)
    for r = 1, #ROWS do
        for c = 1, #ROWS[r] do
            local v = ROWS[r][c]
            if v == 1 then
                id:setPixel(c - 1, r - 1, 1, 1, 1, 1)
            elseif v == 2 then
                id:setPixel(c - 1, r - 1, 0, 0, 0, 1)
            end
        end
    end
    cursorImage = love.graphics.newImage(id)
    cursorImage:setFilter("nearest", "nearest")
    return cursorImage
end

return theme

----------------------------------------------------------------
-- tools/map_editor.lua
-- Map editor tool — top-down grid editor for collision, materials,
-- enemy spawns, save/load.
-- Follows the standard tool interface (open/close/isOpen/update/draw/input/keypressed).
-- Requires ctx.mapAPI to be set by the host cart before opening.
----------------------------------------------------------------
local tool = {}
tool.id    = "map_editor"
tool.title = "Map Editor"

local gfx, sfx

-- Layout (matches raycast cart viewport)
local VIRT_W, VIRT_H = 320, 200
local VP_X, VP_Y = 0, 0
local VP_W, VP_H = 216, 152
local RPANEL_X   = VP_W + 2
local RPANEL_Y   = 0
local RPANEL_W   = VIRT_W - RPANEL_X
local RPANEL_H   = VP_H
local MSG_X, MSG_Y = 0, VP_H + 2
local MSG_W, MSG_H = VIRT_W, VIRT_H - VP_H - 2

-- Tile type constants (must match cart)
local TILE_EMPTY  = 0
local TILE_WALL   = 1
local TILE_DOOR   = 2
local TILE_STAIRS = 3
local TILE_START  = 4

local TILE_NAMES = {
    [TILE_EMPTY]  = "EMPTY",
    [TILE_WALL]   = "WALL",
    [TILE_DOOR]   = "DOOR",
    [TILE_STAIRS] = "STAIRS",
    [TILE_START]  = "START",
}

local TILE_COLORS = {
    [TILE_EMPTY]  = 0,
    [TILE_WALL]   = 7,
    [TILE_DOOR]   = 9,
    [TILE_STAIRS] = 14,
    [TILE_START]  = 10,
}

local BRUSH_ORDER = { TILE_WALL, TILE_EMPTY, TILE_DOOR, TILE_STAIRS, TILE_START }

local EDIT_MODE_NAMES = { "COLLISION", "WALL MAT", "FLOOR MAT", "CEIL MAT", "ENEMIES" }
local EDIT_MODE_CATS  = { nil, "walls", "floor", "ceil", nil }

local math_floor = math.floor
local math_min   = math.min
local math_max   = math.max
local math_abs   = math.abs

local function clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

-- Help text
local EDIT_HELP_LINES = {
    "=== EDIT MODE CONTROLS ===",
    "",
    "ARROWS/DPAD Move cursor",
    "A ......... Paint (brush/material)",
    "B ......... Cycle brush / palette fwd",
    "X / R ..... Erase / reset to default",
    "S ......... Save map to file",
    "L ......... Load map from file",
    "P ......... Test play from start",
    "T ......... Open tracker editor",
    "F1/SELECT . Toggle play/edit mode",
    "H / Y ..... Toggle this help",
    "",
    "=== PAINT MODES ===",
    "",
    "1-5 / L1 .. Cycle paint mode",
    "  1: Collision  2: Wall material",
    "  3: Floor mat  4: Ceiling/roof",
    "  5: Enemy spawns",
    "Q/E ....... Select texture in palette",
    "X / R ..... Reset (ceil: set to sky)",
    "",
    "=== BRUSH TYPES (mode 1) ===",
    "",
    "WALL ...... Solid wall (gray)",
    "EMPTY ..... Open space (black)",
    "DOOR ...... Door tile (blue)",
    "STAIRS .... Level exit (yellow)",
    "START ..... Player spawn (green)",
}

----------------------------------------------------------------
-- Per-session state (stored in ctx.tools.map_editor)
----------------------------------------------------------------
local function getState(ctx)
    return ctx.tools.map_editor
end

local function ensureState(ctx)
    if not ctx.tools.map_editor then
        ctx.tools.map_editor = {
            active = false,
            editMode = 1,
            cursorX = 1,
            cursorY = 1,
            brushType = TILE_WALL,
            paletteSel = 1,
            paletteScroll = 0,
            showHelp = false,
            helpScroll = 0,
            msgLog = {},
        }
    end
    return ctx.tools.map_editor
end

local function addLog(st, text)
    st.msgLog[#st.msgLog + 1] = text
    -- Also forward to cart's addLog if available
    if st.api and st.api.addLog then st.api.addLog(text) end
end

----------------------------------------------------------------
-- PALETTE HELPERS
----------------------------------------------------------------
local function getPaletteList(st)
    local cat = EDIT_MODE_CATS[st.editMode]
    if not cat then return nil end
    local api = st.api
    return api.texCatalog[cat]
end

local function getSelectedMatKey(st)
    if st.editMode == 4 and st.paletteSel == 0 then
        return nil  -- open sky
    end
    local list = getPaletteList(st)
    if not list or #list == 0 then return "default" end
    local idx = clamp(st.paletteSel, 1, #list)
    return list[idx].key
end

local function paletteNext(st)
    local list = getPaletteList(st)
    if not list or #list == 0 then return end
    local minSel = (st.editMode == 4) and 0 or 1
    st.paletteSel = st.paletteSel + 1
    if st.paletteSel > #list then st.paletteSel = minSel end
    local label = (st.paletteSel == 0) and "OPEN SKY" or list[st.paletteSel].key:sub(1, 12)
    addLog(st, "SEL: " .. label)
    if sfx then sfx.play("ui_move") end
end

local function palettePrev(st)
    local list = getPaletteList(st)
    if not list or #list == 0 then return end
    local minSel = (st.editMode == 4) and 0 or 1
    st.paletteSel = st.paletteSel - 1
    if st.paletteSel < minSel then st.paletteSel = #list end
    local label = (st.paletteSel == 0) and "OPEN SKY" or list[st.paletteSel].key:sub(1, 12)
    addLog(st, "SEL: " .. label)
    if sfx then sfx.play("ui_move") end
end

----------------------------------------------------------------
-- DRAWING
----------------------------------------------------------------
local function drawBevel(x, y, w, h)
    gfx.rect(x, y, w, h, 7)
    gfx.line(x, y, x + w - 1, y, 15)
    gfx.line(x, y, x, y + h - 1, 15)
    gfx.line(x + w - 1, y, x + w - 1, y + h - 1, 8)
    gfx.line(x, y + h - 1, x + w - 1, y + h - 1, 8)
end

local function drawMessageBox(st)
    gfx.rect(MSG_X, MSG_Y, MSG_W, MSG_H, 0)
    gfx.rectLine(MSG_X, MSG_Y, MSG_W, MSG_H, 8)
    local tx = MSG_X + 3
    local ty = MSG_Y + 3
    local maxLines = math_floor((MSG_H - 6) / 8)
    local start = math_max(1, #st.msgLog - maxLines + 1)
    for i = start, #st.msgLog do
        gfx.print(st.msgLog[i], tx, ty, 7)
        ty = ty + 8
    end
end

local function drawEditGrid(st)
    local api = st.api
    local mapW, mapH = api.mapW, api.mapH

    local gridArea_W = VP_W
    local gridArea_H = VP_H
    local cellW = math_floor(gridArea_W / mapW)
    local cellH = math_floor(gridArea_H / mapH)
    local cellSize = math_min(cellW, cellH)
    if cellSize < 2 then cellSize = 2 end

    local totalW = cellSize * mapW
    local totalH = cellSize * mapH
    local ox = VP_X + math_floor((gridArea_W - totalW) / 2)
    local oy = VP_Y + math_floor((gridArea_H - totalH) / 2)

    gfx.rect(VP_X, VP_Y, VP_W, VP_H, 0)

    for y = 1, mapH do
        for x = 1, mapW do
            local tile = api.getTile(x, y)
            local col = TILE_COLORS[tile] or 0
            local px = ox + (x - 1) * cellSize
            local py = oy + (y - 1) * cellSize
            gfx.rect(px, py, cellSize, cellSize, col)

            local swatchColor = nil
            if st.editMode == 2 then
                if tile == TILE_WALL then
                    local key = api.getWallMat(x, y)
                    if key then
                        local entry = api.resolveTexEntry("walls", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    end
                end
            elseif st.editMode == 3 then
                if tile == TILE_EMPTY or tile == TILE_DOOR or tile == TILE_START then
                    local key = api.getFloorMat(x, y)
                    if key then
                        local entry = api.resolveTexEntry("floor", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    end
                end
            elseif st.editMode == 4 then
                if tile ~= TILE_WALL then
                    local key = api.getCeilMat(x, y)
                    if key then
                        local entry = api.resolveTexEntry("ceil", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    else
                        if cellSize >= 4 then
                            gfx.setColorRGBA(0.15, 0.15, 0.55, 1)
                            local cSz = math_max(2, math_floor(cellSize / 3))
                            love.graphics.rectangle("fill", px, py, cSz, cSz)
                        end
                    end
                end
            end

            if swatchColor then
                gfx.setColorRGBA(swatchColor[1], swatchColor[2], swatchColor[3], 0.70)
                love.graphics.rectangle("fill", px + 1, py + 1, cellSize - 2, cellSize - 2)
            end

            gfx.setColor(8)
            love.graphics.rectangle("line", px, py, cellSize, cellSize)
        end
    end

    -- Enemy spawn markers
    local enemySpawns = api.enemySpawns
    for _, s in ipairs(enemySpawns) do
        local esx = ox + (s.x - 1) * cellSize
        local esy = oy + (s.y - 1) * cellSize
        if cellSize >= 6 then
            gfx.setColor(4)
            love.graphics.rectangle("fill", esx + 1, esy + 1, cellSize - 2, cellSize - 2)
            gfx.print("E", esx + 1, esy, 12)
        else
            gfx.setColor(12)
            love.graphics.rectangle("fill", esx, esy, cellSize, cellSize)
        end
    end

    -- Player start marker
    local psx = ox + (api.playerStartX - 1) * cellSize
    local psy = oy + (api.playerStartY - 1) * cellSize
    if cellSize >= 6 then
        gfx.print("P", psx + 1, psy, 15)
    else
        gfx.setColor(15)
        love.graphics.rectangle("fill", psx + 1, psy + 1, cellSize - 2, cellSize - 2)
    end

    -- Cursor highlight
    local cx = ox + (st.cursorX - 1) * cellSize
    local cy = oy + (st.cursorY - 1) * cellSize
    gfx.setColor(12)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", cx, cy, cellSize, cellSize)
    love.graphics.rectangle("line", cx + 1, cy + 1, cellSize - 2, cellSize - 2)

    gfx.rectLine(VP_X, VP_Y, VP_W, VP_H, 8)
end

local function drawEditPanel(st)
    local api = st.api
    drawBevel(RPANEL_X, RPANEL_Y, RPANEL_W, RPANEL_H)
    local sx = RPANEL_X + 3
    local sy = RPANEL_Y + 3
    local pw = RPANEL_W - 6

    gfx.print(EDIT_MODE_NAMES[st.editMode] or "?", sx, sy, 0)
    sy = sy + 10
    for i = 1, 5 do
        local col = (i == st.editMode) and 15 or 8
        gfx.print(tostring(i), sx + (i - 1) * 12, sy, col)
    end
    sy = sy + 10
    gfx.print("CUR:" .. st.cursorX .. "," .. st.cursorY, sx, sy, 7)
    sy = sy + 10

    if st.editMode == 1 then
        local curTile = api.getTile(st.cursorX, st.cursorY)
        gfx.print("TILE:" .. (TILE_NAMES[curTile] or "?"), sx, sy, 7)
        sy = sy + 10
        gfx.print("BRUSH:", sx, sy, 15)
        sy = sy + 9
        local brushCol = TILE_COLORS[st.brushType] or 0
        gfx.rect(sx, sy, 6, 6, brushCol)
        gfx.rectLine(sx, sy, 6, 6, 15)
        gfx.print(TILE_NAMES[st.brushType] or "?", sx + 9, sy, 14)
        sy = sy + 10
        for _, tileType in ipairs(BRUSH_ORDER) do
            local col = TILE_COLORS[tileType]
            gfx.rect(sx, sy, 6, 6, col)
            gfx.rectLine(sx, sy, 6, 6, 8)
            gfx.print(TILE_NAMES[tileType], sx + 9, sy, 7)
            sy = sy + 8
        end
    elseif st.editMode == 5 then
        local enemySpawns = api.enemySpawns
        gfx.print("SPAWNS:" .. #enemySpawns, sx, sy, 12)
        sy = sy + 10
        local onSpawn = false
        for _, s in ipairs(enemySpawns) do
            if s.x == st.cursorX and s.y == st.cursorY then onSpawn = true; break end
        end
        gfx.print(onSpawn and "HAS SPAWN" or "NO SPAWN", sx, sy, onSpawn and 12 or 8)
        sy = sy + 10
        gfx.print("A:PLACE", sx, sy, 7)
        sy = sy + 8
        gfx.print("X:REMOVE", sx, sy, 7)
    else
        local list = getPaletteList(st)
        if list and #list > 0 then
            local curKey = "default"
            if st.editMode == 2 then curKey = api.getWallMat(st.cursorX, st.cursorY) or "default"
            elseif st.editMode == 3 then curKey = api.getFloorMat(st.cursorX, st.cursorY) or "default"
            elseif st.editMode == 4 then curKey = api.getCeilMat(st.cursorX, st.cursorY)
            end
            local curLabel = curKey and curKey:sub(1, 12) or "OPEN SKY"
            gfx.print("CUR:" .. curLabel, sx, sy, 7)
            sy = sy + 10
            gfx.print("Q/E:SELECT", sx, sy, 8)
            sy = sy + 10

            local maxVisible = math_floor((RPANEL_H - sy + RPANEL_Y - 20) / 10)
            local scroll = st.paletteScroll or 0

            if st.editMode == 4 then
                local isSel = (st.paletteSel == 0)
                if isSel then gfx.rect(sx - 1, sy, pw + 2, 9, 1) end
                gfx.setColorRGBA(0.05, 0.05, 0.15, 1)
                love.graphics.rectangle("fill", sx, sy + 1, 7, 7)
                gfx.rectLine(sx, sy + 1, 7, 7, 9)
                gfx.print("OPEN SKY", sx + 9, sy, isSel and 14 or 7)
                sy = sy + 10
                maxVisible = maxVisible - 1
            end

            for vi = 1, maxVisible do
                local idx = scroll + vi
                if idx > #list then break end
                local entry = list[idx]
                local isSel = (idx == st.paletteSel)
                if isSel then gfx.rect(sx - 1, sy, pw + 2, 9, 1) end
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setScissor(sx, sy + 1, 7, 7)
                love.graphics.draw(entry.img, sx, sy + 1, 0, 7 / entry.w, 7 / entry.h)
                love.graphics.setScissor()
                local nameCol = isSel and 14 or 7
                gfx.print(entry.key:sub(1, 10), sx + 9, sy, nameCol)
                sy = sy + 10
            end
        else
            if st.editMode == 4 then
                local isSel = (st.paletteSel == 0)
                if isSel then gfx.rect(sx - 1, sy, pw + 2, 9, 1) end
                gfx.setColorRGBA(0.05, 0.05, 0.15, 1)
                love.graphics.rectangle("fill", sx, sy + 1, 7, 7)
                gfx.rectLine(sx, sy + 1, 7, 7, 9)
                gfx.print("OPEN SKY", sx + 9, sy, 14)
                sy = sy + 10
            else
                gfx.print("NO TEXTURES", sx, sy, 12)
            end
        end
    end

    gfx.print("H/Y:HELP", sx, RPANEL_Y + RPANEL_H - 10, 14)
end

local function drawHelpOverlay(st)
    local lines = EDIT_HELP_LINES
    gfx.setColorRGBA(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)
    local pw, ph = 220, 160
    local px = math_floor((VIRT_W - pw) / 2)
    local py = math_floor((VIRT_H - ph) / 2)
    gfx.rect(px, py, pw, ph, 0)
    gfx.rectLine(px, py, pw, ph, 7)
    gfx.setColor(15)
    love.graphics.line(px + 1, py + 1, px + pw - 2, py + 1)
    love.graphics.line(px + 1, py + 1, px + 1, py + ph - 2)
    gfx.setColor(8)
    love.graphics.line(px + pw - 2, py + 1, px + pw - 2, py + ph - 2)
    love.graphics.line(px + 1, py + ph - 2, px + pw - 2, py + ph - 2)
    gfx.rect(px + 2, py + 2, pw - 4, 10, 1)
    gfx.print("HELP", px + 4, py + 3, 15)
    gfx.print("[H] CLOSE", px + pw - 60, py + 3, 14)
    local contentY = py + 14
    local contentH = ph - 28
    local maxLines = math_floor(contentH / 8)
    local scroll = st.helpScroll or 0
    local totalLines = #lines
    for i = 1, maxLines do
        local lineIdx = scroll + i
        if lineIdx > totalLines then break end
        local line = lines[lineIdx]
        local col = 7
        if line:sub(1, 3) == "===" then col = 14 end
        gfx.print(line, px + 6, contentY + (i - 1) * 8, col)
    end
    if totalLines > maxLines then
        local barX = px + pw - 6
        local barY = contentY
        local barH = contentH
        local thumbH = math_max(4, math_floor(barH * maxLines / totalLines))
        local thumbY = barY + math_floor((barH - thumbH) * scroll / math_max(1, totalLines - maxLines))
        gfx.rect(barX, barY, 3, barH, 0)
        gfx.rect(barX, thumbY, 3, thumbH, 8)
    end
end

----------------------------------------------------------------
-- EDIT ACTIONS
----------------------------------------------------------------
local function eraseAtCursor(st)
    local api = st.api
    if st.editMode == 1 then
        api.setTile(st.cursorX, st.cursorY, TILE_EMPTY)
        addLog(st, "CLEARED @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 2 then
        api.setWallMat(st.cursorX, st.cursorY, "default")
        addLog(st, "WALL RESET @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 3 then
        api.setFloorMat(st.cursorX, st.cursorY, "default")
        addLog(st, "FLOOR RESET @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 4 then
        api.setCeilMat(st.cursorX, st.cursorY, nil)
        addLog(st, "CEIL->SKY @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 5 then
        local enemySpawns = api.enemySpawns
        for i = #enemySpawns, 1, -1 do
            if enemySpawns[i].x == st.cursorX and enemySpawns[i].y == st.cursorY then
                table.remove(enemySpawns, i)
                addLog(st, "SPAWN REMOVED @" .. st.cursorX .. "," .. st.cursorY)
            end
        end
    end
    if sfx then sfx.play("paint") end
end

local function cycleEditSubmode(st)
    st.editMode = st.editMode + 1
    if st.editMode > 5 then st.editMode = 1 end
    st.paletteSel = (st.editMode == 4) and 0 or 1
    st.paletteScroll = 0
    addLog(st, "MODE: " .. EDIT_MODE_NAMES[st.editMode])
    if sfx then sfx.play("ui_move") end
end

local function paintAtCursor(st)
    local api = st.api
    local mapW, mapH = api.mapW, api.mapH
    if st.editMode == 1 then
        if st.brushType == TILE_START then
            for y = 1, mapH do
                for x = 1, mapW do
                    if api.getTile(x, y) == TILE_START then
                        api.setTile(x, y, TILE_EMPTY)
                    end
                end
            end
            api.playerStartX = st.cursorX
            api.playerStartY = st.cursorY
        end
        api.setTile(st.cursorX, st.cursorY, st.brushType)
        addLog(st, "PLACED " .. (TILE_NAMES[st.brushType] or "?") .. " @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 2 then
        local key = getSelectedMatKey(st)
        api.setWallMat(st.cursorX, st.cursorY, key)
        addLog(st, "WALL:" .. key:sub(1, 10) .. " @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 3 then
        local key = getSelectedMatKey(st)
        api.setFloorMat(st.cursorX, st.cursorY, key)
        addLog(st, "FLOOR:" .. key:sub(1, 10) .. " @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 4 then
        local key = getSelectedMatKey(st)
        api.setCeilMat(st.cursorX, st.cursorY, key)
        local label = key and key:sub(1, 10) or "OPEN SKY"
        addLog(st, "CEIL:" .. label .. " @" .. st.cursorX .. "," .. st.cursorY)
    elseif st.editMode == 5 then
        local enemySpawns = api.enemySpawns
        local exists = false
        for _, s in ipairs(enemySpawns) do
            if s.x == st.cursorX and s.y == st.cursorY then exists = true; break end
        end
        if not exists then
            enemySpawns[#enemySpawns + 1] = { x = st.cursorX, y = st.cursorY }
            addLog(st, "ENEMY SPAWN @" .. st.cursorX .. "," .. st.cursorY)
        else
            addLog(st, "SPAWN EXISTS HERE")
        end
    end
    if sfx then sfx.play("paint") end
end

----------------------------------------------------------------
-- STANDARD TOOL INTERFACE
----------------------------------------------------------------
function tool.open(ctx, console)
    gfx = console.gfx
    sfx = console.sfx
    local st = ensureState(ctx)
    st.active = true
    local api = ctx.mapAPI
    st.api = api
    -- Set cursor to player position
    st.cursorX = clamp(math_floor(api.playerX or 1), 1, api.mapW)
    st.cursorY = clamp(math_floor(api.playerY or 1), 1, api.mapH)
    st.editMode = 1
    st.brushType = TILE_WALL
    st.paletteSel = 1
    st.paletteScroll = 0
    st.showHelp = false
    st.helpScroll = 0
    addLog(st, "MAP EDITOR OPENED")
end

function tool.close(ctx, console)
    local st = getState(ctx)
    if not st then return end
    st.active = false
    addLog(st, "MAP EDITOR CLOSED")
    -- Notify cart to return to play mode
    if st.api and st.api.onEditorClose then
        st.api.onEditorClose()
    end
end

function tool.isOpen(ctx)
    local st = ctx and ctx.tools and ctx.tools.map_editor
    return st and st.active or false
end

function tool.update(dt, ctx, console)
    -- No continuous update needed
end

function tool.draw(ctx, console)
    local st = getState(ctx)
    if not st or not st.active then return end
    gfx = console.gfx
    drawEditGrid(st)
    drawEditPanel(st)
    drawMessageBox(st)
    if st.showHelp then
        drawHelpOverlay(st)
    end
end

function tool.input(action, pressed, ctx, console)
    if not pressed then return false end
    local st = getState(ctx)
    if not st or not st.active then return false end
    local api = st.api

    -- Help overlay consumes all input except Y to close
    if st.showHelp then
        if action == "Y" then
            st.showHelp = false
            st.helpScroll = 0
        end
        return true
    end

    if action == "UP" then
        st.cursorY = math_max(1, st.cursorY - 1); return true
    elseif action == "DOWN" then
        st.cursorY = math_min(api.mapH, st.cursorY + 1); return true
    elseif action == "LEFT" then
        st.cursorX = math_max(1, st.cursorX - 1); return true
    elseif action == "RIGHT" then
        st.cursorX = math_min(api.mapW, st.cursorX + 1); return true
    elseif action == "A" then
        paintAtCursor(st); return true
    elseif action == "B" then
        if st.editMode == 1 then
            local idx = 1
            for i, bt in ipairs(BRUSH_ORDER) do
                if bt == st.brushType then idx = i; break end
            end
            idx = idx + 1
            if idx > #BRUSH_ORDER then idx = 1 end
            st.brushType = BRUSH_ORDER[idx]
            addLog(st, "BRUSH: " .. (TILE_NAMES[st.brushType] or "?"))
            if sfx then sfx.play("ui_move") end
        else
            paletteNext(st)
        end
        return true
    elseif action == "X" then
        eraseAtCursor(st); return true
    elseif action == "Y" then
        st.showHelp = not st.showHelp
        st.helpScroll = 0
        return true
    elseif action == "L1" then
        cycleEditSubmode(st); return true
    end
    return false
end

function tool.keypressed(key, ctx, console)
    local st = getState(ctx)
    if not st or not st.active then return false end
    local api = st.api

    if key == "h" then
        st.showHelp = not st.showHelp
        st.helpScroll = 0
        return true
    end

    if st.showHelp then
        local maxScroll = math_max(0, #EDIT_HELP_LINES - math_floor(132 / 8))
        if key == "up" then
            st.helpScroll = math_max(0, st.helpScroll - 1)
        elseif key == "down" then
            st.helpScroll = math_min(maxScroll, st.helpScroll + 1)
        elseif key == "pageup" then
            st.helpScroll = math_max(0, st.helpScroll - 8)
        elseif key == "pagedown" then
            st.helpScroll = math_min(maxScroll, st.helpScroll + 8)
        end
        return true
    end

    -- Number keys: switch edit submode
    if key == "1" then st.editMode = 1; st.paletteSel = 1; st.paletteScroll = 0; addLog(st, "MODE: COLLISION"); return true
    elseif key == "2" then st.editMode = 2; st.paletteSel = 1; st.paletteScroll = 0; addLog(st, "MODE: WALL MAT"); return true
    elseif key == "3" then st.editMode = 3; st.paletteSel = 1; st.paletteScroll = 0; addLog(st, "MODE: FLOOR MAT"); return true
    elseif key == "4" then st.editMode = 4; st.paletteSel = 0; st.paletteScroll = 0; addLog(st, "MODE: CEIL MAT"); return true
    elseif key == "5" then st.editMode = 5; st.paletteSel = 1; st.paletteScroll = 0; addLog(st, "MODE: ENEMIES"); return true
    end

    -- Palette navigation
    if st.editMode >= 2 then
        if key == "q" then palettePrev(st); return true
        elseif key == "e" then paletteNext(st); return true
        end
    end

    if key == "r" then
        eraseAtCursor(st); return true
    elseif key == "s" then
        if api.saveMap then api.saveMap() end
        if sfx then sfx.play("save") end
        return true
    elseif key == "l" then
        if api.loadMap then
            if api.loadMap() then
                addLog(st, "MAP LOADED!")
                if sfx then sfx.play("load") end
            else
                addLog(st, "NO SAVED MAP")
                if sfx then sfx.play("bump") end
            end
        end
        return true
    elseif key == "p" then
        -- Test play: close editor, return to play
        tool.close(ctx, console)
        addLog(st, "TEST PLAY")
        return true
    elseif key == "t" then
        -- Open tracker (via registry if available)
        if api.openTracker then api.openTracker() end
        return true
    end

    return false
end

return tool

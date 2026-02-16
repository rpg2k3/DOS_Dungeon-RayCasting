-- ============================================================================
-- RAYCAST DUNGEON — True raycasting 3D renderer (Wolfenstein-style)
-- ============================================================================
local cart = {
    title       = "RAYCAST DUNGEON",
    author      = "SYSTEM",
    description = "Classic raycasting 3D with textured walls, floor & ceiling.",
    id          = "raycast_dungeon",
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local VIRT_W, VIRT_H = 320, 200

-- Layout regions
local VP_X, VP_Y = 0, 0
local VP_W, VP_H = 216, 152
local RPANEL_X   = VP_W + 2
local RPANEL_Y   = 0
local RPANEL_W   = VIRT_W - RPANEL_X
local RPANEL_H   = VP_H
local MSG_X, MSG_Y = 0, VP_H + 2
local MSG_W, MSG_H = VIRT_W, VIRT_H - VP_H - 2

-- Raycaster
local FOV       = math.pi / 3   -- 60 degrees
local HALF_FOV  = FOV / 2
local MAX_DIST  = 20

-- Movement
local MOVE_SPEED = 3.0
local ROT_SPEED  = 2.5

-- Tile types
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

-- Palette colors per tile type (for editor grid)
local TILE_COLORS = {
    [TILE_EMPTY]  = 0,   -- black
    [TILE_WALL]   = 7,   -- light gray
    [TILE_DOOR]   = 9,   -- blue
    [TILE_STAIRS] = 14,  -- yellow
    [TILE_START]  = 10,  -- green
}

local BRUSH_ORDER = { TILE_WALL, TILE_EMPTY, TILE_DOOR, TILE_STAIRS, TILE_START }

-- ============================================================================
-- STATE
-- ============================================================================
local gfx, assets, sfx, input
local texWall, texFloor, texCeil
local texWallW, texWallH, texFloorW, texFloorH, texCeilW, texCeilH
local map, mapW, mapH
local player      -- { x, y, angle }
local msgLog
local quadMesh    -- reusable mesh for textured wall slices

-- Floor/ceiling rendering via ImageData
local floorCeilImageData
local floorCeilImage

-- Pre-created quads for wall texture columns (one per texel column)
local wallQuads

-- Per-column depth buffer for minimap fog (optional)
local zBuffer

-- Texture data cache (ImageData for floor/ceil pixel sampling)
local floorTexData, ceilTexData

-- Edit mode state
local mode          -- "play" or "edit"
local cursorX, cursorY
local brushType
local playerStartX, playerStartY

-- ============================================================================
-- HELPERS
-- ============================================================================
local math_floor = math.floor
local math_cos   = math.cos
local math_sin   = math.sin
local math_abs   = math.abs
local math_max   = math.max
local math_min   = math.min

local function clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

local function addLog(text)
    table.insert(msgLog, text)
    while #msgLog > 6 do table.remove(msgLog, 1) end
end

-- ============================================================================
-- FALLBACK TEXTURE
-- ============================================================================
local function buildFallbackTexture(w, h, c1, c2)
    w, h = w or 16, h or 16
    c1 = c1 or {0.45, 0.30, 0.20, 1}
    c2 = c2 or {0.35, 0.22, 0.14, 1}
    local data = love.image.newImageData(w, h)
    for py = 0, h - 1 do
        for px = 0, w - 1 do
            local c = ((math_floor(px / 4) + math_floor(py / 4)) % 2 == 0) and c1 or c2
            data:setPixel(px, py, c[1], c[2], c[3], c[4])
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    img:setWrap("repeat", "repeat")
    return img
end

-- ============================================================================
-- MESH QUAD HELPER (for wall slices)
-- ============================================================================
local function initQuadMesh()
    local verts = {
        {0,0, 0,0, 1,1,1,1},
        {1,0, 1,0, 1,1,1,1},
        {1,1, 1,1, 1,1,1,1},
        {0,1, 0,1, 1,1,1,1},
    }
    quadMesh = love.graphics.newMesh(
        {{"VertexPosition","float",2}, {"VertexTexCoord","float",2}, {"VertexColor","float",4}},
        verts, "fan", "dynamic"
    )
end

-- ============================================================================
-- MAP DATA
-- ============================================================================
local DEFAULT_MAP = {
    width  = 16,
    height = 16,
    tiles  = {
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,1,1,0,0,1,
        1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1,
        1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1,
        1,1,1,0,1,1,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,1,0,1,1,1,
        1,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,1,1,0,1,1,1,0,0,0,1,1,1,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    },
}

local function getTile(mx, my)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return 1 end
    return map[(my - 1) * mapW + mx]
end

local function setTile(mx, my, val)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return end
    map[(my - 1) * mapW + mx] = val
end

local function isWall(mx, my)
    return getTile(mx, my) == TILE_WALL
end

-- ============================================================================
-- SAVE / LOAD MAP
-- ============================================================================
local function serializeMap()
    local lines = {}
    lines[#lines + 1] = "return {"
    lines[#lines + 1] = "  width = " .. mapW .. ","
    lines[#lines + 1] = "  height = " .. mapH .. ","
    lines[#lines + 1] = "  playerStart = {x = " .. playerStartX .. ", y = " .. playerStartY .. "},"
    lines[#lines + 1] = "  grid = {"
    for y = 1, mapH do
        local row = {}
        for x = 1, mapW do
            row[#row + 1] = tostring(getTile(x, y))
        end
        lines[#lines + 1] = "    " .. table.concat(row, ",") .. ","
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function saveMap()
    love.filesystem.createDirectory("dungeons")
    local content = serializeMap()
    local ok, err = love.filesystem.write("dungeons/main.lua", content)
    if ok then
        addLog("MAP SAVED!")
    else
        addLog("SAVE FAILED: " .. tostring(err))
    end
end

local function loadMapFromFile()
    local info = love.filesystem.getInfo("dungeons/main.lua")
    if not info then return false end
    local content = love.filesystem.read("dungeons/main.lua")
    if not content then return false end
    local fn, err = load(content)
    if not fn then
        addLog("LOAD ERR: " .. tostring(err))
        return false
    end
    local ok, result = pcall(fn)
    if not ok or type(result) ~= "table" then
        addLog("LOAD ERR: BAD DATA")
        return false
    end
    if not result.width or not result.height or not result.grid then
        addLog("LOAD ERR: MISSING FIELDS")
        return false
    end
    mapW = result.width
    mapH = result.height
    map = {}
    for i, v in ipairs(result.grid) do
        map[i] = v
    end
    if result.playerStart then
        playerStartX = result.playerStart.x or 2
        playerStartY = result.playerStart.y or 2
    end
    -- Find START tile if present (overrides playerStart)
    for y = 1, mapH do
        for x = 1, mapW do
            if getTile(x, y) == TILE_START then
                playerStartX = x
                playerStartY = y
            end
        end
    end
    return true
end

local function loadMapDefault()
    mapW = DEFAULT_MAP.width
    mapH = DEFAULT_MAP.height
    map = {}
    for i, v in ipairs(DEFAULT_MAP.tiles) do
        map[i] = v
    end
    playerStartX = 2
    playerStartY = 2
end

local function applyPlayerStart()
    player.x = playerStartX + 0.5
    player.y = playerStartY + 0.5
    player.angle = 0
end

-- ============================================================================
-- DDA RAYCASTING
-- ============================================================================
-- Returns: dist, wallX (0-1 fractional hit pos), side (0=vertical, 1=horizontal)
local function castRay(ox, oy, angle)
    local dirX = math_cos(angle)
    local dirY = math_sin(angle)

    -- Which map cell we're in
    local mapX = math_floor(ox)
    local mapY = math_floor(oy)

    -- Length of ray from one x/y-side to next x/y-side
    local deltaDistX = (dirX == 0) and 1e30 or math_abs(1 / dirX)
    local deltaDistY = (dirY == 0) and 1e30 or math_abs(1 / dirY)

    local stepX, stepY
    local sideDistX, sideDistY

    if dirX < 0 then
        stepX = -1
        sideDistX = (ox - mapX) * deltaDistX
    else
        stepX = 1
        sideDistX = (mapX + 1 - ox) * deltaDistX
    end
    if dirY < 0 then
        stepY = -1
        sideDistY = (oy - mapY) * deltaDistY
    else
        stepY = 1
        sideDistY = (mapY + 1 - oy) * deltaDistY
    end

    -- DDA
    local side = 0
    local dist = 0
    for _ = 1, 64 do
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
            side = 0
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
            side = 1
        end

        -- Map uses 1-based indices
        if isWall(mapX + 1, mapY + 1) then
            -- Perpendicular distance (avoids fisheye)
            if side == 0 then
                dist = (mapX - ox + (1 - stepX) / 2) / dirX
            else
                dist = (mapY - oy + (1 - stepY) / 2) / dirY
            end
            if dist < 0 then dist = 0.001 end

            -- Exact wallX (fractional hit position along wall face)
            local wallX
            if side == 0 then
                wallX = oy + dist * dirY
            else
                wallX = ox + dist * dirX
            end
            wallX = wallX - math_floor(wallX)

            return dist, wallX, side
        end

        -- Max distance check
        if side == 0 then
            dist = sideDistX
        else
            dist = sideDistY
        end
        if dist > MAX_DIST then
            return MAX_DIST, 0, 0
        end
    end

    return MAX_DIST, 0, 0
end

-- ============================================================================
-- FLOOR + CEILING RENDERING (ImageData per frame, samples cached texture data)
-- ============================================================================
local function renderFloorCeiling()
    local halfH = VP_H / 2
    local posX = player.x - 1
    local posY = player.y - 1
    local angle = player.angle

    local dirX = math_cos(angle)
    local dirY = math_sin(angle)

    local planeScale = math.tan(HALF_FOV)
    local planeX = -dirY * planeScale
    local planeY =  dirX * planeScale

    local imgData = floorCeilImageData
    local tw = texFloorW
    local th = texFloorH
    local cw = texCeilW
    local ch = texCeilH

    local fData = floorTexData
    local cData = ceilTexData

    for y = 0, VP_H - 1 do
        local isFloor = y > halfH
        local p = isFloor and (y - halfH) or (halfH - y)
        if p <= 0 then p = 0.5 end

        local rowDist = halfH / p

        local floorStepX = rowDist * 2 * planeX / VP_W
        local floorStepY = rowDist * 2 * planeY / VP_W

        local floorX = posX + rowDist * (dirX - planeX)
        local floorY = posY + rowDist * (dirY - planeY)

        local shade = clamp(1.0 - rowDist * 0.06, 0.08, 1.0)

        for x = 0, VP_W - 1 do
            if isFloor then
                local tx = math_floor(floorX * tw) % tw
                local ty = math_floor(floorY * th) % th
                if tx < 0 then tx = tx + tw end
                if ty < 0 then ty = ty + th end
                local r, g, b = fData:getPixel(tx, ty)
                imgData:setPixel(x, y, r * shade, g * shade, b * shade, 1)
            else
                local ctx = math_floor(floorX * cw) % cw
                local cty = math_floor(floorY * ch) % ch
                if ctx < 0 then ctx = ctx + cw end
                if cty < 0 then cty = cty + ch end
                local r, g, b = cData:getPixel(ctx, cty)
                imgData:setPixel(x, y, r * shade * 0.85, g * shade * 0.85, b * shade * 0.9, 1)
            end

            floorX = floorX + floorStepX
            floorY = floorY + floorStepY
        end
    end
end

-- ============================================================================
-- WALL COLUMN RENDERING
-- ============================================================================
local function renderWalls()
    local posX = player.x - 1  -- 0-based for DDA
    local posY = player.y - 1
    local angle = player.angle
    local halfH = VP_H / 2

    love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)

    for x = 0, VP_W - 1 do
        -- Ray angle for this column
        local cameraX = 2 * x / VP_W - 1  -- -1 to +1
        local rayAngle = angle + math.atan(cameraX * math.tan(HALF_FOV))

        local dist, wallX, side = castRay(posX, posY, rayAngle)

        -- Correct fisheye with cos of angle difference
        local corrDist = dist * math_cos(rayAngle - angle)
        if corrDist < 0.001 then corrDist = 0.001 end

        zBuffer[x] = corrDist

        -- Wall slice height
        local lineH = VP_H / corrDist
        local drawStart = halfH - lineH / 2
        local drawEnd   = halfH + lineH / 2

        -- Texture X coordinate
        local texX = math_floor(wallX * texWallW)
        if texX >= texWallW then texX = texWallW - 1 end
        if texX < 0 then texX = 0 end

        -- Shade by distance + side darkening
        local shade = clamp(1.0 - corrDist * 0.06, 0.08, 1.0)
        if side == 1 then shade = shade * 0.7 end

        -- Draw wall column using mesh quad
        local u0 = texX / texWallW
        local u1 = (texX + 1) / texWallW
        quadMesh:setVertices({
            {VP_X + x,     VP_Y + drawStart, u0, 0, shade, shade, shade, 1},
            {VP_X + x + 1, VP_Y + drawStart, u1, 0, shade, shade, shade, 1},
            {VP_X + x + 1, VP_Y + drawEnd,   u1, 1, shade, shade, shade, 1},
            {VP_X + x,     VP_Y + drawEnd,   u0, 1, shade, shade, shade, 1},
        })
        quadMesh:setTexture(texWall)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(quadMesh)
    end

    love.graphics.setScissor()
end

-- ============================================================================
-- VIEWPORT RENDERING
-- ============================================================================
local function drawViewport()
    -- 1. Render floor & ceiling into ImageData
    renderFloorCeiling()
    floorCeilImage:replacePixels(floorCeilImageData)

    -- 2. Draw floor/ceiling image
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(floorCeilImage, VP_X, VP_Y)

    -- 3. Draw walls on top
    renderWalls()
end

-- ============================================================================
-- MINIMAP
-- ============================================================================
local function drawMinimap()
    local mx, my = RPANEL_X + 2, RPANEL_Y + 2
    local mw, mh = RPANEL_W - 4, 80
    local cellSize = 5
    local viewRadius = 7

    -- Panel background
    gfx.rect(mx, my, mw, mh, 0)
    gfx.rectLine(mx, my, mw, mh, 8)

    for dy = -viewRadius, viewRadius do
        for dx = -viewRadius, viewRadius do
            local wx = math_floor(player.x) + dx
            local wy = math_floor(player.y) + dy
            local px = mx + math_floor(mw / 2) + dx * cellSize - math_floor(cellSize / 2)
            local py = my + math_floor(mh / 2) + dy * cellSize - math_floor(cellSize / 2)

            if px >= mx and py >= my and px + cellSize <= mx + mw and py + cellSize <= my + mh then
                if wx >= 1 and wy >= 1 and wx <= mapW and wy <= mapH then
                    local tile = getTile(wx, wy)
                    local col = TILE_COLORS[tile] or 0
                    gfx.rect(px, py, cellSize, cellSize, col)
                end
            end
        end
    end

    -- Player marker: dot + direction line
    local pcx = mx + math_floor(mw / 2)
    local pcy = my + math_floor(mh / 2)

    -- Direction line
    local lineLen = 6
    local tipX = pcx + math_cos(player.angle) * lineLen
    local tipY = pcy + math_sin(player.angle) * lineLen
    gfx.setColor(14) -- yellow
    love.graphics.setLineWidth(1)
    love.graphics.line(pcx, pcy, tipX, tipY)

    -- Player dot
    gfx.setColor(12) -- red
    love.graphics.rectangle("fill", pcx - 1, pcy - 1, 3, 3)
end

-- ============================================================================
-- STATS PANEL
-- ============================================================================
local function drawStats()
    local sx = RPANEL_X + 2
    local sy = RPANEL_Y + 86

    gfx.print("X:" .. string.format("%.1f", player.x), sx, sy, 7)
    gfx.print("Y:" .. string.format("%.1f", player.y), sx, sy + 10, 7)
    local deg = math_floor(math.deg(player.angle) % 360)
    gfx.print("ANG:" .. deg, sx, sy + 20, 7)
end

-- ============================================================================
-- MESSAGE BOX
-- ============================================================================
local function drawMessageBox()
    gfx.rect(MSG_X, MSG_Y, MSG_W, MSG_H, 0)
    gfx.rectLine(MSG_X, MSG_Y, MSG_W, MSG_H, 8)

    local tx = MSG_X + 3
    local ty = MSG_Y + 3
    local maxLines = math_floor((MSG_H - 6) / 8)
    local start = math_max(1, #msgLog - maxLines + 1)
    for i = start, #msgLog do
        gfx.print(msgLog[i], tx, ty, 7)
        ty = ty + 8
    end
end

-- ============================================================================
-- BEVEL HELPER
-- ============================================================================
local function drawBevel(x, y, w, h)
    gfx.rect(x, y, w, h, 7)
    gfx.line(x, y, x + w - 1, y, 15)
    gfx.line(x, y, x, y + h - 1, 15)
    gfx.line(x + w - 1, y, x + w - 1, y + h - 1, 8)
    gfx.line(x, y + h - 1, x + w - 1, y + h - 1, 8)
end

local function loadTextureData(img)
    -- Convert a love.graphics.Image to ImageData for pixel sampling
    local w, h = img:getWidth(), img:getHeight()
    local canvas = love.graphics.newCanvas(w, h)
    local prevCanvas = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace")
    love.graphics.draw(img, 0, 0)
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas(prevCanvas)
    local data = canvas:newImageData()
    return data
end

-- ============================================================================
-- EDIT MODE DRAWING
-- ============================================================================
local function drawEditGrid()
    -- Fill viewport area with top-down grid
    local gridArea_W = VP_W
    local gridArea_H = VP_H

    -- Calculate cell size to fit the map in the viewport
    local cellW = math_floor(gridArea_W / mapW)
    local cellH = math_floor(gridArea_H / mapH)
    local cellSize = math_min(cellW, cellH)
    if cellSize < 2 then cellSize = 2 end

    -- Center the grid in viewport
    local totalW = cellSize * mapW
    local totalH = cellSize * mapH
    local ox = VP_X + math_floor((gridArea_W - totalW) / 2)
    local oy = VP_Y + math_floor((gridArea_H - totalH) / 2)

    -- Background
    gfx.rect(VP_X, VP_Y, VP_W, VP_H, 0)

    -- Draw each cell
    for y = 1, mapH do
        for x = 1, mapW do
            local tile = getTile(x, y)
            local col = TILE_COLORS[tile] or 0
            local px = ox + (x - 1) * cellSize
            local py = oy + (y - 1) * cellSize
            gfx.rect(px, py, cellSize, cellSize, col)

            -- Draw grid lines (dark gray border between cells)
            gfx.setColor(8)
            love.graphics.rectangle("line", px, py, cellSize, cellSize)
        end
    end

    -- Draw player start marker (always visible, even if tile is overwritten)
    local psx = ox + (playerStartX - 1) * cellSize
    local psy = oy + (playerStartY - 1) * cellSize
    -- Small "P" marker
    if cellSize >= 6 then
        gfx.print("P", psx + 1, psy, 15)
    else
        gfx.setColor(15)
        love.graphics.rectangle("fill", psx + 1, psy + 1, cellSize - 2, cellSize - 2)
    end

    -- Draw cursor highlight (red border)
    local cx = ox + (cursorX - 1) * cellSize
    local cy = oy + (cursorY - 1) * cellSize
    gfx.setColor(12) -- red
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", cx, cy, cellSize, cellSize)
    love.graphics.rectangle("line", cx + 1, cy + 1, cellSize - 2, cellSize - 2)

    -- Viewport border
    gfx.rectLine(VP_X, VP_Y, VP_W, VP_H, 8)
end

local function drawEditPanel()
    drawBevel(RPANEL_X, RPANEL_Y, RPANEL_W, RPANEL_H)

    local sx = RPANEL_X + 3
    local sy = RPANEL_Y + 3

    -- Title
    gfx.print("EDIT MODE", sx, sy, 0)
    sy = sy + 12

    -- Cursor position
    gfx.print("CUR:" .. cursorX .. "," .. cursorY, sx, sy, 7)
    sy = sy + 10

    -- Current tile under cursor
    local curTile = getTile(cursorX, cursorY)
    gfx.print("TILE:" .. (TILE_NAMES[curTile] or "?"), sx, sy, 7)
    sy = sy + 14

    -- Brush
    gfx.print("BRUSH:", sx, sy, 15)
    sy = sy + 10
    local brushCol = TILE_COLORS[brushType] or 0
    gfx.rect(sx, sy, 8, 8, brushCol)
    gfx.rectLine(sx, sy, 8, 8, 15)
    gfx.print(TILE_NAMES[brushType] or "?", sx + 11, sy, 14)
    sy = sy + 14

    -- Legend
    gfx.print("LEGEND:", sx, sy, 15)
    sy = sy + 10
    for _, tileType in ipairs(BRUSH_ORDER) do
        local col = TILE_COLORS[tileType]
        gfx.rect(sx, sy, 6, 6, col)
        gfx.rectLine(sx, sy, 6, 6, 8)
        gfx.print(TILE_NAMES[tileType], sx + 9, sy, 7)
        sy = sy + 9
    end

    sy = sy + 4

    -- Controls help
    gfx.print("A:PAINT", sx, sy, 8)
    sy = sy + 9
    gfx.print("B:BRUSH", sx, sy, 8)
    sy = sy + 9
    gfx.print("F1:PLAY", sx, sy, 8)
end

-- ============================================================================
-- CART INTERFACE
-- ============================================================================
function cart.init(console)
    gfx    = console.gfx
    assets = console.assets
    sfx    = console.sfx
    input  = console.input

    -- Load textures
    texWall = nil
    if assets and assets.get then
        texWall = assets.get("walls", "brick_wall")
                  or assets.get("walls", "cave_wall")
    end
    texFloor = nil
    if assets and assets.get then
        texFloor = assets.get("floor", "wood_floor")
                   or assets.get("floor", "grass_floor")
    end
    texCeil = nil
    if assets and assets.get then
        texCeil = assets.get("bg", "sky_background")
    end

    -- Fallbacks
    if not texWall then
        texWall = buildFallbackTexture(16, 16,
            {0.50, 0.35, 0.25, 1}, {0.40, 0.28, 0.18, 1})
    end
    if not texFloor then
        texFloor = buildFallbackTexture(16, 16,
            {0.35, 0.25, 0.15, 1}, {0.28, 0.20, 0.12, 1})
    end
    if not texCeil then
        texCeil = buildFallbackTexture(16, 16,
            {0.25, 0.25, 0.35, 1}, {0.20, 0.20, 0.30, 1})
    end

    -- Set nearest + repeat
    texWall:setFilter("nearest", "nearest")
    texWall:setWrap("repeat", "repeat")
    texFloor:setFilter("nearest", "nearest")
    texFloor:setWrap("repeat", "repeat")
    texCeil:setFilter("nearest", "nearest")
    texCeil:setWrap("repeat", "repeat")

    -- Cache texture dimensions
    texWallW, texWallH   = texWall:getWidth(), texWall:getHeight()
    texFloorW, texFloorH = texFloor:getWidth(), texFloor:getHeight()
    texCeilW, texCeilH   = texCeil:getWidth(), texCeil:getHeight()

    -- Get ImageData from textures for floor/ceiling pixel sampling
    floorTexData = loadTextureData(texFloor)
    ceilTexData  = loadTextureData(texCeil)

    -- Init mesh
    initQuadMesh()

    -- Init floor/ceiling image (same size as viewport)
    floorCeilImageData = love.image.newImageData(VP_W, VP_H)
    floorCeilImage = love.graphics.newImage(floorCeilImageData)
    floorCeilImage:setFilter("nearest", "nearest")

    -- Z-buffer for minimap/debugging
    zBuffer = {}
    for i = 0, VP_W - 1 do zBuffer[i] = MAX_DIST end

    -- Default player start
    playerStartX = 2
    playerStartY = 2

    -- Try loading saved map, fall back to default
    if not loadMapFromFile() then
        loadMapDefault()
    end

    -- Player start (1-based world coords, facing east)
    player = {
        x     = playerStartX + 0.5,
        y     = playerStartY + 0.5,
        angle = 0,
    }

    -- Edit mode state
    mode = "play"
    cursorX = 1
    cursorY = 1
    brushType = TILE_WALL

    -- Message log
    msgLog = {}
    addLog("RAYCAST DUNGEON")
    addLog("ARROWS: MOVE/TURN")
    addLog("F1: EDIT MODE")
end

function cart.reset(console)
    cart.init(console)
end

function cart.update(dt, console)
    if mode == "edit" then
        -- No continuous update needed in edit mode
        return
    end

    -- PLAY MODE: smooth movement via held keys
    local moved = false

    if input.held.LEFT then
        player.angle = player.angle - ROT_SPEED * dt
        moved = true
    end
    if input.held.RIGHT then
        player.angle = player.angle + ROT_SPEED * dt
        moved = true
    end

    -- Normalize angle to [0, 2pi)
    player.angle = player.angle % (2 * math.pi)

    local dx = math_cos(player.angle)
    local dy = math_sin(player.angle)

    if input.held.UP then
        local nx = player.x + dx * MOVE_SPEED * dt
        local ny = player.y + dy * MOVE_SPEED * dt
        -- Collision: check with margin (player coords are 1-based, floor gives tile index)
        local margin = 0.2
        local py = player.y
        if not isWall(math_floor(nx + margin), math_floor(py + margin)) and
           not isWall(math_floor(nx - margin), math_floor(py + margin)) and
           not isWall(math_floor(nx + margin), math_floor(py - margin)) and
           not isWall(math_floor(nx - margin), math_floor(py - margin)) then
            player.x = nx
        end
        local px = player.x
        if not isWall(math_floor(px + margin), math_floor(ny + margin)) and
           not isWall(math_floor(px - margin), math_floor(ny + margin)) and
           not isWall(math_floor(px + margin), math_floor(ny - margin)) and
           not isWall(math_floor(px - margin), math_floor(ny - margin)) then
            player.y = ny
        end
        moved = true
    end

    if input.held.DOWN then
        local nx = player.x - dx * MOVE_SPEED * dt
        local ny = player.y - dy * MOVE_SPEED * dt
        local margin = 0.2
        local py = player.y
        if not isWall(math_floor(nx + margin), math_floor(py + margin)) and
           not isWall(math_floor(nx - margin), math_floor(py + margin)) and
           not isWall(math_floor(nx + margin), math_floor(py - margin)) and
           not isWall(math_floor(nx - margin), math_floor(py - margin)) then
            player.x = nx
        end
        local px = player.x
        if not isWall(math_floor(px + margin), math_floor(ny + margin)) and
           not isWall(math_floor(px - margin), math_floor(ny + margin)) and
           not isWall(math_floor(px + margin), math_floor(ny - margin)) and
           not isWall(math_floor(px - margin), math_floor(ny - margin)) then
            player.y = ny
        end
        moved = true
    end
end

function cart.input(action, pressed, console)
    if not pressed then return end

    if mode == "edit" then
        -- Edit mode controls via mapped actions
        if action == "UP" then
            cursorY = math_max(1, cursorY - 1)
        elseif action == "DOWN" then
            cursorY = math_min(mapH, cursorY + 1)
        elseif action == "LEFT" then
            cursorX = math_max(1, cursorX - 1)
        elseif action == "RIGHT" then
            cursorX = math_min(mapW, cursorX + 1)
        elseif action == "A" then
            -- Paint tile
            if brushType == TILE_START then
                -- Remove previous START tile
                for y = 1, mapH do
                    for x = 1, mapW do
                        if getTile(x, y) == TILE_START then
                            setTile(x, y, TILE_EMPTY)
                        end
                    end
                end
                playerStartX = cursorX
                playerStartY = cursorY
            end
            setTile(cursorX, cursorY, brushType)
            addLog("PLACED " .. (TILE_NAMES[brushType] or "?") .. " @" .. cursorX .. "," .. cursorY)
        elseif action == "B" then
            -- Cycle brush
            local idx = 1
            for i, bt in ipairs(BRUSH_ORDER) do
                if bt == brushType then idx = i; break end
            end
            idx = idx + 1
            if idx > #BRUSH_ORDER then idx = 1 end
            brushType = BRUSH_ORDER[idx]
            addLog("BRUSH: " .. (TILE_NAMES[brushType] or "?"))
        end
        return
    end

    -- PLAY MODE
    if action == "A" then
        -- Interact: check front cell
        local dx = math_cos(player.angle)
        local dy = math_sin(player.angle)
        local fx = math_floor(player.x + dx)
        local fy = math_floor(player.y + dy)
        if isWall(fx, fy) then
            addLog("SOLID WALL...")
            if sfx then sfx.play("bump") end
        else
            addLog("NOTHING HERE...")
        end
    end
end

function cart.keypressed(key)
    if key == "f1" then
        if mode == "play" then
            mode = "edit"
            cursorX = clamp(math_floor(player.x), 1, mapW)
            cursorY = clamp(math_floor(player.y), 1, mapH)
            addLog("ENTERED EDIT MODE")
        else
            mode = "play"
            applyPlayerStart()
            addLog("ENTERED PLAY MODE")
        end
        return
    end

    if mode == "edit" then
        if key == "r" then
            -- Clear tile at cursor (set to empty)
            setTile(cursorX, cursorY, TILE_EMPTY)
            addLog("CLEARED @" .. cursorX .. "," .. cursorY)
        elseif key == "s" then
            saveMap()
        elseif key == "l" then
            if loadMapFromFile() then
                addLog("MAP LOADED!")
            else
                addLog("NO SAVED MAP")
            end
        elseif key == "p" then
            -- Test play: switch to play mode at player start
            mode = "play"
            applyPlayerStart()
            addLog("TEST PLAY")
        end
    end
end

function cart.draw(console)
    if mode == "edit" then
        -- Edit mode: top-down grid + panel
        drawEditGrid()
        drawEditPanel()
        drawMessageBox()
        return
    end

    -- PLAY MODE
    -- Viewport
    drawViewport()

    -- Right panel background
    drawBevel(RPANEL_X, RPANEL_Y, RPANEL_W, RPANEL_H)

    -- Title
    gfx.print("RAYCAST 3D", RPANEL_X + 4, RPANEL_Y + RPANEL_H - 20, 0)

    -- Minimap
    drawMinimap()

    -- Stats
    drawStats()

    -- Message box
    drawMessageBox()

    -- Viewport border
    gfx.rectLine(VP_X, VP_Y, VP_W, VP_H, 8)
end

return cart

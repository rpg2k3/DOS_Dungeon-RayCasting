local tool = {}
tool.id    = "sprite_editor"
tool.title = "Sprite Editor"

----------------------------------------------------------------
-- Injected refs (set in init)
----------------------------------------------------------------
local gfx, input, sfx, theme, sprites
local consoleRef  -- set from console in open()

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------
local VIRT_W, VIRT_H = 320, 200

-- Canvas area (128x128 sprite, scaled 1:1 pixel on screen = 1 canvas pixel)
local CANVAS_SIZE = 128
local ZOOM_LEVELS = {1, 2, 4, 8}    -- pixel magnification
local DEFAULT_ZOOM = 2               -- index into ZOOM_LEVELS

-- Layout regions
local CANVAS_X, CANVAS_Y = 2, 2     -- top-left of canvas viewport
local CANVAS_VP_W = 192              -- viewport pixel width for canvas
local CANVAS_VP_H = 160              -- viewport pixel height for canvas

local PANEL_X = CANVAS_VP_W + CANVAS_X + 2  -- right panel start
local PANEL_Y = 2
local PANEL_W = VIRT_W - PANEL_X - 1

local STRIP_X = 0
local STRIP_Y = CANVAS_VP_H + CANVAS_Y + 2  -- frame strip Y
local STRIP_H = VIRT_H - STRIP_Y

-- 32-color palette (CGA16 + 16 extended muted/dark tones)
local PALETTE = {}

-- Tools
local TOOL_PENCIL = 1
local TOOL_ERASER = 2
local TOOL_FILL   = 3
local TOOL_NAMES  = {"PENCIL", "ERASER", "FILL"}

-- Editor modes
local MODE_SPRITE     = "sprite"
local MODE_ICON_SHEET = "icon_sheet"
local MODE_PORTRAIT   = "portrait"
local MODE_COMPOSITE  = "composite"
local MODE_TEXTURE    = "texture"
local MODE_NAMES = { "SPRITE", "ICON SHEET", "PORTRAIT", "COMPOSITE", "TEXTURE" }
local MODE_VALUES = { MODE_SPRITE, MODE_ICON_SHEET, MODE_PORTRAIT, MODE_COMPOSITE, MODE_TEXTURE }

-- Texture sub-kinds (subfolder under sprites/textures/)
local TEXTURE_KINDS = { "walls", "floor", "roof", "bg" }
local TEXTURE_KIND_NAMES = { "WALLS", "FLOOR", "ROOF", "BG" }

-- Texture safe area (1-based pixel coords): 16px border on each side
local SAFE_X1, SAFE_Y1 = 17, 17    -- first safe pixel
local SAFE_X2, SAFE_Y2 = 112, 112  -- last safe pixel
local BORDER_W = 16                 -- border width in pixels

-- Border mode constants
local BORDER_WRAP   = 1
local BORDER_MIRROR = 2
local BORDER_MODE_NAMES = { "WRAP", "MIRROR" }

-- Icon sheet constants
local ICON_CELL = 16      -- 16x16 pixels per icon cell
local ICON_COLS = 8       -- 128 / 16 = 8 columns
local ICON_ROWS = 8       -- 128 / 16 = 8 rows
local ICON_COUNT = 64     -- 8x8 = 64 cells

-- Portrait layer slots (draw order: body at bottom, extras on top)
local PORTRAIT_LAYERS = {"body", "face", "eyes", "mouth", "hair", "clothes", "extras", "armor"}

-- Composite slot definitions per category
local COMPOSITE_SLOTS = {
    portraits  = {"body", "face", "eyes", "mouth", "hair", "clothes", "extras", "armor"},
    characters = {"base", "clothes", "hair", "armor", "extras", "weapon"},
}

-- Slot subfolder mapping (category -> slot -> subfolder path for parts)
local SLOT_SUBFOLDER = {
    portraits  = {
        body = "parts/body", face = "parts/face", eyes = "parts/eyes",
        mouth = "parts/mouth", hair = "parts/hair", clothes = "parts/clothes",
        extras = "parts/extras", armor = "parts/armor",
    },
    characters = {
        base = "parts/base", clothes = "parts/clothes", hair = "parts/hair",
        armor = "parts/armor", extras = "parts/extras", weapon = "parts/weapon",
    },
}

-- Default pivot per composite category (feet anchor convention)
local COMP_DEFAULT_PIVOT = {
    portraits  = { x = 64, y = 112 },
    characters = { x = 64, y = 120 },  -- feet anchor near bottom
}

-- Randomization weights: chance (0-100) that a slot gets filled during randomize.
-- Slots not listed default to 100 (always filled).
local SLOT_WEIGHTS = {
    extras = 15,
    armor  = 30,
    clothes = 70,
    weapon = 50,
}

-- Layer names per mode
local DEFAULT_LAYERS = {
    [MODE_SPRITE]     = {"weapon", "hand"},
    [MODE_ICON_SHEET] = {"icons"},
    [MODE_PORTRAIT]   = PORTRAIT_LAYERS,
    [MODE_TEXTURE]    = {"base"},
}

----------------------------------------------------------------
-- Editor state (module-level ref; set from state.tools.spriteEditor in each entry point)
----------------------------------------------------------------
local state = {}

-- Initialize a table with default editor state (for state.tools.spriteEditor)
local function initEditorState(s)
    s.mode = MODE_SPRITE
    s.layers = {}
    s.layerNames = {}
    s.numFrames = 1
    s.activeLayer = 1
    s.activeFrame = 1
    s.curX, s.curY = 64, 64
    s.zoomIdx = DEFAULT_ZOOM
    s.scrollX, s.scrollY = 0, 0
    s.tool = TOOL_PENCIL
    s.color = 15
    s.playing = false
    s.playTimer = 0
    s.fps = 8
    s.menuOpen = false
    s.menuSel = 1
    s.helpOpen = false
    s.layerVisible = {}
    s.dialogMode = nil
    s.dialogCategory = 1
    s.dialogSubfolder = nil
    s.dialogSubfolders = {}
    s.dialogName = ""
    s.dialogSel = 1
    s.dialogAssets = {}
    s.dialogTyping = false
    s.modeSelectOpen = false
    s.modeSelectSel = 1
    s.cursorBlink = 0
    s.repeatTimers = { LEFT = 0, RIGHT = 0, UP = 0, DOWN = 0 }
    s.dirty = false
    s.statusMsg = nil
    s.statusTimer = 0
    s.iconCell = 0
    s.cellLock = false
    s.textureKind = 1
    s.texSafeArea = true
    s.texAutoWrap = true
    s.texBorderMode = BORDER_WRAP
    s.texTilePreview = false
    s.texPanOffset = 0
    s.compSlots = {}
    s.compStack = {}
    s.compSlotSel = 1
    s.compParts = {}
    s.compPartSel = 1
    s.compCategory = "portraits"
    s.compPreviewCanvas = nil
    s.compPreviewDirty = true
    s.compPivot = {x = 64, y = 112}
    s.compFocus = "slots"
end

local function resetState()
    state = {
        -- Editor mode
        mode = MODE_SPRITE,

        -- Canvas data: layers[layerIndex][frameIndex][y][x] = palette index (0=transparent)
        layers = {},
        layerNames = {},
        numFrames = 1,
        activeLayer = 1,
        activeFrame = 1,

        -- Cursor
        curX = 64,
        curY = 64,

        -- Zoom
        zoomIdx = DEFAULT_ZOOM,

        -- Scroll offset (canvas panning)
        scrollX = 0,
        scrollY = 0,

        -- Tool
        tool = TOOL_PENCIL,
        color = 15,  -- palette index (white by default)

        -- Animation preview
        playing = false,
        playTimer = 0,
        fps = 8,

        -- Menu
        menuOpen = false,
        menuSel = 1,

        -- Help overlay
        helpOpen = false,

        -- Layer visibility (indexed by layer index, default all true)
        layerVisible = {},

        -- Save/Load dialog
        dialogMode = nil,  -- nil, "save", "load", "new"
        dialogCategory = 1,
        dialogSubfolder = nil,  -- nil or index into subfolders list
        dialogSubfolders = {},  -- cached subfolder list for current category
        dialogName = "",
        dialogSel = 1,
        dialogAssets = {},
        dialogTyping = false,

        -- Mode selector dialog
        modeSelectOpen = false,
        modeSelectSel = 1,

        -- Cursor blink
        cursorBlink = 0,

        -- Cursor repeat timers
        repeatTimers = { LEFT = 0, RIGHT = 0, UP = 0, DOWN = 0 },

        -- Dirty flag
        dirty = false,

        -- Status message (timed)
        statusMsg = nil,
        statusTimer = 0,

        -- Icon sheet mode
        iconCell = 0,        -- selected cell index (0..63)
        cellLock = false,    -- restrict edits to selected cell

        -- Texture mode
        textureKind = 1,     -- index into TEXTURE_KINDS
        texSafeArea = true,  -- restrict painting to safe area
        texAutoWrap = true,  -- auto-generate border from safe area
        texBorderMode = BORDER_WRAP,  -- WRAP or MIRROR
        texTilePreview = false,  -- 3x3 tiling preview toggle
        texPanOffset = 0,        -- panorama preview scroll offset (pixels)

        -- Composite editor mode
        compSlots = {},      -- ordered slot names (from slotsOrder)
        compStack = {},      -- slot -> {asset=path_or_nil}
        compSlotSel = 1,     -- selected slot index
        compParts = {},      -- available parts for current slot
        compPartSel = 1,     -- selected part in browser
        compCategory = "portraits",  -- category for this composite
        compPreviewCanvas = nil,     -- rendered preview canvas
        compPreviewDirty = true,     -- needs re-render
        compPivot = {x = 64, y = 112},
        compFocus = "slots", -- "slots" or "parts"
    }
end

----------------------------------------------------------------
-- Palette setup
----------------------------------------------------------------
local function initPalette()
    -- First 16: CGA palette from gfx
    for i = 0, 15 do
        local c = gfx.palette[i]
        PALETTE[i] = {c[1], c[2], c[3], 1}
    end
    -- Extended 16 colors (muted/pastel/dark variants)
    local ext = {
        {0.40, 0.26, 0.13},  -- 16 dark brown
        {0.80, 0.52, 0.25},  -- 17 tan/sand
        {1.00, 0.60, 0.40},  -- 18 peach/skin light
        {0.80, 0.40, 0.30},  -- 19 skin medium
        {0.53, 0.27, 0.20},  -- 20 skin dark
        {0.20, 0.40, 0.20},  -- 21 forest green
        {0.60, 0.80, 0.40},  -- 22 lime
        {0.40, 0.60, 0.80},  -- 23 steel blue
        {0.20, 0.20, 0.40},  -- 24 navy
        {0.60, 0.40, 0.60},  -- 25 mauve
        {0.80, 0.60, 0.80},  -- 26 lavender
        {1.00, 0.80, 0.60},  -- 27 cream
        {0.80, 0.80, 0.60},  -- 28 khaki
        {0.40, 0.40, 0.40},  -- 29 mid gray
        {0.13, 0.13, 0.13},  -- 30 near-black
        {0.93, 0.93, 0.93},  -- 31 near-white
    }
    for i, c in ipairs(ext) do
        PALETTE[15 + i] = {c[1], c[2], c[3], 1}
    end
end

----------------------------------------------------------------
-- Canvas image pipeline (composite all visible layers into one Image)
----------------------------------------------------------------
local canvasImgData  -- love ImageData (CANVAS_SIZE x CANVAS_SIZE, rgba8)
local canvasImg      -- love Image (drawn scaled)
local canvasImgDirty = true  -- needs rebuild
local canvasLastFrame = -1   -- track frame changes

local function ensureCanvasImage()
    if not canvasImgData then
        canvasImgData = love.image.newImageData(CANVAS_SIZE, CANVAS_SIZE)
        canvasImg = love.graphics.newImage(canvasImgData)
        canvasImg:setFilter("nearest", "nearest")
    end
end

--- Rebuild canvasImg from layer data. Call after any pixel change.
local function rebuildCanvasImage()
    ensureCanvasImage()
    -- Clear to transparent
    canvasImgData:mapPixel(function() return 0, 0, 0, 0 end)
    -- Composite layers bottom to top
    local fi = state.activeFrame
    for li = #state.layerNames, 1, -1 do
        if state.layerVisible[li] == false then goto skip end
        local frame = state.layers[li] and state.layers[li][fi]
        if not frame then goto skip end
        for y = 1, CANVAS_SIZE do
            local row = frame[y]
            for x = 1, CANVAS_SIZE do
                local col = row[x]
                if col > 0 then
                    local c = PALETTE[col]
                    if c then
                        canvasImgData:setPixel(x - 1, y - 1, c[1], c[2], c[3], c[4] or 1)
                    end
                end
            end
        end
        ::skip::
    end
    canvasImg:replacePixels(canvasImgData)
    canvasImgDirty = false
end

--- Bresenham line: calls fn(x, y) for each pixel on the line from (x0,y0) to (x1,y1).
local function bresenhamLine(x0, y0, x1, y1, fn)
    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        fn(x0, y0)
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then
            err = err + dy
            x0 = x0 + sx
        end
        if e2 <= dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

-- Grid overlay toggle
local gridOn = false

-- Debug overlay toggle
local debugOverlay = true

-- Last mouse stroke pixel (for Bresenham continuity)
local lastStrokePx, lastStrokePy = nil, nil

-- Cached mouse virtual coords for debug display
local debugMx, debugMy = 0, 0
local debugVx, debugVy = 0, 0
local debugPx, debugPy = 0, 0
local debugInside = false

----------------------------------------------------------------
-- Icon cell helpers
----------------------------------------------------------------

--- Get pixel bounds for an icon cell (1-based coordinates).
--- @param cellIdx number 0-based cell index (0..63)
--- @return number x1, number y1, number x2, number y2
local function cellBounds(cellIdx)
    local col = cellIdx % ICON_COLS
    local row = math.floor(cellIdx / ICON_COLS)
    local x1 = col * ICON_CELL + 1
    local y1 = row * ICON_CELL + 1
    return x1, y1, x1 + ICON_CELL - 1, y1 + ICON_CELL - 1
end

--- Get the cell index for a pixel coordinate.
--- @param px number 1-based x
--- @param py number 1-based y
--- @return number cellIdx (0-based)
local function cellFromPixel(px, py)
    local col = math.floor((px - 1) / ICON_CELL)
    local row = math.floor((py - 1) / ICON_CELL)
    return row * ICON_COLS + col
end

--- Check if a pixel is inside the current locked cell.
local function isInLockedCell(px, py)
    if not state.cellLock then return true end
    if state.mode ~= MODE_ICON_SHEET then return true end
    local x1, y1, x2, y2 = cellBounds(state.iconCell)
    return px >= x1 and px <= x2 and py >= y1 and py <= y2
end

----------------------------------------------------------------
-- Layer/frame helpers
----------------------------------------------------------------
local function makeEmptyFrame()
    local frame = {}
    for y = 1, CANVAS_SIZE do
        frame[y] = {}
        for x = 1, CANVAS_SIZE do
            frame[y][x] = 0
        end
    end
    return frame
end

local function copyFrame(src)
    local dst = {}
    for y = 1, CANVAS_SIZE do
        dst[y] = {}
        for x = 1, CANVAS_SIZE do
            dst[y][x] = src[y][x]
        end
    end
    return dst
end

local function initLayers()
    local layerDefs = DEFAULT_LAYERS[state.mode] or {"layer1"}
    state.layerNames = {}
    state.layers = {}
    state.layerVisible = {}
    for i, name in ipairs(layerDefs) do
        state.layerNames[i] = name
        state.layers[i] = { makeEmptyFrame() }
        state.layerVisible[i] = true
    end
    state.numFrames = 1
    state.activeLayer = 1
    state.activeFrame = 1
    canvasImgDirty = true
end

local function addFrame()
    state.numFrames = state.numFrames + 1
    for li = 1, #state.layers do
        state.layers[li][state.numFrames] = makeEmptyFrame()
    end
    state.activeFrame = state.numFrames
    state.dirty = true
end

local function duplicateFrame()
    state.numFrames = state.numFrames + 1
    local src = state.activeFrame
    for li = 1, #state.layers do
        table.insert(state.layers[li], src + 1, copyFrame(state.layers[li][src]))
    end
    state.activeFrame = src + 1
    state.dirty = true
end

local function deleteFrame()
    if state.numFrames <= 1 then return end
    local idx = state.activeFrame
    for li = 1, #state.layers do
        table.remove(state.layers[li], idx)
    end
    state.numFrames = state.numFrames - 1
    if state.activeFrame > state.numFrames then
        state.activeFrame = state.numFrames
    end
    state.dirty = true
end

----------------------------------------------------------------
-- Pixel operations
----------------------------------------------------------------
local function getPixel(layer, frame, x, y)
    if x < 1 or x > CANVAS_SIZE or y < 1 or y > CANVAS_SIZE then return 0 end
    return state.layers[layer][frame][y][x]
end

--- Check if current texture mode is panorama (bg kind = X-wrap only).
local function isPanorama()
    return state.mode == MODE_TEXTURE and TEXTURE_KINDS[state.textureKind] == "bg"
end

local function isInSafeArea(x, y)
    if not state.texSafeArea then return true end
    if state.mode ~= MODE_TEXTURE then return true end
    -- Panorama (bg): only restrict X axis, full Y range is paintable
    if isPanorama() then
        return x >= SAFE_X1 and x <= SAFE_X2
    end
    return x >= SAFE_X1 and x <= SAFE_X2 and y >= SAFE_Y1 and y <= SAFE_Y2
end

local function setPixel(layer, frame, x, y, col)
    if x < 1 or x > CANVAS_SIZE or y < 1 or y > CANVAS_SIZE then return end
    if not isInLockedCell(x, y) then return end
    if not isInSafeArea(x, y) then return end
    state.layers[layer][frame][y][x] = col
    state.dirty = true
    canvasImgDirty = true
end

local function floodFill(layer, frame, sx, sy, newCol)
    if not isInLockedCell(sx, sy) then return end
    if not isInSafeArea(sx, sy) then return end
    local oldCol = getPixel(layer, frame, sx, sy)
    if oldCol == newCol then return end
    local stack = {{sx, sy}}
    local data = state.layers[layer][frame]
    while #stack > 0 do
        local pos = table.remove(stack)
        local px, py = pos[1], pos[2]
        if px >= 1 and px <= CANVAS_SIZE and py >= 1 and py <= CANVAS_SIZE
           and isInLockedCell(px, py) and isInSafeArea(px, py) then
            if data[py][px] == oldCol then
                data[py][px] = newCol
                stack[#stack + 1] = {px - 1, py}
                stack[#stack + 1] = {px + 1, py}
                stack[#stack + 1] = {px, py - 1}
                stack[#stack + 1] = {px, py + 1}
            end
        end
    end
    state.dirty = true
    canvasImgDirty = true
end

--- Regenerate the 16px border around the safe area for seamless tiling.
--- Called after any paint operation in texture mode with autoWrap enabled.
--- In panorama mode (bg), only X borders are wrapped; Y is left as-is.
local function regenerateBorder(layer, frame)
    if state.mode ~= MODE_TEXTURE then return end
    if not state.texSafeArea or not state.texAutoWrap then return end
    local data = state.layers[layer][frame]
    if not data then return end

    local safeW = SAFE_X2 - SAFE_X1 + 1  -- 96
    local bm = state.texBorderMode
    local pano = isPanorama()

    for y = 1, CANVAS_SIZE do
        for x = 1, CANVAS_SIZE do
            -- Determine if this pixel is in the safe area
            local inSafe
            if pano then
                -- Panorama: safe area is full height, only X restricted
                inSafe = (x >= SAFE_X1 and x <= SAFE_X2)
            else
                inSafe = (x >= SAFE_X1 and x <= SAFE_X2 and y >= SAFE_Y1 and y <= SAFE_Y2)
            end

            if not inSafe then
                local srcX, srcY

                if bm == BORDER_WRAP then
                    srcX = x
                    srcY = y
                    if x < SAFE_X1 then srcX = x + safeW end
                    if x > SAFE_X2 then srcX = x - safeW end
                    if not pano then
                        if y < SAFE_Y1 then srcY = y + safeW end
                        if y > SAFE_Y2 then srcY = y - safeW end
                    end
                else
                    srcX = x
                    srcY = y
                    if x < SAFE_X1 then
                        srcX = SAFE_X1 + (SAFE_X1 - x) - 1
                    elseif x > SAFE_X2 then
                        srcX = SAFE_X2 - (x - SAFE_X2) + 1
                    end
                    if not pano then
                        if y < SAFE_Y1 then
                            srcY = SAFE_Y1 + (SAFE_Y1 - y) - 1
                        elseif y > SAFE_Y2 then
                            srcY = SAFE_Y2 - (y - SAFE_Y2) + 1
                        end
                    end
                end

                -- Clamp source to valid range
                if srcX >= 1 and srcX <= CANVAS_SIZE and srcY >= 1 and srcY <= CANVAS_SIZE then
                    data[y][x] = data[srcY][srcX]
                end
            end
        end
    end
    canvasImgDirty = true
end

--- Apply a checker dither blend across the wrap seam boundaries.
--- The seams are at x=SAFE_X1 (left boundary: border meets safe area)
--- and x=SAFE_X2 (right boundary: safe area meets border).
--- For each seam, an 8px strip straddles the boundary (4px on each side).
--- Checker pattern: on odd positions, swap pixel with its wrap-partner.
local function ditherSeam(layer, frame)
    if state.mode ~= MODE_TEXTURE then return end
    local data = state.layers[layer][frame]
    if not data then return end

    local safeW = SAFE_X2 - SAFE_X1 + 1  -- 96
    local pano = isPanorama()
    local yStart = pano and 1 or SAFE_Y1
    local yEnd   = pano and CANVAS_SIZE or SAFE_Y2

    -- Dither strip half-width on each side of each seam boundary
    local halfStrip = 4

    for y = yStart, yEnd do
        -- Left seam boundary: between x=SAFE_X1-1 (border) and x=SAFE_X1 (safe)
        -- Dither strip: x in [SAFE_X1 - halfStrip .. SAFE_X1 + halfStrip - 1]
        for i = 0, halfStrip * 2 - 1 do
            local x = SAFE_X1 - halfStrip + i
            if x >= 1 and x <= CANVAS_SIZE then
                if (x + y) % 2 == 1 then
                    -- Swap with wrapped partner
                    local wx = x + safeW
                    if wx > CANVAS_SIZE then wx = wx - safeW end
                    if wx >= 1 and wx <= CANVAS_SIZE then
                        data[y][x] = data[y][wx]
                    end
                end
            end
        end

        -- Right seam boundary: between x=SAFE_X2 (safe) and x=SAFE_X2+1 (border)
        for i = 0, halfStrip * 2 - 1 do
            local x = SAFE_X2 - halfStrip + 1 + i
            if x >= 1 and x <= CANVAS_SIZE then
                if (x + y) % 2 == 1 then
                    local wx = x - safeW
                    if wx < 1 then wx = wx + safeW end
                    if wx >= 1 and wx <= CANVAS_SIZE then
                        data[y][x] = data[y][wx]
                    end
                end
            end
        end
    end
    canvasImgDirty = true
    state.dirty = true
end

----------------------------------------------------------------
-- Tool action
----------------------------------------------------------------
local function applyTool()
    local x, y = state.curX, state.curY
    local li, fi = state.activeLayer, state.activeFrame
    if state.tool == TOOL_PENCIL then
        setPixel(li, fi, x, y, state.color)
    elseif state.tool == TOOL_ERASER then
        setPixel(li, fi, x, y, 0)
    elseif state.tool == TOOL_FILL then
        floodFill(li, fi, x, y, state.color)
    end
end

----------------------------------------------------------------
-- Save / Load
----------------------------------------------------------------
local CATEGORIES = nil  -- loaded from sprites module

local function assetToState(asset)
    state.layerNames = asset.layerNames or DEFAULT_LAYERS[state.mode] or {"layer1"}
    state.numFrames = asset.numFrames or 1
    -- Restore mode from asset if present
    if asset.mode then
        state.mode = asset.mode
    end
    -- Restore texture kind from asset
    if asset.textureKind then
        for i, kind in ipairs(TEXTURE_KINDS) do
            if kind == asset.textureKind then
                state.textureKind = i
                break
            end
        end
    end
    state.layers = {}
    for li, lname in ipairs(state.layerNames) do
        state.layers[li] = {}
        local savedLayer = asset.layers and asset.layers[li]
        for fi = 1, state.numFrames do
            if savedLayer and savedLayer[fi] then
                local raw = savedLayer[fi]
                if type(raw) == "string" then
                    state.layers[li][fi] = sprites.decodeRLE(raw, CANVAS_SIZE, CANVAS_SIZE)
                elseif type(raw) == "table" then
                    local frame = {}
                    for y = 1, CANVAS_SIZE do
                        frame[y] = {}
                        for x = 1, CANVAS_SIZE do
                            frame[y][x] = raw[(y - 1) * CANVAS_SIZE + x] or 0
                        end
                    end
                    state.layers[li][fi] = frame
                else
                    state.layers[li][fi] = makeEmptyFrame()
                end
            else
                state.layers[li][fi] = makeEmptyFrame()
            end
        end
    end
    state.layerVisible = {}
    for i = 1, #state.layerNames do
        state.layerVisible[i] = true
    end
    state.activeLayer = 1
    state.activeFrame = 1
    state.dirty = false
    canvasImgDirty = true
end

local function stateToAsset()
    local asset = {
        name = state.dialogName ~= "" and state.dialogName or "untitled",
        mode = state.mode,
        width = CANVAS_SIZE,
        height = CANVAS_SIZE,
        numFrames = state.numFrames,
        layerNames = {},
        layers = {},
    }
    -- Texture-specific metadata
    if state.mode == MODE_TEXTURE then
        asset.textureKind = TEXTURE_KINDS[state.textureKind]
    end
    for li, lname in ipairs(state.layerNames) do
        asset.layerNames[li] = lname
        asset.layers[li] = {}
        for fi = 1, state.numFrames do
            local frame = state.layers[li][fi]
            asset.layers[li][fi] = sprites.encodeRLE(frame, CANVAS_SIZE, CANVAS_SIZE)
        end
    end
    return asset
end

local function doSave()
    if state.dialogName == "" then return false end
    local cat = CATEGORIES[state.dialogCategory]
    local sub = currentSubpath()
    local path = cat
    if sub then path = path .. "/" .. sub end
    path = path .. "/" .. state.dialogName
    local asset = stateToAsset()
    local ok, err = sprites.saveAsset(path, asset)
    if ok then
        state.dirty = false
        -- Hot-reload texture into assets if this is a texture save
        if state.mode == MODE_TEXTURE and consoleRef and consoleRef.assets then
            local kind = TEXTURE_KINDS[state.textureKind]
            consoleRef.assets.reloadSpriteTexture(sprites, kind, state.dialogName)
        end
    end
    return ok, err
end

local function doLoad(assetName)
    local cat = CATEGORIES[state.dialogCategory]
    local sub = currentSubpath()
    local path = cat
    if sub then path = path .. "/" .. sub end
    path = path .. "/" .. assetName
    local asset, err = sprites.loadAsset(path)
    if asset then
        assetToState(asset)
        state.dialogName = assetName
        return true
    end
    return false, err
end

local function refreshSubfolders()
    local cat = CATEGORIES[state.dialogCategory]
    state.dialogSubfolders = sprites.listSubfolders(cat)
    if #state.dialogSubfolders == 0 then
        state.dialogSubfolder = nil
    else
        state.dialogSubfolder = state.dialogSubfolder or 1
        if state.dialogSubfolder > #state.dialogSubfolders then
            state.dialogSubfolder = 1
        end
    end
end

local function currentSubpath()
    if state.dialogSubfolder and #state.dialogSubfolders > 0 then
        return state.dialogSubfolders[state.dialogSubfolder]
    end
    return nil
end

local function refreshAssetList()
    local cat = CATEGORIES[state.dialogCategory]
    state.dialogAssets = sprites.listAssets(cat, currentSubpath())
end

local function showStatus(msg)
    state.statusMsg = msg
    state.statusTimer = 3.0
end

----------------------------------------------------------------
-- Menu items
----------------------------------------------------------------
local MENU_ITEMS = {"SAVE", "LOAD", "NEW", "SET MODE", "ADD FRAME", "DUP FRAME", "DEL FRAME", "EXPORT FRAME", "EXPORT SHEET", "EXPORT ALL TEX", "RESUME", "EXIT TO MENU"}

local function handleMenu()
    local sel = MENU_ITEMS[state.menuSel]
    if sel == "SAVE" then
        state.menuOpen = false
        state.dialogMode = "save"
        state.dialogSel = 1
        state.dialogTyping = (state.dialogName == "")
        -- Auto-select category based on mode
        if state.mode == MODE_ICON_SHEET then
            for i, cat in ipairs(CATEGORIES) do
                if cat == "icons" then state.dialogCategory = i; break end
            end
        elseif state.mode == MODE_PORTRAIT then
            for i, cat in ipairs(CATEGORIES) do
                if cat == "portraits" then state.dialogCategory = i; break end
            end
        elseif state.mode == MODE_TEXTURE then
            for i, cat in ipairs(CATEGORIES) do
                if cat == "textures" then state.dialogCategory = i; break end
            end
        end
        refreshSubfolders()
        -- Auto-select texture subfolder
        if state.mode == MODE_TEXTURE and state.dialogSubfolders then
            local kind = TEXTURE_KINDS[state.textureKind]
            for i, sf in ipairs(state.dialogSubfolders) do
                if sf == kind then state.dialogSubfolder = i; break end
            end
        end
        refreshAssetList()
    elseif sel == "LOAD" then
        state.menuOpen = false
        state.dialogMode = "load"
        state.dialogSel = 1
        state.dialogTyping = false
        -- Auto-select category based on mode
        if state.mode == MODE_TEXTURE then
            for i, cat in ipairs(CATEGORIES) do
                if cat == "textures" then state.dialogCategory = i; break end
            end
        end
        refreshSubfolders()
        if state.mode == MODE_TEXTURE and state.dialogSubfolders then
            local kind = TEXTURE_KINDS[state.textureKind]
            for i, sf in ipairs(state.dialogSubfolders) do
                if sf == kind then state.dialogSubfolder = i; break end
            end
        end
        refreshAssetList()
    elseif sel == "NEW" then
        state.menuOpen = false
        initLayers()
        state.dialogName = ""
        state.dirty = false
    elseif sel == "SET MODE" then
        state.menuOpen = false
        state.modeSelectOpen = true
        -- Pre-select current mode
        for i, v in ipairs(MODE_VALUES) do
            if v == state.mode then state.modeSelectSel = i; break end
        end
    elseif sel == "ADD FRAME" then
        addFrame()
        state.menuOpen = false
    elseif sel == "DUP FRAME" then
        duplicateFrame()
        state.menuOpen = false
    elseif sel == "DEL FRAME" then
        deleteFrame()
        state.menuOpen = false
    elseif sel == "EXPORT FRAME" then
        state.menuOpen = false
        if state.dialogName == "" then
            showStatus("SAVE FIRST!")
        else
            local asset = stateToAsset()
            local cat = CATEGORIES[state.dialogCategory]
            local outPath = "exports/" .. cat .. "/" .. state.dialogName
                .. "/" .. state.dialogName
                .. string.format("_frame%03d.png", state.activeFrame)
            local ok, err = sprites.exportPNG(asset, state.activeFrame, outPath)
            if ok then
                showStatus("EXPORTED FRAME " .. state.activeFrame)
            else
                showStatus("ERROR: " .. (err or "unknown"))
            end
        end
    elseif sel == "EXPORT SHEET" then
        state.menuOpen = false
        if state.dialogName == "" then
            showStatus("SAVE FIRST!")
        else
            local asset = stateToAsset()
            local ok, err = sprites.exportIconSheet(asset, state.dialogName, state.activeFrame)
            if ok then
                showStatus("EXPORTED ICON SHEET")
            else
                showStatus("ERROR: " .. (err or "unknown"))
            end
        end
    elseif sel == "EXPORT ALL TEX" then
        state.menuOpen = false
        local exported, failed = sprites.exportAllTextures()
        if failed > 0 then
            showStatus("EXPORTED " .. exported .. ", FAILED " .. failed)
        elseif exported > 0 then
            showStatus("EXPORTED " .. exported .. " TEXTURES")
        else
            showStatus("NO TEXTURES TO EXPORT")
        end
    elseif sel == "RESUME" then
        state.menuOpen = false
    elseif sel == "EXIT TO MENU" then
        state.menuOpen = false
        toolOpen = false
    end
end

----------------------------------------------------------------
-- Mouse state
----------------------------------------------------------------
local mouseDown = { false, false, false }  -- [1]=left, [2]=right, [3]=middle
local escHandled = false  -- set by keypressed to prevent START double-trigger

--- Convert raw window mouse position to virtual (320x200) coordinates.
local function mouseToVirtual(mx, my)
    local vx = (mx - gfx.offsetX) / gfx.scale
    local vy = (my - gfx.offsetY) / gfx.scale
    return vx, vy
end

-- Viewport offset cache (set during drawCanvas, used by mouse mapping)
local viewOX, viewOY = 1, 1

--- Convert virtual screen position to canvas pixel coordinate (1-based).
--- Uses the viewport offset from the last draw call for stable mapping.
--- Returns nil,nil if outside the canvas viewport.
local function virtualToCanvas(vx, vy)
    if vx < CANVAS_X or vx >= CANVAS_X + CANVAS_VP_W then return nil, nil end
    if vy < CANVAS_Y or vy >= CANVAS_Y + CANVAS_VP_H then return nil, nil end

    local zoom = ZOOM_LEVELS[state.zoomIdx]
    local sx = math.floor((vx - CANVAS_X) / zoom)
    local sy = math.floor((vy - CANVAS_Y) / zoom)
    local px = viewOX + sx
    local py = viewOY + sy
    if px < 1 or px > CANVAS_SIZE or py < 1 or py > CANVAS_SIZE then return nil, nil end
    return px, py
end

--- Check if virtual coords are inside the palette grid. Returns palette index or nil.
local function virtualToPalette(vx, vy)
    local px = PANEL_X
    local py = PANEL_Y + 9  -- matches drawPalette offset
    local swatchSize = 7
    local cols = 8

    for i = 0, 31 do
        local row = math.floor(i / cols)
        local col = i % cols
        local sx = px + col * (swatchSize + 1)
        local sy = py + row * (swatchSize + 1)
        if vx >= sx and vx < sx + swatchSize and vy >= sy and vy < sy + swatchSize then
            return i
        end
    end
    return nil
end

--- Check if virtual coords are inside the layer panel. Returns layer index or nil.
local function virtualToLayer(vx, vy)
    -- Layer panel starts after palette. We need to compute the same startY as drawLayerPanel.
    local swatchSize = 7
    local paletteRows = 4
    local paletteEndY = PANEL_Y + 9 + paletteRows * (swatchSize + 1) + 2
    local px = PANEL_X
    local py = paletteEndY + 9  -- after "LAYERS" label

    for i = 1, #state.layerNames do
        local ly = py + (i - 1) * 9
        if vx >= px and vx < px + PANEL_W and vy >= ly and vy < ly + 9 then
            return i
        end
    end
    return nil
end

--- Paint a pixel using the current tool at (px, py).
local function paintAt(px, py)
    local li, fi = state.activeLayer, state.activeFrame
    if state.tool == TOOL_PENCIL then
        setPixel(li, fi, px, py, state.color)
    elseif state.tool == TOOL_ERASER then
        setPixel(li, fi, px, py, 0)
    elseif state.tool == TOOL_FILL then
        floodFill(li, fi, px, py, state.color)
    end
end

--- Erase a pixel at (px, py).
local function eraseAt(px, py)
    setPixel(state.activeLayer, state.activeFrame, px, py, 0)
end

--- Process mouse input each frame (called from tool.update)
local function updateMouse(dt)
    -- Always update debug coords from mouse position
    local mx, my = love.mouse.getPosition()
    local vx, vy = mouseToVirtual(mx, my)
    debugMx, debugMy = math.floor(mx), math.floor(my)
    debugVx, debugVy = vx, vy
    local dpx, dpy = virtualToCanvas(vx, vy)
    debugPx = dpx or 0
    debugPy = dpy or 0
    debugInside = dpx ~= nil

    -- Skip mouse when overlays are open
    if state.helpOpen or state.menuOpen or state.dialogMode or state.modeSelectOpen then
        return
    end
    if state.playing then return end
    if state.mode == MODE_COMPOSITE then return end

    -- Only track mouse position when a button is held (don't fight keyboard cursor)
    local anyMouseDown = mouseDown[1] or mouseDown[2] or mouseDown[3]
    if not anyMouseDown then
        lastStrokePx, lastStrokePy = nil, nil
        return
    end

    local px, py = virtualToCanvas(vx, vy)
    if px and py then
        state.curX = px
        state.curY = py

        -- Track cell under cursor in icon mode
        if state.mode == MODE_ICON_SHEET and not state.cellLock then
            state.iconCell = cellFromPixel(state.curX, state.curY)
        end

        -- Paint/erase with Bresenham line from last position for gapless strokes
        if mouseDown[1] then
            if lastStrokePx and lastStrokePy then
                bresenhamLine(lastStrokePx, lastStrokePy, px, py, paintAt)
            else
                paintAt(px, py)
            end
        end
        if mouseDown[2] then
            if lastStrokePx and lastStrokePy then
                bresenhamLine(lastStrokePx, lastStrokePy, px, py, eraseAt)
            else
                eraseAt(px, py)
            end
        end

        lastStrokePx, lastStrokePy = px, py
    end
end

----------------------------------------------------------------
-- Input handling
----------------------------------------------------------------
local REPEAT_DELAY = 0.35
local REPEAT_RATE  = 0.05

local function handleCursorRepeat(dt, action, dx, dy)
    if input.justPressed[action] then
        state.curX = math.max(1, math.min(CANVAS_SIZE, state.curX + dx))
        state.curY = math.max(1, math.min(CANVAS_SIZE, state.curY + dy))
        state.repeatTimers[action] = -REPEAT_DELAY
        return true
    elseif input.held[action] then
        state.repeatTimers[action] = state.repeatTimers[action] + dt
        if state.repeatTimers[action] >= REPEAT_RATE then
            state.repeatTimers[action] = state.repeatTimers[action] - REPEAT_RATE
            state.curX = math.max(1, math.min(CANVAS_SIZE, state.curX + dx))
            state.curY = math.max(1, math.min(CANVAS_SIZE, state.curY + dy))
            return true
        end
    else
        state.repeatTimers[action] = 0
    end
    return false
end

local function updateEditor(dt)
    -- Panorama preview scroll: LEFT/RIGHT scroll the pan offset
    if state.mode == MODE_TEXTURE and state.texTilePreview and isPanorama() then
        local scrollSpeed = 80  -- pixels per second
        if input.held.LEFT then
            state.texPanOffset = state.texPanOffset - scrollSpeed * dt
        end
        if input.held.RIGHT then
            state.texPanOffset = state.texPanOffset + scrollSpeed * dt
        end
        -- Wrap offset to prevent float drift
        if state.texPanOffset < 0 then state.texPanOffset = state.texPanOffset + CANVAS_SIZE * 10 end
        if state.texPanOffset > CANVAS_SIZE * 10 then state.texPanOffset = state.texPanOffset - CANVAS_SIZE * 10 end
        -- Skip normal cursor movement while in panorama preview
    else
        -- Cursor movement with repeat
        handleCursorRepeat(dt, "LEFT", -1, 0)
        handleCursorRepeat(dt, "RIGHT", 1, 0)
    end
    handleCursorRepeat(dt, "UP", 0, -1)
    handleCursorRepeat(dt, "DOWN", 0, 1)

    -- Track cell under cursor in icon mode
    if state.mode == MODE_ICON_SHEET and not state.cellLock then
        state.iconCell = cellFromPixel(state.curX, state.curY)
    end

    -- Draw while A held
    if input.held.A then
        applyTool()
    end

    -- Erase while B held (secondary tool)
    if input.held.B then
        setPixel(state.activeLayer, state.activeFrame, state.curX, state.curY, 0)
    end

    -- Regenerate texture border when stroke ends (A or B released)
    if input.justReleased.A or input.justReleased.B then
        regenerateBorder(state.activeLayer, state.activeFrame)
    end

    -- X cycles tool
    if input.justPressed.X then
        state.tool = (state.tool % #TOOL_NAMES) + 1
        if sfx then sfx.play("ui_move") end
    end

    -- Y cycles color forward
    if input.justPressed.Y then
        state.color = (state.color + 1) % 32
        if state.color == 0 then state.color = 1 end
    end

    -- L1 = prev frame, DEBUG (R1) = next frame
    if input.justPressed.L1 then
        if state.activeFrame > 1 then
            state.activeFrame = state.activeFrame - 1
            if sfx then sfx.play("ui_move") end
        end
    end
    if input.justPressed.DEBUG then
        if state.activeFrame < state.numFrames then
            state.activeFrame = state.activeFrame + 1
            if sfx then sfx.play("ui_move") end
        end
    end

    -- SELECT = toggle layer (sprite mode) or toggle cell lock (icon mode) or cycle texture kind
    if input.justPressed.SELECT then
        if state.mode == MODE_TEXTURE then
            state.textureKind = (state.textureKind % #TEXTURE_KINDS) + 1
            showStatus("TEXTURE: " .. TEXTURE_KIND_NAMES[state.textureKind])
        elseif state.mode == MODE_ICON_SHEET then
            state.cellLock = not state.cellLock
            if state.cellLock then
                state.iconCell = cellFromPixel(state.curX, state.curY)
                showStatus("CELL LOCK ON [" .. state.iconCell .. "]")
            else
                showStatus("CELL LOCK OFF")
            end
        else
            state.activeLayer = (state.activeLayer % #state.layerNames) + 1
        end
        if sfx then sfx.play("ui_move") end
    end
end

-- Forward declarations for composite functions (defined later)
local initComposite

local function updateMenu(dt)
    if input.justPressed.UP then
        state.menuSel = state.menuSel - 1
        if state.menuSel < 1 then state.menuSel = #MENU_ITEMS end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.DOWN then
        state.menuSel = state.menuSel + 1
        if state.menuSel > #MENU_ITEMS then state.menuSel = 1 end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.A then
        if sfx then sfx.play("ui_select") end
        handleMenu()
    end
    if input.justPressed.B or input.justPressed.START then
        state.menuOpen = false
        if sfx then sfx.play("ui_select") end
    end
end

local function updateModeSelect(dt)
    if input.justPressed.UP then
        state.modeSelectSel = state.modeSelectSel - 1
        if state.modeSelectSel < 1 then state.modeSelectSel = #MODE_VALUES end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.DOWN then
        state.modeSelectSel = state.modeSelectSel + 1
        if state.modeSelectSel > #MODE_VALUES then state.modeSelectSel = 1 end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.A then
        if sfx then sfx.play("ui_select") end
        local newMode = MODE_VALUES[state.modeSelectSel]
        if newMode ~= state.mode then
            state.mode = newMode
            state.cellLock = false
            state.iconCell = 0
            if newMode == MODE_COMPOSITE then
                initComposite("portraits")
            else
                initLayers()
            end
            state.dialogName = ""
            state.dirty = false
            showStatus("MODE: " .. MODE_NAMES[state.modeSelectSel])
        end
        state.modeSelectOpen = false
    end
    if input.justPressed.B or input.justPressed.START then
        state.modeSelectOpen = false
        if sfx then sfx.play("ui_select") end
    end
end

local function updateDialog(dt)
    if state.dialogTyping then
        if input.justPressed.START or input.justPressed.B then
            state.dialogMode = nil
            state.dialogTyping = false
        end
        return
    end

    if input.justPressed.UP then
        state.dialogSel = state.dialogSel - 1
        if state.dialogSel < 1 then state.dialogSel = math.max(1, #state.dialogAssets) end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.DOWN then
        state.dialogSel = state.dialogSel + 1
        if state.dialogSel > #state.dialogAssets then state.dialogSel = 1 end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.LEFT then
        state.dialogCategory = state.dialogCategory - 1
        if state.dialogCategory < 1 then state.dialogCategory = #CATEGORIES end
        state.dialogSubfolder = nil
        refreshSubfolders()
        refreshAssetList()
        state.dialogSel = 1
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.RIGHT then
        state.dialogCategory = state.dialogCategory + 1
        if state.dialogCategory > #CATEGORIES then state.dialogCategory = 1 end
        state.dialogSubfolder = nil
        refreshSubfolders()
        refreshAssetList()
        state.dialogSel = 1
        if sfx then sfx.play("ui_move") end
    end

    -- L1/R1 cycle subfolders
    if #state.dialogSubfolders > 0 then
        if input.justPressed.L1 then
            state.dialogSubfolder = (state.dialogSubfolder or 1) - 1
            if state.dialogSubfolder < 1 then state.dialogSubfolder = #state.dialogSubfolders end
            refreshAssetList()
            state.dialogSel = 1
            if sfx then sfx.play("ui_move") end
        end
        if input.justPressed.DEBUG then  -- R1
            state.dialogSubfolder = (state.dialogSubfolder or 1) + 1
            if state.dialogSubfolder > #state.dialogSubfolders then state.dialogSubfolder = 1 end
            refreshAssetList()
            state.dialogSel = 1
            if sfx then sfx.play("ui_move") end
        end
    end

    if input.justPressed.A then
        if sfx then sfx.play("ui_select") end
        if state.dialogMode == "load" then
            if #state.dialogAssets > 0 then
                local name = state.dialogAssets[state.dialogSel]
                doLoad(name)
                state.dialogMode = nil
            end
        elseif state.dialogMode == "save" then
            state.dialogTyping = true
        end
    end

    if input.justPressed.B or input.justPressed.START then
        state.dialogMode = nil
        if sfx then sfx.play("ui_select") end
    end
end

local function updatePreview(dt)
    if not state.playing then return end
    state.playTimer = state.playTimer + dt
    local interval = 1 / state.fps
    if state.playTimer >= interval then
        state.playTimer = state.playTimer - interval
        state.activeFrame = state.activeFrame + 1
        if state.activeFrame > state.numFrames then
            state.activeFrame = 1
        end
    end
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

local checkerImgData, checkerImg  -- lazily built checkerboard

local function ensureCheckerImage()
    if checkerImg then return end
    checkerImgData = love.image.newImageData(CANVAS_SIZE, CANVAS_SIZE)
    for y = 0, CANVAS_SIZE - 1 do
        for x = 0, CANVAS_SIZE - 1 do
            local c = ((x + y) % 2 == 0) and PALETTE[29] or PALETTE[30]
            if c then
                checkerImgData:setPixel(x, y, c[1], c[2], c[3], 1)
            else
                checkerImgData:setPixel(x, y, 0.13, 0.13, 0.13, 1)
            end
        end
    end
    checkerImg = love.graphics.newImage(checkerImgData)
    checkerImg:setFilter("nearest", "nearest")
end

local function drawCanvas()
    local zoom = ZOOM_LEVELS[state.zoomIdx]
    local viewPixels = math.floor(CANVAS_VP_W / zoom)
    if viewPixels > CANVAS_SIZE then viewPixels = CANVAS_SIZE end
    local viewPixelsY = math.floor(CANVAS_VP_H / zoom)
    if viewPixelsY > CANVAS_SIZE then viewPixelsY = CANVAS_SIZE end

    -- Center view on cursor
    local halfViewX = math.floor(viewPixels / 2)
    local halfViewY = math.floor(viewPixelsY / 2)
    local ox = state.curX - halfViewX
    local oy = state.curY - halfViewY
    ox = math.max(1, math.min(CANVAS_SIZE - viewPixels + 1, ox))
    oy = math.max(1, math.min(CANVAS_SIZE - viewPixelsY + 1, oy))

    -- Cache for stable mouse mapping
    viewOX, viewOY = ox, oy

    -- Rebuild composite image if dirty or frame changed
    if state.activeFrame ~= canvasLastFrame then
        canvasImgDirty = true
        canvasLastFrame = state.activeFrame
    end
    if canvasImgDirty then
        rebuildCanvasImage()
    end

    -- Use a quad to select the visible portion of the canvas
    local qx = ox - 1   -- 0-based pixel offset into the image
    local qy = oy - 1
    local qw = viewPixels
    local qh = viewPixelsY

    -- Checkerboard background (drawn as scaled image, clipped to viewport)
    ensureCheckerImage()
    local checkerQuad = love.graphics.newQuad(qx, qy, qw, qh, CANVAS_SIZE, CANVAS_SIZE)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(checkerImg, checkerQuad, CANVAS_X, CANVAS_Y, 0, zoom, zoom)

    -- Draw composited canvas image on top (transparent pixels show checker)
    local canvasQuad = love.graphics.newQuad(qx, qy, qw, qh, CANVAS_SIZE, CANVAS_SIZE)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvasImg, canvasQuad, CANVAS_X, CANVAS_Y, 0, zoom, zoom)

    -- Pixel grid overlay (toggle with G, only when zoom >= 2)
    if gridOn and zoom >= 2 then
        gfx.setColorRGBA(1, 1, 1, 0.15)
        -- Vertical lines
        for sx = 0, viewPixels do
            local screenGX = CANVAS_X + sx * zoom
            love.graphics.rectangle("fill", screenGX, CANVAS_Y, 1, viewPixelsY * zoom)
        end
        -- Horizontal lines
        for sy = 0, viewPixelsY do
            local screenGY = CANVAS_Y + sy * zoom
            love.graphics.rectangle("fill", CANVAS_X, screenGY, viewPixels * zoom, 1)
        end
    end

    -- Icon sheet grid overlay
    if state.mode == MODE_ICON_SHEET then
        for g = 0, ICON_COLS do
            local gx = g * ICON_CELL + 1
            local screenGX = CANVAS_X + (gx - ox) * zoom
            if screenGX >= CANVAS_X and screenGX <= CANVAS_X + viewPixels * zoom then
                gfx.setColorRGBA(1, 1, 1, 0.25)
                love.graphics.rectangle("fill", screenGX, CANVAS_Y, 1, viewPixelsY * zoom)
            end
        end
        for g = 0, ICON_ROWS do
            local gy = g * ICON_CELL + 1
            local screenGY = CANVAS_Y + (gy - oy) * zoom
            if screenGY >= CANVAS_Y and screenGY <= CANVAS_Y + viewPixelsY * zoom then
                gfx.setColorRGBA(1, 1, 1, 0.25)
                love.graphics.rectangle("fill", CANVAS_X, screenGY, viewPixels * zoom, 1)
            end
        end

        -- Highlight selected cell
        local cx1, cy1, cx2, cy2 = cellBounds(state.iconCell)
        local scx = CANVAS_X + (cx1 - ox) * zoom
        local scy = CANVAS_Y + (cy1 - oy) * zoom
        local scw = ICON_CELL * zoom
        local sch = ICON_CELL * zoom
        if scx + scw > CANVAS_X and scx < CANVAS_X + viewPixels * zoom
           and scy + sch > CANVAS_Y and scy < CANVAS_Y + viewPixelsY * zoom then
            if state.cellLock then
                gfx.setColorRGBA(1, 1, 0, 0.4)
            else
                gfx.setColorRGBA(0.3, 0.6, 1, 0.25)
            end
            love.graphics.rectangle("fill", scx, scy, scw, sch)
            local borderCol = state.cellLock and 14 or 9
            gfx.rectLine(scx, scy, scw, sch, borderCol)
        end
    end

    -- Texture safe area overlay
    if state.mode == MODE_TEXTURE and state.texSafeArea then
        gfx.setColorRGBA(0, 0, 0, 0.35)
        local pano = isPanorama()
        -- Top/bottom borders (skip for panorama — full height is paintable)
        if not pano then
            local sy1 = CANVAS_Y + math.max(0, (1 - oy)) * zoom
            local sy2 = CANVAS_Y + math.max(0, (SAFE_Y1 - oy)) * zoom
            if sy2 > sy1 then
                love.graphics.rectangle("fill", CANVAS_X, sy1, viewPixels * zoom, sy2 - sy1)
            end
            local sy3 = CANVAS_Y + math.max(0, (SAFE_Y2 + 1 - oy)) * zoom
            local sy4 = CANVAS_Y + viewPixelsY * zoom
            if sy4 > sy3 then
                love.graphics.rectangle("fill", CANVAS_X, sy3, viewPixels * zoom, sy4 - sy3)
            end
        end
        -- Left/right borders (always shown, use full viewport height for panorama)
        local safeTop = pano and CANVAS_Y or (CANVAS_Y + math.max(0, (SAFE_Y1 - oy)) * zoom)
        local safeBot = pano and (CANVAS_Y + viewPixelsY * zoom) or (CANVAS_Y + math.max(0, (SAFE_Y2 + 1 - oy)) * zoom)
        local safeH = safeBot - safeTop
        if safeH > 0 then
            local sx1 = CANVAS_X
            local sx2 = CANVAS_X + math.max(0, (SAFE_X1 - ox)) * zoom
            if sx2 > sx1 then
                love.graphics.rectangle("fill", sx1, safeTop, sx2 - sx1, safeH)
            end
            local sx3 = CANVAS_X + math.max(0, (SAFE_X2 + 1 - ox)) * zoom
            local sx4 = CANVAS_X + viewPixels * zoom
            if sx4 > sx3 then
                love.graphics.rectangle("fill", sx3, safeTop, sx4 - sx3, safeH)
            end
        end
    end

    -- Cursor crosshair
    local curSX = CANVAS_X + (state.curX - ox) * zoom
    local curSY = CANVAS_Y + (state.curY - oy) * zoom
    if curSX >= CANVAS_X and curSX + zoom <= CANVAS_X + CANVAS_VP_W
       and curSY >= CANVAS_Y and curSY + zoom <= CANVAS_Y + CANVAS_VP_H then
        local bright = (state.cursorBlink % 30) < 15
        local cc = bright and 15 or 0
        gfx.rectLine(curSX, curSY, zoom, zoom, cc)
        if zoom >= 2 then
            gfx.rectLine(curSX - 1, curSY - 1, zoom + 2, zoom + 2, cc)
        end
    end

    -- Canvas border
    gfx.rectLine(CANVAS_X - 1, CANVAS_Y - 1, CANVAS_VP_W + 2, CANVAS_VP_H + 2, 8)

    -- Debug overlay
    if debugOverlay then
        local zoom_val = ZOOM_LEVELS[state.zoomIdx]
        local dy = CANVAS_Y + CANVAS_VP_H + 2
        gfx.print(string.format("M:%d,%d V:%.0f,%.0f P:%d,%d %s Z:%d G:%s",
            debugMx, debugMy, debugVx, debugVy, debugPx, debugPy,
            debugInside and "IN" or "OUT", zoom_val, gridOn and "ON" or "OFF"),
            CANVAS_X, dy - 10, 8)
    end
end

local function drawPalette()
    local px = PANEL_X
    local py = PANEL_Y
    local swatchSize = 7
    local cols = 8
    local rows = 4

    gfx.print("PALETTE", px, py, 7)
    py = py + 9

    for i = 0, 31 do
        local row = math.floor(i / cols)
        local col = i % cols
        local sx = px + col * (swatchSize + 1)
        local sy = py + row * (swatchSize + 1)

        if i == 0 then
            gfx.rect(sx, sy, swatchSize, swatchSize, 0)
            gfx.rectLine(sx, sy, swatchSize, swatchSize, 8)
            gfx.print("X", sx + 1, sy, 8)
        else
            local c = PALETTE[i]
            if c then
                gfx.setColorRGBA(c[1], c[2], c[3], 1)
                love.graphics.rectangle("fill", sx, sy, swatchSize, swatchSize)
            end
        end

        if i == state.color then
            gfx.rectLine(sx - 1, sy - 1, swatchSize + 2, swatchSize + 2, 15)
        end
    end

    return py + rows * (swatchSize + 1) + 2
end

local function drawLayerPanel(startY)
    local px = PANEL_X
    local py = startY

    gfx.print("LAYERS", px, py, 7)
    py = py + 9

    for i, name in ipairs(state.layerNames) do
        local active = (i == state.activeLayer)
        local visible = state.layerVisible[i] ~= false
        local col = active and 15 or (visible and 8 or 29)
        local prefix = active and ">" or " "
        local visIcon = visible and "" or "-"
        gfx.print(prefix .. visIcon .. name:upper(), px, py, col)
        py = py + 9
    end

    return py + 2
end

local function drawToolInfo(startY)
    local px = PANEL_X
    local py = startY

    -- Mode indicator
    local modeLabel = state.mode == MODE_ICON_SHEET and "ICONS"
                   or state.mode == MODE_PORTRAIT and "PORTRAIT"
                   or state.mode == MODE_TEXTURE and "TEXTURE"
                   or "SPRITE"
    gfx.print("MODE", px, py, 7)
    gfx.print(modeLabel, px + 30, py, 11)
    py = py + 9

    -- Texture kind + safe area indicators
    if state.mode == MODE_TEXTURE then
        gfx.print("KIND", px, py, 7)
        local kindLabel = TEXTURE_KIND_NAMES[state.textureKind]
        if isPanorama() then kindLabel = kindLabel .. " PANO" end
        gfx.print(kindLabel, px + 30, py, 14)
        py = py + 9
        gfx.print("SAFE", px, py, 7)
        local safeLabel = state.texSafeArea and "ON" or "OFF"
        if state.texSafeArea and isPanorama() then safeLabel = "X" end
        gfx.print(safeLabel, px + 30, py, state.texSafeArea and 10 or 8)
        if state.texSafeArea then
            local wrapLabel = state.texAutoWrap and BORDER_MODE_NAMES[state.texBorderMode] or "OFF"
            gfx.print(wrapLabel, px + 48, py, state.texAutoWrap and 11 or 8)
        end
        py = py + 9
        gfx.print("TILE", px, py, 7)
        gfx.print(state.texTilePreview and "ON" or "OFF", px + 30, py, state.texTilePreview and 10 or 8)
        py = py + 9
    end

    -- Tool
    gfx.print("TOOL", px, py, 7)
    gfx.print(TOOL_NAMES[state.tool], px + 30, py, 14)
    py = py + 9

    -- Color swatch
    gfx.print("COL", px, py, 7)
    if state.color == 0 then
        gfx.print("NONE", px + 24, py, 8)
    else
        local c = PALETTE[state.color]
        if c then
            gfx.setColorRGBA(c[1], c[2], c[3], 1)
            love.graphics.rectangle("fill", px + 24, py, 7, 7)
            gfx.rectLine(px + 24, py, 7, 7, 15)
        end
        gfx.print(tostring(state.color), px + 34, py, 7)
    end
    py = py + 9

    -- Cursor position
    gfx.print("POS", px, py, 7)
    gfx.print(state.curX .. "," .. state.curY, px + 24, py, 10)
    py = py + 9

    -- Icon cell info
    if state.mode == MODE_ICON_SHEET then
        gfx.print("CELL", px, py, 7)
        local cellCol = state.cellLock and 14 or 10
        local lockStr = state.cellLock and " LK" or ""
        gfx.print(tostring(state.iconCell) .. lockStr, px + 30, py, cellCol)
        py = py + 9
    end

    -- Zoom
    gfx.print("ZOOM", px, py, 7)
    gfx.print(ZOOM_LEVELS[state.zoomIdx] .. "X", px + 30, py, 10)
    py = py + 9

    return py + 2
end

local function drawFrameStrip()
    local y = STRIP_Y
    local x = 2

    gfx.print("FRAME", x, y + 1, 7)
    x = x + 36

    for i = 1, state.numFrames do
        local active = (i == state.activeFrame)
        local w = 14
        if active then
            gfx.rect(x, y, w, STRIP_H - 1, 1)
            gfx.print(tostring(i), x + 2, y + 2, 15)
        else
            gfx.rect(x, y, w, STRIP_H - 1, 8)
            gfx.print(tostring(i), x + 2, y + 2, 7)
        end
        gfx.rectLine(x, y, w, STRIP_H - 1, 0)
        x = x + w + 1
        if x > VIRT_W - 80 then break end
    end

    local ax = VIRT_W - 76
    if state.playing then
        gfx.print("STOP[P]", ax, y + 1, 12)
    else
        gfx.print("PLAY[P]", ax, y + 1, 10)
    end
    gfx.print("FPS:" .. state.fps, ax + 48, y + 1, 7)

    if state.dirty then
        gfx.print("*", VIRT_W - 6, y + 1, 14)
    end
end

local function drawPreview()
    local px = PANEL_X
    local py = CANVAS_VP_H + CANVAS_Y - 36
    local previewSize = 32

    gfx.print("PREVIEW", px, py - 9, 7)
    gfx.rect(px, py, previewSize, previewSize, 0)

    -- Draw composited canvas image scaled down to preview size
    if canvasImg then
        local previewScale = previewSize / CANVAS_SIZE
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvasImg, px, py, 0, previewScale, previewScale)
    end

    gfx.rectLine(px, py, previewSize, previewSize, 8)

    -- In icon mode, draw grid on preview too
    if state.mode == MODE_ICON_SHEET then
        local cellPreview = previewSize / ICON_COLS  -- 4px per cell
        for g = 1, ICON_COLS - 1 do
            local gx = px + g * cellPreview
            gfx.setColorRGBA(1, 1, 1, 0.2)
            love.graphics.rectangle("fill", gx, py, 1, previewSize)
        end
        for g = 1, ICON_ROWS - 1 do
            local gy = py + g * cellPreview
            gfx.setColorRGBA(1, 1, 1, 0.2)
            love.graphics.rectangle("fill", px, gy, previewSize, 1)
        end
    end
end

local function drawTilePreview()
    -- Ensure canvas image is up to date
    if canvasImgDirty or not canvasImg then
        rebuildCanvasImage()
    end
    if not canvasImg then return end

    -- Background
    gfx.rect(CANVAS_X, CANVAS_Y, CANVAS_VP_W, CANVAS_VP_H, 0)

    if isPanorama() then
        -- Panorama mode: horizontal strip with scrolling offset
        -- Scale to fill viewport height, tile horizontally
        local tileH = CANVAS_VP_H
        local tileScale = tileH / CANVAS_SIZE
        local tileW = math.floor(CANVAS_SIZE * tileScale)
        local panOff = state.texPanOffset or 0

        -- Set scissor to clip to viewport
        love.graphics.setScissor(CANVAS_X, CANVAS_Y, CANVAS_VP_W, CANVAS_VP_H)
        love.graphics.setColor(1, 1, 1, 1)

        -- Draw enough tiles to cover viewport, accounting for scroll offset
        local startTile = math.floor(panOff / tileW)
        local pixelOff = panOff - startTile * tileW
        local tilesNeeded = math.ceil((CANVAS_VP_W + pixelOff) / tileW) + 1
        for i = 0, tilesNeeded - 1 do
            local dx = CANVAS_X + i * tileW - pixelOff
            love.graphics.draw(canvasImg, dx, CANVAS_Y, 0, tileScale, tileScale)
        end

        love.graphics.setScissor()

        -- Label + scroll hint
        gfx.print("PANORAMA [T] </> SCROLL", CANVAS_X + 2, CANVAS_Y + 2, 14)
    else
        -- Normal 3x3 tiling preview
        local tileSize = math.floor(math.min(CANVAS_VP_W, CANVAS_VP_H) / 3)
        local gridW = tileSize * 3
        local gridH = tileSize * 3
        local ox = CANVAS_X + math.floor((CANVAS_VP_W - gridW) / 2)
        local oy = CANVAS_Y + math.floor((CANVAS_VP_H - gridH) / 2)
        local tileScale = tileSize / CANVAS_SIZE

        love.graphics.setColor(1, 1, 1, 1)
        for ty = 0, 2 do
            for tx = 0, 2 do
                love.graphics.draw(canvasImg, ox + tx * tileSize, oy + ty * tileSize, 0, tileScale, tileScale)
            end
        end

        -- Highlight center tile border
        local cx = ox + tileSize
        local cy = oy + tileSize
        gfx.rectLine(cx, cy, tileSize, tileSize, 14)
        if tileSize > 20 then
            gfx.rectLine(cx - 1, cy - 1, tileSize + 2, tileSize + 2, 14)
        end

        gfx.print("3x3 TILE PREVIEW [T]", CANVAS_X + 2, CANVAS_Y + 2, 14)
    end

    -- Canvas border
    gfx.rectLine(CANVAS_X - 1, CANVAS_Y - 1, CANVAS_VP_W + 2, CANVAS_VP_H + 2, 8)
end

local function drawMenuOverlay()
    if not state.menuOpen then return end

    gfx.setColorRGBA(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local mw, mh = 140, 14 + #MENU_ITEMS * 14
    local mx = math.floor((VIRT_W - mw) / 2)
    local my = math.floor((VIRT_H - mh) / 2)

    theme.window(gfx, mx, my, mw, mh, "MENU")

    local bx, by = mx + 4, my + 14
    for i, label in ipairs(MENU_ITEMS) do
        local sel = (i == state.menuSel)
        local ry = by + (i - 1) * 14
        if sel then
            gfx.rect(bx, ry, mw - 8, 12, 1)
        end
        gfx.print(label, bx + 4, ry + 2, sel and 15 or 0)
    end
end

local function drawModeSelectOverlay()
    if not state.modeSelectOpen then return end

    gfx.setColorRGBA(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local mw, mh = 160, 14 + #MODE_NAMES * 14 + 14
    local mx = math.floor((VIRT_W - mw) / 2)
    local my = math.floor((VIRT_H - mh) / 2)

    theme.window(gfx, mx, my, mw, mh, "SET MODE")

    local bx, by = mx + 4, my + 14
    gfx.print("CHANGES RESET CANVAS!", bx + 4, by, 4)
    by = by + 14

    for i, label in ipairs(MODE_NAMES) do
        local sel = (i == state.modeSelectSel)
        local ry = by + (i - 1) * 14
        if sel then
            gfx.rect(bx, ry, mw - 8, 12, 1)
        end
        local active = (MODE_VALUES[i] == state.mode)
        local text = label
        if active then text = text .. " *" end
        gfx.print(text, bx + 4, ry + 2, sel and 15 or 0)
    end
end

local function drawDialogOverlay()
    if not state.dialogMode then return end

    gfx.setColorRGBA(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local title = state.dialogMode == "save" and "SAVE SPRITE" or "LOAD SPRITE"
    local dw, dh = 200, 140
    local dx = math.floor((VIRT_W - dw) / 2)
    local dy = math.floor((VIRT_H - dh) / 2)

    local bx, by, bw, bh = theme.window(gfx, dx, dy, dw, dh, title)

    local cat = CATEGORIES[state.dialogCategory]
    gfx.print("< " .. cat:upper() .. " >", bx + 4, by + 2, 14)
    gfx.print("LR:CATEGORY", bx + bw - 72, by + 2, 8)

    -- Subfolder row (if category has subfolders)
    local subOffset = 0
    if #state.dialogSubfolders > 0 then
        subOffset = 12
        local subName = state.dialogSubfolders[state.dialogSubfolder or 1] or ""
        -- Show just the last segment for readability
        local shortName = subName:match("[^/]+$") or subName
        gfx.print("< " .. shortName:upper() .. " >", bx + 4, by + 14, 11)
        gfx.print("L1R1:SLOT", bx + bw - 60, by + 14, 8)
    end

    local listY = by + 14 + subOffset
    local listH = bh - 44 - subOffset
    gfx.rect(bx + 2, listY, bw - 4, listH, 0)
    gfx.rectLine(bx + 2, listY, bw - 4, listH, 8)

    if #state.dialogAssets == 0 then
        gfx.print("(empty)", bx + 8, listY + 4, 8)
    else
        local maxVisible = math.floor(listH / 10)
        local scrollOff = 0
        if state.dialogSel > maxVisible then
            scrollOff = state.dialogSel - maxVisible
        end
        for i = 1, math.min(#state.dialogAssets, maxVisible) do
            local idx = i + scrollOff
            if idx <= #state.dialogAssets then
                local name = state.dialogAssets[idx]
                local sel = (idx == state.dialogSel)
                local ry = listY + (i - 1) * 10
                if sel then
                    gfx.rect(bx + 3, ry + 1, bw - 6, 9, 1)
                end
                gfx.print(name, bx + 6, ry + 2, sel and 15 or 7)
            end
        end
    end

    if state.dialogMode == "save" then
        local ny = by + bh - 26
        gfx.print("NAME:", bx + 4, ny, 7)
        local nameX = bx + 36
        local nameW = bw - 40
        gfx.rect(nameX, ny - 1, nameW, 10, 0)
        gfx.rectLine(nameX, ny - 1, nameW, 10, state.dialogTyping and 15 or 8)
        local displayName = state.dialogName
        if state.dialogTyping then
            local blink = math.floor(love.timer.getTime() * 3) % 2 == 0
            if blink then displayName = displayName .. "_" end
        end
        gfx.print(displayName, nameX + 2, ny, 15)

        if state.dialogTyping then
            gfx.print("TYPE NAME, ENTER TO SAVE", bx + 4, by + bh - 12, 10)
        else
            gfx.print("A:EDIT NAME  B:CANCEL", bx + 4, by + bh - 12, 8)
        end
    else
        gfx.print("A:LOAD  B:CANCEL", bx + 4, by + bh - 12, 8)
    end
end

local function drawHelpOverlay()
    if not state.helpOpen then return end

    gfx.setColorRGBA(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local hw, hh = 260, 196
    local hx = math.floor((VIRT_W - hw) / 2)
    local hy = math.floor((VIRT_H - hh) / 2)

    theme.window(gfx, hx, hy, hw, hh, "HELP")

    local bx, by = hx + 6, hy + 16
    local col = 15
    local dim = 8
    local dy = 10

    gfx.print("ARROWS/DPAD  Move cursor",       bx, by,          col)
    gfx.print("A / LMB      Draw (pencil)",      bx, by + dy,     col)
    gfx.print("B / RMB      Erase",              bx, by + dy*2,   col)
    gfx.print("MMB          Eyedropper",          bx, by + dy*3,   col)
    gfx.print("X            Cycle tool",          bx, by + dy*4,   col)
    gfx.print("Y            Cycle color",         bx, by + dy*5,   col)
    gfx.print("L1 / R1      Prev/Next frame",    bx, by + dy*6,   col)
    if state.mode == MODE_TEXTURE then
        gfx.print("SELECT       Cycle tex kind",     bx, by + dy*7,   14)
    elseif state.mode == MODE_ICON_SHEET then
        gfx.print("SELECT       Toggle cell lock",   bx, by + dy*7,   14)
    else
        gfx.print("SELECT       Cycle layer",        bx, by + dy*7,   col)
    end
    gfx.print("V            Toggle layer vis",    bx, by + dy*8,   col)
    gfx.print("ESC          Close/Exit",           bx, by + dy*9,   col)
    gfx.print("START        Open menu",            bx, by + dy*10,  col)
    gfx.print("P            Play/Stop anim",      bx, by + dy*11,  col)
    gfx.print("] / [        Zoom in/out",         bx, by + dy*12,  col)
    gfx.print("+/-          FPS up/down",         bx, by + dy*13,  col)
    gfx.print("H            This help",           bx, by + dy*14,  col)
    if state.mode == MODE_ICON_SHEET then
        gfx.print("ICON: 8x8 grid, 16px cells",  bx, by + dy*15,  11)
    elseif state.mode == MODE_PORTRAIT then
        gfx.print("PORTRAIT: 8 part layers",      bx, by + dy*15,  11)
    elseif state.mode == MODE_TEXTURE then
        gfx.print("TEX: S=safe W=wrap T=tile D=dither", bx, by + dy*15,  11)
        if isPanorama() then
            gfx.print("BG=panorama (X-wrap only)", bx, by + dy*16, 14)
        end
    end

    gfx.print("PRESS H TO CLOSE", hx + 80, hy + hh - 14, dim)
end

----------------------------------------------------------------
-- Composite editor
----------------------------------------------------------------

initComposite = function(category)
    category = category or "portraits"
    state.compCategory = category
    state.compSlots = COMPOSITE_SLOTS[category] or {"layer1"}
    state.compStack = {}
    for _, slot in ipairs(state.compSlots) do
        state.compStack[slot] = { asset = nil }
    end
    state.compSlotSel = 1
    state.compPartSel = 1
    state.compParts = {}
    state.compPreviewCanvas = nil
    state.compPreviewDirty = true
    state.compFocus = "slots"
    local dp = COMP_DEFAULT_PIVOT[category] or { x = 64, y = 112 }
    state.compPivot = { x = dp.x, y = dp.y }
    state.dirty = false
end

local function refreshCompParts()
    local slot = state.compSlots[state.compSlotSel]
    local mapping = SLOT_SUBFOLDER[state.compCategory]
    local subfolder = mapping and mapping[slot]
    if subfolder then
        state.compParts = sprites.listAssets(state.compCategory, subfolder)
    else
        state.compParts = {}
    end
    -- Clamp selection
    if state.compPartSel > #state.compParts then
        state.compPartSel = math.max(1, #state.compParts)
    end
end

local function compSlotAssetPath(slot, partName)
    local mapping = SLOT_SUBFOLDER[state.compCategory]
    local subfolder = mapping and mapping[slot]
    if not subfolder then return nil end
    return state.compCategory .. "/" .. subfolder .. "/" .. partName
end

local function markCompDirty()
    state.compPreviewDirty = true
    state.dirty = true
end

local function compToAsset()
    return {
        meta = {
            id = state.dialogName ~= "" and state.dialogName or "untitled",
            category = state.compCategory,
            mode = "composite",
            w = 128,
            h = 128,
        },
        pivot = { x = state.compPivot.x, y = state.compPivot.y },
        slotsOrder = state.compSlots,
        stack = state.compStack,
    }
end

local function compFromAsset(asset)
    local meta = asset.meta or {}
    state.compCategory = meta.category or "portraits"
    state.compSlots = asset.slotsOrder or COMPOSITE_SLOTS[state.compCategory] or {}
    state.compStack = {}
    for _, slot in ipairs(state.compSlots) do
        local s = asset.stack and asset.stack[slot]
        state.compStack[slot] = s and { asset = s.asset } or { asset = nil }
    end
    state.compPivot = asset.pivot or { x = 64, y = 112 }
    state.compSlotSel = 1
    state.compPartSel = 1
    state.compFocus = "slots"
    state.compPreviewDirty = true
    state.dirty = false
    refreshCompParts()
end

local function doCompSave()
    if state.dialogName == "" then return false end
    local path = state.compCategory .. "/composites/" .. state.dialogName
    local asset = compToAsset()
    local ok, err = sprites.saveAsset(path, asset)
    if ok then
        state.dirty = false
    end
    return ok, err
end

local function doCompLoad(name)
    local path = state.compCategory .. "/composites/" .. name
    local asset, err = sprites.loadAsset(path)
    if asset then
        compFromAsset(asset)
        state.dialogName = name
        return true
    end
    return false, err
end

local function refreshCompAssetList()
    state.dialogAssets = sprites.listAssets(state.compCategory, "composites")
end

local function randomizeComposite()
    sprites.clearPartCache()
    for _, slot in ipairs(state.compSlots) do
        local weight = SLOT_WEIGHTS[slot] or 100
        local roll = math.random(1, 100)
        if roll <= weight then
            local mapping = SLOT_SUBFOLDER[state.compCategory]
            local subfolder = mapping and mapping[slot]
            if subfolder then
                local parts = sprites.listAssets(state.compCategory, subfolder)
                if #parts > 0 then
                    local pick = parts[math.random(1, #parts)]
                    state.compStack[slot] = { asset = state.compCategory .. "/" .. subfolder .. "/" .. pick }
                else
                    state.compStack[slot] = { asset = nil }
                end
            end
        else
            state.compStack[slot] = { asset = nil }
        end
    end
    markCompDirty()
    refreshCompParts()
end

local function renderCompPreview()
    if not state.compPreviewDirty then return end
    state.compPreviewDirty = false

    local asset = compToAsset()
    local canvas, err = sprites.renderCompositeToCanvas(asset)
    state.compPreviewCanvas = canvas
end

-- Composite menu items
local COMP_MENU_ITEMS = {"SAVE", "LOAD", "NEW", "SET MODE", "RANDOMIZE", "CLEAR ALL", "RESUME", "EXIT TO MENU"}

local function handleCompMenu()
    local sel = COMP_MENU_ITEMS[state.menuSel]
    if sel == "SAVE" then
        state.menuOpen = false
        state.dialogMode = "save"
        state.dialogSel = 1
        state.dialogTyping = (state.dialogName == "")
        refreshCompAssetList()
    elseif sel == "LOAD" then
        state.menuOpen = false
        state.dialogMode = "load"
        state.dialogSel = 1
        state.dialogTyping = false
        refreshCompAssetList()
    elseif sel == "NEW" then
        state.menuOpen = false
        initComposite(state.compCategory)
        state.dialogName = ""
    elseif sel == "SET MODE" then
        state.menuOpen = false
        state.modeSelectOpen = true
        for i, v in ipairs(MODE_VALUES) do
            if v == state.mode then state.modeSelectSel = i; break end
        end
    elseif sel == "RANDOMIZE" then
        state.menuOpen = false
        randomizeComposite()
        showStatus("RANDOMIZED!")
    elseif sel == "CLEAR ALL" then
        state.menuOpen = false
        for _, slot in ipairs(state.compSlots) do
            state.compStack[slot] = { asset = nil }
        end
        markCompDirty()
        showStatus("ALL SLOTS CLEARED")
    elseif sel == "RESUME" then
        state.menuOpen = false
    elseif sel == "EXIT TO MENU" then
        state.menuOpen = false
        toolOpen = false
    end
end

local function updateCompMenu(dt)
    if input.justPressed.UP then
        state.menuSel = state.menuSel - 1
        if state.menuSel < 1 then state.menuSel = #COMP_MENU_ITEMS end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.DOWN then
        state.menuSel = state.menuSel + 1
        if state.menuSel > #COMP_MENU_ITEMS then state.menuSel = 1 end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.A then
        if sfx then sfx.play("ui_select") end
        handleCompMenu()
    end
    if input.justPressed.B or input.justPressed.START then
        state.menuOpen = false
        if sfx then sfx.play("ui_select") end
    end
end

local function updateCompDialog(dt)
    if state.dialogTyping then
        if input.justPressed.START or input.justPressed.B then
            state.dialogMode = nil
            state.dialogTyping = false
        end
        return
    end

    if input.justPressed.UP then
        state.dialogSel = state.dialogSel - 1
        if state.dialogSel < 1 then state.dialogSel = math.max(1, #state.dialogAssets) end
        if sfx then sfx.play("ui_move") end
    end
    if input.justPressed.DOWN then
        state.dialogSel = state.dialogSel + 1
        if state.dialogSel > #state.dialogAssets then state.dialogSel = 1 end
        if sfx then sfx.play("ui_move") end
    end

    -- L1/R1 cycle composite category (portraits vs characters)
    local compCats = {}
    for cat, _ in pairs(COMPOSITE_SLOTS) do
        compCats[#compCats + 1] = cat
    end
    table.sort(compCats)
    if input.justPressed.L1 or input.justPressed.DEBUG then
        local curIdx = 1
        for i, c in ipairs(compCats) do
            if c == state.compCategory then curIdx = i; break end
        end
        if input.justPressed.L1 then
            curIdx = curIdx - 1
            if curIdx < 1 then curIdx = #compCats end
        else
            curIdx = curIdx + 1
            if curIdx > #compCats then curIdx = 1 end
        end
        state.compCategory = compCats[curIdx]
        refreshCompAssetList()
        state.dialogSel = 1
        if sfx then sfx.play("ui_move") end
    end

    if input.justPressed.A then
        if sfx then sfx.play("ui_select") end
        if state.dialogMode == "load" then
            if #state.dialogAssets > 0 then
                local name = state.dialogAssets[state.dialogSel]
                doCompLoad(name)
                state.dialogMode = nil
            end
        elseif state.dialogMode == "save" then
            state.dialogTyping = true
        end
    end

    if input.justPressed.B or input.justPressed.START then
        state.dialogMode = nil
        if sfx then sfx.play("ui_select") end
    end
end

local function updateComposite(dt)
    if state.dialogMode then
        updateCompDialog(dt)
        return
    end

    if state.menuOpen then
        updateCompMenu(dt)
        return
    end

    if state.modeSelectOpen then
        updateModeSelect(dt)
        return
    end

    if state.helpOpen then
        return
    end

    if input.justPressed.START and not escHandled then
        state.menuOpen = true
        state.menuSel = 1
        if sfx then sfx.play("ui_select") end
        escHandled = false
        return
    end
    escHandled = false

    -- LEFT/RIGHT switches focus between slots and parts
    if input.justPressed.LEFT and state.compFocus == "parts" then
        state.compFocus = "slots"
        if sfx then sfx.play("ui_move") end
        return
    end
    if input.justPressed.RIGHT and state.compFocus == "slots" then
        state.compFocus = "parts"
        refreshCompParts()
        if sfx then sfx.play("ui_move") end
        return
    end

    if state.compFocus == "slots" then
        -- UP/DOWN navigates slots
        if input.justPressed.UP then
            state.compSlotSel = state.compSlotSel - 1
            if state.compSlotSel < 1 then state.compSlotSel = #state.compSlots end
            refreshCompParts()
            if sfx then sfx.play("ui_move") end
        end
        if input.justPressed.DOWN then
            state.compSlotSel = state.compSlotSel + 1
            if state.compSlotSel > #state.compSlots then state.compSlotSel = 1 end
            refreshCompParts()
            if sfx then sfx.play("ui_move") end
        end
        -- A on a slot = jump to parts browser
        if input.justPressed.A then
            state.compFocus = "parts"
            refreshCompParts()
            if sfx then sfx.play("ui_select") end
        end
        -- B on a slot = clear that slot
        if input.justPressed.B then
            local slot = state.compSlots[state.compSlotSel]
            state.compStack[slot] = { asset = nil }
            markCompDirty()
            showStatus(slot:upper() .. " CLEARED")
            if sfx then sfx.play("ui_select") end
        end
        -- X = randomize all
        if input.justPressed.X then
            randomizeComposite()
            showStatus("RANDOMIZED!")
            if sfx then sfx.play("ui_select") end
        end
    else  -- parts focus
        -- UP/DOWN navigates parts list
        if input.justPressed.UP then
            state.compPartSel = state.compPartSel - 1
            if state.compPartSel < 1 then state.compPartSel = math.max(1, #state.compParts) end
            if sfx then sfx.play("ui_move") end
        end
        if input.justPressed.DOWN then
            state.compPartSel = state.compPartSel + 1
            if state.compPartSel > #state.compParts then state.compPartSel = 1 end
            if sfx then sfx.play("ui_move") end
        end
        -- A = assign part to slot
        if input.justPressed.A then
            if #state.compParts > 0 then
                local slot = state.compSlots[state.compSlotSel]
                local partName = state.compParts[state.compPartSel]
                local path = compSlotAssetPath(slot, partName)
                state.compStack[slot] = { asset = path }
                markCompDirty()
                showStatus(slot:upper() .. " = " .. partName:upper())
                if sfx then sfx.play("ui_select") end
            end
        end
        -- B = back to slots
        if input.justPressed.B then
            state.compFocus = "slots"
            if sfx then sfx.play("ui_select") end
        end
    end
end

local function drawCompSlotList()
    local sx = 2
    local sy = 2
    local slotW = 120
    local lineH = 11

    local label = state.compCategory:upper() .. " COMPOSITE"
    gfx.print(label, sx, sy, 7)
    sy = sy + 11

    for i, slot in ipairs(state.compSlots) do
        local sel = (i == state.compSlotSel) and state.compFocus == "slots"
        local ry = sy + (i - 1) * lineH

        if sel then
            gfx.rect(sx, ry, slotW, lineH - 1, 1)
        end

        -- Slot name
        local slotCol = sel and 15 or 7
        gfx.print(slot:upper(), sx + 2, ry + 1, slotCol)

        -- Current part assignment (truncated)
        local slotData = state.compStack[slot]
        local partLabel = "(empty)"
        local partCol = 29
        if slotData and slotData.asset then
            partLabel = slotData.asset:match("[^/]+$") or slotData.asset
            partCol = sel and 14 or 10
        end
        if #partLabel > 12 then partLabel = partLabel:sub(1, 11) .. "~" end
        gfx.print(partLabel, sx + 46, ry + 1, partCol)
    end

    -- Highlight the active slot row even when in parts focus
    if state.compFocus == "parts" then
        local ry = sy + (state.compSlotSel - 1) * lineH
        gfx.rectLine(sx, ry, slotW, lineH - 1, 11)
    end

    return sy + #state.compSlots * lineH + 4
end

local function drawCompPreview(startY)
    renderCompPreview()

    local px = 2
    local py = startY
    local previewSize = 64

    gfx.print("PREVIEW", px, py, 7)
    py = py + 9

    gfx.rect(px, py, previewSize, previewSize, 0)

    if state.compPreviewCanvas then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(state.compPreviewCanvas, px, py, 0,
            previewSize / 128, previewSize / 128)
    end

    gfx.rectLine(px, py, previewSize, previewSize, 8)

    return py + previewSize + 4
end

local function drawCompPartBrowser()
    local bx = 124
    local by = 2
    local bw = VIRT_W - bx - 2
    local bh = CANVAS_VP_H + CANVAS_Y

    local slot = state.compSlots[state.compSlotSel] or "?"
    gfx.print("PARTS: " .. slot:upper(), bx, by, state.compFocus == "parts" and 14 or 8)
    by = by + 11

    local listH = bh - 14
    gfx.rect(bx, by, bw, listH, 0)
    gfx.rectLine(bx, by, bw, listH, state.compFocus == "parts" and 15 or 8)

    if #state.compParts == 0 then
        gfx.print("(no parts)", bx + 4, by + 4, 29)
    else
        local maxVisible = math.floor(listH / 10)
        local scrollOff = 0
        if state.compPartSel > maxVisible then
            scrollOff = state.compPartSel - maxVisible
        end
        for i = 1, math.min(#state.compParts, maxVisible) do
            local idx = i + scrollOff
            if idx <= #state.compParts then
                local name = state.compParts[idx]
                local sel = (idx == state.compPartSel) and state.compFocus == "parts"
                local ry = by + (i - 1) * 10
                if sel then
                    gfx.rect(bx + 1, ry + 1, bw - 2, 9, 1)
                end
                gfx.print(name, bx + 4, ry + 2, sel and 15 or 7)
            end
        end
    end
end

local function drawCompStatusBar()
    local y = VIRT_H - 10
    gfx.print("LR:FOCUS  UD:NAV  A:SELECT  B:CLEAR  X:RANDOM  START:MENU", 2, y, 8)
end

local function drawCompMenuOverlay()
    if not state.menuOpen then return end

    gfx.setColorRGBA(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local mw, mh = 140, 14 + #COMP_MENU_ITEMS * 14
    local mx = math.floor((VIRT_W - mw) / 2)
    local my = math.floor((VIRT_H - mh) / 2)

    theme.window(gfx, mx, my, mw, mh, "MENU")

    local bx, by = mx + 4, my + 14
    for i, label in ipairs(COMP_MENU_ITEMS) do
        local sel = (i == state.menuSel)
        local ry = by + (i - 1) * 14
        if sel then
            gfx.rect(bx, ry, mw - 8, 12, 1)
        end
        gfx.print(label, bx + 4, ry + 2, sel and 15 or 0)
    end
end

local function drawCompDialogOverlay()
    if not state.dialogMode then return end

    gfx.setColorRGBA(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local title = state.dialogMode == "save" and "SAVE COMPOSITE" or "LOAD COMPOSITE"
    local dw, dh = 200, 140
    local dx = math.floor((VIRT_W - dw) / 2)
    local dy = math.floor((VIRT_H - dh) / 2)

    local bx, by, bw, bh = theme.window(gfx, dx, dy, dw, dh, title)

    gfx.print(state.compCategory:upper() .. "/COMPOSITES", bx + 4, by + 2, 14)
    gfx.print("L1R1:TYPE", bx + bw - 60, by + 2, 8)

    local listY = by + 14
    local listH = bh - 44
    gfx.rect(bx + 2, listY, bw - 4, listH, 0)
    gfx.rectLine(bx + 2, listY, bw - 4, listH, 8)

    if #state.dialogAssets == 0 then
        gfx.print("(empty)", bx + 8, listY + 4, 8)
    else
        local maxVisible = math.floor(listH / 10)
        local scrollOff = 0
        if state.dialogSel > maxVisible then
            scrollOff = state.dialogSel - maxVisible
        end
        for i = 1, math.min(#state.dialogAssets, maxVisible) do
            local idx = i + scrollOff
            if idx <= #state.dialogAssets then
                local name = state.dialogAssets[idx]
                local sel = (idx == state.dialogSel)
                local ry = listY + (i - 1) * 10
                if sel then
                    gfx.rect(bx + 3, ry + 1, bw - 6, 9, 1)
                end
                gfx.print(name, bx + 6, ry + 2, sel and 15 or 7)
            end
        end
    end

    if state.dialogMode == "save" then
        local ny = by + bh - 26
        gfx.print("NAME:", bx + 4, ny, 7)
        local nameX = bx + 36
        local nameW = bw - 40
        gfx.rect(nameX, ny - 1, nameW, 10, 0)
        gfx.rectLine(nameX, ny - 1, nameW, 10, state.dialogTyping and 15 or 8)
        local displayName = state.dialogName
        if state.dialogTyping then
            local blink = math.floor(love.timer.getTime() * 3) % 2 == 0
            if blink then displayName = displayName .. "_" end
        end
        gfx.print(displayName, nameX + 2, ny, 15)

        if state.dialogTyping then
            gfx.print("TYPE NAME, ENTER TO SAVE", bx + 4, by + bh - 12, 10)
        else
            gfx.print("A:EDIT NAME  B:CANCEL", bx + 4, by + bh - 12, 8)
        end
    else
        gfx.print("A:LOAD  B:CANCEL", bx + 4, by + bh - 12, 8)
    end
end

local function drawCompHelpOverlay()
    if not state.helpOpen then return end

    gfx.setColorRGBA(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    local hw, hh = 260, 140
    local hx = math.floor((VIRT_W - hw) / 2)
    local hy = math.floor((VIRT_H - hh) / 2)

    theme.window(gfx, hx, hy, hw, hh, "COMPOSITE HELP")

    local bx, by = hx + 6, hy + 16
    local col = 15
    local dy = 10

    gfx.print("LEFT/RIGHT   Switch slots/parts", bx, by,         col)
    gfx.print("UP/DOWN      Navigate list",       bx, by + dy,    col)
    gfx.print("A            Select / Assign",     bx, by + dy*2,  col)
    gfx.print("B            Clear slot / Back",   bx, by + dy*3,  col)
    gfx.print("X            Randomize all",        bx, by + dy*4,  col)
    gfx.print("START        Open menu",            bx, by + dy*5,  col)
    gfx.print("H            This help",            bx, by + dy*6,  col)

    gfx.print("Assemble composite from part assets", bx, by + dy*8, 11)
    gfx.print("PRESS H TO CLOSE", hx + 80, hy + hh - 14, 8)
end

local function drawComposite()
    gfx.cls(0)

    local slotsEndY = drawCompSlotList()
    drawCompPreview(slotsEndY)
    drawCompPartBrowser()

    -- Status bar
    if state.statusMsg then
        gfx.print(state.statusMsg, 2, VIRT_H - 8, 14)
    else
        drawCompStatusBar()
    end

    -- Dirty indicator
    if state.dirty then
        gfx.print("*", VIRT_W - 6, 2, 14)
    end

    -- Title
    local titleText = "COMPOSITE"
    if state.dialogName ~= "" then
        titleText = titleText .. " - " .. state.dialogName:upper()
    end
    gfx.print(titleText, 70, VIRT_H - 8, 8)

    -- Overlays
    drawCompMenuOverlay()
    drawCompDialogOverlay()
    drawModeSelectOverlay()
    drawCompHelpOverlay()
end

----------------------------------------------------------------
-- Tool module API (state = host state; editor state in state.tools.spriteEditor)
----------------------------------------------------------------

function tool.open(hostState, console)
    hostState.tools = hostState.tools or {}
    hostState.tools.spriteEditor = hostState.tools.spriteEditor or {}
    local s = hostState.tools.spriteEditor
    if not s.inited then
        gfx     = console.gfx
        input   = console.input
        sfx     = console.sfx
        theme   = require("console.theme")
        sprites = console.sprites
        consoleRef = console
        if not CATEGORIES then CATEGORIES = sprites.listCategories() end
        initPalette()
        initEditorState(s)
        state = s
        initLayers()
        s.inited = true
    end
    s.open = true
    state = s
    canvasImgDirty = true
end

function tool.close(hostState, console)
    if hostState.tools and hostState.tools.spriteEditor then
        hostState.tools.spriteEditor.open = false
    end
end

function tool.isOpen(hostState)
    return hostState.tools and hostState.tools.spriteEditor and hostState.tools.spriteEditor.open
end

function tool.update(dt, hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor then return end
    state = hostState.tools.spriteEditor
    if not state.open then return end

    state.cursorBlink = (state.cursorBlink or 0) + 1

    -- Tick status message
    if state.statusTimer > 0 then
        state.statusTimer = state.statusTimer - dt
        if state.statusTimer <= 0 then
            state.statusMsg = nil
        end
    end

    -- Composite mode has its own update path
    if state.mode == MODE_COMPOSITE then
        updateComposite(dt)
        return
    end

    updatePreview(dt)

    if state.helpOpen then
        return
    end

    if state.modeSelectOpen then
        updateModeSelect(dt)
        return
    end

    if state.dialogMode then
        updateDialog(dt)
        return
    end

    if state.menuOpen then
        updateMenu(dt)
        return
    end

    -- START opens menu (skip if ESC already handled this frame)
    if input.justPressed.START and not (state._escHandled) then
        state.menuOpen = true
        state.menuSel = 1
        if sfx then sfx.play("ui_select") end
        return
    end
    state._escHandled = false

    if not state.playing then
        updateEditor(dt)
    end

    -- Mouse input (runs after keyboard so cursor position is correct)
    updateMouse(dt)
end

function tool.draw(hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor or not hostState.tools.spriteEditor.open then return end
    state = hostState.tools.spriteEditor

    -- Composite mode has its own draw path
    if state.mode == MODE_COMPOSITE then
        drawComposite()
        return
    end

    gfx.cls(0)

    -- In texture mode with tile preview, replace canvas with 3x3 tiled view
    if state.mode == MODE_TEXTURE and state.texTilePreview then
        drawTilePreview()
    else
        drawCanvas()
    end

    -- Right panel
    local panelY = drawPalette()
    panelY = drawLayerPanel(panelY)
    panelY = drawToolInfo(panelY)
    drawPreview()

    -- Bottom strip
    drawFrameStrip()

    -- Overlays
    drawMenuOverlay()
    drawModeSelectOverlay()
    drawDialogOverlay()
    drawHelpOverlay()

    -- Status bar
    if state.statusMsg then
        gfx.print(state.statusMsg, CANVAS_X, VIRT_H - 8, 14)
    else
        local titleText = "SPRITE EDITOR"
        if state.dialogName ~= "" then
            titleText = titleText .. " - " .. state.dialogName:upper()
        end
        if state.mode == MODE_TEXTURE then
            titleText = titleText .. " [" .. TEXTURE_KIND_NAMES[state.textureKind] .. "]"
        end
        gfx.print(titleText, CANVAS_X, VIRT_H - 8, 8)
    end
end

function tool.input(action, pressed, hostState, console)
    if not pressed or not hostState.tools or not hostState.tools.spriteEditor then return false end
    state = hostState.tools.spriteEditor
    if not state.open then return false end
    if action == "START" then
        state.open = false
        if sfx then sfx.play("ui_select") end
        return true
    end
    return false
end

function tool.keypressed(key, hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor then return end
    state = hostState.tools.spriteEditor
    if not state.open then return end

    -- ESC: close overlays first, then close tool
    if key == "escape" then
        state._escHandled = true
        if state.helpOpen then
            state.helpOpen = false
        elseif state.dialogMode then
            if state.dialogTyping then
                state.dialogTyping = false
                if state.dialogName == "" then state.dialogMode = nil end
            else
                state.dialogMode = nil
            end
        elseif state.modeSelectOpen then
            state.modeSelectOpen = false
        elseif state.menuOpen then
            state.menuOpen = false
        else
            state.open = false
        end
        if sfx then sfx.play("ui_select") end
        return
    end

    -- Help toggle
    if key == "h" then
        if state.dialogMode or state.menuOpen or state.modeSelectOpen then return end
        state.helpOpen = not state.helpOpen
        return
    end

    -- Grid overlay toggle
    if key == "g" then
        if state.dialogMode or state.menuOpen or state.modeSelectOpen or state.dialogTyping then return end
        gridOn = not gridOn
        return
    end

    -- Debug overlay toggle
    if key == "f3" then
        debugOverlay = not debugOverlay
        return
    end

    -- Dialog typing mode (shared by pixel and composite modes)
    if state.dialogMode and state.dialogTyping then
        if key == "return" then
            if state.dialogName ~= "" then
                local ok, err
                if state.mode == MODE_COMPOSITE then
                    ok, err = doCompSave()
                else
                    ok, err = doSave()
                end
                if ok then
                    state.dialogMode = nil
                    state.dialogTyping = false
                    showStatus("SAVED!")
                else
                    showStatus("ERROR: " .. (err or "unknown"))
                end
            end
        elseif key == "backspace" then
            state.dialogName = state.dialogName:sub(1, -2)
        elseif key == "escape" then
            state.dialogTyping = false
            if state.dialogName == "" then
                state.dialogMode = nil
            end
        end
        return
    end

    -- Composite mode has no extra key bindings
    if state.mode == MODE_COMPOSITE then return end

    -- Layer visibility toggle
    if key == "v" and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        local li = state.activeLayer
        state.layerVisible[li] = not state.layerVisible[li]
        canvasImgDirty = true
        local vis = state.layerVisible[li] and "ON" or "OFF"
        showStatus(state.layerNames[li]:upper() .. " " .. vis)
        return
    end

    -- Texture safe area toggle (S key)
    if key == "s" and state.mode == MODE_TEXTURE
       and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.texSafeArea = not state.texSafeArea
        state.texAutoWrap = state.texSafeArea  -- auto-wrap follows safe area
        showStatus("SAFE AREA: " .. (state.texSafeArea and "ON" or "OFF"))
        if state.texAutoWrap then
            regenerateBorder(state.activeLayer, state.activeFrame)
        end
        return
    end

    -- Texture wrap mode cycle (W key)
    if key == "w" and state.mode == MODE_TEXTURE and state.texSafeArea
       and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        if not state.texAutoWrap then
            state.texAutoWrap = true
            state.texBorderMode = BORDER_WRAP
        elseif state.texBorderMode == BORDER_WRAP then
            state.texBorderMode = BORDER_MIRROR
        else
            state.texAutoWrap = false
        end
        local label = state.texAutoWrap and BORDER_MODE_NAMES[state.texBorderMode] or "OFF"
        showStatus("BORDER: " .. label)
        if state.texAutoWrap then
            regenerateBorder(state.activeLayer, state.activeFrame)
        end
        return
    end

    -- Texture 3x3 tiling preview toggle (T key)
    if key == "t" and state.mode == MODE_TEXTURE
       and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.texTilePreview = not state.texTilePreview
        showStatus("TILE PREVIEW: " .. (state.texTilePreview and "ON" or "OFF"))
        return
    end

    -- Dither seam (D key) — applies checker dither across wrap seam boundaries
    if key == "d" and state.mode == MODE_TEXTURE and state.texSafeArea
       and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        regenerateBorder(state.activeLayer, state.activeFrame)
        ditherSeam(state.activeLayer, state.activeFrame)
        showStatus("DITHER SEAM APPLIED")
        return
    end

    -- Play/stop toggle
    if key == "p" and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.playing = not state.playing
        state.playTimer = 0
        return
    end

    -- Zoom
    if key == "]" and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.zoomIdx = math.min(#ZOOM_LEVELS, state.zoomIdx + 1)
        return
    end
    if key == "[" and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.zoomIdx = math.max(1, state.zoomIdx - 1)
        return
    end

    -- FPS adjust
    if (key == "=" or key == "+") and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.fps = math.min(30, state.fps + 1)
        return
    end
    if key == "-" and not state.menuOpen and not state.dialogMode and not state.modeSelectOpen then
        state.fps = math.max(1, state.fps - 1)
        return
    end
end

function tool.textinput(text, hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor then return end
    state = hostState.tools.spriteEditor
    if not state.open then return end
    if state.dialogMode == "save" and state.dialogTyping then
        local ch = text:match("[%w_%-]")
        if ch and #state.dialogName < 24 then
            state.dialogName = state.dialogName .. ch
        end
    end
end

function tool.mousepressed(x, y, button, hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor then return false end
    state = hostState.tools.spriteEditor
    if not state.open then return false end
    mouseDown[button] = true

    local vx, vy = mouseToVirtual(x, y)

    -- Skip clicks when overlays are open
    if state.helpOpen or state.menuOpen or state.dialogMode or state.modeSelectOpen then
        return true
    end
    if state.mode == MODE_COMPOSITE then return true end

    -- Palette click
    local palIdx = virtualToPalette(vx, vy)
    if palIdx then
        state.color = palIdx
        if sfx then sfx.play("ui_move") end
        return true
    end

    -- Layer click
    local layerIdx = virtualToLayer(vx, vy)
    if layerIdx then
        state.activeLayer = layerIdx
        if sfx then sfx.play("ui_move") end
        return true
    end

    -- Middle click = eyedropper (sample color under cursor)
    if button == 3 then
        local px, py = virtualToCanvas(vx, vy)
        if px and py then
            for li = 1, #state.layerNames do
                if state.layerVisible[li] ~= false then
                    local col = getPixel(li, state.activeFrame, px, py)
                    if col > 0 then
                        state.color = col
                        if sfx then sfx.play("ui_move") end
                        return true
                    end
                end
            end
        end
    end
    return true
end

function tool.mousereleased(x, y, button, hostState, console)
    if not hostState.tools or not hostState.tools.spriteEditor then return false end
    state = hostState.tools.spriteEditor
    if not state.open then return false end
    mouseDown[button] = false

    -- Clear stroke tracking so next click starts fresh
    if button == 1 or button == 2 then
        lastStrokePx, lastStrokePy = nil, nil
        regenerateBorder(state.activeLayer, state.activeFrame)
    end
    return true
end

return tool

local sprites = {}

----------------------------------------------------------------
-- Folder structure
----------------------------------------------------------------
local SPRITE_ROOT = "sprites"

local CATEGORIES = {
    "hands",
    "weapons",
    "monsters",
    "characters",
    "props",
    "portraits",
    "icons",
    "textures",
}

-- Subfolders that must exist under certain categories
local SUBFOLDERS = {
    portraits  = { "parts/body", "parts/face", "parts/eyes", "parts/mouth", "parts/hair", "parts/clothes", "parts/extras", "parts/armor", "composites" },
    characters = { "templates", "parts/base", "parts/clothes", "parts/hair", "parts/armor", "parts/extras", "parts/weapon", "composites" },
    textures   = { "walls", "floor", "roof", "bg" },
}

----------------------------------------------------------------
-- Serialization (self-contained, no external deps)
----------------------------------------------------------------
local serialize

serialize = function(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "number" then
        if val ~= val then return "0" end
        if val == math.huge then return "math.huge" end
        if val == -math.huge then return "-math.huge" end
        -- preserve integers vs floats
        if val == math.floor(val) and val >= -2^31 and val <= 2^31-1 then
            return string.format("%d", val)
        end
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        local inner = indent .. "  "
        -- array portion first (sequential integer keys)
        local arrayLen = #val
        for i = 1, arrayLen do
            parts[#parts + 1] = inner .. serialize(val[i], inner)
        end
        -- hash portion (non-integer or out-of-range keys)
        for k, v in pairs(val) do
            local isArrayKey = type(k) == "number" and k >= 1 and k <= arrayLen and k == math.floor(k)
            if not isArrayKey then
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. serialize(k, "") .. "]"
                end
                parts[#parts + 1] = inner .. keyStr .. " = " .. serialize(v, inner)
            end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

----------------------------------------------------------------
-- RLE encoding/decoding
-- Format: "idx:run,idx:run,..." scanning row-major (y=1..h, x=1..w)
----------------------------------------------------------------

--- Encode a 2D pixel array [y][x] into an RLE string.
--- @param pixels2D table  pixels2D[y][x] = palette index (0..31)
--- @param w number  width
--- @param h number  height
--- @return string
function sprites.encodeRLE(pixels2D, w, h)
    local parts = {}
    local curVal = nil
    local curRun = 0

    for y = 1, h do
        local row = pixels2D[y]
        for x = 1, w do
            local v = row[x]
            if v == curVal then
                curRun = curRun + 1
            else
                if curVal ~= nil then
                    parts[#parts + 1] = curVal .. ":" .. curRun
                end
                curVal = v
                curRun = 1
            end
        end
    end
    -- flush last run
    if curVal ~= nil then
        parts[#parts + 1] = curVal .. ":" .. curRun
    end

    return table.concat(parts, ",")
end

--- Decode an RLE string back into a 2D pixel array [y][x].
--- @param rleStr string  RLE-encoded string
--- @param w number  width
--- @param h number  height
--- @return table pixels2D
function sprites.decodeRLE(rleStr, w, h)
    local pixels2D = {}
    for y = 1, h do
        pixels2D[y] = {}
        for x = 1, w do
            pixels2D[y][x] = 0
        end
    end

    if not rleStr or rleStr == "" then
        return pixels2D
    end

    local px = 1
    local py = 1
    for pair in rleStr:gmatch("[^,]+") do
        local valStr, runStr = pair:match("^(%d+):(%d+)$")
        if valStr and runStr then
            local val = tonumber(valStr)
            local run = tonumber(runStr)
            for _ = 1, run do
                if py <= h and px <= w then
                    pixels2D[py][px] = val
                    px = px + 1
                    if px > w then
                        px = 1
                        py = py + 1
                    end
                end
            end
        end
    end

    return pixels2D
end

----------------------------------------------------------------
-- PNG export
----------------------------------------------------------------

--- Build the full 32-color palette as RGBA tables (0-255 range).
--- Used internally for PNG export.
local function buildPalette256()
    local pal = {}
    -- CGA 16 from gfx module
    for i = 0, 15 do
        local c = love.graphics and sprites._gfxPalette and sprites._gfxPalette[i]
        if c then
            pal[i] = { math.floor(c[1] * 255 + 0.5),
                        math.floor(c[2] * 255 + 0.5),
                        math.floor(c[3] * 255 + 0.5), 255 }
        else
            pal[i] = { 0, 0, 0, 255 }
        end
    end
    -- Extended 16
    local ext = {
        {0.40, 0.26, 0.13},  {0.80, 0.52, 0.25},  {1.00, 0.60, 0.40},
        {0.80, 0.40, 0.30},  {0.53, 0.27, 0.20},  {0.20, 0.40, 0.20},
        {0.60, 0.80, 0.40},  {0.40, 0.60, 0.80},  {0.20, 0.20, 0.40},
        {0.60, 0.40, 0.60},  {0.80, 0.60, 0.80},  {1.00, 0.80, 0.60},
        {0.80, 0.80, 0.60},  {0.40, 0.40, 0.40},  {0.13, 0.13, 0.13},
        {0.93, 0.93, 0.93},
    }
    for i, c in ipairs(ext) do
        pal[15 + i] = { math.floor(c[1] * 255 + 0.5),
                         math.floor(c[2] * 255 + 0.5),
                         math.floor(c[3] * 255 + 0.5), 255 }
    end
    return pal
end

--- Composite layers for a single frame into ImageData.
--- Layers are composited bottom-to-top (last index = bottom, drawn first).
--- @param asset table   loaded asset with .layers (RLE strings), .layerNames, .width, .height
--- @param frameIndex number  1-based frame index
--- @return love.ImageData
function sprites.compositeFrame(asset, frameIndex)
    local w = asset.width or 128
    local h = asset.height or 128
    local imgData = love.image.newImageData(w, h)
    local pal = buildPalette256()
    local numLayers = #(asset.layerNames or {})

    -- Draw bottom layer first (highest index), then overlay upper layers
    for li = numLayers, 1, -1 do
        local layerFrames = asset.layers and asset.layers[li]
        if layerFrames then
            local rle = layerFrames[frameIndex]
            if rle and type(rle) == "string" then
                local pixels2D = sprites.decodeRLE(rle, w, h)
                for y = 1, h do
                    for x = 1, w do
                        local col = pixels2D[y][x]
                        if col > 0 then
                            local c = pal[col]
                            if c then
                                imgData:setPixel(x - 1, y - 1,
                                    c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255)
                            end
                        end
                    end
                end
            end
        end
    end

    return imgData
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

--- Ensure a directory exists, creating it (and parents) if needed.
--- love.filesystem.createDirectory handles recursive creation.
local function ensureDir(path)
    local info = love.filesystem.getInfo(path)
    if not info then
        love.filesystem.createDirectory(path)
    end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

--- Create all sprite category folders and subfolders in the save directory.
function sprites.ensureFolders()
    ensureDir(SPRITE_ROOT)
    ensureDir("exports")
    for _, cat in ipairs(CATEGORIES) do
        local catPath = SPRITE_ROOT .. "/" .. cat
        ensureDir(catPath)
        ensureDir("exports/" .. cat)
        -- create subfolders if defined
        local subs = SUBFOLDERS[cat]
        if subs then
            for _, sub in ipairs(subs) do
                ensureDir(catPath .. "/" .. sub)
            end
        end
    end
end

--- Return the list of top-level category names.
--- @return string[]
function sprites.listCategories()
    local out = {}
    for _, cat in ipairs(CATEGORIES) do
        out[#out + 1] = cat
    end
    return out
end

--- Return the list of subfolders defined for a category.
--- @param category string  e.g. "portraits"
--- @return string[]
function sprites.listSubfolders(category)
    local subs = SUBFOLDERS[category]
    if not subs then return {} end
    local out = {}
    for _, s in ipairs(subs) do
        out[#out + 1] = s
    end
    return out
end

--- List .lua sprite assets in a category (optionally under a subpath).
--- Returns a list of basenames (without .lua extension).
--- @param category string  e.g. "weapons"
--- @param subpath  string? e.g. "parts/hair" or nil for root
--- @return string[]
function sprites.listAssets(category, subpath)
    local dir = SPRITE_ROOT .. "/" .. category
    if subpath and subpath ~= "" then
        dir = dir .. "/" .. subpath
    end
    local info = love.filesystem.getInfo(dir)
    if not info then return {} end

    local items = love.filesystem.getDirectoryItems(dir)
    local out = {}
    for _, file in ipairs(items) do
        local base = file:match("^(.+)%.lua$")
        if base then
            out[#out + 1] = base
        end
    end
    table.sort(out)
    return out
end

--- List texture assets for a specific texture kind.
--- @param kind string  e.g. "walls", "floor", "roof", "bg"
--- @return string[]  list of asset basenames
function sprites.listTextureAssets(kind)
    return sprites.listAssets("textures", kind)
end

--- Load a sprite asset table from a .lua file.
--- @param pathNoExt string  e.g. "weapons/test_sword" (relative to sprites/)
--- @return table|nil asset  the returned table, or nil on failure
--- @return string|nil err   error message on failure
function sprites.loadAsset(pathNoExt)
    local path = SPRITE_ROOT .. "/" .. pathNoExt .. ".lua"
    local info = love.filesystem.getInfo(path)
    if not info then
        return nil, "file not found: " .. path
    end
    local content, readErr = love.filesystem.read(path)
    if not content then
        return nil, "read error: " .. (readErr or "unknown")
    end
    local fn, loadErr = load(content)
    if not fn then
        return nil, "parse error: " .. (loadErr or "unknown")
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, "runtime error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "asset must return a table, got " .. type(result)
    end
    return result, nil
end

--- Save a sprite asset table to a .lua file.
--- Writes `return <table>\n` using the safe serializer.
--- @param pathNoExt  string  e.g. "weapons/test_sword"
--- @param assetTable table   the asset data
--- @return boolean ok
--- @return string|nil err
function sprites.saveAsset(pathNoExt, assetTable)
    if type(assetTable) ~= "table" then
        return false, "assetTable must be a table"
    end
    local path = SPRITE_ROOT .. "/" .. pathNoExt .. ".lua"
    local content = "return " .. serialize(assetTable) .. "\n"
    local ok, err = love.filesystem.write(path, content)
    return ok, err
end

--- Export a single frame of a sprite asset as a PNG file.
--- Composites all layers and writes to outPath in the save directory.
--- @param asset table       loaded asset table (with RLE layers)
--- @param frameIndex number which frame to export (1-based)
--- @param outPath string    output PNG path in save directory
--- @return boolean ok
--- @return string|nil err
function sprites.exportPNG(asset, frameIndex, outPath)
    if not asset or not asset.layers then
        return false, "invalid asset"
    end
    if frameIndex < 1 or frameIndex > (asset.numFrames or 1) then
        return false, "frame index out of range"
    end

    -- Ensure parent directory exists
    local dir = outPath:match("^(.+)/[^/]+$")
    if dir then ensureDir(dir) end

    local ok, imgData = pcall(sprites.compositeFrame, asset, frameIndex)
    if not ok then
        return false, "composite error: " .. tostring(imgData)
    end

    local encOk, fileData = pcall(imgData.encode, imgData, "png")
    if not encOk then
        return false, "encode error: " .. tostring(fileData)
    end

    local writeOk, writeErr = love.filesystem.write(outPath, fileData:getString())
    return writeOk, writeErr
end

--- Export all frames as individual PNGs into a subfolder.
--- Output: exports/<category>/<assetName>/<assetName>_frameNNN.png
--- @param asset table       loaded asset table (with RLE layers)
--- @param category string   category name
--- @param assetName string  asset name
--- @return number exported  count of frames exported
--- @return string|nil err   first error encountered, if any
function sprites.exportAllFrames(asset, category, assetName)
    local baseDir = "exports/" .. category .. "/" .. assetName
    ensureDir(baseDir)

    local exported = 0
    for fi = 1, (asset.numFrames or 1) do
        local outPath = baseDir .. "/" .. assetName .. string.format("_frame%03d.png", fi)
        local ok, err = sprites.exportPNG(asset, fi, outPath)
        if ok then
            exported = exported + 1
        else
            return exported, err
        end
    end
    return exported, nil
end

--- Export a single frame as an icon sheet (the full 128x128 as one PNG).
--- Output: exports/icons/<assetName>.png
--- @param asset table       loaded asset table (with RLE layers)
--- @param assetName string  asset name
--- @param frameIndex number which frame to export (default 1)
--- @return boolean ok
--- @return string|nil err
function sprites.exportIconSheet(asset, assetName, frameIndex)
    frameIndex = frameIndex or 1
    local outPath = "exports/icons/" .. assetName .. ".png"
    ensureDir("exports/icons")
    return sprites.exportPNG(asset, frameIndex, outPath)
end

--- Export all texture assets across all kinds to PNG files.
--- Output: exports/textures/{walls,floor,roof,bg}/<name>.png
--- @return number exported  total count of PNGs exported
--- @return number failed    total count of failures
function sprites.exportAllTextures()
    local kinds = { "walls", "floor", "roof", "bg" }
    local exported = 0
    local failed = 0
    for _, kind in ipairs(kinds) do
        local outDir = "exports/textures/" .. kind
        ensureDir(outDir)
        local names = sprites.listTextureAssets(kind)
        for _, name in ipairs(names) do
            local asset, err = sprites.loadAsset("textures/" .. kind .. "/" .. name)
            if asset then
                local outPath = outDir .. "/" .. name .. ".png"
                local ok, expErr = sprites.exportPNG(asset, 1, outPath)
                if ok then
                    exported = exported + 1
                else
                    failed = failed + 1
                end
            else
                failed = failed + 1
            end
        end
    end
    return exported, failed
end

--- Store a reference to the gfx palette for PNG export.
--- Called once during init to avoid circular dependency.
--- @param palette table  gfx.palette (indices 0-15, each {r,g,b} in 0-1 range)
function sprites.setPalette(palette)
    sprites._gfxPalette = palette
end

--- Create a 128x128 canvas suitable for sprite editing.
--- @return love.Canvas
function sprites.makeCanvas128()
    local canvas = love.graphics.newCanvas(128, 128)
    canvas:setFilter("nearest", "nearest")
    return canvas
end

----------------------------------------------------------------
-- Runtime Icon API
----------------------------------------------------------------

-- Cache for loaded icon sheet images: iconSheetCache[assetId] = love.Image
local iconSheetCache = {}

-- Icon sheet constants
local ICON_CELL = 16
local ICON_COLS = 8
local SHEET_SIZE = 128

--- Load an icon sheet asset and create a GPU image from it.
--- Caches the result so subsequent calls are free.
--- @param assetId string  asset path without extension, e.g. "icons/ui_icons"
--- @param frameIndex number? which frame to use (default 1)
--- @return love.Image|nil  the icon sheet image
--- @return string|nil err
function sprites.loadIconSheet(assetId, frameIndex)
    frameIndex = frameIndex or 1
    local cacheKey = assetId .. ":" .. frameIndex

    if iconSheetCache[cacheKey] then
        return iconSheetCache[cacheKey], nil
    end

    local asset, err = sprites.loadAsset(assetId)
    if not asset then
        return nil, err
    end

    local imgData = sprites.compositeFrame(asset, frameIndex)
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")

    iconSheetCache[cacheKey] = img
    return img, nil
end

--- Get a Quad for a specific icon cell from a 128x128 icon sheet.
--- @param index number  0-based cell index (0..63)
--- @return love.Quad
function sprites.getIconQuad(index)
    local col = index % ICON_COLS
    local row = math.floor(index / ICON_COLS)
    return love.graphics.newQuad(
        col * ICON_CELL, row * ICON_CELL,
        ICON_CELL, ICON_CELL,
        SHEET_SIZE, SHEET_SIZE
    )
end

--- Draw a single icon from a loaded icon sheet.
--- @param sheetImage love.Image  the loaded icon sheet image
--- @param index number  0-based cell index (0..63)
--- @param x number  screen x position
--- @param y number  screen y position
--- @param scale number? draw scale (default 1)
function sprites.drawIcon(sheetImage, index, x, y, scale)
    scale = scale or 1
    local quad = sprites.getIconQuad(index)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sheetImage, quad, x, y, 0, scale, scale)
end

--- Clear the icon sheet cache (call when assets change).
function sprites.clearIconCache()
    iconSheetCache = {}
end

----------------------------------------------------------------
-- Composite Asset API
----------------------------------------------------------------

-- Cache for loaded part assets: partCache[assetPath] = loaded asset table
local partCache = {}

--- Load a part asset (with caching).
--- @param assetPathNoExt string  e.g. "portraits/parts/hair/hair_spiky_01"
--- @return table|nil asset
--- @return string|nil err
function sprites.loadPart(assetPathNoExt)
    if partCache[assetPathNoExt] then
        return partCache[assetPathNoExt], nil
    end
    local asset, err = sprites.loadAsset(assetPathNoExt)
    if asset then
        partCache[assetPathNoExt] = asset
    end
    return asset, err
end

--- Clear the part cache (call when assets change).
function sprites.clearPartCache()
    partCache = {}
end

--- Render a composite asset to a LÖVE Canvas by loading and layering its parts.
--- Each slot in slotsOrder is looked up in stack; if its .asset is set, that part
--- is loaded, decoded, and drawn bottom-to-top.
--- @param compositeAsset table  composite asset with meta, slotsOrder, stack
--- @param frameIndex number?    frame index for parts (default 1)
--- @return love.Canvas|nil      the rendered canvas
--- @return string|nil err
function sprites.renderCompositeToCanvas(compositeAsset, frameIndex)
    frameIndex = frameIndex or 1
    local meta = compositeAsset.meta or {}
    local w = meta.w or 128
    local h = meta.h or 128
    local slotsOrder = compositeAsset.slotsOrder
    local stack = compositeAsset.stack
    if not slotsOrder or not stack then
        return nil, "composite missing slotsOrder or stack"
    end

    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")

    local pal = buildPalette256()

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    for _, slotName in ipairs(slotsOrder) do
        local slotData = stack[slotName]
        if slotData and slotData.asset and slotData.asset ~= "" then
            -- Strip "sprites/" prefix if present (loadAsset expects path relative to sprites/)
            local assetPath = slotData.asset
            if assetPath:sub(1, 8) == "sprites/" then
                assetPath = assetPath:sub(9)
            end

            local part, err = sprites.loadPart(assetPath)
            if part and part.layers then
                -- Find the layer that matches this slot name, or use first layer
                local layerIdx = 1
                if part.layerNames then
                    for li, ln in ipairs(part.layerNames) do
                        if ln == slotName then
                            layerIdx = li
                            break
                        end
                    end
                end

                local layerFrames = part.layers[layerIdx]
                if layerFrames then
                    local rle = layerFrames[frameIndex] or layerFrames[1]
                    if rle and type(rle) == "string" then
                        local pw = part.width or w
                        local ph = part.height or h
                        local pixels2D = sprites.decodeRLE(rle, pw, ph)
                        for y = 1, ph do
                            for x = 1, pw do
                                local col = pixels2D[y][x]
                                if col > 0 then
                                    local c = pal[col]
                                    if c then
                                        love.graphics.setColor(c[1]/255, c[2]/255, c[3]/255, 1)
                                        love.graphics.points(x - 1, y - 1)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    return canvas, nil
end

--- Render a composite asset to a love.Image (suitable for drawing/billboards).
--- Convenience wrapper around renderCompositeToCanvas.
--- @param compositeAsset table  composite asset with meta, slotsOrder, stack
--- @param frameIndex number?    frame index for parts (default 1)
--- @return love.Image|nil       the rendered image (nearest filter)
--- @return string|nil err
function sprites.renderCompositeToImage(compositeAsset, frameIndex)
    local canvas, err = sprites.renderCompositeToCanvas(compositeAsset, frameIndex)
    if not canvas then return nil, err end
    local imgData = canvas:newImageData()
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    imgData:release()
    canvas:release()
    return img, nil
end

--- Render a single layer+frame of a sprite asset to a love.Image.
--- @param asset table       loaded sprite asset with .layers, .layerNames, .width, .height
--- @param layerIndex number  1-based layer index
--- @param frameIndex number? 1-based frame index (default 1)
--- @return love.Image|nil
function sprites.renderLayerToImage(asset, layerIndex, frameIndex)
    frameIndex = frameIndex or 1
    local w = asset.width or 128
    local h = asset.height or 128
    local layerFrames = asset.layers and asset.layers[layerIndex]
    if not layerFrames then return nil end
    local rle = layerFrames[frameIndex] or layerFrames[1]
    if not rle or type(rle) ~= "string" then return nil end

    local pal = buildPalette256()
    local pixels2D = sprites.decodeRLE(rle, w, h)
    local imgData = love.image.newImageData(w, h)
    for y = 1, h do
        for x = 1, w do
            local col = pixels2D[y][x]
            if col > 0 then
                local c = pal[col]
                if c then
                    imgData:setPixel(x - 1, y - 1, c[1]/255, c[2]/255, c[3]/255, 1)
                end
            end
        end
    end
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    imgData:release()
    return img
end

--- Find layer index by name in an asset.
--- @param asset table   loaded asset with .layerNames
--- @param name string   layer name to find
--- @return number|nil   1-based index or nil
function sprites.findLayer(asset, name)
    if not asset.layerNames then return nil end
    for i, ln in ipairs(asset.layerNames) do
        if ln == name then return i end
    end
    return nil
end

return sprites

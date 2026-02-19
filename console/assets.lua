local assets = {}

assets.images = {}
assets.categories = {
    walls = {},
    floor = {},
    roof  = {},
    bg    = {},
}

-- Load a single image with caching
function assets.image(path, wrapMode)
    if assets.images[path] then
        return assets.images[path]
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok then
        return nil
    end
    img:setFilter("nearest", "nearest")
    if wrapMode then
        img:setWrap(wrapMode, wrapMode)
    end
    assets.images[path] = img
    return img
end

-- Scan textures/<name>/ and load all .png files into a category
function assets.loadCategory(name)
    local dir = "textures/" .. name
    local ok, items = pcall(love.filesystem.getDirectoryItems, dir)
    if not ok or not items then return end
    assets.categories[name] = assets.categories[name] or {}
    for _, file in ipairs(items) do
        local key = file:match("^(.+)%.png$")
        if key then
            local path = dir .. "/" .. file
            local img = assets.image(path, "repeat")
            if img then
                assets.categories[name][key] = img
            end
        end
    end
end

-- Retrieve a texture by category and key
function assets.get(category, key)
    local cat = assets.categories[category]
    if cat then return cat[key] end
    return nil
end

-- Load all standard categories
function assets.init()
    assets.loadCategory("walls")
    assets.loadCategory("floor")
    assets.loadCategory("roof")
    assets.loadCategory("bg")
end

--- Load user-made sprite textures from the save directory into asset categories.
--- Sprite textures in sprites/textures/{walls,floor,roof,bg}/ are composited
--- into love.Image objects and added to assets.categories alongside PNG textures.
--- @param spritesModule table  the console.sprites module (must have setPalette called already)
function assets.loadSpriteTextures(spritesModule)
    if not spritesModule then return end
    local kinds = { "walls", "floor", "roof", "bg" }
    -- Map sprite texture kinds to asset category names (same names)
    for _, kind in ipairs(kinds) do
        local assetNames = spritesModule.listTextureAssets(kind)
        for _, name in ipairs(assetNames) do
            -- Skip if a PNG texture with same key already exists
            if not assets.categories[kind][name] then
                local asset, err = spritesModule.loadAsset("textures/" .. kind .. "/" .. name)
                if asset then
                    local ok, imgData = pcall(spritesModule.compositeFrame, asset, 1)
                    if ok and imgData then
                        local img = love.graphics.newImage(imgData)
                        img:setFilter("nearest", "nearest")
                        if kind == "bg" then
                            img:setWrap("repeat", "clampzero")
                        else
                            img:setWrap("repeat", "repeat")
                        end
                        assets.categories[kind][name] = img
                        assets.images["sprite:" .. kind .. "/" .. name] = img
                    end
                end
            end
        end
    end
end

--- Reload a single sprite texture by kind and name (after editing/saving in sprite editor).
--- @param spritesModule table  the console.sprites module
--- @param kind string  "walls", "floor", "roof", or "bg"
--- @param name string  asset name (e.g. "brick_01")
function assets.reloadSpriteTexture(spritesModule, kind, name)
    if not spritesModule then return end
    local asset, err = spritesModule.loadAsset("textures/" .. kind .. "/" .. name)
    if not asset then return end
    local ok, imgData = pcall(spritesModule.compositeFrame, asset, 1)
    if not ok or not imgData then return end
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    if kind == "bg" then
        img:setWrap("repeat", "clampzero")
    else
        img:setWrap("repeat", "repeat")
    end
    assets.categories[kind][name] = img
    assets.images["sprite:" .. kind .. "/" .. name] = img
end

return assets

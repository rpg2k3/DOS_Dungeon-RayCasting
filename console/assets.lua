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

return assets

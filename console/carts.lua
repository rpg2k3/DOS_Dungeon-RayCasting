local carts = {}

carts.list = {}

function carts.register(cart)
    carts.list[#carts.list + 1] = cart
end

local function tryLoad(moduleName)
    local ok, cart = pcall(require, moduleName)
    if ok and cart then
        carts.register(cart)
    else
        print("Warning: failed to load cart: " .. moduleName)
    end
end

function carts.init()
    tryLoad("carts.raycast_dungeon")
end

function carts.get(index)
    return carts.list[index]
end

function carts.count()
    return #carts.list
end

return carts

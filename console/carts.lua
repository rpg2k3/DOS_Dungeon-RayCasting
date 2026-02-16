local carts = {}

carts.list = {}

function carts.register(cart)
    carts.list[#carts.list + 1] = cart
end

function carts.init()
    carts.register(require("carts.dos_dungeon"))
    carts.register(require("carts.raycast_dungeon"))
end

function carts.get(index)
    return carts.list[index]
end

function carts.count()
    return #carts.list
end

return carts

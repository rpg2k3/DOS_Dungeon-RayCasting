local app = require("console.app")

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    app.init()
end

function love.update(dt)
    app.update(dt)
end

function love.draw()
    app.draw()
end

function love.keypressed(key)
    app.keypressed(key)
end

function love.keyreleased(key)
    app.keyreleased(key)
end

function love.resize(w, h)
    app.resize(w, h)
end

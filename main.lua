local app = require("console.app")

function love.load(arg)
    love.graphics.setDefaultFilter("nearest", "nearest")
    -- Quick self-test modes
    for _, v in ipairs(arg or {}) do
        if v == "--test-sprites" then
            local test = require("test_sprites")
            test()
            love.event.quit(0)
            return
        elseif v == "--shader-test" then
            require("shader_test").run()
            return
        end
    end
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

function love.textinput(text)
    app.textinput(text)
end

function love.keyreleased(key)
    app.keyreleased(key)
end

function love.gamepadpressed(joy, button)
    app.gamepadpressed(joy, button)
end

function love.gamepadreleased(joy, button)
    app.gamepadreleased(joy, button)
end

function love.joystickadded(joy)
    app.joystickadded(joy)
end

function love.joystickremoved(joy)
    app.joystickremoved(joy)
end

function love.mousepressed(x, y, button)
    app.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    app.mousereleased(x, y, button)
end

function love.resize(w, h)
    app.resize(w, h)
end

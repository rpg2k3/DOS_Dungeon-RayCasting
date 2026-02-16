function love.conf(t)
    t.window.title = "Dungeon Console"
    t.window.width = 960
    t.window.height = 600
    t.window.resizable = true
    t.window.vsync = 1
    t.window.minwidth = 320
    t.window.minheight = 200
    t.modules.joystick = true
    t.modules.physics = false
    t.modules.video = false
end

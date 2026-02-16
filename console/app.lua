local gfx     = require("console.gfx")
local input   = require("console.input")
local sfx     = require("console.sfx")
local storage = require("console.storage")
local assets  = require("console.assets")
local carts   = require("console.carts")
local theme   = require("console.theme")

local app = {}

-- console object passed to carts
local console = {
    gfx     = gfx,
    sfx     = sfx,
    storage = storage,
    input   = input,
    assets  = assets,
    time    = { dt = 0, frame = 0, total = 0 },
    state   = "BOOT",
}

local state        = "BOOT"
local bootTimer    = 0
local bootDone     = false
local menuSel      = 1
local currentCart   = nil
local debugOn      = false
local crtOn        = false
local pauseSel     = 1   -- 1=Resume, 2=Reset, 3=Menu

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------
local function switchState(s)
    state = s
    console.state = s
end

local function initCart(cart)
    currentCart = cart
    if cart.init then cart.init(console) end
end

local function resetCart()
    if currentCart and currentCart.reset then
        currentCart.reset(console)
    end
end

local function fireCartInput(action, pressed)
    if currentCart and currentCart.input then
        currentCart.input(action, pressed, console)
    end
end

----------------------------------------------------------------
-- State: BOOT  (Win3.1 startup with progress bar window)
----------------------------------------------------------------
local BOOT_DUR = 1.8  -- total boot animation seconds

local function updateBoot(dt)
    bootTimer = bootTimer + dt
    if bootTimer >= BOOT_DUR then bootDone = true end
    if bootDone and input.justPressed.A then
        sfx.play("ui_select")
        switchState("MENU")
    end
end

local function drawBoot()
    -- dark background
    gfx.cls(0)

    -- centered "Starting Dungeon Console..." window
    local ww, wh = 220, 70
    local wx = math.floor((gfx.VIRT_W - ww) / 2)
    local wy = math.floor((gfx.VIRT_H - wh) / 2) - 10

    local bx, by, bw, bh = theme.window(gfx, wx, wy, ww, wh, "DUNGEON CONSOLE")

    -- status text
    local frac = math.min(1, bootTimer / BOOT_DUR)
    if frac < 1 then
        gfx.print("LOADING SYSTEM...", bx + 4, by + 4, theme.C.winText)
    else
        gfx.print("SYSTEM READY", bx + 4, by + 4, theme.C.winText)
    end

    -- progress bar
    theme.progressBar(gfx, bx + 4, by + 18, bw - 8, 14, frac)

    -- version text below window
    gfx.print("V1.0  (C) 2026", wx + 70, wy + wh + 8, 8)

    -- blink prompt once done
    if bootDone then
        local sub = "PRESS A TO CONTINUE"
        local blink = math.floor(bootTimer * 3) % 2 == 0
        if blink then
            local sw = gfx.textWidth(sub)
            gfx.print(sub, math.floor((gfx.VIRT_W - sw) / 2), wy + wh + 24, 7)
        end
    end
end

----------------------------------------------------------------
-- State: MENU  (Desktop + centered cart selector window)
----------------------------------------------------------------
local function updateMenu()
    local count = carts.count()
    if count == 0 then return end
    if input.justPressed.UP then
        menuSel = menuSel - 1
        if menuSel < 1 then menuSel = count end
        sfx.play("ui_move")
    end
    if input.justPressed.DOWN then
        menuSel = menuSel + 1
        if menuSel > count then menuSel = 1 end
        sfx.play("ui_move")
    end
    if input.justPressed.A then
        sfx.play("ui_select")
        local cart = carts.get(menuSel)
        if cart then
            initCart(cart)
            switchState("RUNNING")
        end
    end
end

local function drawMenu()
    local W, H = gfx.VIRT_W, gfx.VIRT_H
    local TASKBAR_H = 14

    -- desktop background
    theme.desktop(gfx, W, H - TASKBAR_H)

    -- centered window
    local ww, wh = 240, 140
    local wx = math.floor((W - ww) / 2)
    local wy = math.floor(((H - TASKBAR_H) - wh) / 2)

    local bx, by, bw, bh = theme.window(gfx, wx, wy, ww, wh, "PROGRAM MANAGER")

    -- instruction text
    gfx.print("SELECT CARTRIDGE:", bx + 4, by + 2, theme.C.winText)

    -- listbox
    local lx = bx + 4
    local ly = by + 14
    local lw = bw - 8
    local lh = bh - 38

    local items = {}
    local count = carts.count()
    for i = 1, count do
        local c = carts.get(i)
        items[i] = {
            text = c.title or "???",
            sub  = c.author and ("BY " .. c.author) or "",
        }
    end
    theme.listbox(gfx, lx, ly, lw, lh, items, menuSel, 20)

    -- launch button
    local btnW, btnH = 80, 16
    local btnX = bx + math.floor((bw - btnW) / 2)
    local btnY = by + bh - btnH - 2
    theme.button(gfx, btnX, btnY, btnW, btnH, "LAUNCH [A]")

    -- taskbar
    theme.taskbar(gfx, H - TASKBAR_H, W, TASKBAR_H, "DUNGEON CONSOLE", "V1.0")
end

----------------------------------------------------------------
-- State: RUNNING
----------------------------------------------------------------
local prevHeldSnap = {}

local function updateRunning(dt)
    -- check pause
    if input.justPressed.START then
        sfx.play("ui_select")
        pauseSel = 1
        switchState("PAUSED")
        return
    end
    -- debug toggle (CRT toggle when not in cart editor)
    if input.justPressed.DEBUG then
        debugOn = not debugOn
    end
    -- fire input events to cart
    for _, a in ipairs({"LEFT","RIGHT","UP","DOWN","A","B"}) do
        if input.justPressed[a] then fireCartInput(a, true) end
        if input.justReleased[a] then fireCartInput(a, false) end
    end
    -- update cart
    if currentCart and currentCart.update then
        currentCart.update(dt, console)
    end
end

local function drawRunning()
    if currentCart and currentCart.draw then
        currentCart.draw(console)
    end
end

----------------------------------------------------------------
-- State: PAUSED  (Win3.1 modal dialog over game)
----------------------------------------------------------------
local PAUSE_ITEMS = {"RESUME", "RESET", "QUIT TO MENU"}

local function updatePaused()
    -- navigate buttons
    if input.justPressed.UP then
        pauseSel = pauseSel - 1
        if pauseSel < 1 then pauseSel = #PAUSE_ITEMS end
        sfx.play("ui_move")
    end
    if input.justPressed.DOWN then
        pauseSel = pauseSel + 1
        if pauseSel > #PAUSE_ITEMS then pauseSel = 1 end
        sfx.play("ui_move")
    end
    if input.justPressed.A then
        sfx.play("ui_select")
        if pauseSel == 1 then
            switchState("RUNNING")
        elseif pauseSel == 2 then
            resetCart()
            switchState("RUNNING")
        elseif pauseSel == 3 then
            currentCart = nil
            switchState("MENU")
        end
    end
    -- quick resume
    if input.justPressed.START then
        sfx.play("ui_select")
        switchState("RUNNING")
    end
    if input.justPressed.B then
        sfx.play("ui_select")
        currentCart = nil
        switchState("MENU")
    end
end

local function drawPaused()
    -- draw game underneath
    drawRunning()

    -- dark overlay
    gfx.setColorRGBA(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, gfx.VIRT_W, gfx.VIRT_H)

    -- centered Win3.1 dialog window
    local pw, ph = 160, 90
    local px = math.floor((gfx.VIRT_W - pw) / 2)
    local py = math.floor((gfx.VIRT_H - ph) / 2)

    local bx, by, bw, bh = theme.window(gfx, px, py, pw, ph, "PAUSED")

    -- button column
    local btnW, btnH = bw - 16, 16
    local btnX = bx + 8
    for i, label in ipairs(PAUSE_ITEMS) do
        local btnY = by + 4 + (i - 1) * (btnH + 4)
        local sel = (i == pauseSel)
        theme.button(gfx, btnX, btnY, btnW, btnH, label, sel)
    end

    -- hint
    gfx.print("START:PAUSE  B:MENU", px + 10, py + ph - 14, theme.C.disabled)
end

----------------------------------------------------------------
-- Debug overlay
----------------------------------------------------------------
local function drawDebug()
    if not debugOn then return end
    local dw = 130
    local dh = 62
    local dx = gfx.VIRT_W - dw - 2
    local dy = 2
    gfx.rect(dx, dy, dw, dh, 0)
    gfx.panel(dx, dy, dw, dh, 10)
    gfx.print("FPS: " .. love.timer.getFPS(), dx + 4, dy + 4, 10)
    gfx.print("FRM: " .. console.time.frame, dx + 4, dy + 14, 10)
    local held = input.heldList()
    gfx.print("INP: " .. table.concat(held, ","), dx + 4, dy + 24, 10)
    gfx.print("ST: " .. state, dx + 4, dy + 34, 10)
    gfx.print("CRT: " .. (crtOn and "ON" or "OFF"), dx + 4, dy + 44, crtOn and 10 or 12)
end

----------------------------------------------------------------
-- Mouse cursor
----------------------------------------------------------------
local function drawCursor()
    -- only show cursor on menu/pause states
    if state ~= "MENU" and state ~= "PAUSED" and state ~= "BOOT" then return end

    local cursor = theme.getCursor()
    if not cursor then return end

    -- get mouse position in virtual coords
    local mx, my = love.mouse.getPosition()
    local vx = math.floor((mx - gfx.offsetX) / gfx.scale)
    local vy = math.floor((my - gfx.offsetY) / gfx.scale)

    -- clamp to virtual screen
    vx = math.max(0, math.min(gfx.VIRT_W - 1, vx))
    vy = math.max(0, math.min(gfx.VIRT_H - 1, vy))

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(cursor, vx, vy)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function app.init()
    gfx.init()
    input.init()
    sfx.init()
    storage.init()
    assets.init()
    carts.init()
    -- hide system cursor
    love.mouse.setVisible(false)
    switchState("BOOT")
end

function app.update(dt)
    console.time.dt    = dt
    console.time.frame = console.time.frame + 1
    console.time.total = console.time.total + dt

    local limit = (state == "RUNNING")
    input.update(limit)

    -- CRT toggle: DEBUG key when NOT in RUNNING state (where it goes to cart)
    if state ~= "RUNNING" and input.justPressed.DEBUG then
        crtOn = not crtOn
    end

    if     state == "BOOT"    then updateBoot(dt)
    elseif state == "MENU"    then updateMenu()
    elseif state == "RUNNING" then updateRunning(dt)
    elseif state == "PAUSED"  then updatePaused()
    end
end

function app.draw()
    gfx.beginDraw()

    if     state == "BOOT"    then drawBoot()
    elseif state == "MENU"    then drawMenu()
    elseif state == "RUNNING" then drawRunning()
    elseif state == "PAUSED"  then drawPaused()
    end

    drawCursor()
    drawDebug()
    gfx.endDraw(crtOn)
end

function app.keypressed(key)
    input.keypressed(key)
    -- Forward raw keypresses to cart (for edit mode keys like F1, S, L, R, P)
    if state == "RUNNING" and currentCart and currentCart.keypressed then
        currentCart.keypressed(key)
    end
end

function app.keyreleased(key)
    input.keyreleased(key)
end

function app.gamepadpressed(joy, button)
    input.gamepadpressed(joy, button)
end

function app.gamepadreleased(joy, button)
    input.gamepadreleased(joy, button)
end

function app.joystickadded(joy)
    input.joystickadded(joy)
end

function app.joystickremoved(joy)
    input.joystickremoved(joy)
end

function app.resize(w, h)
    gfx.resize()
end

return app

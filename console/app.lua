local gfx     = require("console.gfx")
local input   = require("console.input")
local sfx     = require("console.sfx")
local music   = require("console.music")
local storage = require("console.storage")
local assets  = require("console.assets")
local carts   = require("console.carts")
local theme   = require("console.theme")
local tracker = require("console.tracker")

local app = {}

-- console object passed to carts
local console = {
    gfx     = gfx,
    sfx     = sfx,
    music   = music,
    storage = storage,
    input   = input,
    assets  = assets,
    tracker = tracker,
    time    = { dt = 0, frame = 0, total = 0 },
    state   = "BOOT",
    texturesEnabled = true,
    brightness = 5,
    renderScale = "CRISP",  -- "CRISP" or "LOW"
    fovDeg = 60,            -- 45-90
    fogStrength = 1.0,      -- 0.0-2.0
    torchRadius = 5.0,      -- 1-10
    torchStrength = 1.0,    -- 0.0-2.0
}

local state        = "BOOT"
local bootTimer    = 0
local bootDone     = false
local menuSel      = 1
local currentCart   = nil
local debugOn      = false
local crtOn        = false
local musicOn      = false
local pauseSel     = 1   -- 1=Resume, 2=Reset, 3=Settings, 4=Menu
local settingsSel  = 1   -- selected row in settings dialog
local settingsFrom = nil -- "MENU" or "PAUSED", so we return to the right place

-- Settings defaults
local SETTINGS_DEFAULTS = {
    crt           = false,
    textures      = true,
    brightness    = 5,       -- 1-10 scale
    renderScale   = "CRISP", -- "CRISP" or "LOW"
    fovDeg        = 60,      -- 45-90
    fogStrength   = 10,      -- 0-20 (displayed as 0.0-2.0)
    torchRadius   = 50,      -- 10-100 (displayed as 1.0-10.0)
    torchStrength = 10,      -- 0-20 (displayed as 0.0-2.0)
}

-- Load settings from storage (or defaults)
local function loadSettings()
    crtOn = storage.get("set_crt", SETTINGS_DEFAULTS.crt)
    console.texturesEnabled = storage.get("set_textures", SETTINGS_DEFAULTS.textures)
    console.brightness = storage.get("set_brightness", SETTINGS_DEFAULTS.brightness)
    console.renderScale = storage.get("set_renderscale", SETTINGS_DEFAULTS.renderScale)
    console.fovDeg = storage.get("set_fov", SETTINGS_DEFAULTS.fovDeg)
    console.fogStrength = storage.get("set_fog", SETTINGS_DEFAULTS.fogStrength) / 10
    console.torchRadius = storage.get("set_torchrad", SETTINGS_DEFAULTS.torchRadius) / 10
    console.torchStrength = storage.get("set_torchstr", SETTINGS_DEFAULTS.torchStrength) / 10
end

-- Save current settings to storage
local function saveSettings()
    storage.set("set_crt", crtOn)
    storage.set("set_textures", console.texturesEnabled)
    storage.set("set_brightness", console.brightness)
    storage.set("set_renderscale", console.renderScale)
    storage.set("set_fov", console.fovDeg)
    storage.set("set_fog", math.floor(console.fogStrength * 10 + 0.5))
    storage.set("set_torchrad", math.floor(console.torchRadius * 10 + 0.5))
    storage.set("set_torchstr", math.floor(console.torchStrength * 10 + 0.5))
    storage.flush()
end

-- Reset all settings to defaults
local function resetSettings()
    crtOn = SETTINGS_DEFAULTS.crt
    console.texturesEnabled = SETTINGS_DEFAULTS.textures
    console.brightness = SETTINGS_DEFAULTS.brightness
    console.renderScale = SETTINGS_DEFAULTS.renderScale
    console.fovDeg = SETTINGS_DEFAULTS.fovDeg
    console.fogStrength = SETTINGS_DEFAULTS.fogStrength / 10
    console.torchRadius = SETTINGS_DEFAULTS.torchRadius / 10
    console.torchStrength = SETTINGS_DEFAULTS.torchStrength / 10
    saveSettings()
end

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
    -- B opens settings from menu
    if input.justPressed.B then
        sfx.play("ui_select")
        settingsSel = 2  -- skip header row
        settingsFrom = "MENU"
        switchState("SETTINGS")
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

    local count = carts.count()

    if count == 0 then
        -- Empty state: show diagnostics
        theme.bevelRect(gfx, lx, ly, lw, lh, false)
        gfx.rect(lx + 2, ly + 2, lw - 4, lh - 4, theme.C.listBg)

        local report = carts.report
        local dy = ly + 4
        gfx.print("NO CARTS FOUND!", lx + 4, dy, 4)
        dy = dy + 12
        gfx.print("Folder exists: " .. (report.folderExists and "YES" or "NO"), lx + 4, dy, theme.C.winText)
        dy = dy + 10
        gfx.print("Files in /carts: " .. #report.items, lx + 4, dy, theme.C.winText)
        dy = dy + 10
        gfx.print("Modules tried: " .. #report.attempted, lx + 4, dy, theme.C.winText)
        dy = dy + 10
        gfx.print("Errors: " .. #report.errors, lx + 4, dy, #report.errors > 0 and 4 or theme.C.winText)
        if #report.errors > 0 then
            dy = dy + 12
            local firstErr = report.errors[1]
            local errText = firstErr.module .. ":"
            gfx.print(errText, lx + 4, dy, 4)
            dy = dy + 10
            -- Truncate long error messages to fit the listbox
            local errMsg = firstErr.err
            if #errMsg > 40 then errMsg = errMsg:sub(1, 37) .. "..." end
            gfx.print(errMsg, lx + 4, dy, 12)
        end
        dy = dy + 14
        gfx.print("Check console output.", lx + 4, dy, theme.C.disabled)
    else
        local items = {}
        for i = 1, count do
            local c = carts.get(i)
            items[i] = {
                text = c.title or "???",
                sub  = c.author and ("BY " .. c.author) or "",
            }
        end
        theme.listbox(gfx, lx, ly, lw, lh, items, menuSel, 20)
    end

    -- launch button
    local btnW, btnH = 80, 16
    local btnX = bx + math.floor((bw - btnW) / 2)
    local btnY = by + bh - btnH - 2
    theme.button(gfx, btnX, btnY, btnW, btnH, count > 0 and "LAUNCH [A]" or "NO CARTS")

    -- settings hint (below launch button)
    gfx.print("[B] SETTINGS", bx + 4, btnY + btnH + 2, theme.C.disabled)

    -- taskbar
    theme.taskbar(gfx, H - TASKBAR_H, W, TASKBAR_H, "DUNGEON CONSOLE", "V1.0")
end

----------------------------------------------------------------
-- State: RUNNING
----------------------------------------------------------------
local prevHeldSnap = {}

local function updateRunning(dt)
    -- Tracker overlay takes priority when active
    if tracker.isActive() then
        tracker.update(dt)
        return
    end
    -- Skip pause trigger for one frame after tracker closes (escape key overlap)
    if tracker.wasJustClosed() then
        return
    end
    -- check pause
    if input.justPressed.START then
        sfx.play("ui_select")
        pauseSel = 1
        switchState("PAUSED")
        return
    end
    -- fire input events to cart
    for _, a in ipairs({"LEFT","RIGHT","UP","DOWN","A","B","SELECT","X","Y","L1"}) do
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
    -- Draw tracker overlay on top if active
    if tracker.isActive() then
        tracker.draw()
    end
end

----------------------------------------------------------------
-- State: PAUSED  (Win3.1 modal dialog over game)
----------------------------------------------------------------
local PAUSE_ITEMS = {"RESUME", "RESET", "SETTINGS", "QUIT TO MENU"}

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
            settingsSel = 2  -- skip header row
            settingsFrom = "PAUSED"
            switchState("SETTINGS")
        elseif pauseSel == 4 then
            currentCart = nil
            switchState("MENU")
        end
    end
    -- quick resume (START or B = go back)
    if input.justPressed.START or input.justPressed.B then
        sfx.play("ui_select")
        switchState("RUNNING")
    end
end

local function drawPaused()
    -- draw game underneath
    drawRunning()

    -- dark overlay
    gfx.setColorRGBA(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, gfx.VIRT_W, gfx.VIRT_H)

    -- centered Win3.1 dialog window
    local pw, ph = 160, 110
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
    gfx.print("START/B:RESUME  A:SELECT", px + 4, py + ph - 14, theme.C.disabled)
end

----------------------------------------------------------------
-- State: SETTINGS  (Win3.1 dialog with toggle/slider items)
----------------------------------------------------------------
-- Settings rows: { label, type, get, set }
-- type = "toggle", "slider", "action", or "header"
local SETTINGS_ROWS = {
    { label = "-- DISPLAY --",   type = "header" },
    { label = "CRT EFFECT",      type = "toggle",  key = "crt" },
    { label = "TEXTURES",        type = "toggle",  key = "textures" },
    { label = "BRIGHTNESS",      type = "slider",  key = "brightness", min = 1, max = 10, step = 1 },
    { label = "RENDER SCALE",    type = "toggle",  key = "renderScale" },
    { label = "FOV",             type = "slider",  key = "fov", min = 45, max = 90, step = 5 },
    { label = "-- LIGHTING --",  type = "header" },
    { label = "FOG",             type = "slider",  key = "fog", min = 0, max = 20, step = 1 },
    { label = "TORCH RADIUS",   type = "slider",  key = "torchRadius", min = 10, max = 100, step = 5 },
    { label = "TORCH POWER",    type = "slider",  key = "torchStrength", min = 0, max = 20, step = 1 },
    { label = "DEFAULTS",        type = "action" },
    { label = "BACK",            type = "action" },
}

local function getSettingVal(idx)
    local row = SETTINGS_ROWS[idx]
    if not row or not row.key then return nil end
    local k = row.key
    if k == "crt" then return crtOn
    elseif k == "textures" then return console.texturesEnabled
    elseif k == "brightness" then return console.brightness
    elseif k == "renderScale" then return console.renderScale == "LOW"
    elseif k == "fov" then return console.fovDeg
    elseif k == "fog" then return math.floor(console.fogStrength * 10 + 0.5)
    elseif k == "torchRadius" then return math.floor(console.torchRadius * 10 + 0.5)
    elseif k == "torchStrength" then return math.floor(console.torchStrength * 10 + 0.5)
    end
    return nil
end

local function setSettingVal(idx, val)
    local row = SETTINGS_ROWS[idx]
    if not row or not row.key then return end
    local k = row.key
    if k == "crt" then crtOn = val
    elseif k == "textures" then console.texturesEnabled = val
    elseif k == "brightness" then console.brightness = math.max(1, math.min(10, val))
    elseif k == "renderScale" then console.renderScale = val and "LOW" or "CRISP"
    elseif k == "fov" then console.fovDeg = math.max(45, math.min(90, val))
    elseif k == "fog" then console.fogStrength = math.max(0, math.min(20, val)) / 10
    elseif k == "torchRadius" then console.torchRadius = math.max(10, math.min(100, val)) / 10
    elseif k == "torchStrength" then console.torchStrength = math.max(0, math.min(20, val)) / 10
    end
end

-- Skip header rows when navigating settings
local function settingsNavUp()
    repeat
        settingsSel = settingsSel - 1
        if settingsSel < 1 then settingsSel = #SETTINGS_ROWS end
    until SETTINGS_ROWS[settingsSel].type ~= "header"
end

local function settingsNavDown()
    repeat
        settingsSel = settingsSel + 1
        if settingsSel > #SETTINGS_ROWS then settingsSel = 1 end
    until SETTINGS_ROWS[settingsSel].type ~= "header"
end

local function updateSettings()
    -- navigate
    if input.justPressed.UP then
        settingsNavUp()
        sfx.play("ui_move")
    end
    if input.justPressed.DOWN then
        settingsNavDown()
        sfx.play("ui_move")
    end

    local row = SETTINGS_ROWS[settingsSel]

    -- left/right for sliders
    if row.type == "slider" then
        local step = row.step or 1
        if input.justPressed.LEFT then
            setSettingVal(settingsSel, getSettingVal(settingsSel) - step)
            sfx.play("ui_move")
        end
        if input.justPressed.RIGHT then
            setSettingVal(settingsSel, getSettingVal(settingsSel) + step)
            sfx.play("ui_move")
        end
    end

    -- A to toggle or activate
    if input.justPressed.A then
        sfx.play("ui_select")
        if row.type == "toggle" then
            setSettingVal(settingsSel, not getSettingVal(settingsSel))
        elseif row.type == "action" then
            if row.label == "DEFAULTS" then
                resetSettings()
                -- skip to first non-header row
                settingsSel = 1
                if SETTINGS_ROWS[settingsSel].type == "header" then settingsNavDown() end
            elseif row.label == "BACK" then
                saveSettings()
                switchState(settingsFrom or "MENU")
            end
        end
    end

    -- B / START to go back
    if input.justPressed.B or input.justPressed.START then
        sfx.play("ui_select")
        saveSettings()
        switchState(settingsFrom or "MENU")
    end
end

-- Format a slider value for display
local function formatSliderVal(row, val)
    local k = row.key
    if k == "fog" or k == "torchStrength" then
        return string.format("%.1f", val / 10)
    elseif k == "torchRadius" then
        return string.format("%.1f", val / 10)
    elseif k == "fov" then
        return tostring(val)
    end
    return tostring(val)
end

local function drawSettings()
    -- draw appropriate background
    if settingsFrom == "PAUSED" then
        drawRunning()
        gfx.setColorRGBA(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, gfx.VIRT_W, gfx.VIRT_H)
    else
        local W, H = gfx.VIRT_W, gfx.VIRT_H
        theme.desktop(gfx, W, H - 14)
        theme.taskbar(gfx, H - 14, W, 14, "DUNGEON CONSOLE", "V1.0")
    end

    -- centered settings window (taller to fit all rows)
    local rowH = 13
    local numRows = #SETTINGS_ROWS
    local pw, ph = 210, 24 + numRows * rowH + 14
    local px = math.floor((gfx.VIRT_W - pw) / 2)
    local py = math.floor((gfx.VIRT_H - ph) / 2)

    local bx, by, bw, bh = theme.window(gfx, px, py, pw, ph, "SETTINGS")

    -- draw each row
    for i, row in ipairs(SETTINGS_ROWS) do
        local ry = by + 2 + (i - 1) * rowH
        local sel = (i == settingsSel)

        if row.type == "header" then
            -- Section header (not selectable)
            gfx.print(row.label, bx + 6, ry + 2, 14)
        elseif row.type == "toggle" then
            -- highlight bar
            if sel then
                gfx.rect(bx + 2, ry, bw - 4, rowH - 1, 1)
            end
            local textCol = sel and 15 or theme.C.winText
            local val = getSettingVal(i)
            gfx.print(row.label, bx + 6, ry + 2, textCol)
            -- checkbox
            local cbx = bx + bw - 44
            gfx.rect(cbx, ry + 2, 8, 8, 15)
            gfx.rectLine(cbx, ry + 2, 8, 8, 0)
            if val then
                gfx.print("X", cbx + 1, ry + 2, 0)
            end
            -- Label for renderScale toggle
            local label
            if row.key == "renderScale" then
                label = val and "LOW" or "CRISP"
            else
                label = val and "ON" or "OFF"
            end
            gfx.print(label, cbx + 12, ry + 2, textCol)
        elseif row.type == "slider" then
            if sel then
                gfx.rect(bx + 2, ry, bw - 4, rowH - 1, 1)
            end
            local textCol = sel and 15 or theme.C.winText
            local val = getSettingVal(i)
            gfx.print(row.label, bx + 6, ry + 2, textCol)
            -- slider bar
            local sbx = bx + bw - 80
            local sbw = 50
            gfx.rect(sbx, ry + 4, sbw, 4, 8)
            gfx.rectLine(sbx, ry + 4, sbw, 4, 0)
            -- filled portion
            local frac = (val - row.min) / (row.max - row.min)
            local fillW = math.floor(sbw * frac)
            if fillW > 0 then
                gfx.rect(sbx, ry + 4, fillW, 4, 9)
            end
            -- value text
            gfx.print(formatSliderVal(row, val), sbx + sbw + 4, ry + 2, textCol)
        elseif row.type == "action" then
            if sel then
                gfx.rect(bx + 2, ry, bw - 4, rowH - 1, 1)
            end
            local lw = gfx.textWidth(row.label)
            local lx = bx + math.floor((bw - lw) / 2)
            gfx.print(row.label, lx, ry + 2, sel and 14 or theme.C.disabled)
        end
    end

    -- hint at bottom
    gfx.print("A:TOGGLE  LR:SLIDER  B:BACK", px + 4, py + ph - 12, theme.C.disabled)
end

----------------------------------------------------------------
-- Debug overlay
----------------------------------------------------------------
local function drawDebug()
    if not debugOn then return end
    local dw = 130
    local dh = 72
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
    gfx.print("MUS: " .. (musicOn and "ON" or "OFF"), dx + 4, dy + 54, musicOn and 10 or 12)
end

----------------------------------------------------------------
-- Mouse cursor
----------------------------------------------------------------
local function drawCursor()
    -- only show cursor on menu/pause states
    if state ~= "MENU" and state ~= "PAUSED" and state ~= "BOOT" and state ~= "SETTINGS" then return end

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
    music.init()
    storage.init()
    loadSettings()
    assets.init()
    carts.init()
    tracker.init(console)
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
    music.update(dt)

    -- Debug overlay toggle (global, any state except SETTINGS)
    if state ~= "SETTINGS" and input.justPressed.DEBUG then
        debugOn = not debugOn
    end

    if     state == "BOOT"     then updateBoot(dt)
    elseif state == "MENU"     then updateMenu()
    elseif state == "RUNNING"  then updateRunning(dt)
    elseif state == "PAUSED"   then updatePaused()
    elseif state == "SETTINGS" then updateSettings()
    end
end

function app.draw()
    gfx.beginDraw()

    if     state == "BOOT"     then drawBoot()
    elseif state == "MENU"     then drawMenu()
    elseif state == "RUNNING"  then drawRunning()
    elseif state == "PAUSED"   then drawPaused()
    elseif state == "SETTINGS" then drawSettings()
    end

    drawCursor()
    drawDebug()
    gfx.endDraw(crtOn, console.brightness)
end

function app.keypressed(key)
    input.keypressed(key)
    -- Music toggle (global, any state) — but NOT when tracker is active
    if key == "m" and not tracker.isActive() then
        musicOn = music.toggle()
    end
    -- Tracker captures all keys when active
    if state == "RUNNING" and tracker.isActive() then
        tracker.keypressed(key)
        return
    end
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

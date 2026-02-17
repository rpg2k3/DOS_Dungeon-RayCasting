local input = {}

local keyMap = {
    left    = "LEFT",
    right   = "RIGHT",
    up      = "UP",
    down    = "DOWN",
    space   = "A",
    ["return"] = "A",
    lshift  = "B",
    backspace = "B",
    escape  = "START",
    r       = "RESET",
    c       = "DEBUG",
}

-- Gamepad button -> action mapping (LÖVE gamepad button names)
local padMap = {
    dpup          = "UP",
    dpdown        = "DOWN",
    dpleft        = "LEFT",
    dpright       = "RIGHT",
    a             = "A",
    b             = "B",
    x             = "X",
    y             = "Y",
    start         = "START",
    back          = "SELECT",
    leftshoulder  = "L1",
    rightshoulder = "DEBUG",
}

local GAMEPLAY = {"LEFT", "RIGHT", "UP", "DOWN", "A", "B"}
local META     = {"START", "RESET", "DEBUG", "SELECT", "X", "Y", "L1"}
local ALL      = {"LEFT", "RIGHT", "UP", "DOWN", "A", "B", "START", "RESET", "DEBUG", "SELECT", "X", "Y", "L1"}

input.held        = {}
input.justPressed = {}
input.justReleased= {}

local rawHeld    = {}   -- keyboard held state
local padHeld    = {}   -- gamepad button held state
local axisHeld   = {}   -- analog stick held state (current frame)
local axisPrev   = {}   -- analog stick held state (previous frame)
local prevHeld   = {}   -- combined held from last frame (for edge detection)

-- Active joystick (first connected gamepad, or last used)
input.activeJoy = nil

local DEADZONE = 0.35

function input.init()
    for _, a in ipairs(ALL) do
        input.held[a]         = false
        input.justPressed[a]  = false
        input.justReleased[a] = false
        rawHeld[a]            = false
        padHeld[a]            = false
        axisHeld[a]           = false
        axisPrev[a]           = false
        prevHeld[a]           = false
    end
    -- Pick up any already-connected joystick
    local joys = love.joystick.getJoysticks()
    for _, j in ipairs(joys) do
        if j:isGamepad() then
            input.activeJoy = j
            break
        end
    end
end

----------------------------------------------------------------
-- Keyboard callbacks (unchanged)
----------------------------------------------------------------
function input.keypressed(key)
    local action = keyMap[key]
    if action then rawHeld[action] = true end
end

function input.keyreleased(key)
    local action = keyMap[key]
    if action then rawHeld[action] = false end
end

----------------------------------------------------------------
-- Gamepad button callbacks
----------------------------------------------------------------
function input.gamepadpressed(joy, button)
    input.activeJoy = joy
    local action = padMap[button]
    if action then padHeld[action] = true end
end

function input.gamepadreleased(joy, button)
    local action = padMap[button]
    if action then padHeld[action] = false end
end

----------------------------------------------------------------
-- Joystick hot-plug
----------------------------------------------------------------
function input.joystickadded(joy)
    if not input.activeJoy and joy:isGamepad() then
        input.activeJoy = joy
    end
end

function input.joystickremoved(joy)
    if input.activeJoy == joy then
        input.activeJoy = nil
        -- Clear pad state since that controller is gone
        for _, a in ipairs(ALL) do
            padHeld[a]  = false
            axisHeld[a] = false
            axisPrev[a] = false
        end
        -- Try to pick another gamepad
        local joys = love.joystick.getJoysticks()
        for _, j in ipairs(joys) do
            if j:isGamepad() then
                input.activeJoy = j
                break
            end
        end
    end
end

----------------------------------------------------------------
-- Update (called once per frame)
----------------------------------------------------------------
function input.update(limitActions)
    -- save previous combined held
    for _, a in ipairs(ALL) do
        prevHeld[a] = input.held[a]
    end

    -- poll analog stick
    for _, a in ipairs(ALL) do
        axisPrev[a] = axisHeld[a]
    end
    -- reset axis state
    axisHeld.LEFT  = false
    axisHeld.RIGHT = false
    axisHeld.UP    = false
    axisHeld.DOWN  = false

    local joy = input.activeJoy
    if joy and joy:isConnected() and joy:isGamepad() then
        local lx = joy:getGamepadAxis("leftx")
        local ly = joy:getGamepadAxis("lefty")
        if lx < -DEADZONE then axisHeld.LEFT  = true end
        if lx >  DEADZONE then axisHeld.RIGHT = true end
        if ly < -DEADZONE then axisHeld.UP    = true end
        if ly >  DEADZONE then axisHeld.DOWN  = true end
    end

    -- Combine: keyboard OR gamepad button OR analog stick
    local combined = {}
    for _, a in ipairs(ALL) do
        combined[a] = rawHeld[a] or padHeld[a] or axisHeld[a]
    end

    -- meta actions always pass through
    for _, a in ipairs(META) do
        input.held[a] = combined[a]
    end

    -- gameplay actions, optionally limited to 2 simultaneous
    if limitActions then
        local count = 0
        for _, a in ipairs(GAMEPLAY) do
            if combined[a] and count < 2 then
                input.held[a] = true
                count = count + 1
            else
                input.held[a] = false
            end
        end
    else
        for _, a in ipairs(GAMEPLAY) do
            input.held[a] = combined[a]
        end
    end

    -- derive edges
    for _, a in ipairs(ALL) do
        input.justPressed[a]  = input.held[a] and not prevHeld[a]
        input.justReleased[a] = not input.held[a] and prevHeld[a]
    end
end

-- Utility: get a list of currently held action names (for debug display)
function input.heldList()
    local t = {}
    for _, a in ipairs(ALL) do
        if input.held[a] then t[#t+1] = a end
    end
    return t
end

return input

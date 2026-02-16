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

local GAMEPLAY = {"LEFT", "RIGHT", "UP", "DOWN", "A", "B"}
local META     = {"START", "RESET", "DEBUG"}
local ALL      = {"LEFT", "RIGHT", "UP", "DOWN", "A", "B", "START", "RESET", "DEBUG"}

input.held        = {}
input.justPressed = {}
input.justReleased= {}

local rawHeld = {}
local prevHeld = {}

function input.init()
    for _, a in ipairs(ALL) do
        input.held[a]         = false
        input.justPressed[a]  = false
        input.justReleased[a] = false
        rawHeld[a]            = false
        prevHeld[a]           = false
    end
end

function input.keypressed(key)
    local action = keyMap[key]
    if action then rawHeld[action] = true end
end

function input.keyreleased(key)
    local action = keyMap[key]
    if action then rawHeld[action] = false end
end

function input.update(limitActions)
    -- save previous
    for _, a in ipairs(ALL) do
        prevHeld[a] = input.held[a]
    end

    -- meta actions always pass through
    for _, a in ipairs(META) do
        input.held[a] = rawHeld[a]
    end

    -- gameplay actions, optionally limited to 2 simultaneous
    if limitActions then
        local count = 0
        for _, a in ipairs(GAMEPLAY) do
            if rawHeld[a] and count < 2 then
                input.held[a] = true
                count = count + 1
            else
                input.held[a] = false
            end
        end
    else
        for _, a in ipairs(GAMEPLAY) do
            input.held[a] = rawHeld[a]
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

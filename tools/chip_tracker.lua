----------------------------------------------------------------
-- tools/chip_tracker.lua
-- Thin adapter wrapping console/tracker.lua to the standard tool interface.
-- The actual tracker implementation stays in console/tracker.lua;
-- this module just delegates to it.
----------------------------------------------------------------
local tool = {}
tool.id    = "chip_tracker"
tool.title = "Chip Tracker"

-- Reference to the real tracker module (set on first open)
local trackerMod = nil

function tool.open(ctx, console)
    if not trackerMod then
        trackerMod = console.tracker
    end
    if trackerMod then
        trackerMod.open()
    end
end

function tool.close(ctx, console)
    if trackerMod then
        trackerMod.close()
    end
end

function tool.isOpen(ctx)
    if trackerMod then
        return trackerMod.isActive()
    end
    return false
end

function tool.update(dt, ctx, console)
    if trackerMod and trackerMod.isActive() then
        trackerMod.update(dt)
    end
end

function tool.draw(ctx, console)
    if trackerMod and trackerMod.isActive() then
        trackerMod.draw()
    end
end

function tool.keypressed(key, ctx, console)
    if trackerMod and trackerMod.isActive() then
        trackerMod.keypressed(key)
        return true
    end
    return false
end

function tool.input(action, pressed, ctx, console)
    -- Tracker consumes all mapped input when active
    if trackerMod and trackerMod.isActive() then
        return true
    end
    return false
end

return tool

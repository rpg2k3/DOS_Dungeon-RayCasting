----------------------------------------------------------------
-- tools/registry.lua
-- Tool registry: auto-discovers tool modules in tools/ folder
-- Each tool must return a table with standard interface fields
----------------------------------------------------------------
local registry = {}

-- Registered tools keyed by id
local tools = {}
-- Ordered list of tool ids (for menu display)
local toolOrder = {}

----------------------------------------------------------------
-- Register a tool module (called internally during init)
----------------------------------------------------------------
local function register(mod)
    if not mod or not mod.id then return end
    tools[mod.id] = mod
    toolOrder[#toolOrder + 1] = mod.id
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

--- Return ordered list of tool tables
function registry.list()
    local out = {}
    for _, id in ipairs(toolOrder) do
        out[#out + 1] = tools[id]
    end
    return out
end

--- Get a single tool by id (or nil)
function registry.get(id)
    return tools[id]
end

----------------------------------------------------------------
-- Init: load all known tool modules
----------------------------------------------------------------
function registry.init()
    tools = {}
    toolOrder = {}

    -- List of tool module paths (order = menu order)
    local modules = {
        "tools.map_editor",
        "tools.sprite_editor",
        "tools.chip_tracker",
    }

    for _, modPath in ipairs(modules) do
        local ok, mod = pcall(require, modPath)
        if ok and mod and mod.id then
            register(mod)
        end
    end
end

return registry

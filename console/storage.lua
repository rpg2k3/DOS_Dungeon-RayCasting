local storage = {}

local data = {}
local dirty = false
local SAVE_FILE = "save.lua"

----------------------------------------------------------------
-- Serialization
----------------------------------------------------------------
local serialize

serialize = function(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "number" then
        if val ~= val then return "0" end           -- NaN guard
        if val == math.huge then return "math.huge" end
        if val == -math.huge then return "-math.huge" end
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        local inner = indent .. "  "
        for k, v in pairs(val) do
            local keyStr
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. serialize(k, "") .. "]"
            end
            parts[#parts + 1] = inner .. keyStr .. " = " .. serialize(v, inner)
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function storage.init()
    local info = love.filesystem.getInfo(SAVE_FILE)
    if info then
        local content = love.filesystem.read(SAVE_FILE)
        if content then
            local fn, err = load(content)
            if fn then
                local ok, result = pcall(fn)
                if ok and type(result) == "table" then
                    data = result
                end
            end
        end
    end
end

function storage.get(key, default)
    if data[key] ~= nil then return data[key] end
    return default
end

function storage.set(key, val)
    data[key] = val
    dirty = true
end

function storage.flush()
    if not dirty then return true end
    local content = "return " .. serialize(data) .. "\n"
    local ok, err = love.filesystem.write(SAVE_FILE, content)
    if ok then dirty = false end
    return ok, err
end

function storage.clear()
    data = {}
    dirty = true
end

return storage

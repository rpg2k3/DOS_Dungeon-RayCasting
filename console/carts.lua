local carts = {}

carts.list = {}

-- Diagnostic report, exposed so UI can display it
carts.report = {
    folderExists = false,
    folderInfo   = nil,
    items        = {},    -- raw file list from getDirectoryItems
    attempted    = {},    -- module names we tried to require
    loaded       = {},    -- titles of successfully loaded carts
    errors       = {},    -- { module = ..., err = ... }
}

function carts.register(cart)
    carts.list[#carts.list + 1] = cart
end

local REQUIRED_FIELDS = { "id", "title", "init", "update", "draw" }

local function validate(cart, moduleName)
    if type(cart) ~= "table" then
        local msg = moduleName .. " did not return a table (got " .. type(cart) .. ")"
        print("[CART DISCOVERY] INVALID: " .. msg)
        carts.report.errors[#carts.report.errors + 1] = { module = moduleName, err = msg }
        return false
    end
    local missing = {}
    for _, field in ipairs(REQUIRED_FIELDS) do
        local ft = type(cart[field])
        local expected = (field == "id" or field == "title") and "string" or "function"
        if ft ~= expected then
            missing[#missing + 1] = field .. " (expected " .. expected .. ", got " .. ft .. ")"
        end
    end
    if #missing > 0 then
        local msg = moduleName .. " missing/invalid fields: " .. table.concat(missing, ", ")
        print("[CART DISCOVERY] INVALID: " .. msg)
        carts.report.errors[#carts.report.errors + 1] = { module = moduleName, err = msg }
        return false
    end
    return true
end

local function tryLoad(moduleName)
    print("[CART DISCOVERY] TRY require(\"" .. moduleName .. "\")")
    carts.report.attempted[#carts.report.attempted + 1] = moduleName

    -- Clear cached module so edits during dev are picked up
    package.loaded[moduleName] = nil

    local ok, result = pcall(require, moduleName)
    if not ok then
        local msg = tostring(result)
        print("[CART DISCOVERY] REQUIRE FAILED: " .. moduleName .. " => " .. msg)
        carts.report.errors[#carts.report.errors + 1] = { module = moduleName, err = msg }
        return
    end
    print("[CART DISCOVERY] require returned " .. type(result))

    if not validate(result, moduleName) then
        return
    end

    carts.register(result)
    local title = tostring(result.title)
    local id = tostring(result.id)
    print("[CART DISCOVERY] OK: " .. title .. " (" .. id .. ")")
    carts.report.loaded[#carts.report.loaded + 1] = title
end

function carts.init()
    carts.list = {}
    carts.report = {
        folderExists = false,
        folderInfo   = nil,
        items        = {},
        attempted    = {},
        loaded       = {},
        errors       = {},
    }

    print("================================================================")
    print("[CART DISCOVERY] Starting cart auto-discovery...")
    print("================================================================")

    -- Step 1: Check if carts/ folder exists
    local info = love.filesystem.getInfo("carts")
    carts.report.folderInfo = info

    if not info then
        print("[CART DISCOVERY] ERROR: love.filesystem.getInfo('carts') returned nil!")
        print("[CART DISCOVERY] The 'carts' folder does not exist in LÖVE's filesystem.")
        print("[CART DISCOVERY] Source dir: " .. tostring(love.filesystem.getSource()))
        print("[CART DISCOVERY] Save dir: " .. tostring(love.filesystem.getSaveDirectory()))
        carts.report.errors[#carts.report.errors + 1] = {
            module = "(folder)",
            err = "carts/ folder not found in LÖVE filesystem"
        }
        return
    end

    if info.type ~= "directory" then
        print("[CART DISCOVERY] ERROR: 'carts' exists but is type '" .. tostring(info.type) .. "', not 'directory'!")
        carts.report.errors[#carts.report.errors + 1] = {
            module = "(folder)",
            err = "carts/ is type '" .. tostring(info.type) .. "', not directory"
        }
        return
    end

    carts.report.folderExists = true
    print("[CART DISCOVERY] carts/ folder exists (type: directory)")
    print("[CART DISCOVERY] Source: " .. tostring(love.filesystem.getSource()))

    -- Step 2: List directory contents
    local files = love.filesystem.getDirectoryItems("carts")
    print("[CART DISCOVERY] getDirectoryItems returned " .. #files .. " item(s):")
    for i, f in ipairs(files) do
        local finfo = love.filesystem.getInfo("carts/" .. f)
        local ftype = finfo and finfo.type or "???"
        print("[CART DISCOVERY]   [" .. i .. "] " .. f .. " (type: " .. ftype .. ")")
        carts.report.items[#carts.report.items + 1] = f
    end

    -- Step 3: Filter and load .lua files
    local luaCount = 0
    for _, filename in ipairs(files) do
        -- Skip non-.lua files
        local base = filename:match("^(.+)%.lua$")
        if not base then
            print("[CART DISCOVERY] SKIP (not .lua): " .. filename)
        elseif filename == "init.lua" then
            print("[CART DISCOVERY] SKIP (init.lua): " .. filename)
        elseif base:sub(1, 1) == "_" then
            print("[CART DISCOVERY] SKIP (underscore prefix): " .. filename)
        else
            -- Check it's actually a file, not a directory named "foo.lua"
            local finfo = love.filesystem.getInfo("carts/" .. filename)
            if finfo and finfo.type == "file" then
                luaCount = luaCount + 1
                local moduleName = "carts." .. base
                tryLoad(moduleName)
            else
                print("[CART DISCOVERY] SKIP (not a file): " .. filename)
            end
        end
    end

    print("================================================================")
    if #carts.list == 0 then
        print("[CART DISCOVERY] WARNING: No valid carts loaded!")
        print("[CART DISCOVERY]   Folder exists: " .. tostring(carts.report.folderExists))
        print("[CART DISCOVERY]   Total items: " .. #carts.report.items)
        print("[CART DISCOVERY]   .lua files tried: " .. luaCount)
        print("[CART DISCOVERY]   Errors: " .. #carts.report.errors)
        for i, e in ipairs(carts.report.errors) do
            print("[CART DISCOVERY]     " .. i .. ") " .. e.module .. ": " .. e.err)
        end
    else
        print("[CART DISCOVERY] SUCCESS: " .. #carts.list .. " cart(s) loaded")
        for i, title in ipairs(carts.report.loaded) do
            print("[CART DISCOVERY]   " .. i .. ") " .. title)
        end
    end
    print("================================================================")

    -- Write debug log to save directory for inspection
    local logLines = {}
    logLines[#logLines + 1] = "folderExists: " .. tostring(carts.report.folderExists)
    logLines[#logLines + 1] = "items: " .. #carts.report.items
    for i, f in ipairs(carts.report.items) do
        logLines[#logLines + 1] = "  item[" .. i .. "]: " .. f
    end
    logLines[#logLines + 1] = "attempted: " .. #carts.report.attempted
    for i, m in ipairs(carts.report.attempted) do
        logLines[#logLines + 1] = "  tried[" .. i .. "]: " .. m
    end
    logLines[#logLines + 1] = "loaded: " .. #carts.report.loaded
    for i, t in ipairs(carts.report.loaded) do
        logLines[#logLines + 1] = "  loaded[" .. i .. "]: " .. t
    end
    logLines[#logLines + 1] = "errors: " .. #carts.report.errors
    for i, e in ipairs(carts.report.errors) do
        logLines[#logLines + 1] = "  error[" .. i .. "]: " .. e.module .. " => " .. e.err
    end
    logLines[#logLines + 1] = "carts.list count: " .. #carts.list
    love.filesystem.write("cart_debug.log", table.concat(logLines, "\n"))
    -- Also write to source dir via io.open for easy access
    local src = love.filesystem.getSource()
    local f = io.open(src .. "/cart_debug.log", "w")
    if f then
        f:write(table.concat(logLines, "\n"))
        f:close()
    end
end

function carts.get(index)
    return carts.list[index]
end

function carts.count()
    return #carts.list
end

return carts

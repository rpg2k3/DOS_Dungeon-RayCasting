-- ============================================================================
-- RAYCAST DUNGEON — True raycasting 3D renderer (Wolfenstein-style)
-- ============================================================================
local cart = {
    title       = "RAYCAST DUNGEON",
    author      = "SYSTEM",
    description = "Classic raycasting 3D with textured walls, floor & ceiling.",
    id          = "raycast_dungeon",
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local VIRT_W, VIRT_H = 320, 200

-- Layout regions
local VP_X, VP_Y = 0, 0
local VP_W, VP_H = 216, 152
local RPANEL_X   = VP_W + 2
local RPANEL_Y   = 0
local RPANEL_W   = VIRT_W - RPANEL_X
local RPANEL_H   = VP_H
local MSG_X, MSG_Y = 0, VP_H + 2
local MSG_W, MSG_H = VIRT_W, VIRT_H - VP_H - 2

-- Raycaster
local FOV       = math.pi / 3   -- 60 degrees
local HALF_FOV  = FOV / 2
local MAX_DIST  = 20

-- Movement
local MOVE_SPEED = 3.0
local ROT_SPEED  = 2.5

-- Lighting / Fog
local AMBIENT       = 0.28
local FOG_DIST      = 8.0
local TORCH_RADIUS  = 5.0
local TORCH_STRENGTH = 1.0

-- Player stats
local MOVE_COST     = 2     -- stamina per tile moved
local MELEE_COST    = 12    -- stamina per melee attack (future)
local RANGED_COST   = 8     -- stamina per ranged shot (future)
local STAM_REGEN    = 15    -- stamina regen per second (when not attacking)
local DEATH_DELAY   = 1.5   -- seconds before respawn after death

-- Tile types
local TILE_EMPTY  = 0
local TILE_WALL   = 1
local TILE_DOOR   = 2
local TILE_STAIRS = 3
local TILE_START  = 4

local TILE_NAMES = {
    [TILE_EMPTY]  = "EMPTY",
    [TILE_WALL]   = "WALL",
    [TILE_DOOR]   = "DOOR",
    [TILE_STAIRS] = "STAIRS",
    [TILE_START]  = "START",
}

-- Palette colors per tile type (for editor grid)
local TILE_COLORS = {
    [TILE_EMPTY]  = 0,   -- black
    [TILE_WALL]   = 7,   -- light gray
    [TILE_DOOR]   = 9,   -- blue
    [TILE_STAIRS] = 14,  -- yellow
    [TILE_START]  = 10,  -- green
}

local BRUSH_ORDER = { TILE_WALL, TILE_EMPTY, TILE_DOOR, TILE_STAIRS, TILE_START }

-- ============================================================================
-- STATE
-- ============================================================================
local gfx, assets, sfx, input
local trackerRef  -- reference to console.tracker
local consoleRef  -- reference to console object (for live settings access)
local texWall, texFloor, texCeil
local texWallW, texWallH, texFloorW, texFloorH, texCeilW, texCeilH
local map, mapW, mapH
local player      -- { x, y, angle }
local msgLog
local quadMesh    -- reusable mesh for textured wall slices

-- Floor/ceiling rendering via ImageData
local floorCeilImageData
local floorCeilImage

-- Low-res rendering (half resolution for "LOW" render scale)
local floorCeilImageDataLow
local floorCeilImageLow

-- Pre-created quads for wall texture columns (one per texel column)
local wallQuads

-- Per-column depth buffer for minimap fog (optional)
local zBuffer

-- Texture data cache (ImageData for floor/ceil pixel sampling)
local floorTexData, ceilTexData

-- Skybox
local texSky       -- sky background image (from textures/bg/)
local texSkyW, texSkyH

-- Material system: per-tile texture keys
local wallMat       -- flat array [idx] = texture key string
local floorMat      -- flat array [idx] = texture key string
local ceilMat       -- flat array [idx] = texture key string

-- Texture catalog: { category = { {key=..., img=..., data=...}, ... } }
local texCatalog    -- built from assets at init
local texByKey      -- { "walls/brick_wall" = {img=..., data=..., w=..., h=...} }

-- Editor material mode
local editMode      -- 1=collision, 2=wall mat, 3=floor mat, 4=ceil mat
local paletteSel    -- selected index in current palette list
local paletteScroll -- scroll offset for palette list

-- Edit mode state
local mode          -- "play" or "edit"
local cursorX, cursorY
local brushType
local playerStartX, playerStartY
local showHelp      -- help overlay visible in edit mode
local helpScroll    -- scroll offset for help text

-- Torch state
local torchEnabled  -- toggle with F key in play mode

-- SFX state
local stepTimer     -- accumulator for footstep sound throttle
local STEP_INTERVAL = 0.25  -- seconds between step sounds

-- Tutorial state: reduce HUD text after first movement
local hasMovedOnce

-- Forward-declared map helpers (defined after map loading code)
local isWall  -- isWall(mx, my) -> bool; needed by hasLOS/enemyStepToward/updateProjectiles

-- ============================================================================
-- INVENTORY + ITEMS
-- ============================================================================
local INV_SIZE = 12     -- 4x3 grid
local INV_COLS = 4
local INV_ROWS = 3

-- Item database: templates keyed by id
local ITEM_DB = {
    knife  = { id="knife",  name="KNIFE",  type="melee",  dmg=15, cooldown=0.35, iconCol=15 },
    bow    = { id="bow",    name="BOW",    type="ranged", dmg=10, cooldown=0.50, ammoId="arrow", iconCol=14 },
    arrow  = { id="arrow",  name="ARROW",  type="ammo",   maxQty=50, iconCol=7 },
    potion = { id="potion", name="POTION", type="consumable", heal=35, maxQty=10, iconCol=4 },
    key    = { id="key",    name="KEY",    type="key",    maxQty=5, iconCol=6 },
}

-- Inventory state
local inventory        -- array of slots: {id, qty} or nil (empty)
local equipMelee       -- index into inventory (or nil)
local equipRanged      -- index into inventory (or nil)
local equipArmor       -- index into inventory (or nil)

-- Inventory UI state
local invOpen          -- true when inventory modal is visible
local invCursor        -- 0-based index (0..INV_SIZE-1)

-- Map entities: pickups on the ground
local entities         -- array of {type="pickup", x=N, y=N, itemId=string, qty=N}

-- Enemies
local enemies          -- array of enemy tables
local enemySpawns      -- array of {x=N, y=N} for editor persistence

-- Enemy constants
local ENEMY_HP        = 30
local ENEMY_SPEED     = 1.2    -- tiles per second when chasing
local ENEMY_SIGHT     = 6      -- detection range in tiles
local ENEMY_ATK_DMG   = 8      -- damage per hit
local ENEMY_ATK_CD    = 1.0    -- attack cooldown seconds
local ENEMY_MOVE_CD   = 0.6    -- seconds between chase steps
local ENEMY_DROP      = { "potion", "arrow" }  -- random drop on death

-- Projectiles
local projectiles      -- array of {x,y,dx,dy,speed,dmg,life}

-- Combat visual feedback
local screenShake      -- {timer, intensity} or nil
local meleeFlash       -- timer for melee swing visual (>0 while showing)

-- ============================================================================
-- HELPERS
-- ============================================================================
local math_floor = math.floor
local math_cos   = math.cos
local math_sin   = math.sin
local math_abs   = math.abs
local math_max   = math.max
local math_min   = math.min

local function clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end

local function calcLight(dist)
    -- Read live settings (fall back to constants if consoleRef not yet set)
    local fogStr = (consoleRef and consoleRef.fogStrength) or 1.0
    local tRadius = (consoleRef and consoleRef.torchRadius) or TORCH_RADIUS
    local tStrength = (consoleRef and consoleRef.torchStrength) or TORCH_STRENGTH
    local fogDist = FOG_DIST / math_max(fogStr, 0.01)

    local fog   = clamp(1.0 - (dist / fogDist), 0.0, 1.0)
    local torch = 0
    if torchEnabled then
        torch = clamp(1.0 - (dist / tRadius), 0.0, 1.0)
        torch = torch * torch * torch * 0.5 + torch * 0.5  -- ~pow 1.5 approx
    end
    return clamp(AMBIENT + fog * 0.45 + torch * tStrength * 0.55, 0.0, 1.0)
end

local function addLog(text)
    table.insert(msgLog, text)
    while #msgLog > 6 do table.remove(msgLog, 1) end
end

-- ============================================================================
-- INVENTORY HELPERS
-- ============================================================================
local function invNewSlot(itemId, qty)
    local db = ITEM_DB[itemId]
    if not db then return nil end
    return { id = itemId, qty = qty or 1 }
end

local function invFindItem(itemId)
    for i = 1, INV_SIZE do
        if inventory[i] and inventory[i].id == itemId then return i end
    end
    return nil
end

local function invFindEmpty()
    for i = 1, INV_SIZE do
        if not inventory[i] then return i end
    end
    return nil
end

--- Try to add an item to inventory. Returns true on success.
local function invAddItem(itemId, qty)
    qty = qty or 1
    local db = ITEM_DB[itemId]
    if not db then return false end

    -- Stackable items: try to merge into existing stack first
    if db.maxQty then
        local idx = invFindItem(itemId)
        if idx then
            local slot = inventory[idx]
            local space = db.maxQty - slot.qty
            if space >= qty then
                slot.qty = slot.qty + qty
                return true
            elseif space > 0 then
                slot.qty = db.maxQty
                qty = qty - space
                -- overflow falls through to new slot below
            end
        end
    end

    -- Need a new slot
    local empty = invFindEmpty()
    if not empty then return false end  -- inventory full
    inventory[empty] = invNewSlot(itemId, qty)
    return true
end

local function invRemoveAt(idx)
    inventory[idx] = nil
    -- Unequip if this slot was equipped
    if equipMelee  == idx then equipMelee  = nil end
    if equipRanged == idx then equipRanged = nil end
    if equipArmor  == idx then equipArmor  = nil end
end

local function invUseItem(idx)
    local slot = inventory[idx]
    if not slot then return end
    local db = ITEM_DB[slot.id]
    if not db then return end

    if db.type == "consumable" then
        if db.heal then
            local before = player.hp
            player.hp = math_min(player.hpMax, player.hp + db.heal)
            addLog("HEALED +" .. math_floor(player.hp - before) .. " HP")
        end
        slot.qty = slot.qty - 1
        if slot.qty <= 0 then invRemoveAt(idx) end
        if sfx then sfx.play("ui_select") end
    elseif db.type == "melee" then
        equipMelee = (equipMelee == idx) and nil or idx
        addLog(equipMelee and ("EQUIP " .. db.name) or ("UNEQUIP " .. db.name))
        if sfx then sfx.play("ui_select") end
    elseif db.type == "ranged" then
        equipRanged = (equipRanged == idx) and nil or idx
        addLog(equipRanged and ("EQUIP " .. db.name) or ("UNEQUIP " .. db.name))
        if sfx then sfx.play("ui_select") end
    else
        addLog("CAN'T USE " .. db.name)
    end
end

-- ============================================================================
-- ENTITY HELPERS (pickups on map)
-- ============================================================================
local function spawnPickup(mx, my, itemId, qty)
    entities[#entities + 1] = { type="pickup", x=mx, y=my, itemId=itemId, qty=qty or 1 }
end

local function checkPickups()
    local px = math_floor(player.x)
    local py = math_floor(player.y)
    local i = 1
    while i <= #entities do
        local e = entities[i]
        if e.type == "pickup" and e.x == px and e.y == py then
            if invAddItem(e.itemId, e.qty) then
                local db = ITEM_DB[e.itemId]
                local name = db and db.name or e.itemId
                addLog("PICKED UP " .. name .. (e.qty > 1 and (" x" .. e.qty) or ""))
                if sfx then sfx.play("ui_select") end
                table.remove(entities, i)
            else
                addLog("INVENTORY FULL")
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

local function initDefaultEntities()
    entities = {}
    -- Scatter some test pickups in the default map
    spawnPickup(3, 2, "knife")
    spawnPickup(4, 2, "bow")
    spawnPickup(5, 2, "arrow", 10)
    spawnPickup(3, 3, "potion", 2)
    spawnPickup(4, 3, "arrow", 5)
    spawnPickup(8, 2, "potion")
    spawnPickup(12, 2, "key")
end

-- ============================================================================
-- ENEMY HELPERS
-- ============================================================================
local function spawnEnemy(mx, my)
    enemies[#enemies + 1] = {
        x = mx + 0.5, y = my + 0.5,  -- center of tile
        hp = ENEMY_HP,
        state = "idle",     -- idle | chase | dead
        atkTimer = 0,       -- cooldown before next attack
        moveTimer = 0,      -- cooldown before next step
        flashTimer = 0,     -- visual hit flash
    }
end

-- Line-of-sight check: walk grid from (ax,ay) to (bx,by), return true if no wall blocks
local function hasLOS(ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.01 then return true end
    local steps = math_floor(dist * 2) + 1  -- check every half-tile
    local sx = dx / steps
    local sy = dy / steps
    for i = 1, steps do
        local cx = ax + sx * i
        local cy = ay + sy * i
        if isWall(math_floor(cx), math_floor(cy)) then
            return false
        end
    end
    return true
end

-- Move enemy one grid step toward player (grid-based pathfinding: pick best adjacent cell)
local function enemyStepToward(enemy)
    local px, py = player.x, player.y
    local ex, ey = enemy.x, enemy.y
    local bestDist = math.huge
    local bestX, bestY = ex, ey

    -- Try 4 cardinal directions (grid step = 1 tile)
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    for _, d in ipairs(dirs) do
        local nx = math_floor(ex) + d[1] + 0.5
        local ny = math_floor(ey) + d[2] + 0.5
        local mx = math_floor(nx)
        local my = math_floor(ny)
        -- Check wall collision
        if not isWall(mx, my) then
            -- Check if another enemy is already on that tile
            local blocked = false
            for _, other in ipairs(enemies) do
                if other ~= enemy and other.hp > 0 then
                    if math_floor(other.x) == mx and math_floor(other.y) == my then
                        blocked = true
                        break
                    end
                end
            end
            if not blocked then
                local ddx = px - nx
                local ddy = py - ny
                local d2 = ddx * ddx + ddy * ddy
                if d2 < bestDist then
                    bestDist = d2
                    bestX = nx
                    bestY = ny
                end
            end
        end
    end

    enemy.x = bestX
    enemy.y = bestY
end

local function updateEnemies(dt)
    local px, py = player.x, player.y
    local i = 1
    while i <= #enemies do
        local e = enemies[i]

        -- Flash timer
        if e.flashTimer > 0 then
            e.flashTimer = e.flashTimer - dt
        end

        -- Dead enemy: remove after brief flash
        if e.hp <= 0 then
            if e.state ~= "dead" then
                e.state = "dead"
                e.flashTimer = 0.3
                -- Drop loot
                local dropId = ENEMY_DROP[math.random(#ENEMY_DROP)]
                local dropQty = (dropId == "arrow") and math.random(2, 5) or 1
                spawnPickup(math_floor(e.x), math_floor(e.y), dropId, dropQty)
                addLog("ENEMY KILLED!")
            end
            if e.flashTimer <= 0 then
                table.remove(enemies, i)
            else
                i = i + 1
            end
            goto continue
        end

        -- Distance to player
        local ddx = px - e.x
        local ddy = py - e.y
        local dist = math.sqrt(ddx * ddx + ddy * ddy)

        -- State transitions
        if e.state == "idle" then
            -- Detect player within sight range + LOS
            if dist <= ENEMY_SIGHT and hasLOS(e.x, e.y, px, py) then
                e.state = "chase"
                e.moveTimer = ENEMY_MOVE_CD * 0.5  -- short initial delay
            end
        elseif e.state == "chase" then
            -- Lose aggro if player too far or no LOS
            if dist > ENEMY_SIGHT * 1.5 or not hasLOS(e.x, e.y, px, py) then
                e.state = "idle"
                goto nextEnemy
            end

            -- Attack if adjacent (distance < 1.2)
            if dist < 1.2 then
                e.atkTimer = e.atkTimer - dt
                if e.atkTimer <= 0 then
                    player.hp = player.hp - ENEMY_ATK_DMG
                    e.atkTimer = ENEMY_ATK_CD
                    addLog("ENEMY HIT YOU! -" .. ENEMY_ATK_DMG .. " HP")
                    if sfx then sfx.play("bump") end
                end
            else
                -- Chase: move toward player on cooldown
                e.moveTimer = e.moveTimer - dt
                if e.moveTimer <= 0 then
                    enemyStepToward(e)
                    e.moveTimer = ENEMY_MOVE_CD
                end
            end
        end

        ::nextEnemy::
        i = i + 1
        ::continue::
    end
end

-- ============================================================================
-- COMBAT HELPERS
-- ============================================================================
local function triggerScreenShake(intensity, duration)
    screenShake = { timer = duration or 0.15, intensity = intensity or 2 }
end

local function doMeleeAttack()
    -- Already on cooldown?
    if player.attackCooldown > 0 then return end

    -- Check stamina
    if player.stam < MELEE_COST then
        addLog("TOO TIRED")
        return
    end

    -- Get equipped melee weapon stats (or bare fists)
    local dmg = 5  -- bare fist fallback
    local cooldown = 0.5
    if equipMelee and inventory[equipMelee] then
        local db = ITEM_DB[inventory[equipMelee].id]
        if db and db.dmg then dmg = db.dmg end
        if db and db.cooldown then cooldown = db.cooldown end
    end

    -- Drain stamina + set cooldown
    player.stam = math_max(0, player.stam - MELEE_COST)
    player.attackCooldown = cooldown

    -- Visual feedback
    meleeFlash = 0.12
    triggerScreenShake(2, 0.08)

    -- Check for enemies in melee cone (distance <= 1.5, angle within 25 degrees)
    local px, py = player.x, player.y
    local pAngle = player.angle
    local hitAny = false

    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            local ddx = e.x - px
            local ddy = e.y - py
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            if dist <= 1.5 then
                -- Check angle
                local angleToEnemy = math.atan2(ddy, ddx)
                local diff = angleToEnemy - pAngle
                -- Normalize to [-pi, pi]
                diff = (diff + math.pi) % (2 * math.pi) - math.pi
                if math_abs(diff) < math.rad(25) then
                    e.hp = e.hp - dmg
                    e.flashTimer = 0.15
                    hitAny = true
                    addLog("HIT! -" .. dmg .. " DMG")
                    if sfx then sfx.play("bump") end
                end
            end
        end
    end

    if not hitAny then
        addLog("SWING!")
        if sfx then sfx.play("step") end
    end
end

local function doRangedAttack()
    -- Already on cooldown?
    if player.attackCooldown > 0 then return end

    -- Check stamina
    if player.stam < RANGED_COST then
        addLog("TOO TIRED")
        return
    end

    -- Must have ranged weapon equipped
    if not equipRanged or not inventory[equipRanged] then
        addLog("NO RANGED WEAPON")
        return
    end

    local slot = inventory[equipRanged]
    local db = ITEM_DB[slot.id]
    if not db then return end

    -- Check ammo
    local ammoId = db.ammoId
    if ammoId then
        local ammoIdx = invFindItem(ammoId)
        if not ammoIdx then
            addLog("NO " .. (ITEM_DB[ammoId] and ITEM_DB[ammoId].name or "AMMO"))
            return
        end
        -- Consume 1 ammo
        local ammoSlot = inventory[ammoIdx]
        ammoSlot.qty = ammoSlot.qty - 1
        if ammoSlot.qty <= 0 then
            invRemoveAt(ammoIdx)
        end
    end

    -- Drain stamina + set cooldown
    player.stam = math_max(0, player.stam - RANGED_COST)
    player.attackCooldown = db.cooldown or 0.5

    -- Spawn projectile
    local dirX = math_cos(player.angle)
    local dirY = math_sin(player.angle)
    projectiles[#projectiles + 1] = {
        x = player.x + dirX * 0.3,
        y = player.y + dirY * 0.3,
        dx = dirX,
        dy = dirY,
        speed = 8.0,
        dmg = db.dmg or 10,
        life = 2.0,  -- seconds before despawn
    }

    addLog("FIRED!")
    if sfx then sfx.play("ui_select") end
end

local function updateProjectiles(dt)
    local i = 1
    while i <= #projectiles do
        local p = projectiles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(projectiles, i)
            goto nextProj
        end

        -- Move
        p.x = p.x + p.dx * p.speed * dt
        p.y = p.y + p.dy * p.speed * dt

        -- Wall collision
        if isWall(math_floor(p.x), math_floor(p.y)) then
            table.remove(projectiles, i)
            goto nextProj
        end

        -- Enemy collision
        local hit = false
        for _, e in ipairs(enemies) do
            if e.hp > 0 then
                local ddx = e.x - p.x
                local ddy = e.y - p.y
                if ddx * ddx + ddy * ddy < 0.4 then
                    e.hp = e.hp - p.dmg
                    e.flashTimer = 0.15
                    addLog("ARROW HIT! -" .. p.dmg .. " DMG")
                    if sfx then sfx.play("bump") end
                    triggerScreenShake(1, 0.05)
                    table.remove(projectiles, i)
                    hit = true
                    break
                end
            end
        end
        if hit then goto nextProj end

        i = i + 1
        ::nextProj::
    end
end

local function initDefaultEnemySpawns()
    enemySpawns = {
        { x = 8, y = 7 },
        { x = 12, y = 5 },
        { x = 5, y = 10 },
    }
end

local function spawnEnemiesFromSpawns()
    enemies = {}
    for _, s in ipairs(enemySpawns) do
        spawnEnemy(s.x, s.y)
    end
end

-- ============================================================================
-- FALLBACK TEXTURE
-- ============================================================================
local function buildFallbackTexture(w, h, c1, c2)
    w, h = w or 16, h or 16
    c1 = c1 or {0.45, 0.30, 0.20, 1}
    c2 = c2 or {0.35, 0.22, 0.14, 1}
    local data = love.image.newImageData(w, h)
    for py = 0, h - 1 do
        for px = 0, w - 1 do
            local c = ((math_floor(px / 4) + math_floor(py / 4)) % 2 == 0) and c1 or c2
            data:setPixel(px, py, c[1], c[2], c[3], c[4])
        end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    img:setWrap("repeat", "repeat")
    return img
end

-- ============================================================================
-- MESH QUAD HELPER (for wall slices)
-- ============================================================================
local function initQuadMesh()
    local verts = {
        {0,0, 0,0, 1,1,1,1},
        {1,0, 1,0, 1,1,1,1},
        {1,1, 1,1, 1,1,1,1},
        {0,1, 0,1, 1,1,1,1},
    }
    quadMesh = love.graphics.newMesh(
        {{"VertexPosition","float",2}, {"VertexTexCoord","float",2}, {"VertexColor","float",4}},
        verts, "fan", "dynamic"
    )
end

-- ============================================================================
-- MAP DATA
-- ============================================================================
local DEFAULT_MAP = {
    width  = 16,
    height = 16,
    tiles  = {
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
        1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,1,1,0,0,1,
        1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1,
        1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,1,
        1,1,1,0,1,1,1,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,1,1,0,1,1,1,
        1,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,1,1,0,1,1,1,0,0,0,1,1,1,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
        1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    },
}

local function getTile(mx, my)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return 1 end
    return map[(my - 1) * mapW + mx]
end

local function setTile(mx, my, val)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return end
    map[(my - 1) * mapW + mx] = val
end

isWall = function(mx, my)
    return getTile(mx, my) == TILE_WALL
end

-- Material helpers
local function matIdx(mx, my) return (my - 1) * mapW + mx end

local function getWallMat(mx, my)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return nil end
    return wallMat[matIdx(mx, my)]
end
local function getFloorMat(mx, my)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return nil end
    return floorMat[matIdx(mx, my)]
end
local function getCeilMat(mx, my)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return nil end
    return ceilMat[matIdx(mx, my)]
end

local function setWallMat(mx, my, key)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return end
    wallMat[matIdx(mx, my)] = key
end
local function setFloorMat(mx, my, key)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return end
    floorMat[matIdx(mx, my)] = key
end
local function setCeilMat(mx, my, key)
    if mx < 1 or my < 1 or mx > mapW or my > mapH then return end
    ceilMat[matIdx(mx, my)] = key
end

-- Initialize material grids with defaults
local function initMaterialGrids()
    wallMat  = {}
    floorMat = {}
    ceilMat  = {}
    for i = 1, mapW * mapH do
        wallMat[i]  = "default"
        floorMat[i] = "default"
        ceilMat[i]  = nil   -- nil = open sky (no roof)
    end
end

-- Resolve a material key to a texture catalog entry
local function resolveTexEntry(catName, key)
    local entry = texByKey[catName .. "/" .. key]
    if entry then return entry end
    -- Fallback to first in catalog
    if texCatalog[catName] and #texCatalog[catName] > 0 then
        return texCatalog[catName][1]
    end
    return nil
end

-- ============================================================================
-- SAVE / LOAD MAP
-- ============================================================================
local function serializeMatRow(mat, y)
    local row = {}
    for x = 1, mapW do
        local v = mat[matIdx(x, y)]
        if v == nil then
            row[#row + 1] = "nil"
        else
            row[#row + 1] = string.format("%q", v)
        end
    end
    return table.concat(row, ",")
end

local function serializeMap()
    local lines = {}
    lines[#lines + 1] = "return {"
    lines[#lines + 1] = "  width = " .. mapW .. ","
    lines[#lines + 1] = "  height = " .. mapH .. ","
    lines[#lines + 1] = "  playerStart = {x = " .. playerStartX .. ", y = " .. playerStartY .. "},"
    lines[#lines + 1] = "  grid = {"
    for y = 1, mapH do
        local row = {}
        for x = 1, mapW do
            row[#row + 1] = tostring(getTile(x, y))
        end
        lines[#lines + 1] = "    " .. table.concat(row, ",") .. ","
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "  mats = {"
    lines[#lines + 1] = "    wall = {"
    for y = 1, mapH do
        lines[#lines + 1] = "      " .. serializeMatRow(wallMat, y) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    floor = {"
    for y = 1, mapH do
        lines[#lines + 1] = "      " .. serializeMatRow(floorMat, y) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    ceil = {"
    for y = 1, mapH do
        lines[#lines + 1] = "      " .. serializeMatRow(ceilMat, y) .. ","
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "  },"
    -- Entities (pickups, enemy spawns, etc.)
    lines[#lines + 1] = "  entities = {"
    for _, e in ipairs(entities) do
        if e.type == "pickup" then
            lines[#lines + 1] = string.format(
                '    {type="pickup", x=%d, y=%d, itemId=%q, qty=%d},',
                e.x, e.y, e.itemId, e.qty or 1)
        end
    end
    lines[#lines + 1] = "  },"
    -- Enemy spawn points
    lines[#lines + 1] = "  enemySpawns = {"
    for _, s in ipairs(enemySpawns) do
        lines[#lines + 1] = string.format("    {x=%d, y=%d},", s.x, s.y)
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function saveMap()
    love.filesystem.createDirectory("dungeons")
    local content = serializeMap()
    local ok, err = love.filesystem.write("dungeons/main.lua", content)
    if ok then
        addLog("MAP SAVED!")
    else
        addLog("SAVE FAILED: " .. tostring(err))
    end
end

local function loadMapFromFile()
    local info = love.filesystem.getInfo("dungeons/main.lua")
    if not info then return false end
    local content = love.filesystem.read("dungeons/main.lua")
    if not content then return false end
    local fn, err = load(content)
    if not fn then
        addLog("LOAD ERR: " .. tostring(err))
        return false
    end
    local ok, result = pcall(fn)
    if not ok or type(result) ~= "table" then
        addLog("LOAD ERR: BAD DATA")
        return false
    end
    if not result.width or not result.height or not result.grid then
        addLog("LOAD ERR: MISSING FIELDS")
        return false
    end
    mapW = result.width
    mapH = result.height
    map = {}
    for i, v in ipairs(result.grid) do
        map[i] = v
    end
    if result.playerStart then
        playerStartX = result.playerStart.x or 2
        playerStartY = result.playerStart.y or 2
    end
    -- Find START tile if present (overrides playerStart)
    for y = 1, mapH do
        for x = 1, mapW do
            if getTile(x, y) == TILE_START then
                playerStartX = x
                playerStartY = y
            end
        end
    end
    -- Load materials (backward compat: fill defaults if missing)
    initMaterialGrids()
    if result.mats then
        local function loadMatGrid(dest, src)
            if not src then return end
            for i, v in ipairs(src) do
                if type(v) == "string" then dest[i] = v end
            end
        end
        loadMatGrid(wallMat,  result.mats.wall)
        loadMatGrid(floorMat, result.mats.floor)
        -- Ceiling: nil = open sky, use numeric loop (ipairs stops at nil)
        if result.mats.ceil then
            local total = mapW * mapH
            for i = 1, total do
                local v = result.mats.ceil[i]
                if v == nil or v == "default" then
                    ceilMat[i] = nil  -- open sky
                elseif type(v) == "string" then
                    ceilMat[i] = v
                end
            end
        end
    end
    -- Load entities (backward compat: use defaults if missing)
    if result.entities then
        entities = {}
        for _, e in ipairs(result.entities) do
            if e.type == "pickup" and e.itemId and e.x and e.y then
                entities[#entities + 1] = { type="pickup", x=e.x, y=e.y, itemId=e.itemId, qty=e.qty or 1 }
            end
        end
    else
        initDefaultEntities()
    end
    -- Load enemy spawns (backward compat: use defaults if missing)
    if result.enemySpawns then
        enemySpawns = {}
        for _, s in ipairs(result.enemySpawns) do
            if s.x and s.y then
                enemySpawns[#enemySpawns + 1] = { x = s.x, y = s.y }
            end
        end
    else
        initDefaultEnemySpawns()
    end
    return true
end

local function loadMapDefault()
    mapW = DEFAULT_MAP.width
    mapH = DEFAULT_MAP.height
    map = {}
    for i, v in ipairs(DEFAULT_MAP.tiles) do
        map[i] = v
    end
    playerStartX = 2
    playerStartY = 2
    initMaterialGrids()
end

local function applyPlayerStart()
    player.x = playerStartX + 0.5
    player.y = playerStartY + 0.5
    player.angle = 0
    player.hp   = player.hpMax
    player.stam = player.stamMax
    player.dead = false
    player.deathTimer = 0
    player.attackCooldown = 0
    -- Respawn enemies from spawn points
    if enemySpawns then
        spawnEnemiesFromSpawns()
    end
    -- Clear projectiles
    if projectiles then
        for i = #projectiles, 1, -1 do projectiles[i] = nil end
    end
    screenShake = nil
    meleeFlash = 0
end

-- ============================================================================
-- DDA RAYCASTING
-- ============================================================================
-- Returns: dist, wallX (0-1 fractional hit pos), side (0=vert, 1=horiz), hitCellX, hitCellY (1-based)
local function castRay(ox, oy, angle)
    local dirX = math_cos(angle)
    local dirY = math_sin(angle)

    -- Which map cell we're in
    local mapX = math_floor(ox)
    local mapY = math_floor(oy)

    -- Length of ray from one x/y-side to next x/y-side
    local deltaDistX = (dirX == 0) and 1e30 or math_abs(1 / dirX)
    local deltaDistY = (dirY == 0) and 1e30 or math_abs(1 / dirY)

    local stepX, stepY
    local sideDistX, sideDistY

    if dirX < 0 then
        stepX = -1
        sideDistX = (ox - mapX) * deltaDistX
    else
        stepX = 1
        sideDistX = (mapX + 1 - ox) * deltaDistX
    end
    if dirY < 0 then
        stepY = -1
        sideDistY = (oy - mapY) * deltaDistY
    else
        stepY = 1
        sideDistY = (mapY + 1 - oy) * deltaDistY
    end

    -- DDA
    local side = 0
    local dist = 0
    for _ = 1, 64 do
        if sideDistX < sideDistY then
            sideDistX = sideDistX + deltaDistX
            mapX = mapX + stepX
            side = 0
        else
            sideDistY = sideDistY + deltaDistY
            mapY = mapY + stepY
            side = 1
        end

        -- Map uses 1-based indices
        if isWall(mapX + 1, mapY + 1) then
            -- Perpendicular distance (avoids fisheye)
            if side == 0 then
                dist = (mapX - ox + (1 - stepX) / 2) / dirX
            else
                dist = (mapY - oy + (1 - stepY) / 2) / dirY
            end
            if dist < 0 then dist = 0.001 end

            -- Exact wallX (fractional hit position along wall face)
            local wallX
            if side == 0 then
                wallX = oy + dist * dirY
            else
                wallX = ox + dist * dirX
            end
            wallX = wallX - math_floor(wallX)

            return dist, wallX, side, mapX + 1, mapY + 1
        end

        -- Max distance check
        if side == 0 then
            dist = sideDistX
        else
            dist = sideDistY
        end
        if dist > MAX_DIST then
            return MAX_DIST, 0, 0, 0, 0
        end
    end

    return MAX_DIST, 0, 0, 0, 0
end

-- ============================================================================
-- FLOOR + CEILING RENDERING (ImageData per frame, samples cached texture data)
-- ============================================================================
local function renderFloorCeiling(imgData, rW, rH)
    local texOn = consoleRef and consoleRef.texturesEnabled ~= false
    local fovRad = math.rad((consoleRef and consoleRef.fovDeg) or 60)
    local halfFov = fovRad / 2
    local halfH = rH / 2
    local posX = player.x - 1
    local posY = player.y - 1
    local angle = player.angle

    local dirX = math_cos(angle)
    local dirY = math_sin(angle)

    local planeScale = math.tan(halfFov)
    local planeX = -dirY * planeScale
    local planeY =  dirX * planeScale

    -- Default floor/ceil texture data (used when material is "default")
    local defFData = floorTexData
    local defFW, defFH = texFloorW, texFloorH
    local defCData = ceilTexData
    local defCW, defCH = texCeilW, texCeilH

    -- Per-scanline cache to avoid repeated resolveTexEntry calls
    local lastFCellKey = nil
    local lastFEntry = nil
    local lastCCellKey = nil
    local lastCEntry = nil

    for y = 0, rH - 1 do
        local isFloor = y > halfH
        local p = isFloor and (y - halfH) or (halfH - y)
        if p <= 0 then p = 0.5 end

        local rowDist = halfH / p

        local floorStepX = rowDist * 2 * planeX / rW
        local floorStepY = rowDist * 2 * planeY / rW

        local floorX = posX + rowDist * (dirX - planeX)
        local floorY = posY + rowDist * (dirY - planeY)

        local shade = calcLight(rowDist)

        if not texOn then
            -- Flat-color mode: no texture sampling
            for x = 0, rW - 1 do
                if isFloor then
                    -- Gray floor shaded by distance
                    local g = 0.50 * shade
                    imgData:setPixel(x, y, g, g, g, 1)
                else
                    -- Check if ceiling exists at this cell
                    local cellX = math_floor(floorX) + 1
                    local cellY = math_floor(floorY) + 1
                    local matKey = nil
                    if cellX >= 1 and cellY >= 1 and cellX <= mapW and cellY <= mapH then
                        matKey = ceilMat[matIdx(cellX, cellY)]
                    end
                    if not matKey or matKey == "" then
                        -- Open sky: transparent
                        imgData:setPixel(x, y, 0, 0, 0, 0)
                    else
                        -- Gray roof shaded by distance
                        local g = 0.40 * shade
                        imgData:setPixel(x, y, g, g, g * 1.05, 1)
                    end
                end
                floorX = floorX + floorStepX
                floorY = floorY + floorStepY
            end
        else
            -- Textured mode
            for x = 0, rW - 1 do
                -- Determine which map cell this pixel falls in (1-based)
                local cellX = math_floor(floorX) + 1
                local cellY = math_floor(floorY) + 1

                if isFloor then
                    -- Look up floor material for this cell
                    local fData, fw, fh = defFData, defFW, defFH
                    if cellX >= 1 and cellY >= 1 and cellX <= mapW and cellY <= mapH then
                        local matKey = floorMat[matIdx(cellX, cellY)]
                        if matKey and matKey ~= "default" then
                            if matKey ~= lastFCellKey then
                                lastFCellKey = matKey
                                lastFEntry = resolveTexEntry("floor", matKey)
                            end
                            if lastFEntry then
                                fData = lastFEntry.data
                                fw = lastFEntry.w
                                fh = lastFEntry.h
                            end
                        end
                    end
                    local tx = math_floor(floorX * fw) % fw
                    local ty = math_floor(floorY * fh) % fh
                    if tx < 0 then tx = tx + fw end
                    if ty < 0 then ty = ty + fh end
                    local r, g, b = fData:getPixel(tx, ty)
                    imgData:setPixel(x, y, r * shade, g * shade, b * shade, 1)
                else
                    -- Look up ceiling material for this cell
                    -- Rule: nil/empty ceilMat = open sky (transparent), else render roof texture
                    local matKey = nil
                    if cellX >= 1 and cellY >= 1 and cellX <= mapW and cellY <= mapH then
                        matKey = ceilMat[matIdx(cellX, cellY)]
                    end

                    if not matKey or matKey == "" then
                        -- Open sky: transparent pixel (skybox shows through)
                        imgData:setPixel(x, y, 0, 0, 0, 0)
                    else
                        -- Roof texture
                        local cData, cw, ch = defCData, defCW, defCH
                        if matKey ~= "default" then
                            if matKey ~= lastCCellKey then
                                lastCCellKey = matKey
                                lastCEntry = resolveTexEntry("ceil", matKey)
                            end
                            if lastCEntry then
                                cData = lastCEntry.data
                                cw = lastCEntry.w
                                ch = lastCEntry.h
                            end
                        end
                        local ctx = math_floor(floorX * cw) % cw
                        local cty = math_floor(floorY * ch) % ch
                        if ctx < 0 then ctx = ctx + cw end
                        if cty < 0 then cty = cty + ch end
                        local r, g, b = cData:getPixel(ctx, cty)
                        imgData:setPixel(x, y, r * shade * 0.85, g * shade * 0.85, b * shade * 0.9, 1)
                    end
                end

                floorX = floorX + floorStepX
                floorY = floorY + floorStepY
            end
        end
    end
end

-- ============================================================================
-- WALL COLUMN RENDERING
-- ============================================================================
local function renderWalls(colStep)
    colStep = colStep or 1
    local texOn = consoleRef and consoleRef.texturesEnabled ~= false
    local fovRad = math.rad((consoleRef and consoleRef.fovDeg) or 60)
    local halfFov = fovRad / 2
    local posX = player.x - 1  -- 0-based for DDA
    local posY = player.y - 1
    local angle = player.angle
    local halfH = VP_H / 2

    love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)

    for x = 0, VP_W - 1, colStep do
        -- Ray angle for this column
        local cameraX = 2 * x / VP_W - 1  -- -1 to +1
        local rayAngle = angle + math.atan(cameraX * math.tan(halfFov))

        local dist, wallX, side, hitCX, hitCY = castRay(posX, posY, rayAngle)

        -- Correct fisheye with cos of angle difference
        local corrDist = dist * math_cos(rayAngle - angle)
        if corrDist < 0.001 then corrDist = 0.001 end

        -- Fill zBuffer for all pixels in this column group
        for zx = x, math.min(x + colStep - 1, VP_W - 1) do
            zBuffer[zx] = corrDist
        end

        if dist >= MAX_DIST then goto continueWall end

        -- Wall slice height
        local lineH = VP_H / corrDist
        local drawStart = halfH - lineH / 2
        local drawEnd   = halfH + lineH / 2

        -- Lighting: fog + torch + side darkening
        local shade = calcLight(corrDist)
        if side == 1 then shade = shade * 0.85 end

        if texOn then
            -- Resolve wall texture from material grid
            local wKey = getWallMat(hitCX, hitCY)
            local wEntry = resolveTexEntry("walls", wKey or "default")
            local wImg = wEntry and wEntry.img or texWall
            local wW   = wEntry and wEntry.w or texWallW

            -- Texture X coordinate
            local texX = math_floor(wallX * wW)
            if texX >= wW then texX = wW - 1 end
            if texX < 0 then texX = 0 end

            -- Draw wall column using mesh quad (colStep wide)
            local u0 = texX / wW
            local u1 = (texX + 1) / wW
            quadMesh:setVertices({
                {VP_X + x,            VP_Y + drawStart, u0, 0, shade, shade, shade, 1},
                {VP_X + x + colStep,  VP_Y + drawStart, u1, 0, shade, shade, shade, 1},
                {VP_X + x + colStep,  VP_Y + drawEnd,   u1, 1, shade, shade, shade, 1},
                {VP_X + x,            VP_Y + drawEnd,   u0, 1, shade, shade, shade, 1},
            })
            quadMesh:setTexture(wImg)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(quadMesh)
        else
            -- Flat white wall shaded by lighting
            love.graphics.setColor(shade, shade, shade, 1)
            love.graphics.rectangle("fill", VP_X + x, VP_Y + drawStart, colStep, drawEnd - drawStart)
        end

        ::continueWall::
    end

    love.graphics.setScissor()
end

-- ============================================================================
-- SKYBOX RENDERING (drawn behind everything, parallax by player angle)
-- ============================================================================
local skyQuadObj  -- cached Quad for skybox (avoids per-frame allocation)

local function drawSkybox()
    local texOn = consoleRef and consoleRef.texturesEnabled ~= false

    if not texSky or not texOn then
        -- No skybox texture or textures off: fill upper half with solid blue
        gfx.setColorRGBA(0.05, 0.05, 0.15, 1)
        love.graphics.rectangle("fill", VP_X, VP_Y, VP_W, VP_H / 2)
        return
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setScissor(VP_X, VP_Y, VP_W, math_floor(VP_H / 2))

    -- Parallax: scroll horizontally based on player angle
    -- Full 2*PI rotation = one full texture width
    local scrollX = math_floor((player.angle / (2 * math.pi)) * texSkyW) % texSkyW
    local halfH = math_floor(VP_H / 2)

    if not skyQuadObj then
        skyQuadObj = love.graphics.newQuad(0, 0, VP_W, halfH, texSkyW, texSkyH)
    end
    skyQuadObj:setViewport(scrollX, 0, VP_W, halfH)
    love.graphics.draw(texSky, skyQuadObj, VP_X, VP_Y)

    love.graphics.setScissor()
end

-- ============================================================================
-- ENEMY BILLBOARD RENDERING
-- ============================================================================
local function renderEnemies()
    if not enemies or #enemies == 0 then return end

    local fovRad = math.rad((consoleRef and consoleRef.fovDeg) or 60)
    local halfFov = fovRad / 2
    local halfH = VP_H / 2
    local pAngle = player.angle
    local px, py = player.x, player.y

    -- Direction vectors for projection
    local dirX = math_cos(pAngle)
    local dirY = math_sin(pAngle)
    local planeScale = math.tan(halfFov)
    local planeX = -dirY * planeScale
    local planeY =  dirX * planeScale

    love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)

    -- Sort enemies by distance (far first for painter's algorithm)
    local sorted = {}
    for _, e in ipairs(enemies) do
        local dx = e.x - px
        local dy = e.y - py
        local dist = dx * dx + dy * dy
        sorted[#sorted + 1] = { e = e, dist2 = dist }
    end
    table.sort(sorted, function(a, b) return a.dist2 > b.dist2 end)

    for _, se in ipairs(sorted) do
        local e = se.e

        -- Relative position to player
        local dx = e.x - px
        local dy = e.y - py

        -- Transform to camera space
        -- invDet = 1 / (planeX * dirY - dirX * planeY)
        local invDet = 1.0 / (planeX * dirY - dirX * planeY)
        local transformX = invDet * (dirY * dx - dirX * dy)
        local transformY = invDet * (-planeY * dx + planeX * dy)

        -- Behind camera check
        if transformY > 0.1 then
            -- Screen X position
            local spriteScreenX = math_floor((VP_W / 2) * (1 + transformX / transformY))

            -- Sprite height/width on screen (full tile height = VP_H / transformY, enemy is ~0.7 tall)
            local spriteH = math_floor(math_abs(VP_H * 0.7 / transformY))
            local spriteW = math_floor(math_abs(VP_H * 0.3 / transformY))
            if spriteW < 2 then spriteW = 2 end
            if spriteH < 2 then spriteH = 2 end

            local drawStartY = math_floor(halfH - spriteH / 2)
            local drawEndY   = drawStartY + spriteH
            local drawStartX = spriteScreenX - math_floor(spriteW / 2)
            local drawEndX   = drawStartX + spriteW

            -- Lighting
            local shade = calcLight(transformY)

            -- Color: red for alive, flash white on hit
            local r, g, b = 0.7 * shade, 0.1 * shade, 0.1 * shade
            if e.flashTimer and e.flashTimer > 0 then
                r, g, b = 1.0, 1.0, 1.0
            end
            if e.state == "dead" then
                r, g, b = 0.3 * shade, 0.0, 0.0
            end

            -- Draw column by column, depth-tested against zBuffer
            for sx = math_max(drawStartX, 0), math_min(drawEndX - 1, VP_W - 1) do
                if transformY < (zBuffer[sx] or MAX_DIST) then
                    gfx.setColorRGBA(r, g, b, 1)
                    love.graphics.rectangle("fill",
                        VP_X + sx, VP_Y + math_max(drawStartY, 0),
                        1, math_min(drawEndY, VP_H) - math_max(drawStartY, 0))
                end
            end

            -- Eyes (2 white pixels near top, if close enough and alive)
            if transformY < 8 and e.hp > 0 and spriteW >= 6 then
                local eyeY = VP_Y + drawStartY + math_floor(spriteH * 0.2)
                local eyeL = VP_X + spriteScreenX - math_floor(spriteW * 0.2)
                local eyeR = VP_X + spriteScreenX + math_floor(spriteW * 0.2)
                if eyeY >= VP_Y and eyeY < VP_Y + VP_H then
                    local eyeSz = math_max(1, math_floor(spriteW / 8))
                    gfx.setColorRGBA(1, 1, 0.3, 1)
                    if eyeL >= VP_X and eyeL < VP_X + VP_W and transformY < (zBuffer[eyeL - VP_X] or MAX_DIST) then
                        love.graphics.rectangle("fill", eyeL, eyeY, eyeSz, eyeSz)
                    end
                    if eyeR >= VP_X and eyeR < VP_X + VP_W and transformY < (zBuffer[eyeR - VP_X] or MAX_DIST) then
                        love.graphics.rectangle("fill", eyeR, eyeY, eyeSz, eyeSz)
                    end
                end
            end
        end
    end

    love.graphics.setScissor()
end

-- ============================================================================
-- VIEWPORT RENDERING
-- ============================================================================
local function drawViewport()
    -- 0. Draw skybox behind everything (visible through open-sky ceiling pixels)
    drawSkybox()

    local isLow = consoleRef and consoleRef.renderScale == "LOW"

    if isLow then
        -- LOW mode: render floor/ceiling at half resolution, scale up 2x
        local lowW = math_floor(VP_W / 2)
        local lowH = math_floor(VP_H / 2)
        renderFloorCeiling(floorCeilImageDataLow, lowW, lowH)
        floorCeilImageLow:replacePixels(floorCeilImageDataLow)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(floorCeilImageLow, VP_X, VP_Y, 0, 2, 2)
        -- Walls: skip every other column, draw 2-wide strips
        renderWalls(2)
    else
        -- CRISP mode: full resolution
        renderFloorCeiling(floorCeilImageData, VP_W, VP_H)
        floorCeilImage:replacePixels(floorCeilImageData)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(floorCeilImage, VP_X, VP_Y)
        renderWalls(1)
    end

    -- Render enemy billboards (after walls, depth-tested)
    renderEnemies()

    -- Render projectiles as small bright dots
    if projectiles and #projectiles > 0 then
        local fovRad = math.rad((consoleRef and consoleRef.fovDeg) or 60)
        local halfFov = fovRad / 2
        local halfH = VP_H / 2
        local pAngle = player.angle
        local ppx, ppy = player.x, player.y
        local dirX = math_cos(pAngle)
        local dirY = math_sin(pAngle)
        local planeScale = math.tan(halfFov)
        local planeX = -dirY * planeScale
        local planeY =  dirX * planeScale
        local invDet = 1.0 / (planeX * dirY - dirX * planeY)

        love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)
        for _, p in ipairs(projectiles) do
            local dx = p.x - ppx
            local dy = p.y - ppy
            local tX = invDet * (dirY * dx - dirX * dy)
            local tY = invDet * (-planeY * dx + planeX * dy)
            if tY > 0.1 then
                local sx = math_floor((VP_W / 2) * (1 + tX / tY))
                local sy = math_floor(halfH)
                local sz = math_max(1, math_floor(3 / tY))
                if sx >= 0 and sx < VP_W and tY < (zBuffer[sx] or MAX_DIST) then
                    gfx.setColorRGBA(1, 1, 0.5, 1)
                    love.graphics.rectangle("fill", VP_X + sx - sz, VP_Y + sy - sz, sz * 2 + 1, sz * 2 + 1)
                end
            end
        end
        love.graphics.setScissor()
    end
end

-- ============================================================================
-- MINIMAP
-- ============================================================================
local function drawMinimap()
    local mx, my = RPANEL_X + 2, RPANEL_Y + 2
    local mw, mh = RPANEL_W - 4, 80
    local cellSize = 5
    local viewRadius = 7

    -- Panel background
    gfx.rect(mx, my, mw, mh, 0)
    gfx.rectLine(mx, my, mw, mh, 8)

    for dy = -viewRadius, viewRadius do
        for dx = -viewRadius, viewRadius do
            local wx = math_floor(player.x) + dx
            local wy = math_floor(player.y) + dy
            local px = mx + math_floor(mw / 2) + dx * cellSize - math_floor(cellSize / 2)
            local py = my + math_floor(mh / 2) + dy * cellSize - math_floor(cellSize / 2)

            if px >= mx and py >= my and px + cellSize <= mx + mw and py + cellSize <= my + mh then
                if wx >= 1 and wy >= 1 and wx <= mapW and wy <= mapH then
                    local tile = getTile(wx, wy)
                    local col = TILE_COLORS[tile] or 0
                    gfx.rect(px, py, cellSize, cellSize, col)
                end
            end
        end
    end

    -- Pickup markers on minimap
    local playerMX = math_floor(player.x)
    local playerMY = math_floor(player.y)
    for _, e in ipairs(entities) do
        if e.type == "pickup" then
            local edx = e.x - playerMX
            local edy = e.y - playerMY
            if math_abs(edx) <= viewRadius and math_abs(edy) <= viewRadius then
                local epx = mx + math_floor(mw / 2) + edx * cellSize - math_floor(cellSize / 2)
                local epy = my + math_floor(mh / 2) + edy * cellSize - math_floor(cellSize / 2)
                if epx >= mx and epy >= my and epx + cellSize <= mx + mw and epy + cellSize <= my + mh then
                    gfx.setColor(14) -- yellow dot for pickup
                    love.graphics.rectangle("fill", epx + 1, epy + 1, cellSize - 2, cellSize - 2)
                end
            end
        end
    end

    -- Enemy markers on minimap (red blinking dots)
    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            local edx = math_floor(e.x) - playerMX
            local edy = math_floor(e.y) - playerMY
            if math_abs(edx) <= viewRadius and math_abs(edy) <= viewRadius then
                local epx = mx + math_floor(mw / 2) + edx * cellSize - math_floor(cellSize / 2)
                local epy = my + math_floor(mh / 2) + edy * cellSize - math_floor(cellSize / 2)
                if epx >= mx and epy >= my and epx + cellSize <= mx + mw and epy + cellSize <= my + mh then
                    gfx.setColor(4) -- dark red for enemies
                    love.graphics.rectangle("fill", epx + 1, epy + 1, cellSize - 2, cellSize - 2)
                end
            end
        end
    end

    -- Player marker: dot + direction line
    local pcx = mx + math_floor(mw / 2)
    local pcy = my + math_floor(mh / 2)

    -- Direction line
    local lineLen = 6
    local tipX = pcx + math_cos(player.angle) * lineLen
    local tipY = pcy + math_sin(player.angle) * lineLen
    gfx.setColor(14) -- yellow
    love.graphics.setLineWidth(1)
    love.graphics.line(pcx, pcy, tipX, tipY)

    -- Player dot
    gfx.setColor(12) -- red
    love.graphics.rectangle("fill", pcx - 1, pcy - 1, 3, 3)
end

-- ============================================================================
-- STATS PANEL
-- ============================================================================
local function drawStatBar(x, y, w, h, current, max, fgCol, bgCol)
    gfx.rect(x, y, w, h, bgCol or 0)
    local fw = math_floor(w * math_max(current, 0) / max)
    if fw > 0 then gfx.rect(x, y, fw, h, fgCol) end
    gfx.rectLine(x, y, w, h, 0)
end

local function drawStats()
    local sx = RPANEL_X + 2
    local sy = RPANEL_Y + 86
    local barW = RPANEL_W - 6

    -- HP bar
    gfx.print("HP", sx, sy, 12)
    drawStatBar(sx + 16, sy + 1, barW - 16, 6, player.hp, player.hpMax, 4, 0)
    local hpStr = math_floor(player.hp) .. "/" .. player.hpMax
    gfx.print(hpStr, sx + barW - gfx.textWidth(hpStr), sy, 7)

    -- Stamina bar
    sy = sy + 10
    gfx.print("ST", sx, sy, 14)
    drawStatBar(sx + 16, sy + 1, barW - 16, 6, player.stam, player.stamMax, 6, 0)
    local stStr = math_floor(player.stam) .. "/" .. player.stamMax
    gfx.print(stStr, sx + barW - gfx.textWidth(stStr), sy, 7)

    -- Compact position + torch
    sy = sy + 12
    local deg = math_floor(math.deg(player.angle) % 360)
    gfx.print(string.format("%.0f,%.0f %d", player.x, player.y, deg), sx, sy, 8)
    sy = sy + 10
    local torchCol = torchEnabled and 14 or 8
    gfx.print("TORCH:" .. (torchEnabled and "ON" or "OFF"), sx, sy, torchCol)
end

-- ============================================================================
-- MESSAGE BOX
-- ============================================================================
local function drawMessageBox()
    gfx.rect(MSG_X, MSG_Y, MSG_W, MSG_H, 0)
    gfx.rectLine(MSG_X, MSG_Y, MSG_W, MSG_H, 8)

    local tx = MSG_X + 3
    local ty = MSG_Y + 3
    local maxLines = math_floor((MSG_H - 6) / 8)
    local start = math_max(1, #msgLog - maxLines + 1)
    for i = start, #msgLog do
        gfx.print(msgLog[i], tx, ty, 7)
        ty = ty + 8
    end
end

-- ============================================================================
-- INVENTORY UI
-- ============================================================================
local function drawInventory()
    if not invOpen then return end

    -- Dark backdrop
    gfx.setColorRGBA(0, 0, 0, 0.70)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    -- Panel dimensions
    local cellSz = 22
    local pad = 4
    local pw = INV_COLS * cellSz + pad * 2 + 2
    local ph = INV_ROWS * cellSz + pad * 2 + 30  -- extra for title + equip info
    local px = math_floor((VIRT_W - pw) / 2)
    local py = math_floor((VIRT_H - ph) / 2)

    -- Panel background + border (Windows 92 style bevel)
    gfx.rect(px, py, pw, ph, 7)
    -- Raised bevel
    gfx.setColor(15)
    love.graphics.line(px, py, px + pw - 1, py)
    love.graphics.line(px, py, px, py + ph - 1)
    gfx.setColor(8)
    love.graphics.line(px + pw - 1, py, px + pw - 1, py + ph - 1)
    love.graphics.line(px, py + ph - 1, px + pw - 1, py + ph - 1)

    -- Title bar
    gfx.rect(px + 2, py + 2, pw - 4, 10, 1)
    gfx.print("INVENTORY", px + 4, py + 3, 15)
    gfx.print("[I]", px + pw - 20, py + 3, 14)

    -- Grid origin
    local gx = px + pad + 1
    local gy = py + 14

    -- Draw grid cells
    for i = 0, INV_SIZE - 1 do
        local col = i % INV_COLS
        local row = math_floor(i / INV_COLS)
        local cx = gx + col * cellSz
        local cy = gy + row * cellSz
        local slotIdx = i + 1

        -- Cell sunken background
        gfx.rect(cx, cy, cellSz - 1, cellSz - 1, 0)
        gfx.setColor(8)
        love.graphics.line(cx, cy, cx + cellSz - 2, cy)
        love.graphics.line(cx, cy, cx, cy + cellSz - 2)
        gfx.setColor(15)
        love.graphics.line(cx + cellSz - 2, cy, cx + cellSz - 2, cy + cellSz - 2)
        love.graphics.line(cx, cy + cellSz - 2, cx + cellSz - 2, cy + cellSz - 2)

        -- Item in slot
        local slot = inventory[slotIdx]
        if slot then
            local db = ITEM_DB[slot.id]
            if db then
                -- Colored icon square
                gfx.rect(cx + 3, cy + 3, cellSz - 7, cellSz - 7, db.iconCol or 7)
                -- First letter overlay
                gfx.print(db.name:sub(1, 1), cx + 5, cy + 4, 0)
                -- Quantity (bottom-right)
                if slot.qty > 1 then
                    local qs = tostring(slot.qty)
                    gfx.print(qs, cx + cellSz - 3 - gfx.textWidth(qs), cy + cellSz - 10, 15)
                end
                -- Equip indicator
                if slotIdx == equipMelee or slotIdx == equipRanged or slotIdx == equipArmor then
                    gfx.print("E", cx + 1, cy + 1, 14)
                end
            end
        end

        -- Cursor highlight
        if i == invCursor then
            gfx.setColor(14)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", cx - 1, cy - 1, cellSz + 1, cellSz + 1)
        end
    end

    -- Info area below grid
    local infoY = gy + INV_ROWS * cellSz + 2
    local selSlot = inventory[invCursor + 1]
    if selSlot then
        local db = ITEM_DB[selSlot.id]
        if db then
            gfx.print(db.name, px + pad, infoY, 15)
            local desc = db.type:upper()
            if db.dmg then desc = desc .. " DMG:" .. db.dmg end
            if db.heal then desc = desc .. " HEAL:" .. db.heal end
            gfx.print(desc, px + pad, infoY + 8, 7)
        end
    else
        gfx.print("EMPTY SLOT", px + pad, infoY, 8)
    end

    -- Controls hint
    gfx.print("A:USE/EQUIP  B:CLOSE", px + pad, py + ph - 10, 8)
end

-- ============================================================================
-- BEVEL HELPER
-- ============================================================================
local function drawBevel(x, y, w, h)
    gfx.rect(x, y, w, h, 7)
    gfx.line(x, y, x + w - 1, y, 15)
    gfx.line(x, y, x, y + h - 1, 15)
    gfx.line(x + w - 1, y, x + w - 1, y + h - 1, 8)
    gfx.line(x, y + h - 1, x + w - 1, y + h - 1, 8)
end

local function loadTextureData(img)
    -- Convert a love.graphics.Image to ImageData for pixel sampling
    local w, h = img:getWidth(), img:getHeight()
    local canvas = love.graphics.newCanvas(w, h)
    local prevCanvas = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace")
    love.graphics.draw(img, 0, 0)
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas(prevCanvas)
    local data = canvas:newImageData()
    return data
end

-- Compute average RGB color from ImageData (for editor swatches)
local function computeAvgColor(imgData)
    local w, h = imgData:getWidth(), imgData:getHeight()
    local rr, gg, bb = 0, 0, 0
    local count = w * h
    for py = 0, h - 1 do
        for px = 0, w - 1 do
            local r, g, b = imgData:getPixel(px, py)
            rr = rr + r; gg = gg + g; bb = bb + b
        end
    end
    return { rr / count, gg / count, bb / count }
end

-- ============================================================================
-- MATERIAL PALETTE HELPERS
-- ============================================================================
local EDIT_MODE_NAMES = { "COLLISION", "WALL MAT", "FLOOR MAT", "CEIL MAT", "ENEMIES" }
local EDIT_MODE_CATS  = { nil, "walls", "floor", "ceil", nil }

local function getPaletteList()
    local cat = EDIT_MODE_CATS[editMode]
    if not cat then return nil end
    return texCatalog[cat]
end

-- For ceiling mode, palette index 0 = "OPEN SKY" (nil ceilMat)
local function getSelectedMatKey()
    if editMode == 4 and paletteSel == 0 then
        return nil  -- open sky
    end
    local list = getPaletteList()
    if not list or #list == 0 then return "default" end
    local idx = clamp(paletteSel, 1, #list)
    return list[idx].key
end

-- ============================================================================
-- EDIT MODE DRAWING
-- ============================================================================
local function drawEditGrid()
    -- Fill viewport area with top-down grid
    local gridArea_W = VP_W
    local gridArea_H = VP_H

    -- Calculate cell size to fit the map in the viewport
    local cellW = math_floor(gridArea_W / mapW)
    local cellH = math_floor(gridArea_H / mapH)
    local cellSize = math_min(cellW, cellH)
    if cellSize < 2 then cellSize = 2 end

    -- Center the grid in viewport
    local totalW = cellSize * mapW
    local totalH = cellSize * mapH
    local ox = VP_X + math_floor((gridArea_W - totalW) / 2)
    local oy = VP_Y + math_floor((gridArea_H - totalH) / 2)

    -- Background
    gfx.rect(VP_X, VP_Y, VP_W, VP_H, 0)

    -- Draw each cell
    for y = 1, mapH do
        for x = 1, mapW do
            local tile = getTile(x, y)
            local col = TILE_COLORS[tile] or 0
            local px = ox + (x - 1) * cellSize
            local py = oy + (y - 1) * cellSize
            gfx.rect(px, py, cellSize, cellSize, col)

            -- Material swatch overlay based on edit mode
            local swatchColor = nil
            if editMode == 2 then
                -- Wall material: show on wall tiles only
                if tile == TILE_WALL then
                    local key = getWallMat(x, y)
                    if key then
                        local entry = resolveTexEntry("walls", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    end
                end
            elseif editMode == 3 then
                -- Floor material: show on walkable tiles (empty, door, start)
                if tile == TILE_EMPTY or tile == TILE_DOOR or tile == TILE_START then
                    local key = getFloorMat(x, y)
                    if key then
                        local entry = resolveTexEntry("floor", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    end
                end
            elseif editMode == 4 then
                -- Roof material: show on all non-wall tiles
                if tile ~= TILE_WALL then
                    local key = getCeilMat(x, y)
                    if key then
                        local entry = resolveTexEntry("ceil", key)
                        if entry and entry.avgColor then
                            swatchColor = entry.avgColor
                        end
                    else
                        -- nil ceilMat = open sky: small blue corner indicator
                        if cellSize >= 4 then
                            gfx.setColorRGBA(0.15, 0.15, 0.55, 1)
                            local cSz = math_max(2, math_floor(cellSize / 3))
                            love.graphics.rectangle("fill", px, py, cSz, cSz)
                        end
                    end
                end
            end

            if swatchColor then
                -- Draw a subtle swatch: fill interior with 70% opacity average color
                gfx.setColorRGBA(swatchColor[1], swatchColor[2], swatchColor[3], 0.70)
                love.graphics.rectangle("fill", px + 1, py + 1, cellSize - 2, cellSize - 2)
            end

            -- Draw grid lines (dark gray border between cells)
            gfx.setColor(8)
            love.graphics.rectangle("line", px, py, cellSize, cellSize)
        end
    end

    -- Draw enemy spawn markers (red "E" or red squares)
    for _, s in ipairs(enemySpawns) do
        local esx = ox + (s.x - 1) * cellSize
        local esy = oy + (s.y - 1) * cellSize
        if cellSize >= 6 then
            gfx.setColor(4) -- dark red bg
            love.graphics.rectangle("fill", esx + 1, esy + 1, cellSize - 2, cellSize - 2)
            gfx.print("E", esx + 1, esy, 12)
        else
            gfx.setColor(12)
            love.graphics.rectangle("fill", esx, esy, cellSize, cellSize)
        end
    end

    -- Draw player start marker (always visible, even if tile is overwritten)
    local psx = ox + (playerStartX - 1) * cellSize
    local psy = oy + (playerStartY - 1) * cellSize
    -- Small "P" marker
    if cellSize >= 6 then
        gfx.print("P", psx + 1, psy, 15)
    else
        gfx.setColor(15)
        love.graphics.rectangle("fill", psx + 1, psy + 1, cellSize - 2, cellSize - 2)
    end

    -- Draw cursor highlight (red border)
    local cx = ox + (cursorX - 1) * cellSize
    local cy = oy + (cursorY - 1) * cellSize
    gfx.setColor(12) -- red
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", cx, cy, cellSize, cellSize)
    love.graphics.rectangle("line", cx + 1, cy + 1, cellSize - 2, cellSize - 2)

    -- Viewport border
    gfx.rectLine(VP_X, VP_Y, VP_W, VP_H, 8)
end

local function drawEditPanel()
    drawBevel(RPANEL_X, RPANEL_Y, RPANEL_W, RPANEL_H)

    local sx = RPANEL_X + 3
    local sy = RPANEL_Y + 3
    local pw = RPANEL_W - 6

    -- Mode title with number keys
    gfx.print(EDIT_MODE_NAMES[editMode] or "?", sx, sy, 0)
    sy = sy + 10

    -- Mode selector: 1-5 tabs
    for i = 1, 5 do
        local label = tostring(i)
        local col = (i == editMode) and 15 or 8
        gfx.print(label, sx + (i - 1) * 12, sy, col)
    end
    sy = sy + 10

    -- Cursor position
    gfx.print("CUR:" .. cursorX .. "," .. cursorY, sx, sy, 7)
    sy = sy + 10

    if editMode == 1 then
        -- Collision mode: show brush + legend
        local curTile = getTile(cursorX, cursorY)
        gfx.print("TILE:" .. (TILE_NAMES[curTile] or "?"), sx, sy, 7)
        sy = sy + 10

        gfx.print("BRUSH:", sx, sy, 15)
        sy = sy + 9
        local brushCol = TILE_COLORS[brushType] or 0
        gfx.rect(sx, sy, 6, 6, brushCol)
        gfx.rectLine(sx, sy, 6, 6, 15)
        gfx.print(TILE_NAMES[brushType] or "?", sx + 9, sy, 14)
        sy = sy + 10

        for _, tileType in ipairs(BRUSH_ORDER) do
            local col = TILE_COLORS[tileType]
            gfx.rect(sx, sy, 6, 6, col)
            gfx.rectLine(sx, sy, 6, 6, 8)
            gfx.print(TILE_NAMES[tileType], sx + 9, sy, 7)
            sy = sy + 8
        end
    elseif editMode == 5 then
        -- Enemy spawn mode: show spawn count + instructions
        gfx.print("SPAWNS:" .. #enemySpawns, sx, sy, 12)
        sy = sy + 10
        -- Check if cursor is on a spawn
        local onSpawn = false
        for _, s in ipairs(enemySpawns) do
            if s.x == cursorX and s.y == cursorY then onSpawn = true; break end
        end
        gfx.print(onSpawn and "HAS SPAWN" or "NO SPAWN", sx, sy, onSpawn and 12 or 8)
        sy = sy + 10
        gfx.print("A:PLACE", sx, sy, 7)
        sy = sy + 8
        gfx.print("X:REMOVE", sx, sy, 7)
    else
        -- Material mode: show palette list
        local list = getPaletteList()
        if list and #list > 0 then
            -- Current tile material
            local curKey = "default"
            if editMode == 2 then curKey = getWallMat(cursorX, cursorY) or "default"
            elseif editMode == 3 then curKey = getFloorMat(cursorX, cursorY) or "default"
            elseif editMode == 4 then curKey = getCeilMat(cursorX, cursorY)
            end
            local curLabel = curKey and curKey:sub(1, 12) or "OPEN SKY"
            gfx.print("CUR:" .. curLabel, sx, sy, 7)
            sy = sy + 10

            gfx.print("Q/E:SELECT", sx, sy, 8)
            sy = sy + 10

            -- Palette list (ceiling mode has index 0 = OPEN SKY)
            local maxVisible = math_floor((RPANEL_H - sy + RPANEL_Y - 20) / 10)
            local scroll = paletteScroll or 0

            -- Draw OPEN SKY entry for ceiling mode
            if editMode == 4 then
                local isSel = (paletteSel == 0)
                if isSel then
                    gfx.rect(sx - 1, sy, pw + 2, 9, 1)
                end
                -- Sky swatch: dark blue block
                gfx.setColorRGBA(0.05, 0.05, 0.15, 1)
                love.graphics.rectangle("fill", sx, sy + 1, 7, 7)
                gfx.rectLine(sx, sy + 1, 7, 7, 9)
                local nameCol = isSel and 14 or 7
                gfx.print("OPEN SKY", sx + 9, sy, nameCol)
                sy = sy + 10
                maxVisible = maxVisible - 1
            end

            for vi = 1, maxVisible do
                local idx = scroll + vi
                if idx > #list then break end
                local entry = list[idx]
                local isSel = (idx == paletteSel)

                if isSel then
                    gfx.rect(sx - 1, sy, pw + 2, 9, 1)
                end

                -- Small texture swatch
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setScissor(sx, sy + 1, 7, 7)
                love.graphics.draw(entry.img, sx, sy + 1, 0, 7 / entry.w, 7 / entry.h)
                love.graphics.setScissor()

                -- Name
                local nameCol = isSel and 14 or 7
                local shortName = entry.key:sub(1, 10)
                gfx.print(shortName, sx + 9, sy, nameCol)
                sy = sy + 10
            end
        else
            if editMode == 4 then
                -- Ceiling with no roof textures: still show OPEN SKY
                local isSel = (paletteSel == 0)
                if isSel then
                    gfx.rect(sx - 1, sy, pw + 2, 9, 1)
                end
                gfx.setColorRGBA(0.05, 0.05, 0.15, 1)
                love.graphics.rectangle("fill", sx, sy + 1, 7, 7)
                gfx.rectLine(sx, sy + 1, 7, 7, 9)
                gfx.print("OPEN SKY", sx + 9, sy, 14)
                sy = sy + 10
            else
                gfx.print("NO TEXTURES", sx, sy, 12)
            end
        end
    end

    -- Bottom hint
    gfx.print("H/Y:HELP", sx, RPANEL_Y + RPANEL_H - 10, 14)
end

-- ============================================================================
-- HELP OVERLAY (edit mode)
-- ============================================================================
local EDIT_HELP_LINES = {
    "=== EDIT MODE CONTROLS ===",
    "",
    "ARROWS/DPAD Move cursor",
    "A ......... Paint (brush/material)",
    "B ......... Cycle brush / palette fwd",
    "X / R ..... Erase / reset to default",
    "S ......... Save map to file",
    "L ......... Load map from file",
    "P ......... Test play from start",
    "T ......... Open tracker editor",
    "F1/SELECT . Toggle play/edit mode",
    "H / Y ..... Toggle this help",
    "",
    "=== PAINT MODES ===",
    "",
    "1-5 / L1 .. Cycle paint mode",
    "  1: Collision  2: Wall material",
    "  3: Floor mat  4: Ceiling/roof",
    "  5: Enemy spawns",
    "Q/E ....... Select texture in palette",
    "X / R ..... Reset (ceil: set to sky)",
    "",
    "=== BRUSH TYPES (mode 1) ===",
    "",
    "WALL ...... Solid wall (gray)",
    "EMPTY ..... Open space (black)",
    "DOOR ...... Door tile (blue)",
    "STAIRS .... Level exit (yellow)",
    "START ..... Player spawn (green)",
    "",
    "=== PLAY MODE ===",
    "",
    "ARROWS/DPAD Move / turn",
    "A ......... Melee attack",
    "B ......... Ranged attack",
    "X / F ..... Toggle torch",
    "I / Y ..... Inventory",
    "F1/SELECT . Back to edit mode",
    "START/ESC . Pause menu",
}

local function drawHelpOverlay(lines)
    -- Dark backdrop
    gfx.setColorRGBA(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    -- Centered panel
    local pw, ph = 220, 160
    local px = math_floor((VIRT_W - pw) / 2)
    local py = math_floor((VIRT_H - ph) / 2)

    -- Panel background + border
    gfx.rect(px, py, pw, ph, 0)
    gfx.rectLine(px, py, pw, ph, 7)

    -- Inner border (raised bevel look)
    gfx.setColor(15)
    love.graphics.line(px + 1, py + 1, px + pw - 2, py + 1)
    love.graphics.line(px + 1, py + 1, px + 1, py + ph - 2)
    gfx.setColor(8)
    love.graphics.line(px + pw - 2, py + 1, px + pw - 2, py + ph - 2)
    love.graphics.line(px + 1, py + ph - 2, px + pw - 2, py + ph - 2)

    -- Title bar
    gfx.rect(px + 2, py + 2, pw - 4, 10, 1)
    gfx.print("HELP", px + 4, py + 3, 15)
    gfx.print("[H] CLOSE", px + pw - 60, py + 3, 14)

    -- Content area
    local contentY = py + 14
    local contentH = ph - 28
    local maxLines = math_floor(contentH / 8)
    local scroll = helpScroll or 0
    local totalLines = #lines

    for i = 1, maxLines do
        local lineIdx = scroll + i
        if lineIdx > totalLines then break end
        local line = lines[lineIdx]
        local col = 7
        if line:sub(1, 3) == "===" then col = 14 end
        gfx.print(line, px + 6, contentY + (i - 1) * 8, col)
    end

    -- Scroll indicator
    if totalLines > maxLines then
        local barX = px + pw - 6
        local barY = contentY
        local barH = contentH
        local thumbH = math_max(4, math_floor(barH * maxLines / totalLines))
        local thumbY = barY + math_floor((barH - thumbH) * scroll / math_max(1, totalLines - maxLines))
        gfx.rect(barX, barY, 3, barH, 0)
        gfx.rect(barX, thumbY, 3, thumbH, 7)
    end

    -- Bottom hint
    gfx.print("UP/DN:SCROLL  H:CLOSE", px + 6, py + ph - 10, 8)
end

-- ============================================================================
-- CART INTERFACE (split into helpers to stay under LuaJIT 60-upvalue limit)
-- ============================================================================

-- Helper: load textures and build catalog (~25 upvalues)
local function initTextures()
    texCatalog = { walls = {}, floor = {}, ceil = {} }
    texByKey = {}
    skyQuadObj = nil  -- reset cached skybox quad

    local function registerTex(catName, key, img)
        img:setFilter("nearest", "nearest")
        img:setWrap("repeat", "repeat")
        local data = loadTextureData(img)
        local entry = {
            key  = key,
            img  = img,
            data = data,
            w    = img:getWidth(),
            h    = img:getHeight(),
            avgColor = computeAvgColor(data),
        }
        table.insert(texCatalog[catName], entry)
        texByKey[catName .. "/" .. key] = entry
    end

    -- Load wall textures from assets
    if assets and assets.categories then
        for key, img in pairs(assets.categories.walls or {}) do
            registerTex("walls", key, img)
        end
        for key, img in pairs(assets.categories.floor or {}) do
            registerTex("floor", key, img)
        end
        -- roof category -> ceil catalog (roof textures for indoor ceilings)
        for key, img in pairs(assets.categories.roof or {}) do
            registerTex("ceil", key, img)
        end

        -- Load skybox from bg category (first found image)
        texSky = nil
        texSkyW, texSkyH = 0, 0
        for _, img in pairs(assets.categories.bg or {}) do
            texSky = img
            texSky:setFilter("nearest", "nearest")
            texSky:setWrap("repeat", "clampzero")
            texSkyW = texSky:getWidth()
            texSkyH = texSky:getHeight()
            break  -- use first bg texture as skybox
        end
    end

    -- Ensure at least one fallback per category
    if #texCatalog.walls == 0 then
        registerTex("walls", "default", buildFallbackTexture(16, 16,
            {0.50, 0.35, 0.25, 1}, {0.40, 0.28, 0.18, 1}))
    end
    if #texCatalog.floor == 0 then
        registerTex("floor", "default", buildFallbackTexture(16, 16,
            {0.35, 0.25, 0.15, 1}, {0.28, 0.20, 0.12, 1}))
    end
    if #texCatalog.ceil == 0 then
        registerTex("ceil", "default", buildFallbackTexture(16, 16,
            {0.25, 0.25, 0.35, 1}, {0.20, 0.20, 0.30, 1}))
    end

    -- Default textures (first in each catalog) for backward compat
    texWall  = texCatalog.walls[1].img
    texFloor = texCatalog.floor[1].img
    texCeil  = texCatalog.ceil[1].img
    texWallW, texWallH   = texWall:getWidth(), texWall:getHeight()
    texFloorW, texFloorH = texFloor:getWidth(), texFloor:getHeight()
    texCeilW, texCeilH   = texCeil:getWidth(), texCeil:getHeight()
    floorTexData = texCatalog.floor[1].data
    ceilTexData  = texCatalog.ceil[1].data
end

-- Helper: init rendering resources (~15 upvalues)
local function initRendering()
    initQuadMesh()

    -- Init floor/ceiling image (same size as viewport)
    floorCeilImageData = love.image.newImageData(VP_W, VP_H)
    floorCeilImage = love.graphics.newImage(floorCeilImageData)
    floorCeilImage:setFilter("nearest", "nearest")

    -- Init low-res floor/ceiling image (half size)
    local lowW = math_floor(VP_W / 2)
    local lowH = math_floor(VP_H / 2)
    floorCeilImageDataLow = love.image.newImageData(lowW, lowH)
    floorCeilImageLow = love.graphics.newImage(floorCeilImageDataLow)
    floorCeilImageLow:setFilter("nearest", "nearest")

    -- Z-buffer for minimap/debugging
    zBuffer = {}
    for i = 0, VP_W - 1 do zBuffer[i] = MAX_DIST end
end

-- Helper: init game state (~30 upvalues)
local function initGameState()
    -- Default player start
    playerStartX = 2
    playerStartY = 2

    -- Try loading saved map, fall back to default
    if not loadMapFromFile() then
        loadMapDefault()
    end

    -- Player start (1-based world coords, facing east)
    player = {
        x     = playerStartX + 0.5,
        y     = playerStartY + 0.5,
        angle = 0,
        hpMax  = 100, hp  = 100,
        stamMax = 100, stam = 100,
        dead = false,
        deathTimer = 0,
        attackCooldown = 0,  -- blocks stam regen while > 0
    }

    -- Inventory
    inventory = {}
    for i = 1, INV_SIZE do inventory[i] = nil end
    equipMelee  = nil
    equipRanged = nil
    equipArmor  = nil
    invOpen   = false
    invCursor = 0

    -- Entities (pickups on map)
    initDefaultEntities()

    -- Enemies
    initDefaultEnemySpawns()
    spawnEnemiesFromSpawns()

    -- Projectiles + combat
    projectiles = {}
    screenShake = nil
    meleeFlash = 0

    -- Torch / lighting
    torchEnabled = true

    -- Edit mode state
    mode = "play"
    cursorX = 1
    cursorY = 1
    brushType = TILE_WALL
    stepTimer = 0
    showHelp = false
    helpScroll = 0
    editMode = 1       -- 1=collision, 2=wall, 3=floor, 4=ceil
    paletteSel = 1     -- (reset to 0 when switching to ceil mode)
    paletteScroll = 0

    -- Tutorial state
    hasMovedOnce = false

    -- Message log
    msgLog = {}
    addLog("RAYCAST DUNGEON")
    addLog("A:MELEE B:RANGED I:INV")
    addLog("F1:EDIT  ESC:PAUSE")
end

function cart.init(console)
    gfx    = console.gfx
    assets = console.assets
    sfx    = console.sfx
    input  = console.input
    trackerRef = console.tracker
    consoleRef = console

    initTextures()
    initRendering()
    initGameState()
end

function cart.reset(console)
    cart.init(console)
end

function cart.update(dt, console)
    if mode == "edit" then
        -- No continuous update needed in edit mode
        return
    end

    -- Death timer: count down then respawn
    if player.dead then
        player.deathTimer = player.deathTimer - dt
        if player.deathTimer <= 0 then
            applyPlayerStart()
            addLog("Respawned.")
        end
        return  -- block all input while dead
    end

    -- Stamina regen (only when not recently attacking)
    player.attackCooldown = math_max(0, player.attackCooldown - dt)
    if player.attackCooldown <= 0 then
        player.stam = math.min(player.stamMax, player.stam + STAM_REGEN * dt)
    end

    -- Update enemies (runs even with inventory open — they don't wait for you)
    updateEnemies(dt)

    -- Update projectiles
    updateProjectiles(dt)

    -- Screen shake timer
    if screenShake then
        screenShake.timer = screenShake.timer - dt
        if screenShake.timer <= 0 then screenShake = nil end
    end

    -- Melee flash timer
    if meleeFlash > 0 then
        meleeFlash = meleeFlash - dt
    end

    -- Block movement while inventory is open
    if invOpen then return end

    -- PLAY MODE: smooth movement via held keys
    local moved = false
    local walking = false  -- true if actually translating (UP/DOWN)

    if input.held.LEFT then
        player.angle = player.angle - ROT_SPEED * dt
        moved = true
    end
    if input.held.RIGHT then
        player.angle = player.angle + ROT_SPEED * dt
        moved = true
    end

    -- Turn sound on direction change start
    if input.justPressed.LEFT or input.justPressed.RIGHT then
        if sfx then sfx.play("turn") end
    end

    -- Normalize angle to [0, 2pi)
    player.angle = player.angle % (2 * math.pi)

    local dx = math_cos(player.angle)
    local dy = math_sin(player.angle)

    if input.held.UP then
        local nx = player.x + dx * MOVE_SPEED * dt
        local ny = player.y + dy * MOVE_SPEED * dt
        -- Collision: check with margin (player coords are 1-based, floor gives tile index)
        local margin = 0.2
        local py = player.y
        if not isWall(math_floor(nx + margin), math_floor(py + margin)) and
           not isWall(math_floor(nx - margin), math_floor(py + margin)) and
           not isWall(math_floor(nx + margin), math_floor(py - margin)) and
           not isWall(math_floor(nx - margin), math_floor(py - margin)) then
            player.x = nx
        end
        local px = player.x
        if not isWall(math_floor(px + margin), math_floor(ny + margin)) and
           not isWall(math_floor(px - margin), math_floor(ny + margin)) and
           not isWall(math_floor(px + margin), math_floor(ny - margin)) and
           not isWall(math_floor(px - margin), math_floor(ny - margin)) then
            player.y = ny
        end
        moved = true
        walking = true
    end

    if input.held.DOWN then
        local nx = player.x - dx * MOVE_SPEED * dt
        local ny = player.y - dy * MOVE_SPEED * dt
        local margin = 0.2
        local py = player.y
        if not isWall(math_floor(nx + margin), math_floor(py + margin)) and
           not isWall(math_floor(nx - margin), math_floor(py + margin)) and
           not isWall(math_floor(nx + margin), math_floor(py - margin)) and
           not isWall(math_floor(nx - margin), math_floor(py - margin)) then
            player.x = nx
        end
        local px = player.x
        if not isWall(math_floor(px + margin), math_floor(ny + margin)) and
           not isWall(math_floor(px - margin), math_floor(ny + margin)) and
           not isWall(math_floor(px + margin), math_floor(ny - margin)) and
           not isWall(math_floor(px - margin), math_floor(ny - margin)) then
            player.y = ny
        end
        moved = true
        walking = true
    end

    -- Stamina drain while walking (MOVE_COST per tile, at MOVE_SPEED tiles/sec)
    if walking then
        player.stam = math_max(0, player.stam - MOVE_COST * MOVE_SPEED * dt)
    end

    -- Check for item pickups at player position
    if walking then
        checkPickups()
    end

    -- Footstep sound throttle
    if input.held.UP or input.held.DOWN then
        stepTimer = stepTimer + dt
        if stepTimer >= STEP_INTERVAL then
            stepTimer = stepTimer - STEP_INTERVAL
            if sfx then sfx.play("step") end
        end
    else
        stepTimer = 0
    end

    -- Death check
    if player.hp <= 0 and not player.dead then
        player.dead = true
        player.deathTimer = DEATH_DELAY
        addLog("You died!")
    end

    -- After first movement, reduce tutorial to minimal status
    if moved and not hasMovedOnce then
        hasMovedOnce = true
        msgLog = {}
        addLog("F1:EDIT  ESC:PAUSE")
    end
end

-- Helper: toggle play/edit mode (shared by F1 key and SELECT action)
local function toggleEditMode()
    showHelp = false
    helpScroll = 0
    if mode == "play" then
        mode = "edit"
        cursorX = clamp(math_floor(player.x), 1, mapW)
        cursorY = clamp(math_floor(player.y), 1, mapH)
        addLog("ENTERED EDIT MODE")
    else
        mode = "play"
        applyPlayerStart()
        addLog("ENTERED PLAY MODE")
    end
    if sfx then sfx.play("ui_select") end
end

-- Helper: erase/reset at cursor (shared by R key and X action in edit mode)
local function eraseAtCursor()
    if editMode == 1 then
        setTile(cursorX, cursorY, TILE_EMPTY)
        addLog("CLEARED @" .. cursorX .. "," .. cursorY)
    elseif editMode == 2 then
        setWallMat(cursorX, cursorY, "default")
        addLog("WALL RESET @" .. cursorX .. "," .. cursorY)
    elseif editMode == 3 then
        setFloorMat(cursorX, cursorY, "default")
        addLog("FLOOR RESET @" .. cursorX .. "," .. cursorY)
    elseif editMode == 4 then
        setCeilMat(cursorX, cursorY, nil)
        addLog("CEIL->SKY @" .. cursorX .. "," .. cursorY)
    elseif editMode == 5 then
        -- Remove enemy spawn at cursor
        for i = #enemySpawns, 1, -1 do
            if enemySpawns[i].x == cursorX and enemySpawns[i].y == cursorY then
                table.remove(enemySpawns, i)
                addLog("SPAWN REMOVED @" .. cursorX .. "," .. cursorY)
            end
        end
    end
    if sfx then sfx.play("paint") end
end

-- Helper: cycle edit submode forward 1->2->3->4->1
local function cycleEditSubmode()
    editMode = editMode + 1
    if editMode > 5 then editMode = 1 end
    paletteSel = (editMode == 4) and 0 or 1
    paletteScroll = 0
    addLog("MODE: " .. EDIT_MODE_NAMES[editMode])
    if sfx then sfx.play("ui_move") end
end

-- Helper: cycle palette selection forward (shared by E key and B action in material modes)
local function paletteNext()
    local list = getPaletteList()
    if not list or #list == 0 then return end
    local minSel = (editMode == 4) and 0 or 1
    paletteSel = paletteSel + 1
    if paletteSel > #list then paletteSel = minSel end
    local label = (paletteSel == 0) and "OPEN SKY" or list[paletteSel].key:sub(1, 12)
    addLog("SEL: " .. label)
    if sfx then sfx.play("ui_move") end
end

-- Helper: cycle palette selection backward (shared by Q key)
local function palettePrev()
    local list = getPaletteList()
    if not list or #list == 0 then return end
    local minSel = (editMode == 4) and 0 or 1
    paletteSel = paletteSel - 1
    if paletteSel < minSel then paletteSel = #list end
    local label = (paletteSel == 0) and "OPEN SKY" or list[paletteSel].key:sub(1, 12)
    addLog("SEL: " .. label)
    if sfx then sfx.play("ui_move") end
end

function cart.input(action, pressed, console)
    if not pressed then return end

    -- SELECT toggles edit/play mode (same as F1) from any mode
    if action == "SELECT" then
        toggleEditMode()
        return
    end

    if mode == "edit" then
        -- Block all mapped actions while help is showing
        if showHelp then
            -- Y closes help when it's open
            if action == "Y" then
                showHelp = false
                helpScroll = 0
            end
            return
        end
        -- Edit mode controls via mapped actions
        if action == "UP" then
            cursorY = math_max(1, cursorY - 1)
        elseif action == "DOWN" then
            cursorY = math_min(mapH, cursorY + 1)
        elseif action == "LEFT" then
            cursorX = math_max(1, cursorX - 1)
        elseif action == "RIGHT" then
            cursorX = math_min(mapW, cursorX + 1)
        elseif action == "A" then
            if editMode == 1 then
                -- Paint collision tile
                if brushType == TILE_START then
                    for y = 1, mapH do
                        for x = 1, mapW do
                            if getTile(x, y) == TILE_START then
                                setTile(x, y, TILE_EMPTY)
                            end
                        end
                    end
                    playerStartX = cursorX
                    playerStartY = cursorY
                end
                setTile(cursorX, cursorY, brushType)
                addLog("PLACED " .. (TILE_NAMES[brushType] or "?") .. " @" .. cursorX .. "," .. cursorY)
            elseif editMode == 2 then
                local key = getSelectedMatKey()
                setWallMat(cursorX, cursorY, key)
                addLog("WALL:" .. key:sub(1, 10) .. " @" .. cursorX .. "," .. cursorY)
            elseif editMode == 3 then
                local key = getSelectedMatKey()
                setFloorMat(cursorX, cursorY, key)
                addLog("FLOOR:" .. key:sub(1, 10) .. " @" .. cursorX .. "," .. cursorY)
            elseif editMode == 4 then
                local key = getSelectedMatKey()
                setCeilMat(cursorX, cursorY, key)
                local label = key and key:sub(1, 10) or "OPEN SKY"
                addLog("CEIL:" .. label .. " @" .. cursorX .. "," .. cursorY)
            elseif editMode == 5 then
                -- Place enemy spawn at cursor (no duplicates on same tile)
                local exists = false
                for _, s in ipairs(enemySpawns) do
                    if s.x == cursorX and s.y == cursorY then exists = true; break end
                end
                if not exists then
                    enemySpawns[#enemySpawns + 1] = { x = cursorX, y = cursorY }
                    addLog("ENEMY SPAWN @" .. cursorX .. "," .. cursorY)
                else
                    addLog("SPAWN EXISTS HERE")
                end
            end
            if sfx then sfx.play("paint") end
        elseif action == "B" then
            if editMode == 1 then
                -- Cycle brush (collision mode only)
                local idx = 1
                for i, bt in ipairs(BRUSH_ORDER) do
                    if bt == brushType then idx = i; break end
                end
                idx = idx + 1
                if idx > #BRUSH_ORDER then idx = 1 end
                brushType = BRUSH_ORDER[idx]
                addLog("BRUSH: " .. (TILE_NAMES[brushType] or "?"))
            else
                -- Material modes: cycle palette forward
                paletteNext()
            end
            if editMode == 1 then
                if sfx then sfx.play("ui_move") end
            end
        elseif action == "X" then
            -- Erase / reset at cursor
            eraseAtCursor()
        elseif action == "Y" then
            -- Toggle help overlay
            showHelp = not showHelp
            helpScroll = 0
        elseif action == "L1" then
            -- Cycle edit submode (collision / wall mat / floor mat / ceil mat)
            cycleEditSubmode()
        end
        return
    end

    -- PLAY MODE: inventory open — handle inventory navigation
    if invOpen then
        if action == "UP" then
            invCursor = invCursor - INV_COLS
            if invCursor < 0 then invCursor = invCursor + INV_SIZE end
            if sfx then sfx.play("ui_move") end
        elseif action == "DOWN" then
            invCursor = invCursor + INV_COLS
            if invCursor >= INV_SIZE then invCursor = invCursor - INV_SIZE end
            if sfx then sfx.play("ui_move") end
        elseif action == "LEFT" then
            invCursor = invCursor - 1
            if invCursor < 0 then invCursor = INV_SIZE - 1 end
            if sfx then sfx.play("ui_move") end
        elseif action == "RIGHT" then
            invCursor = invCursor + 1
            if invCursor >= INV_SIZE then invCursor = 0 end
            if sfx then sfx.play("ui_move") end
        elseif action == "A" then
            invUseItem(invCursor + 1)
        elseif action == "B" or action == "Y" then
            invOpen = false
            if sfx then sfx.play("ui_select") end
        end
        return
    end

    -- PLAY MODE: normal controls
    if player.dead then return end
    if action == "A" then
        -- Melee attack
        doMeleeAttack()
    elseif action == "B" then
        -- Ranged attack
        doRangedAttack()
    elseif action == "Y" then
        -- Toggle inventory
        invOpen = true
        if sfx then sfx.play("ui_select") end
    elseif action == "X" then
        -- Torch toggle (play mode)
        torchEnabled = not torchEnabled
        addLog("TORCH " .. (torchEnabled and "ON" or "OFF"))
    end
end

function cart.keypressed(key)
    -- Auto-close help overlay on escape
    if key == "escape" then
        showHelp = false
        helpScroll = 0
    end

    if key == "f1" then
        toggleEditMode()
        return
    end

    -- Inventory toggle (play mode)
    if mode == "play" and key == "i" then
        invOpen = not invOpen
        if sfx then sfx.play("ui_select") end
        return
    end

    -- Close inventory on escape
    if mode == "play" and invOpen and key == "escape" then
        invOpen = false
        if sfx then sfx.play("ui_select") end
        return
    end

    -- Torch toggle (play mode only)
    if mode == "play" and not invOpen and key == "f" then
        torchEnabled = not torchEnabled
        addLog("TORCH " .. (torchEnabled and "ON" or "OFF"))
        return
    end

    if mode == "edit" then
        -- Help overlay toggle and scroll
        if key == "h" then
            showHelp = not showHelp
            helpScroll = 0
            return
        end
        if showHelp then
            -- Only handle scroll keys when help is open
            local maxScroll = math_max(0, #EDIT_HELP_LINES - math_floor(132 / 8))
            if key == "up" then
                helpScroll = math_max(0, helpScroll - 1)
            elseif key == "down" then
                helpScroll = math_min(maxScroll, helpScroll + 1)
            elseif key == "pageup" then
                helpScroll = math_max(0, helpScroll - 8)
            elseif key == "pagedown" then
                helpScroll = math_min(maxScroll, helpScroll + 8)
            end
            return  -- consume all keys while help is open
        end
        -- Edit mode number keys: switch paint mode
        if key == "1" then editMode = 1; paletteSel = 1; paletteScroll = 0; addLog("MODE: COLLISION"); return
        elseif key == "2" then editMode = 2; paletteSel = 1; paletteScroll = 0; addLog("MODE: WALL MAT"); return
        elseif key == "3" then editMode = 3; paletteSel = 1; paletteScroll = 0; addLog("MODE: FLOOR MAT"); return
        elseif key == "4" then editMode = 4; paletteSel = 0; paletteScroll = 0; addLog("MODE: CEIL MAT"); return
        elseif key == "5" then editMode = 5; paletteSel = 1; paletteScroll = 0; addLog("MODE: ENEMIES"); return
        end
        -- Palette navigation (material modes only)
        if editMode >= 2 then
            if key == "q" then palettePrev(); return
            elseif key == "e" then paletteNext(); return
            end
        end
        if key == "r" then
            eraseAtCursor()
        elseif key == "s" then
            saveMap()
            if sfx then sfx.play("save") end
        elseif key == "l" then
            if loadMapFromFile() then
                addLog("MAP LOADED!")
                if sfx then sfx.play("load") end
            else
                addLog("NO SAVED MAP")
                if sfx then sfx.play("bump") end
            end
        elseif key == "p" then
            -- Test play: switch to play mode at player start
            mode = "play"
            applyPlayerStart()
            addLog("TEST PLAY")
        elseif key == "t" then
            -- Open tracker editor
            if trackerRef then
                trackerRef.open()
                addLog("TRACKER OPENED")
                if sfx then sfx.play("ui_select") end
            end
        end
    end
end

function cart.draw(console)
    if mode == "edit" then
        -- Edit mode: top-down grid + panel
        drawEditGrid()
        drawEditPanel()
        drawMessageBox()
        if showHelp then
            drawHelpOverlay(EDIT_HELP_LINES)
        end
        return
    end

    -- PLAY MODE
    -- Screen shake offset
    local shakeX, shakeY = 0, 0
    if screenShake then
        local intensity = screenShake.intensity
        shakeX = math.random(-intensity, intensity)
        shakeY = math.random(-intensity, intensity)
    end

    -- Apply screen shake to viewport
    if shakeX ~= 0 or shakeY ~= 0 then
        love.graphics.push()
        love.graphics.translate(shakeX, shakeY)
    end

    -- Viewport
    drawViewport()

    -- Melee flash overlay (brief white flash on viewport)
    if meleeFlash > 0 then
        gfx.setColorRGBA(1, 1, 1, 0.15)
        love.graphics.rectangle("fill", VP_X, VP_Y, VP_W, VP_H)
    end

    -- Viewport border
    gfx.rectLine(VP_X, VP_Y, VP_W, VP_H, 8)

    if shakeX ~= 0 or shakeY ~= 0 then
        love.graphics.pop()
    end

    -- Right panel background
    drawBevel(RPANEL_X, RPANEL_Y, RPANEL_W, RPANEL_H)

    -- Title
    gfx.print("RAYCAST 3D", RPANEL_X + 4, RPANEL_Y + RPANEL_H - 20, 0)

    -- Minimap
    drawMinimap()

    -- Stats
    drawStats()

    -- Message box
    drawMessageBox()

    -- Death overlay
    if player.dead then
        gfx.setColorRGBA(0.4, 0, 0, 0.5)
        love.graphics.rectangle("fill", VP_X, VP_Y, VP_W, VP_H)
        local txt = "YOU DIED"
        local tw = gfx.textWidth(txt)
        gfx.print(txt, VP_X + math_floor((VP_W - tw) / 2), VP_Y + math_floor(VP_H / 2) - 4, 12)
    end

    -- Inventory overlay (drawn last, on top of everything)
    drawInventory()
end

return cart

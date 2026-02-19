-- ============================================================================
-- RAYCAST DUNGEON — True raycasting 3D renderer (Wolfenstein-style)
-- ============================================================================
local cart = {
    title       = "RAYCAST DUNGEON",
    author      = "SYSTEM",
    description = "Classic raycasting 3D with textured walls, floor & ceiling.",
    id          = "raycast_dungeon",
    handlesStart = true,  -- cart owns pause menu; ESC/START opens it, only menu quits
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

-- Lighting / Fog (grouped to reduce local count)
local LIGHTING = { AMBIENT = 0.28, FOG_DIST = 8.0, TORCH_RADIUS = 5.0, TORCH_STRENGTH = 1.0 }

-- Player stats (grouped to reduce local count)
local PLAYER_CONST = {
    MOVE_COST   = 2,      -- stamina per tile moved
    MELEE_COST  = 12,     -- stamina per melee attack (future)
    RANGED_COST = 8,      -- stamina per ranged shot (future)
    STAM_REGEN  = 15,     -- stamina regen per second (when not attacking)
    DEATH_DELAY = 1.5,    -- seconds before respawn after death
}

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
local gfx, assets, sfx, input, sprites
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

-- Edit mode state
local mode          -- "play" or "edit"
local playerStartX, playerStartY

-- Torch state
local torchEnabled  -- toggle with F key in play mode

-- NPC billboard test
local npcs          -- array of { x, y, img, pivotY }

-- Weapon overlay state
local wpnOverlay    -- { weapon = {frames}, hand = {frames} } per weapon id
local wpnBobTimer = 0  -- walk bob accumulator

-- SFX state
local stepTimer     -- accumulator for footstep sound throttle
local STEP_INTERVAL = 0.25  -- seconds between step sounds

-- Tutorial state: reduce HUD text after first movement
local hasMovedOnce

-- Run frame counter: avoid first-frame SELECT (e.g. from menu) toggling edit mode
local runFrames = 0

-- Tool registry + cart state for tools (require deferred to init so cart parses even if tools fail to load)
local toolRegistry = nil
local cartState = { tools = {} }
local activeToolId = nil  -- id of currently active tool (or nil)

-- Pause menu (inside cart; ESC/START opens, only "Quit to Program Manager" exits)
-- Grouped into a table to stay under LuaJIT's 200-local limit
local pmenu = {
    open = false,
    toolsOpen = false,
    sel = 1,
    toolsSel = 1,
    items = {"Resume", "Tools >", "Settings >", "Reset Cart", "Quit to Program Manager"},
    toolItems = {},   -- populated from registry at init
    toolIds = {},     -- populated from registry at init
}

-- Forward-declared map helpers (defined after map loading code)
local isWall  -- isWall(mx, my) -> bool; needed by hasLOS/enemyStepToward/updateProjectiles

-- ============================================================================
-- INVENTORY + ITEMS
-- ============================================================================
local INV = { SIZE = 12, COLS = 4, ROWS = 3 }  -- 4x3 grid

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
local invCursor        -- 0-based index (0..INV.SIZE-1)

-- Map entities: pickups on the ground
local entities         -- array of {type="pickup", x=N, y=N, itemId=string, qty=N}

-- Enemies
local enemies          -- array of enemy tables
local enemySpawns      -- array of {x=N, y=N} for editor persistence

-- Enemy constants (grouped to reduce local count)
local ENEMY = {
    HP        = 30,
    SPEED     = 1.2,      -- tiles per second when chasing
    SIGHT     = 6,        -- detection range in tiles
    ATK_DMG   = 8,        -- damage per hit
    ATK_CD    = 1.0,      -- attack cooldown seconds
    MOVE_CD   = 0.6,      -- seconds between chase steps
    DROP      = { "potion", "arrow" },  -- random drop on death
}

-- Projectiles
local projectiles      -- array of {x,y,dx,dy,speed,dmg,life}

-- Combat visual feedback
local screenShake      -- {timer, intensity} or nil
local meleeFlash       -- timer for melee swing visual (>0 while showing)
local stamFlash        -- timer for stamina bar flash when insufficient (>0 while flashing)

-- Weapon definitions: timing in seconds, data-driven combat
local WEAPONS = {
    knife = {
        id = "knife", type = "melee",
        dmg = 15, range = 1.2, coneDeg = 25,
        cost = 12,
        windup  = 0.12,   -- anticipation phase
        strike  = 0.10,   -- active swing window
        recover = 0.22,   -- cooldown before next action
        hitAt   = 0.03,   -- seconds into STRIKE when hit check fires
        sfxWindup = "step",
        sfxHit    = "bump",
        sfxMiss   = "turn",
    },
    bow = {
        id = "bow", type = "ranged",
        dmg = 10, projSpeed = 8.0, ammoId = "arrow",
        cost = 8,
        windup  = 0.20,   -- draw phase
        strike  = 0.01,   -- release is nearly instant
        recover = 0.35,   -- re-nock cooldown
        hitAt   = 0.00,   -- fires immediately on STRIKE enter
        sfxWindup = "ui_move",
        sfxHit    = "bump",
        sfxMiss   = "ui_select",
    },
    fist = {
        id = "fist", type = "melee",
        dmg = 5, range = 1.0, coneDeg = 30,
        cost = 8,
        windup  = 0.08,
        strike  = 0.10,
        recover = 0.30,
        hitAt   = 0.02,
        sfxWindup = "step",
        sfxHit    = "bump",
        sfxMiss   = "turn",
    },
}

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
    local tRadius = (consoleRef and consoleRef.torchRadius) or LIGHTING.TORCH_RADIUS
    local tStrength = (consoleRef and consoleRef.torchStrength) or LIGHTING.TORCH_STRENGTH
    local fogDist = LIGHTING.FOG_DIST / math_max(fogStr, 0.01)

    local fog   = clamp(1.0 - (dist / fogDist), 0.0, 1.0)
    local torch = 0
    if torchEnabled then
        torch = clamp(1.0 - (dist / tRadius), 0.0, 1.0)
        torch = torch * torch * torch * 0.5 + torch * 0.5  -- ~pow 1.5 approx
    end
    return clamp(LIGHTING.AMBIENT + fog * 0.45 + torch * tStrength * 0.55, 0.0, 1.0)
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
    for i = 1, INV.SIZE do
        if inventory[i] and inventory[i].id == itemId then return i end
    end
    return nil
end

local function invFindEmpty()
    for i = 1, INV.SIZE do
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
        hp = ENEMY.HP,
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
                local dropId = ENEMY.DROP[math.random(#ENEMY.DROP)]
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
            if dist <= ENEMY.SIGHT and hasLOS(e.x, e.y, px, py) then
                e.state = "chase"
                e.moveTimer = ENEMY.MOVE_CD * 0.5  -- short initial delay
            end
        elseif e.state == "chase" then
            -- Lose aggro if player too far or no LOS
            if dist > ENEMY.SIGHT * 1.5 or not hasLOS(e.x, e.y, px, py) then
                e.state = "idle"
                goto nextEnemy
            end

            -- Attack if adjacent (distance < 1.2)
            if dist < 1.2 then
                e.atkTimer = e.atkTimer - dt
                if e.atkTimer <= 0 then
                    player.hp = player.hp - ENEMY.ATK_DMG
                    e.atkTimer = ENEMY.ATK_CD
                    addLog("ENEMY HIT YOU! -" .. ENEMY.ATK_DMG .. " HP")
                    if sfx then sfx.play("bump") end
                end
            else
                -- Chase: move toward player on cooldown
                e.moveTimer = e.moveTimer - dt
                if e.moveTimer <= 0 then
                    enemyStepToward(e)
                    e.moveTimer = ENEMY.MOVE_CD
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

-- ============================================================================
-- WEAPON STATE MACHINE
-- ============================================================================

--- Get the weapon definition for a given attack kind ("melee" or "ranged").
--- Returns a WEAPONS entry, or nil if ranged weapon not equipped.
local function weaponGetDef(kind)
    if kind == "melee" then
        if equipMelee and inventory[equipMelee] then
            local itemId = inventory[equipMelee].id
            return WEAPONS[itemId] or WEAPONS.fist
        end
        return WEAPONS.fist
    elseif kind == "ranged" then
        if not equipRanged or not inventory[equipRanged] then
            return nil
        end
        local itemId = inventory[equipRanged].id
        return WEAPONS[itemId]
    end
    return nil
end

--- Execute the melee hit check: find the SINGLE nearest enemy in cone+range.
local function weaponDoHitMelee(def)
    local px, py = player.x, player.y
    local pAngle = player.angle
    local coneRad = math.rad(def.coneDeg or 25)
    local bestDist = math.huge
    local bestEnemy = nil

    for _, e in ipairs(enemies) do
        if e.hp > 0 then
            local ddx = e.x - px
            local ddy = e.y - py
            local dist = math.sqrt(ddx * ddx + ddy * ddy)
            if dist <= (def.range or 1.2) and dist < bestDist then
                local angleToEnemy = math.atan2(ddy, ddx)
                local diff = angleToEnemy - pAngle
                diff = (diff + math.pi) % (2 * math.pi) - math.pi
                if math_abs(diff) < coneRad then
                    bestDist = dist
                    bestEnemy = e
                end
            end
        end
    end

    if bestEnemy then
        bestEnemy.hp = bestEnemy.hp - (def.dmg or 5)
        bestEnemy.flashTimer = 0.15
        addLog("HIT! -" .. (def.dmg or 5) .. " DMG")
        if sfx then sfx.play(def.sfxHit or "bump") end
        triggerScreenShake(2, 0.08)
    else
        addLog("SWING!")
        if sfx then sfx.play(def.sfxMiss or "turn") end
    end
end

--- Execute ranged shot: consume ammo, spawn projectile.
local function weaponDoShootRanged(def)
    local ammoId = def.ammoId
    if ammoId then
        local ammoIdx = invFindItem(ammoId)
        if not ammoIdx then
            addLog("NO " .. (ITEM_DB[ammoId] and ITEM_DB[ammoId].name or "AMMO"))
            return
        end
        local ammoSlot = inventory[ammoIdx]
        ammoSlot.qty = ammoSlot.qty - 1
        if ammoSlot.qty <= 0 then
            invRemoveAt(ammoIdx)
        end
    end

    local dirX = math_cos(player.angle)
    local dirY = math_sin(player.angle)
    projectiles[#projectiles + 1] = {
        x = player.x + dirX * 0.3,
        y = player.y + dirY * 0.3,
        dx = dirX,
        dy = dirY,
        speed = def.projSpeed or 8.0,
        dmg = def.dmg or 10,
        life = 2.0,
    }

    addLog("FIRED!")
    if sfx then sfx.play(def.sfxHit or "ui_select") end
end

--- Try to begin an attack. Called from cart.input.
--- If already attacking, buffers the input for queued attack.
local function weaponStartAttack(kind)
    local wpn = player.wpn

    -- If currently attacking, buffer input
    if wpn.state ~= "IDLE" then
        wpn.queue = kind
        return
    end

    local def = weaponGetDef(kind)
    if not def then
        if kind == "ranged" then
            addLog("NO RANGED WEAPON")
        end
        return
    end

    if player.stam < def.cost then
        addLog("TOO TIRED")
        stamFlash = 0.25
        return
    end

    -- Commit: drain stamina and enter WINDUP
    player.stam = math_max(0, player.stam - def.cost)
    wpn.state  = "WINDUP"
    wpn.t      = 0
    wpn.didHit = false
    wpn.mode   = kind
    wpn.def    = def

    if sfx then sfx.play(def.sfxWindup or "step") end
end

--- Tick the weapon state machine. Called from cart.update every frame.
local function weaponUpdate(dt)
    local wpn = player.wpn
    if wpn.state == "IDLE" then
        if wpn.queue then
            local kind = wpn.queue
            wpn.queue = nil
            weaponStartAttack(kind)
        end
        return
    end

    wpn.t = wpn.t + dt
    local def = wpn.def

    if wpn.state == "WINDUP" then
        if wpn.t >= (def.windup or 0.12) then
            wpn.state = "STRIKE"
            wpn.t = 0
            if wpn.mode == "melee" then
                meleeFlash = def.strike or 0.10
            end
        end

    elseif wpn.state == "STRIKE" then
        if not wpn.didHit and wpn.t >= (def.hitAt or 0) then
            wpn.didHit = true
            if wpn.mode == "melee" then
                weaponDoHitMelee(def)
            elseif wpn.mode == "ranged" then
                weaponDoShootRanged(def)
            end
        end

        if wpn.t >= (def.strike or 0.10) then
            wpn.state = "RECOVER"
            wpn.t = 0
        end

    elseif wpn.state == "RECOVER" then
        if wpn.t >= (def.recover or 0.22) then
            wpn.state = "IDLE"
            wpn.t = 0
            wpn.def = nil
            wpn.mode = nil
        end
    end
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
    player.wpn = { state = "IDLE", t = 0, didHit = false, queue = nil, mode = nil, def = nil }
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
    stamFlash = 0
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
-- NPC BILLBOARD RENDERING (character composites)
-- ============================================================================

--- Create a simple procedural character image (used when no composite asset exists).
local function buildFallbackNPCImage()
    local w, h = 32, 48
    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- Head (circle-ish)
    love.graphics.setColor(0.85, 0.65, 0.45, 1)
    love.graphics.rectangle("fill", 11, 2, 10, 10)
    -- Body
    love.graphics.setColor(0.2, 0.3, 0.7, 1)
    love.graphics.rectangle("fill", 9, 12, 14, 14)
    -- Legs
    love.graphics.setColor(0.3, 0.2, 0.15, 1)
    love.graphics.rectangle("fill", 10, 26, 5, 12)
    love.graphics.rectangle("fill", 17, 26, 5, 12)
    -- Arms
    love.graphics.setColor(0.85, 0.65, 0.45, 1)
    love.graphics.rectangle("fill", 5, 13, 4, 10)
    love.graphics.rectangle("fill", 23, 13, 4, 10)
    -- Eyes
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", 13, 5, 2, 2)
    love.graphics.rectangle("fill", 18, 5, 2, 2)
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    local imgData = canvas:newImageData()
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    imgData:release()
    canvas:release()
    return img, h  -- pivotY at bottom (feet)
end

--- Try loading a character composite, fall back to procedural image.
local function initTestNPC()
    npcs = {}
    local img, pivotY
    -- Try to find a character composite on disk
    if sprites then
        local composites = sprites.listAssets("characters", "composites")
        if composites and #composites > 0 then
            local asset = sprites.loadAsset("characters/composites/" .. composites[1])
            if asset and asset.meta and asset.meta.mode == "composite" then
                img = sprites.renderCompositeToImage(asset)
                pivotY = (asset.pivot and asset.pivot.y) or 120
            end
        end
    end
    if not img then
        img, pivotY = buildFallbackNPCImage()
    end
    -- Place test NPC at tile (4,4) center
    npcs[#npcs + 1] = {
        x = 4.5, y = 4.5,
        img = img,
        imgW = img:getWidth(),
        imgH = img:getHeight(),
        pivotY = pivotY,
    }
end

local function renderNPCs()
    if not npcs or #npcs == 0 then return end

    local fovRad = math.rad((consoleRef and consoleRef.fovDeg) or 60)
    local halfFov = fovRad / 2
    local halfH = VP_H / 2
    local pAngle = player.angle
    local px, py = player.x, player.y

    local dirX = math_cos(pAngle)
    local dirY = math_sin(pAngle)
    local planeScale = math.tan(halfFov)
    local planeX = -dirY * planeScale
    local planeY =  dirX * planeScale

    love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)

    -- Sort by distance (far first)
    local sorted = {}
    for _, n in ipairs(npcs) do
        local dx = n.x - px
        local dy = n.y - py
        sorted[#sorted + 1] = { n = n, dist2 = dx*dx + dy*dy }
    end
    table.sort(sorted, function(a, b) return a.dist2 > b.dist2 end)

    for _, sn in ipairs(sorted) do
        local n = sn.n
        local dx = n.x - px
        local dy = n.y - py

        local invDet = 1.0 / (planeX * dirY - dirX * planeY)
        local transformX = invDet * (dirY * dx - dirX * dy)
        local transformY = invDet * (-planeY * dx + planeX * dy)

        if transformY > 0.1 then
            local spriteScreenX = math_floor((VP_W / 2) * (1 + transformX / transformY))

            -- Full tile height on screen
            local tileScreenH = math_abs(VP_H / transformY)
            -- Sprite occupies its height proportional to tile (128px part in a 1.0 tile)
            local sprScale = tileScreenH / n.imgH
            -- Anchor: pivotY maps to ground level (halfH in screen space for a 1-tile object)
            local spriteH = math_floor(n.imgH * sprScale)
            local spriteW = math_floor(n.imgW * sprScale)
            if spriteW < 2 or spriteH < 2 then goto continueNPC end

            -- Floor Y on screen at this depth: halfH + half a tile height
            local floorY = halfH + tileScreenH * 0.5
            -- pivotY is in pixel coords from image top; the feet are at pivotY
            -- The bottom of the drawn sprite (at pivotY) should align with the floor
            local drawTopY = math_floor(floorY - n.pivotY * sprScale)

            local drawStartX = spriteScreenX - math_floor(spriteW / 2)
            local drawEndX   = drawStartX + spriteW

            -- Lighting
            local shade = calcLight(transformY)

            -- Draw visible column spans (depth-tested, batched)
            gfx.setColorRGBA(shade, shade, shade, 1)
            local spanStart = nil
            local colMin = math_max(drawStartX, 0)
            local colMax = math_min(drawEndX - 1, VP_W - 1)
            for sx = colMin, colMax + 1 do
                local visible = sx <= colMax and transformY < (zBuffer[sx] or MAX_DIST)
                if visible and not spanStart then
                    spanStart = sx
                elseif not visible and spanStart then
                    -- Draw the visible span using scissor
                    love.graphics.setScissor(VP_X + spanStart, VP_Y, sx - spanStart, VP_H)
                    love.graphics.draw(n.img, VP_X + drawStartX, VP_Y + drawTopY, 0, sprScale, sprScale)
                    spanStart = nil
                end
            end
        end
        ::continueNPC::
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================================
-- WEAPON OVERLAY (first-person weapon + hands)
-- ============================================================================

--- Build a simple procedural weapon image (fallback when no sprite asset exists).
local function buildFallbackWeapon(weaponId)
    local w, h = 32, 48
    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    if weaponId == "bow" then
        -- Simple bow shape
        love.graphics.setColor(0.55, 0.35, 0.15, 1)
        love.graphics.rectangle("fill", 14, 2, 4, 44)   -- stave
        love.graphics.setColor(0.8, 0.8, 0.7, 1)
        love.graphics.rectangle("fill", 16, 2, 1, 44)   -- string
    elseif weaponId == "fist" then
        -- No weapon, just transparent
    else
        -- Sword/knife shape
        love.graphics.setColor(0.7, 0.7, 0.75, 1)
        love.graphics.rectangle("fill", 13, 2, 6, 30)   -- blade
        love.graphics.setColor(0.9, 0.85, 0.3, 1)
        love.graphics.rectangle("fill", 11, 32, 10, 3)  -- crossguard
        love.graphics.setColor(0.45, 0.25, 0.1, 1)
        love.graphics.rectangle("fill", 14, 35, 4, 11)  -- grip
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    local imgData = canvas:newImageData()
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    imgData:release()
    canvas:release()
    return img
end

--- Build a simple procedural hand image (fallback).
local function buildFallbackHand()
    local w, h = 32, 32
    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- Palm
    love.graphics.setColor(0.85, 0.65, 0.45, 1)
    love.graphics.rectangle("fill", 8, 8, 16, 18)
    -- Fingers (curled around weapon grip)
    love.graphics.rectangle("fill", 6, 4, 5, 8)
    love.graphics.rectangle("fill", 11, 2, 5, 8)
    love.graphics.rectangle("fill", 16, 2, 5, 8)
    love.graphics.rectangle("fill", 21, 4, 5, 8)
    -- Thumb
    love.graphics.setColor(0.80, 0.60, 0.40, 1)
    love.graphics.rectangle("fill", 4, 12, 6, 10)
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    local imgData = canvas:newImageData()
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    imgData:release()
    canvas:release()
    return img
end

--- Load weapon overlay images. Tries sprite assets first, falls back to procedural.
local function initWeaponOverlay()
    wpnOverlay = {}
    wpnBobTimer = 0

    -- Try loading sprite assets for each weapon type
    for weaponId, _ in pairs(WEAPONS) do
        local entry = { weapon = nil, hand = nil }

        -- Try loading weapon sprite: sprites/weapons/<weaponId>.lua
        if sprites then
            local asset = sprites.loadAsset("weapons/" .. weaponId)
            if asset and asset.layers then
                -- Use first layer as weapon image
                entry.weapon = sprites.renderLayerToImage(asset, 1, 1)
            end
            -- Try loading hand sprite: sprites/hands/human_hand.lua
            local handAsset = sprites.loadAsset("hands/human_hand")
            if handAsset and handAsset.layers then
                entry.hand = sprites.renderLayerToImage(handAsset, 1, 1)
            end
        end

        -- Fallbacks
        if not entry.weapon then
            entry.weapon = buildFallbackWeapon(weaponId)
        end
        if not entry.hand then
            entry.hand = buildFallbackHand()
        end

        wpnOverlay[weaponId] = entry
    end
end

--- Draw the first-person weapon + hand overlay.
--- Called after drawViewport(), inside screen shake transform.
local function drawWeaponOverlay()
    local wpn = player.wpn
    local def = wpn.def
    -- During active attack, use the attack weapon; during IDLE, show equipped melee
    local weaponId
    if def then
        weaponId = def.id
    elseif equipMelee and inventory[equipMelee] then
        weaponId = inventory[equipMelee].id
    else
        weaponId = "fist"
    end
    local entry = wpnOverlay and wpnOverlay[weaponId]
    if not entry then return end

    local state = wpn.state
    local t = wpn.t

    -- Base position: bottom-center-right of viewport
    local baseX = VP_X + VP_W * 0.5
    local baseY = VP_Y + VP_H - 4
    local scale = 2.0  -- scale up the small sprites

    local weaponImg = entry.weapon
    local handImg   = entry.hand

    -- Animation offsets based on weapon state
    local offX, offY = 0, 0
    local rot = 0  -- rotation in radians

    if state == "WINDUP" then
        -- Pull back: move right and down, slight rotation
        local frac = def and (t / def.windup) or 0
        frac = math_min(frac, 1)
        -- smoothstep
        frac = frac * frac * (3 - 2 * frac)
        offX = frac * 20
        offY = frac * 10
        rot  = frac * 0.3
    elseif state == "STRIKE" then
        -- Swing forward: move left and up quickly
        local frac = def and (t / def.strike) or 0
        frac = math_min(frac, 1)
        frac = frac * frac * (3 - 2 * frac)
        offX = 20 - frac * 50   -- from pulled-back to forward
        offY = 10 - frac * 30   -- from down to up
        rot  = 0.3 - frac * 0.8 -- swing through
    elseif state == "RECOVER" then
        -- Return to rest from strike end position
        local frac = def and (t / def.recover) or 0
        frac = math_min(frac, 1)
        frac = frac * frac * (3 - 2 * frac)
        offX = -30 + frac * 30  -- from forward back to center
        offY = -20 + frac * 20
        rot  = -0.5 + frac * 0.5
    end

    -- Walk bob (sinusoidal)
    local bobY = 0
    if wpnBobTimer > 0 then
        bobY = math.sin(wpnBobTimer * 10) * 3
    end

    -- Final position (anchor at bottom-center of weapon)
    local drawX = baseX + offX
    local drawY = baseY + offY + bobY

    -- Scissor to viewport
    love.graphics.setScissor(VP_X, VP_Y, VP_W, VP_H)

    -- Draw weapon underneath (origin at bottom-center)
    if weaponId ~= "fist" then
        gfx.setColorRGBA(1, 1, 1, 1)
        love.graphics.draw(weaponImg,
            drawX, drawY,
            rot,
            scale, scale,
            weaponImg:getWidth() * 0.5, weaponImg:getHeight()  -- origin: bottom-center
        )
    end

    -- Draw hand on top (positioned at grip area)
    gfx.setColorRGBA(1, 1, 1, 1)
    love.graphics.draw(handImg,
        drawX, drawY,
        rot * 0.5,  -- hand rotates less than weapon
        scale, scale,
        handImg:getWidth() * 0.5, handImg:getHeight() * 0.3  -- origin: upper-center
    )

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
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
        if floorCeilImageLow then
            floorCeilImageLow:replacePixels(floorCeilImageDataLow)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(floorCeilImageLow, VP_X, VP_Y, 0, 2, 2)
        else
            love.graphics.setColor(0.15, 0.12, 0.18, 1)
            love.graphics.rectangle("fill", VP_X, VP_Y, VP_W, VP_H)
        end
        -- Walls: skip every other column, draw 2-wide strips
        renderWalls(2)
    else
        -- CRISP mode: full resolution
        renderFloorCeiling(floorCeilImageData, VP_W, VP_H)
        if floorCeilImage then
            floorCeilImage:replacePixels(floorCeilImageData)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(floorCeilImage, VP_X, VP_Y)
        else
            love.graphics.setColor(0.15, 0.12, 0.18, 1)
            love.graphics.rectangle("fill", VP_X, VP_Y, VP_W, VP_H)
        end
        renderWalls(1)
    end

    -- Render enemy billboards (after walls, depth-tested)
    renderEnemies()

    -- Render NPC billboards (character composites)
    renderNPCs()

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

    -- Stamina bar (flashes when insufficient)
    sy = sy + 10
    local stamCol = 6  -- green
    if stamFlash and stamFlash > 0 then
        -- Blink between red and yellow at ~8Hz
        stamCol = (math_floor(stamFlash * 8) % 2 == 0) and 12 or 14
    end
    gfx.print("ST", sx, sy, stamCol == 6 and 14 or stamCol)
    drawStatBar(sx + 16, sy + 1, barW - 16, 6, player.stam, player.stamMax, stamCol, 0)
    local stStr = math_floor(player.stam) .. "/" .. player.stamMax
    gfx.print(stStr, sx + barW - gfx.textWidth(stStr), sy, 7)

    -- Weapon state (only shown when not IDLE)
    if player.wpn.state ~= "IDLE" then
        sy = sy + 10
        local wpnState = player.wpn.state
        local stateCol = wpnState == "WINDUP" and 14 or wpnState == "STRIKE" and 12 or 8
        gfx.print(wpnState, sx, sy, stateCol)
    else
        sy = sy + 10
    end

    -- Compact position + torch
    sy = sy + 2
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
    local pw = INV.COLS * cellSz + pad * 2 + 2
    local ph = INV.ROWS * cellSz + pad * 2 + 30  -- extra for title + equip info
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
    for i = 0, INV.SIZE - 1 do
        local col = i % INV.COLS
        local row = math_floor(i / INV.COLS)
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
    local infoY = gy + INV.ROWS * cellSz + 2
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
    if not img then return nil end
    local ok, data = pcall(function()
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
        return canvas:newImageData()
    end)
    return ok and data or nil
end

-- Compute average RGB color from ImageData (for editor swatches)
local function computeAvgColor(imgData)
    if not imgData then return { 0.5, 0.5, 0.5 } end
    local w, h = imgData:getWidth(), imgData:getHeight()
    if w == 0 or h == 0 then return { 0.5, 0.5, 0.5 } end
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
-- CART INTERFACE (split into helpers to stay under LuaJIT 60-upvalue limit)
-- ============================================================================

-- Helper: load textures and build catalog (~25 upvalues)
local function initTextures()
    texCatalog = { walls = {}, floor = {}, ceil = {} }
    texByKey = {}
    skyQuadObj = nil  -- reset cached skybox quad

    local function registerTex(catName, key, img)
        if not img then return end
        local ok, err = pcall(function()
            img:setFilter("nearest", "nearest")
            img:setWrap("repeat", "repeat")
        end)
        if not ok then return end
        local data = loadTextureData(img)
        local w, h = img:getWidth(), img:getHeight()
        local entry = {
            key  = key,
            img  = img,
            data = data,
            w    = w,
            h    = h,
            avgColor = computeAvgColor(data),
        }
        table.insert(texCatalog[catName], entry)
        texByKey[catName .. "/" .. key] = entry
    end

    -- Load wall textures from assets (skip missing/invalid; fallbacks added below if empty)
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

        -- Load skybox from bg category (first found image; skip invalid)
        texSky = nil
        texSkyW, texSkyH = 0, 0
        for _, img in pairs(assets.categories.bg or {}) do
            if img and pcall(function() img:setFilter("nearest", "nearest") end) then
                texSky = img
                texSky:setWrap("repeat", "clampzero")
                texSkyW = texSky:getWidth()
                texSkyH = texSky:getHeight()
                break  -- use first bg texture as skybox
            end
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

    -- Init floor/ceiling image (same size as viewport); fallback to nil-safe creation
    floorCeilImageData = love.image.newImageData(VP_W, VP_H)
    local ok1, img1 = pcall(love.graphics.newImage, floorCeilImageData)
    floorCeilImage = (ok1 and img1) or nil
    if floorCeilImage then floorCeilImage:setFilter("nearest", "nearest") end

    -- Init low-res floor/ceiling image (half size)
    local lowW = math_floor(VP_W / 2)
    local lowH = math_floor(VP_H / 2)
    floorCeilImageDataLow = love.image.newImageData(lowW, lowH)
    local ok2, img2 = pcall(love.graphics.newImage, floorCeilImageDataLow)
    floorCeilImageLow = (ok2 and img2) or nil
    if floorCeilImageLow then floorCeilImageLow:setFilter("nearest", "nearest") end

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
        wpn = { state = "IDLE", t = 0, didHit = false, queue = nil, mode = nil, def = nil },
    }

    -- Inventory
    inventory = {}
    for i = 1, INV.SIZE do inventory[i] = nil end
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
    stamFlash = 0

    -- Torch / lighting
    torchEnabled = true

    -- Edit mode state
    mode = "play"
    stepTimer = 0

    -- Close any active tool
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.close then activeTool.close(cartState, consoleRef) end
        activeToolId = nil
    end

    -- Tutorial state
    hasMovedOnce = false
    runFrames = 0
    pmenu.open = false
    pmenu.toolsOpen = false
    pmenu.sel = 1
    pmenu.toolsSel = 1

    -- Message log
    msgLog = {}
    addLog("RAYCAST DUNGEON")
    addLog("A:MELEE B:RANGED I:INV")
    addLog("F1:EDIT  ESC:PAUSE")
end

-- Build the mapAPI table that tools/map_editor uses to access cart state
local function buildMapAPI()
    return {
        -- Map dimensions (updated by reference through the table)
        mapW = mapW,
        mapH = mapH,
        -- Player position (for cursor init)
        playerX = player and player.x or 2,
        playerY = player and player.y or 2,
        playerStartX = playerStartX,
        playerStartY = playerStartY,
        -- Tile accessors
        getTile = getTile,
        setTile = setTile,
        -- Material accessors
        getWallMat = getWallMat,
        setWallMat = setWallMat,
        getFloorMat = getFloorMat,
        setFloorMat = setFloorMat,
        getCeilMat = getCeilMat,
        setCeilMat = setCeilMat,
        -- Texture catalog
        texCatalog = texCatalog,
        texByKey = texByKey,
        resolveTexEntry = resolveTexEntry,
        -- Enemy spawns (by reference — edits are live)
        enemySpawns = enemySpawns,
        -- Save/load
        saveMap = saveMap,
        loadMap = loadMapFromFile,
        -- Callbacks
        addLog = addLog,
        onEditorClose = function()
            mode = "play"
            applyPlayerStart()
        end,
        openTracker = function()
            local trackerTool = toolRegistry.get("chip_tracker")
            if trackerTool then
                trackerTool.open(cartState, consoleRef)
                activeToolId = "chip_tracker"
                addLog("TRACKER OPENED")
            end
        end,
    }
end

function cart.init(console)
    gfx    = console.gfx
    assets = console.assets
    sfx    = console.sfx
    input  = console.input
    sprites = console.sprites
    consoleRef = console

    -- Load tool registry on first init (deferred from top-level so cart loads even if tools fail)
    if not toolRegistry then
        local ok, reg = pcall(require, "tools.registry")
        if ok and reg and reg.init then
            toolRegistry = reg
        else
            toolRegistry = {
                list = function() return {} end,
                get = function() return nil end,
                init = function() end,
            }
        end
    end
    toolRegistry.init()

    -- Build tools menu from registry
    pmenu.toolItems = {}
    pmenu.toolIds = {}
    local toolList = toolRegistry.list()
    for _, t in ipairs(toolList) do
        pmenu.toolItems[#pmenu.toolItems + 1] = t.title
        pmenu.toolIds[#pmenu.toolIds + 1] = t.id
    end
    pmenu.toolItems[#pmenu.toolItems + 1] = "Back"
    pmenu.toolIds[#pmenu.toolIds + 1] = nil

    initTextures()
    initRendering()
    initGameState()
    initTestNPC()
    initWeaponOverlay()

    -- Build mapAPI for tools (after state is initialized)
    cartState.mapAPI = buildMapAPI()
end

function cart.reset(console)
    cart.init(console)
end

function cart.update(dt, console)
    runFrames = runFrames + 1

    -- Active tool has priority when open
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) then
            if activeTool.update then activeTool.update(dt, cartState, consoleRef) end
            return
        else
            activeToolId = nil
        end
    end

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

    -- Weapon state machine tick
    weaponUpdate(dt)

    -- Stamina regen (only when weapon is IDLE)
    if player.wpn.state == "IDLE" then
        player.stam = math.min(player.stamMax, player.stam + PLAYER_CONST.STAM_REGEN * dt)
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

    -- Stamina flash timer
    if stamFlash and stamFlash > 0 then
        stamFlash = stamFlash - dt
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
        player.stam = math_max(0, player.stam - PLAYER_CONST.MOVE_COST * MOVE_SPEED * dt)
    end

    -- Check for item pickups at player position
    if walking then
        checkPickups()
    end

    -- Footstep sound throttle + weapon bob
    if input.held.UP or input.held.DOWN then
        stepTimer = stepTimer + dt
        if stepTimer >= STEP_INTERVAL then
            stepTimer = stepTimer - STEP_INTERVAL
            if sfx then sfx.play("step") end
        end
        wpnBobTimer = wpnBobTimer + dt
    else
        stepTimer = 0
        -- Decay bob smoothly to zero
        if wpnBobTimer > 0 then
            wpnBobTimer = math_max(0, wpnBobTimer - dt * 4)
        end
    end

    -- Death check
    if player.hp <= 0 and not player.dead then
        player.dead = true
        player.deathTimer = PLAYER_CONST.DEATH_DELAY
        addLog("You died!")
    end

    -- After first movement, reduce tutorial to minimal status
    if moved and not hasMovedOnce then
        hasMovedOnce = true
        msgLog = {}
        addLog("F1:EDIT  ESC:PAUSE")
    end
end

-- Tool state for Pause menu — uses tool registry
function cart.getToolState(id)
    local t = toolRegistry.get(id)
    if t and t.isOpen then return t.isOpen(cartState) end
    return false
end

function cart.setToolState(id, open)
    local t = toolRegistry.get(id)
    if not t then addLog(id .. " NOT AVAILABLE"); return end

    if open then
        -- Close any currently active tool first
        if activeToolId and activeToolId ~= id then
            local prev = toolRegistry.get(activeToolId)
            if prev and prev.close then prev.close(cartState, consoleRef) end
        end
        -- Map editor needs special handling: set mode to "edit"
        if id == "map_editor" then
            mode = "edit"
            -- Refresh mapAPI with current state
            cartState.mapAPI = buildMapAPI()
        end
        if t.open then t.open(cartState, consoleRef) end
        activeToolId = id
    else
        if t.close then t.close(cartState, consoleRef) end
        if activeToolId == id then activeToolId = nil end
        if id == "map_editor" then
            mode = "play"
            applyPlayerStart()
        end
    end
end

-- Used by app: ESC closes top overlay before opening pause menu
function cart.hasOverlayOpen()
    if activeToolId then
        local t = toolRegistry.get(activeToolId)
        if t and t.isOpen and t.isOpen(cartState) then return true end
    end
    if mode == "edit" then return true end
    return false
end

function cart.closeOverlay()
    if activeToolId then
        local t = toolRegistry.get(activeToolId)
        if t and t.isOpen and t.isOpen(cartState) then
            cart.setToolState(activeToolId, false)
            return
        end
    end
    if mode == "edit" then
        mode = "play"
        applyPlayerStart()
        addLog("MAP EDITOR CLOSED")
    end
end

-- Helper: toggle play/edit mode (shared by F1 key and SELECT action)
local function toggleEditMode()
    if mode == "play" then
        cart.setToolState("map_editor", true)
        addLog("ENTERED EDIT MODE")
    else
        cart.setToolState("map_editor", false)
        addLog("ENTERED PLAY MODE")
    end
    if sfx then sfx.play("ui_select") end
end


function cart.input(action, pressed, console)
    if not pressed then return end

    -- 1) Pause menu open: menu consumes input
    if pmenu.open then
        if pmenu.toolsOpen then
            if action == "UP" then pmenu.toolsSel = math.max(1, pmenu.toolsSel - 1); if sfx then sfx.play("ui_move") end; return end
            if action == "DOWN" then pmenu.toolsSel = math.min(#pmenu.toolItems, pmenu.toolsSel + 1); if sfx then sfx.play("ui_move") end; return end
            if action == "A" then
                if sfx then sfx.play("ui_select") end
                local id = pmenu.toolIds[pmenu.toolsSel]
                if id then
                    cart.setToolState(id, true)
                    pmenu.open = false
                    pmenu.toolsOpen = false
                else
                    pmenu.toolsOpen = false
                end
                return
            end
            if action == "B" or action == "START" then pmenu.toolsOpen = false; if sfx then sfx.play("ui_select") end; return end
        else
            if action == "UP" then pmenu.sel = (pmenu.sel - 2) % #pmenu.items + 1; if sfx then sfx.play("ui_move") end; return end
            if action == "DOWN" then pmenu.sel = pmenu.sel % #pmenu.items + 1; if sfx then sfx.play("ui_move") end; return end
            if action == "A" then
                if sfx then sfx.play("ui_select") end
                local sel = pmenu.items[pmenu.sel]
                if sel == "Resume" then pmenu.open = false
                elseif sel == "Tools >" then pmenu.toolsOpen = true; pmenu.toolsSel = 1
                elseif sel == "Settings >" then pmenu.open = false; if consoleRef then consoleRef.requestOpenSettings = true end
                elseif sel == "Reset Cart" then pmenu.open = false; if cart.reset then cart.reset(console) end
                elseif sel == "Quit to Program Manager" then if consoleRef then consoleRef.requestQuitToMenu = true end
                end
                return
            end
            if action == "B" or action == "START" then pmenu.open = false; if sfx then sfx.play("ui_select") end; return end
        end
        return
    end

    -- 2) START/ESC: open pause menu (or close tool if one is open)
    if action == "START" then
        if cart.hasOverlayOpen() then
            cart.closeOverlay()
            if sfx then sfx.play("ui_select") end
        else
            pmenu.open = true
            pmenu.sel = 1
            pmenu.toolsOpen = false
            if sfx then sfx.play("ui_select") end
        end
        return
    end

    -- 3) Active tool consumes all mapped input when open
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) and activeTool.input then
            activeTool.input(action, pressed, cartState, consoleRef)
            return
        end
    end

    -- SELECT toggles edit/play mode (same as F1) — ignore for first 15 frames to avoid menu key carry-over
    if action == "SELECT" then
        if runFrames > 15 then
            toggleEditMode()
        end
        return
    end

    -- PLAY MODE: inventory open — handle inventory navigation
    if invOpen then
        if action == "UP" then
            invCursor = invCursor - INV.COLS
            if invCursor < 0 then invCursor = invCursor + INV.SIZE end
            if sfx then sfx.play("ui_move") end
        elseif action == "DOWN" then
            invCursor = invCursor + INV.COLS
            if invCursor >= INV.SIZE then invCursor = invCursor - INV.SIZE end
            if sfx then sfx.play("ui_move") end
        elseif action == "LEFT" then
            invCursor = invCursor - 1
            if invCursor < 0 then invCursor = INV.SIZE - 1 end
            if sfx then sfx.play("ui_move") end
        elseif action == "RIGHT" then
            invCursor = invCursor + 1
            if invCursor >= INV.SIZE then invCursor = 0 end
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
        -- Melee attack (or queue if mid-swing)
        weaponStartAttack("melee")
    elseif action == "B" then
        -- Ranged attack (or queue if mid-action)
        weaponStartAttack("ranged")
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
    -- Active tool captures keypresses when open
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) then
            if key == "escape" then
                cart.setToolState(activeToolId, false)
                return
            end
            if activeTool.keypressed then activeTool.keypressed(key, cartState, consoleRef) end
            return
        end
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
end

function cart.draw(console)
    -- Declare at top so goto drawPauseMenu does not jump into their scope (Lua rule)
    local shakeX, shakeY = 0, 0

    -- If map editor (or another full-screen tool) is active, let it draw
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) and activeTool.draw then
            activeTool.draw(cartState, consoleRef)
            -- Still draw pause menu on top if open
            if pmenu.open then goto drawPauseMenu end
            return
        end
    end

    -- PLAY MODE
    -- Screen shake offset
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

    -- First-person weapon + hands overlay
    drawWeaponOverlay()

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

    -- Pause menu overlay (inside cart)
    ::drawPauseMenu::
    if pmenu.open then
        gfx.setColorRGBA(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)
        local pw, ph = 200, 130
        local px = math_floor((VIRT_W - pw) / 2)
        local py = math_floor((VIRT_H - ph) / 2)
        drawBevel(px, py, pw, ph)
        gfx.rect(px + 2, py + 2, pw - 4, 14, 1)
        gfx.print("PAUSED", px + math_floor((pw - gfx.textWidth("PAUSED")) / 2), py + 4, 15)
        local by = py + 20
        local items = pmenu.toolsOpen and pmenu.toolItems or pmenu.items
        local curSel = pmenu.toolsOpen and pmenu.toolsSel or pmenu.sel
        for i = 1, #items do
            local label = items[i]
            if pmenu.toolsOpen and pmenu.toolIds[i] and cart.getToolState(pmenu.toolIds[i]) then
                label = label .. "  [ON]"
            elseif pmenu.toolsOpen and pmenu.toolIds[i] then
                label = label .. "  [OFF]"
            end
            local col = (i == curSel) and 15 or 7
            gfx.print(label, px + 8, by + (i - 1) * 12, col)
        end
        gfx.print("ESC/B:BACK  A:SELECT", px + 4, py + ph - 12, 8)
    end
end

function cart.textinput(text)
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) and activeTool.textinput then
            activeTool.textinput(text, cartState, consoleRef)
        end
    end
end

function cart.mousepressed(x, y, button, console)
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) and activeTool.mousepressed then
            activeTool.mousepressed(x, y, button, cartState, consoleRef)
        end
    end
end

function cart.mousereleased(x, y, button, console)
    if activeToolId then
        local activeTool = toolRegistry.get(activeToolId)
        if activeTool and activeTool.isOpen(cartState) and activeTool.mousereleased then
            activeTool.mousereleased(x, y, button, cartState, consoleRef)
        end
    end
end

return cart

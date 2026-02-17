----------------------------------------------------------------
-- console/tracker.lua
-- Chiptune Tracker Editor — pattern-grid UI with real-time playback
-- Accessible as modal overlay from cart edit modes
----------------------------------------------------------------
local tracker = {}

-- Dependencies (set during init)
local gfx, sfx, music, storage

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------
local VIRT_W, VIRT_H = 320, 200
local CHAR_W, CHAR_H = 6, 8

-- Layout regions
local TOP_BAR_Y   = 0
local TOP_BAR_H   = 10
local GRID_X      = 0
local GRID_Y      = TOP_BAR_H
local GRID_W      = 234
local GRID_H      = 176
local HDR_H       = CHAR_H        -- channel header row inside grid
local DATA_Y      = GRID_Y + HDR_H
local DATA_H      = GRID_H - HDR_H
local VISIBLE_ROWS = math.floor(DATA_H / CHAR_H)  -- 21

local ROW_NUM_W   = 18             -- 3 chars for "00 "
local CH_W        = 54             -- 9 chars per channel (NNN II VV + seps)
local CHANNELS    = 4

local INST_PANEL_X = 236
local INST_PANEL_Y = TOP_BAR_H
local INST_PANEL_W = 84
local INST_PANEL_H = 150

local HELP_PANEL_X = 236
local HELP_PANEL_Y = INST_PANEL_Y + INST_PANEL_H + 2
local HELP_PANEL_W = 84
local HELP_PANEL_H = VIRT_H - HELP_PANEL_Y - 10

local BOTTOM_BAR_Y = VIRT_H - CHAR_H
local BOTTOM_BAR_H = CHAR_H

local MAX_PATTERNS   = 32
local DEFAULT_ROWS   = 32

-- Note names for display
local NOTE_NAMES = {"C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"}

-- Drum note names (channel 4)
local DRUM_NAMES = {"KCK", "SNR", "HAT", "NSE"}

-- Chromatic keyboard mapping: key -> semitone offset from base octave
local KEY_NOTE_MAP = {
    z = 0,  s = 1,  x = 2,  d = 3,  c = 4,
    v = 5,  g = 6,  b = 7,  h = 8,  n = 9,
    j = 10, m = 11,
    q = 12, ["2"] = 13, w = 14, ["3"] = 15, e = 16,
    r = 17, ["5"] = 18, t = 19, ["6"] = 20, y = 21,
    ["7"] = 22, u = 23,
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local active       = false
local justClosedFlag = false

-- Song data
local song = nil

-- Cursor
local cursorRow   = 1     -- 1-based row within current pattern
local cursorCh    = 1     -- 1-4
local cursorCol   = 1     -- 1=note, 2=inst, 3=vol
local currentPat  = 1     -- pattern index being edited
local currentOrd  = 1     -- position in song.order
local octave      = 4     -- note entry octave (1-7)
local currentInst = 1     -- instrument index for note entry

-- Scroll
local scrollRow   = 0     -- topmost visible row offset (0-based)

-- Playback tracking
local playPatIdx  = nil
local playRowIdx  = nil

-- Message
local message     = ""
local msgTimer    = 0

-- Help overlay
local showHelp    = false
local helpScroll  = 0

-- Blink timer for cursor
local blinkTimer  = 0
local BLINK_RATE  = 0.4  -- seconds per half-cycle

-- Channel activity tracking (which channels triggered a note this row)
local chActivity  = {0, 0, 0, 0}  -- decay timers per channel

----------------------------------------------------------------
-- SONG DATA MANAGEMENT
----------------------------------------------------------------
local function newSong()
    return {
        name = "UNTITLED",
        bpm = 120,
        rowsPerPattern = DEFAULT_ROWS,
        order = {1},
        channels = CHANNELS,
        patterns = {
            [1] = { rows = {} },
        },
        instruments = {
            [1] = {name="SQ1",  wave="square",   vol=0.30, env={a=0.005,d=0.04,s=0.6,r=0.05}},
            [2] = {name="SQ2",  wave="square",   vol=0.25, env={a=0.005,d=0.06,s=0.55,r=0.05}},
            [3] = {name="TRI",  wave="triangle", vol=0.35, env={a=0.005,d=0.08,s=0.5,r=0.06}},
            [4] = {name="NSE",  wave="noise",    vol=0.25, env={a=0.002,d=0.04,s=0.2,r=0.04}},
        },
    }
end

local function getRow(patIdx, rowIdx)
    local pat = song.patterns[patIdx]
    if not pat then return nil end
    if not pat.rows[rowIdx] then
        pat.rows[rowIdx] = {}
    end
    return pat.rows[rowIdx]
end

local function getCell(patIdx, rowIdx, ch)
    local pat = song.patterns[patIdx]
    if not pat then return nil end
    local row = pat.rows[rowIdx]
    if not row then return nil end
    return row[ch]
end

local function setCell(patIdx, rowIdx, ch, cell)
    local row = getRow(patIdx, rowIdx)
    if not row then return end
    row[ch] = cell
end

local function clearCell(patIdx, rowIdx, ch)
    local pat = song.patterns[patIdx]
    if not pat then return end
    local row = pat.rows[rowIdx]
    if not row then return end
    row[ch] = nil
end

----------------------------------------------------------------
-- DISPLAY HELPERS
----------------------------------------------------------------
local function noteToStr(note)
    if not note then return "..." end
    if note == "---" then return "---" end
    return note
end

local function instToStr(inst)
    if not inst then return ".." end
    return string.format("%02d", inst)
end

local function volToStr(vol)
    if not vol then return ".." end
    return string.format("%02X", vol)
end

local function setMessage(text)
    message = text
    msgTimer = 3.0
end

----------------------------------------------------------------
-- NOTE ENTRY
----------------------------------------------------------------
local function semitoneToNote(semitone, oct)
    local noteIdx = semitone % 12
    local noteOct = oct + math.floor(semitone / 12)
    if noteOct < 0 then noteOct = 0 end
    if noteOct > 8 then noteOct = 8 end
    return NOTE_NAMES[noteIdx + 1] .. tostring(noteOct)
end

local function enterNote(key)
    -- Drum channel: cycle drum types with note keys
    if cursorCh == CHANNELS then
        local drumIdx = KEY_NOTE_MAP[key]
        if drumIdx then
            local dIdx = (drumIdx % #DRUM_NAMES) + 1
            local drumNote = DRUM_NAMES[dIdx]
            local cell = getCell(currentPat, cursorRow, cursorCh) or {}
            cell.note = drumNote
            cell.inst = cell.inst or currentInst
            setCell(currentPat, cursorRow, cursorCh, cell)
            -- Preview drum
            if music and music.previewNote and song.instruments[cell.inst] then
                music.previewNote(nil, song.instruments[cell.inst])
            end
            -- Auto-advance
            if cursorRow < song.rowsPerPattern then
                cursorRow = cursorRow + 1
            end
            return true
        end
        return false
    end

    local semi = KEY_NOTE_MAP[key]
    if not semi then return false end
    local noteStr = semitoneToNote(semi, octave)
    local cell = getCell(currentPat, cursorRow, cursorCh) or {}
    cell.note = noteStr
    cell.inst = cell.inst or currentInst
    setCell(currentPat, cursorRow, cursorCh, cell)

    -- Preview the note
    if music and music.previewNote and song.instruments[cell.inst] then
        music.previewNote(noteStr, song.instruments[cell.inst])
    end

    -- Auto-advance cursor down
    if cursorRow < song.rowsPerPattern then
        cursorRow = cursorRow + 1
    end

    return true
end

----------------------------------------------------------------
-- SCROLLING
----------------------------------------------------------------
local function ensureCursorVisible()
    if cursorRow - 1 < scrollRow then
        scrollRow = cursorRow - 1
    end
    if cursorRow - 1 >= scrollRow + VISIBLE_ROWS then
        scrollRow = cursorRow - VISIBLE_ROWS
    end
    if scrollRow < 0 then scrollRow = 0 end
end

----------------------------------------------------------------
-- SERIALIZATION (for save/load)
----------------------------------------------------------------
local serializeValue
serializeValue = function(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "number" then
        if val ~= val then return "0" end
        if val == math.huge then return "math.huge" end
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local parts = {}
        local inner = indent .. "  "
        local arrayLen = #val
        local usedKeys = {}
        for i = 1, arrayLen do
            parts[#parts + 1] = inner .. serializeValue(val[i], inner)
            usedKeys[i] = true
        end
        for k, v in pairs(val) do
            if not usedKeys[k] then
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. serializeValue(k, "") .. "]"
                end
                parts[#parts + 1] = inner .. keyStr .. " = " .. serializeValue(v, inner)
            end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

----------------------------------------------------------------
-- SAVE / LOAD
----------------------------------------------------------------
function tracker.save(filename)
    love.filesystem.createDirectory("music")
    local content = "return " .. serializeValue(song) .. "\n"
    local ok, err = love.filesystem.write("music/" .. filename .. ".lua", content)
    if ok then
        setMessage("SAVED: " .. filename)
        if sfx then sfx.play("save") end
    else
        setMessage("SAVE FAILED!")
    end
end

function tracker.load(filename)
    local path = "music/" .. filename .. ".lua"
    local info = love.filesystem.getInfo(path)
    if not info then
        setMessage("NO FILE: " .. filename)
        if sfx then sfx.play("bump") end
        return false
    end
    local content = love.filesystem.read(path)
    if not content then
        setMessage("READ FAILED")
        return false
    end
    local fn, err = load(content)
    if not fn then
        setMessage("PARSE ERROR")
        return false
    end
    local ok, result = pcall(fn)
    if not ok or type(result) ~= "table" then
        setMessage("BAD DATA")
        return false
    end
    song = result
    currentPat = song.order[1] or 1
    currentOrd = 1
    cursorRow = 1
    scrollRow = 0
    setMessage("LOADED: " .. filename)
    if sfx then sfx.play("load") end
    return true
end

----------------------------------------------------------------
-- HELP OVERLAY DATA
----------------------------------------------------------------
local TRACKER_HELP_LINES = {
    "=== TRACKER CONTROLS ===",
    "",
    "SPACE .... Play/stop pattern",
    "ENTER .... Play/stop song",
    "ARROWS ... Navigate grid",
    "TAB ...... Next channel",
    "SHIFT+TAB  Prev channel",
    "PGUP/DN .. Jump 16 rows",
    "",
    "=== NOTE ENTRY ===",
    "",
    "Z-M ...... Notes C-B (lower)",
    "Q-U ...... Notes C-B (upper)",
    "F2/F3 .... Octave down/up",
    "I ........ Next instrument",
    "SHIFT+I .. Prev instrument",
    "DEL ...... Clear cell",
    "BKSP ..... Clear + move up",
    "",
    "=== PATTERN/SONG ===",
    "",
    "[ / ] .... Prev/next order pos",
    "F5 ....... New pattern",
    "F6 ....... Duplicate pattern",
    "+/- ...... BPM up/down",
    "",
    "=== FILE ===",
    "",
    "F9 ....... Save song",
    "F10 ...... Load song",
    "ESC ...... Exit tracker",
    "H ........ Toggle this help",
}

----------------------------------------------------------------
-- DRAWING
----------------------------------------------------------------
local function drawTopBar()
    gfx.rect(0, TOP_BAR_Y, VIRT_W, TOP_BAR_H, 1)
    gfx.print(song.name, 2, 1, 15)
    gfx.print("BPM:" .. song.bpm, 66, 1, 14)
    gfx.print("PAT:" .. string.format("%02d", currentPat), 114, 1, 10)
    gfx.print("ORD:" .. currentOrd .. "/" .. #song.order, 156, 1, 11)
    gfx.print("OCT:" .. octave, 210, 1, 13)
    gfx.print("I:" .. string.format("%02d", currentInst), 248, 1, 14)
    local status = music.isPlaying() and "PLAY" or "STOP"
    local statusCol = music.isPlaying() and 10 or 12
    gfx.print(status, VIRT_W - 28, 1, statusCol)
end

local function drawGrid()
    -- Background
    gfx.rect(GRID_X, GRID_Y, GRID_W, GRID_H, 0)

    -- Channel headers
    gfx.rect(GRID_X, GRID_Y, GRID_W, HDR_H, 7)
    gfx.print("RW", GRID_X + 1, GRID_Y, 0)
    for ch = 1, CHANNELS do
        local hx = GRID_X + ROW_NUM_W + (ch - 1) * CH_W
        local label = "CH" .. ch
        if ch == CHANNELS then label = "DRM" end
        gfx.print(label, hx + 2, GRID_Y, 0)

        -- Activity meter: small bar next to channel label
        if chActivity[ch] > 0 then
            local meterW = math.floor(16 * math.min(1, chActivity[ch]))
            local meterCol = ch == CHANNELS and 12 or 10  -- red for drums, green otherwise
            gfx.rect(hx + 22, GRID_Y + 2, meterW, 4, meterCol)
        end
    end

    -- Blink state for cursor (on for 60%, off for 40% of cycle)
    local blinkOn = (blinkTimer % BLINK_RATE) < (BLINK_RATE * 0.6)

    -- Data rows
    for visRow = 0, VISIBLE_ROWS - 1 do
        local rowIdx = scrollRow + visRow + 1
        if rowIdx > song.rowsPerPattern then break end

        local y = DATA_Y + visRow * CHAR_H
        local isPlayRow = (playPatIdx == currentPat and playRowIdx == rowIdx)
        local isCursorRow = (rowIdx == cursorRow)

        -- Background: cursor row, playing row, beat lines
        if isPlayRow then
            gfx.rect(GRID_X, y, GRID_W, CHAR_H, 1)  -- blue for playing
        elseif isCursorRow then
            gfx.rect(GRID_X, y, GRID_W, CHAR_H, 8)  -- dark gray for cursor row
        end

        -- Row number
        local rowNumCol = 8
        if rowIdx % 4 == 1 then rowNumCol = 7 end
        if isPlayRow then rowNumCol = 11 end
        gfx.print(string.format("%02X", rowIdx - 1), GRID_X + 1, y, rowNumCol)

        -- Playhead marker: triangle arrow in gutter
        if isPlayRow then
            gfx.print(">", GRID_X + 13, y, 14)
        end

        -- Channel separator and data
        for ch = 1, CHANNELS do
            local cellX = GRID_X + ROW_NUM_W + (ch - 1) * CH_W
            local cell = getCell(currentPat, rowIdx, ch)

            -- Separator line
            if ch > 1 then
                gfx.line(cellX, GRID_Y, cellX, GRID_Y + GRID_H - 1, 8)
            end

            local noteStr = noteToStr(cell and cell.note)
            local instStr = instToStr(cell and cell.inst)
            local volStr  = volToStr(cell and cell.vol)

            -- Default colors
            local noteCol = (cell and cell.note) and 15 or 8
            local instCol = (cell and cell.inst) and 14 or 8
            local volCol  = (cell and cell.vol)  and 10 or 8

            -- Cursor highlight: invert active sub-column with blink
            if isCursorRow and ch == cursorCh and blinkOn then
                if cursorCol == 1 then
                    gfx.rect(cellX + 1, y, 18, CHAR_H, 15)
                    noteCol = 0
                elseif cursorCol == 2 then
                    gfx.rect(cellX + 20, y, 12, CHAR_H, 14)
                    instCol = 0
                elseif cursorCol == 3 then
                    gfx.rect(cellX + 33, y, 12, CHAR_H, 10)
                    volCol = 0
                end
            elseif isCursorRow and ch == cursorCh and not blinkOn then
                -- Dim cursor phase: show subtle outline
                if cursorCol == 1 then
                    gfx.rectLine(cellX + 1, y, 18, CHAR_H, 7)
                elseif cursorCol == 2 then
                    gfx.rectLine(cellX + 20, y, 12, CHAR_H, 7)
                elseif cursorCol == 3 then
                    gfx.rectLine(cellX + 33, y, 12, CHAR_H, 7)
                end
            end

            gfx.print(noteStr, cellX + 2, y, noteCol)
            gfx.print(instStr, cellX + 21, y, instCol)
            gfx.print(volStr,  cellX + 34, y, volCol)
        end

        -- Beat line marker (every 4 rows)
        if rowIdx % 4 == 1 and not isCursorRow and not isPlayRow then
            gfx.line(GRID_X, y, GRID_X + GRID_W - 1, y, 8)
        end
    end

    -- Grid border
    gfx.rectLine(GRID_X, GRID_Y, GRID_W, GRID_H, 7)

    -- Scrollbar indicator
    if song.rowsPerPattern > VISIBLE_ROWS then
        local sbX = GRID_X + GRID_W - 3
        local sbY = DATA_Y
        local sbH = DATA_H
        local thumbH = math.max(4, math.floor(sbH * VISIBLE_ROWS / song.rowsPerPattern))
        local thumbY = sbY + math.floor((sbH - thumbH) * scrollRow / (song.rowsPerPattern - VISIBLE_ROWS))
        gfx.rect(sbX, sbY, 2, sbH, 0)
        gfx.rect(sbX, thumbY, 2, thumbH, 7)
    end
end

local function drawInstPanel()
    gfx.rect(INST_PANEL_X, INST_PANEL_Y, INST_PANEL_W, INST_PANEL_H, 0)
    gfx.rectLine(INST_PANEL_X, INST_PANEL_Y, INST_PANEL_W, INST_PANEL_H, 7)

    local x = INST_PANEL_X + 2
    local y = INST_PANEL_Y + 2

    gfx.print("INSTRUMENTS", x, y, 15)
    y = y + 10

    for i, inst in ipairs(song.instruments) do
        local col = (i == currentInst) and 14 or 7
        if i == currentInst then
            gfx.rect(x - 1, y, INST_PANEL_W - 2, CHAR_H, 1)
        end
        gfx.print(string.format("%02d %s", i, inst.name), x, y, col)
        y = y + CHAR_H
        if y > INST_PANEL_Y + INST_PANEL_H - 36 then break end
    end

    -- Current instrument detail
    y = INST_PANEL_Y + INST_PANEL_H - 56
    local inst = song.instruments[currentInst]
    if inst then
        gfx.line(x, y, x + INST_PANEL_W - 6, y, 8)
        y = y + 2
        gfx.print("WAVE:" .. (inst.wave or "?"):sub(1,6), x, y, 11)
        y = y + CHAR_H
        gfx.print("VOL:" .. string.format("%.2f", inst.vol or 0), x, y, 10)
        y = y + CHAR_H
        if inst.env then
            local env = inst.env
            gfx.print(string.format("A:%.3f D:%.3f", env.a or 0, env.d or 0), x, y, 8)
            y = y + CHAR_H
            gfx.print(string.format("S:%.2f  R:%.3f", env.s or 0, env.r or 0), x, y, 8)
            y = y + CHAR_H + 2

            -- Mini ADSR envelope visualization
            local envW = INST_PANEL_W - 8
            local envH = 12
            local envX = x
            local envY = y
            gfx.rect(envX, envY, envW, envH, 0)
            gfx.rectLine(envX, envY, envW, envH, 8)

            local a = math.min(env.a or 0, 0.2) / 0.2  -- normalize to 0-1
            local d = math.min(env.d or 0, 0.2) / 0.2
            local s = env.s or 0
            local r = math.min(env.r or 0, 0.2) / 0.2

            local segW = math.floor(envW / 4)
            local x0 = envX
            local bot = envY + envH - 2
            local top = envY + 1

            -- Attack: 0 -> 1
            local ax1 = x0 + math.floor(segW * math.max(a, 0.1))
            gfx.line(x0, bot, ax1, top, 10)
            -- Decay: 1 -> sustain
            local sy = bot - math.floor((envH - 3) * s)
            local dx1 = ax1 + math.floor(segW * math.max(d, 0.1))
            gfx.line(ax1, top, dx1, sy, 14)
            -- Sustain: hold
            local sx1 = x0 + segW * 3
            gfx.line(dx1, sy, sx1, sy, 11)
            -- Release: sustain -> 0
            gfx.line(sx1, sy, x0 + envW - 1, bot, 12)
        end
    end
end

local function drawHelpPanel()
    gfx.rect(HELP_PANEL_X, HELP_PANEL_Y, HELP_PANEL_W, HELP_PANEL_H, 0)
    gfx.rectLine(HELP_PANEL_X, HELP_PANEL_Y, HELP_PANEL_W, HELP_PANEL_H, 7)

    local x = HELP_PANEL_X + 2
    local y = HELP_PANEL_Y + 2

    gfx.print("SPC:PLAY", x, y, 11); gfx.print("H:HELP", x + 48, y, 14)
    y = y + CHAR_H
    gfx.print("RET:SONG", x, y, 11); gfx.print("ESC:EXIT", x + 48, y, 12)
end

local function drawBottomBar()
    gfx.rect(0, BOTTOM_BAR_Y, VIRT_W, BOTTOM_BAR_H, 1)
    if message ~= "" then
        gfx.print(message, 2, BOTTOM_BAR_Y, 14)
    end
end

----------------------------------------------------------------
-- INPUT HANDLING
----------------------------------------------------------------
function tracker.keypressed(key)
    if not active then return false end

    -- Reset blink timer on any keypress so cursor starts visible
    blinkTimer = 0

    -- Escape: close tracker (but not while help is open — close help instead)
    if key == "escape" then
        if showHelp then
            showHelp = false
            helpScroll = 0
            return true
        end
        tracker.close()
        return true
    end

    -- Help overlay toggle
    if key == "h" then
        showHelp = not showHelp
        helpScroll = 0
        return true
    end

    -- When help is open, only handle scroll keys
    if showHelp then
        local maxScroll = math.max(0, #TRACKER_HELP_LINES - math.floor(132 / CHAR_H))
        if key == "up" then
            helpScroll = math.max(0, helpScroll - 1)
        elseif key == "down" then
            helpScroll = math.min(maxScroll, helpScroll + 1)
        elseif key == "pageup" then
            helpScroll = math.max(0, helpScroll - 8)
        elseif key == "pagedown" then
            helpScroll = math.min(maxScroll, helpScroll + 8)
        end
        return true  -- consume all keys while help is open
    end

    -- Play/Stop pattern: space
    if key == "space" then
        if music.isPlaying() then
            music.stop()
        else
            music.setSong(song)
            music.playFrom(currentPat, 1, "pattern")
        end
        return true
    end

    -- Play/Stop song: enter
    if key == "return" then
        if music.isPlaying() then
            music.stop()
        else
            music.setSong(song)
            music.playSong(currentOrd)
        end
        return true
    end

    -- Navigation: arrows
    if key == "up" then
        cursorRow = cursorRow - 1
        if cursorRow < 1 then cursorRow = 1 end
        ensureCursorVisible()
        return true
    end
    if key == "down" then
        cursorRow = cursorRow + 1
        if cursorRow > song.rowsPerPattern then cursorRow = song.rowsPerPattern end
        ensureCursorVisible()
        return true
    end
    if key == "left" then
        cursorCol = cursorCol - 1
        if cursorCol < 1 then
            cursorCh = cursorCh - 1
            if cursorCh < 1 then cursorCh = 1; cursorCol = 1
            else cursorCol = 3 end
        end
        return true
    end
    if key == "right" then
        cursorCol = cursorCol + 1
        if cursorCol > 3 then
            cursorCh = cursorCh + 1
            if cursorCh > CHANNELS then cursorCh = CHANNELS; cursorCol = 3
            else cursorCol = 1 end
        end
        return true
    end

    -- Page up/down: jump 16 rows
    if key == "pageup" then
        cursorRow = math.max(1, cursorRow - 16)
        ensureCursorVisible()
        return true
    end
    if key == "pagedown" then
        cursorRow = math.min(song.rowsPerPattern, cursorRow + 16)
        ensureCursorVisible()
        return true
    end

    -- Tab / Shift+Tab: next/prev channel
    if key == "tab" then
        if love.keyboard.isDown("lshift", "rshift") then
            cursorCh = cursorCh - 1
            if cursorCh < 1 then cursorCh = CHANNELS end
        else
            cursorCh = cursorCh + 1
            if cursorCh > CHANNELS then cursorCh = 1 end
        end
        cursorCol = 1
        return true
    end

    -- BPM: +/-
    if key == "=" or key == "kp+" then
        song.bpm = math.min(240, song.bpm + 5)
        if music.isPlaying() then music.setBpm(song.bpm) end
        setMessage("BPM: " .. song.bpm)
        return true
    end
    if key == "-" and not love.keyboard.isDown("lshift", "rshift") then
        -- Only handle minus when not shifted (to avoid conflict)
        if cursorCol ~= 1 then  -- don't conflict with note entry
            song.bpm = math.max(60, song.bpm - 5)
            if music.isPlaying() then music.setBpm(song.bpm) end
            setMessage("BPM: " .. song.bpm)
            return true
        end
    end

    -- Instrument select: I key
    if key == "i" and cursorCol ~= 1 then
        if love.keyboard.isDown("lshift", "rshift") then
            currentInst = currentInst - 1
            if currentInst < 1 then currentInst = #song.instruments end
        else
            currentInst = currentInst + 1
            if currentInst > #song.instruments then currentInst = 1 end
        end
        local inst = song.instruments[currentInst]
        setMessage("INST " .. currentInst .. ": " .. (inst and inst.name or "?"))
        return true
    end

    -- Octave: F2/F3
    if key == "f2" then
        octave = math.max(1, octave - 1)
        setMessage("OCTAVE: " .. octave)
        return true
    end
    if key == "f3" then
        octave = math.min(7, octave + 1)
        setMessage("OCTAVE: " .. octave)
        return true
    end

    -- Delete/Backspace: clear cell
    if key == "delete" then
        clearCell(currentPat, cursorRow, cursorCh)
        return true
    end
    if key == "backspace" then
        clearCell(currentPat, cursorRow, cursorCh)
        if cursorRow > 1 then cursorRow = cursorRow - 1 end
        ensureCursorVisible()
        return true
    end

    -- Pattern/Order navigation: [ and ]
    if key == "[" then
        currentOrd = math.max(1, currentOrd - 1)
        currentPat = song.order[currentOrd]
        cursorRow = 1
        scrollRow = 0
        setMessage("ORD " .. currentOrd .. " PAT " .. currentPat)
        return true
    end
    if key == "]" then
        currentOrd = math.min(#song.order, currentOrd + 1)
        currentPat = song.order[currentOrd]
        cursorRow = 1
        scrollRow = 0
        setMessage("ORD " .. currentOrd .. " PAT " .. currentPat)
        return true
    end

    -- New pattern: F5
    if key == "f5" then
        local newPatIdx = #song.patterns + 1
        if newPatIdx <= MAX_PATTERNS then
            song.patterns[newPatIdx] = { rows = {} }
            table.insert(song.order, currentOrd + 1, newPatIdx)
            currentOrd = currentOrd + 1
            currentPat = newPatIdx
            cursorRow = 1
            scrollRow = 0
            setMessage("NEW PAT " .. newPatIdx .. " AT ORD " .. currentOrd)
        else
            setMessage("MAX PATTERNS REACHED")
        end
        return true
    end

    -- Duplicate pattern: F6
    if key == "f6" then
        local newPatIdx = #song.patterns + 1
        if newPatIdx <= MAX_PATTERNS then
            local srcPat = song.patterns[currentPat]
            local newPat = { rows = {} }
            if srcPat and srcPat.rows then
                for r, row in pairs(srcPat.rows) do
                    newPat.rows[r] = {}
                    for ch, cell in pairs(row) do
                        newPat.rows[r][ch] = {
                            note = cell.note,
                            inst = cell.inst,
                            vol  = cell.vol,
                        }
                    end
                end
            end
            song.patterns[newPatIdx] = newPat
            table.insert(song.order, currentOrd + 1, newPatIdx)
            currentOrd = currentOrd + 1
            currentPat = newPatIdx
            setMessage("DUP PAT -> " .. newPatIdx)
        else
            setMessage("MAX PATTERNS REACHED")
        end
        return true
    end

    -- Save: F9
    if key == "f9" then
        tracker.save("song01")
        return true
    end

    -- Load: F10
    if key == "f10" then
        tracker.load("song01")
        return true
    end

    -- Note entry (only on note column)
    if cursorCol == 1 then
        if enterNote(key) then
            ensureCursorVisible()
            return true
        end
    end

    -- Instrument number entry (on inst column)
    if cursorCol == 2 then
        local digit = tonumber(key)
        if digit then
            local cell = getCell(currentPat, cursorRow, cursorCh) or {}
            local curInst = cell.inst or 0
            local newInst = (curInst % 10) * 10 + digit
            if newInst < 1 then newInst = 1 end
            if newInst > #song.instruments then newInst = #song.instruments end
            cell.inst = newInst
            setCell(currentPat, cursorRow, cursorCh, cell)
            return true
        end
    end

    -- Volume entry (hex digit, on vol column)
    if cursorCol == 3 then
        local hex = tonumber(key, 16)
        if hex then
            local cell = getCell(currentPat, cursorRow, cursorCh) or {}
            local curVol = cell.vol or 0
            cell.vol = math.min(64, (curVol % 16) * 16 + hex)
            setCell(currentPat, cursorRow, cursorCh, cell)
            return true
        end
    end

    -- Consume all keys while tracker is active (prevent leaking)
    return true
end

----------------------------------------------------------------
-- UPDATE
----------------------------------------------------------------
function tracker.update(dt)
    if not active then return end

    -- Blink timer
    blinkTimer = blinkTimer + dt

    -- Fade message
    if msgTimer > 0 then
        msgTimer = msgTimer - dt
        if msgTimer <= 0 then
            message = ""
            msgTimer = 0
        end
    end

    -- Poll playback position
    local prevPlayRow = playRowIdx
    if music.isPlaying() and music.getPosition then
        playPatIdx, playRowIdx = music.getPosition()
    else
        playPatIdx = nil
        playRowIdx = nil
    end

    -- Update channel activity: trigger on new row, decay over time
    if playPatIdx and playRowIdx and playRowIdx ~= prevPlayRow then
        for ch = 1, CHANNELS do
            local cell = getCell(playPatIdx, playRowIdx, ch)
            if cell and cell.note then
                chActivity[ch] = 1.0
            end
        end
    end
    for ch = 1, CHANNELS do
        if chActivity[ch] > 0 then
            chActivity[ch] = chActivity[ch] - dt * 4  -- decay over ~0.25s
            if chActivity[ch] < 0 then chActivity[ch] = 0 end
        end
    end
end

local function drawHelpOverlay()
    -- Dark backdrop
    gfx.setColorRGBA(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, VIRT_W, VIRT_H)

    -- Centered panel
    local pw, ph = 220, 160
    local px = math.floor((VIRT_W - pw) / 2)
    local py = math.floor((VIRT_H - ph) / 2)

    -- Panel background + border
    gfx.rect(px, py, pw, ph, 0)
    gfx.rectLine(px, py, pw, ph, 7)

    -- Raised bevel
    gfx.setColor(15)
    love.graphics.line(px + 1, py + 1, px + pw - 2, py + 1)
    love.graphics.line(px + 1, py + 1, px + 1, py + ph - 2)
    gfx.setColor(8)
    love.graphics.line(px + pw - 2, py + 1, px + pw - 2, py + ph - 2)
    love.graphics.line(px + 1, py + ph - 2, px + pw - 2, py + ph - 2)

    -- Title bar
    gfx.rect(px + 2, py + 2, pw - 4, 10, 1)
    gfx.print("TRACKER HELP", px + 4, py + 3, 15)
    gfx.print("[H] CLOSE", px + pw - 60, py + 3, 14)

    -- Content area
    local contentY = py + 14
    local contentH = ph - 28
    local maxLines = math.floor(contentH / CHAR_H)
    local scroll = helpScroll or 0
    local totalLines = #TRACKER_HELP_LINES

    for i = 1, maxLines do
        local lineIdx = scroll + i
        if lineIdx > totalLines then break end
        local line = TRACKER_HELP_LINES[lineIdx]
        local col = 7
        if line:sub(1, 3) == "===" then col = 14 end
        gfx.print(line, px + 6, contentY + (i - 1) * CHAR_H, col)
    end

    -- Scroll indicator
    if totalLines > maxLines then
        local barX = px + pw - 6
        local barY = contentY
        local barH = contentH
        local thumbH = math.max(4, math.floor(barH * maxLines / totalLines))
        local thumbY = barY + math.floor((barH - thumbH) * scroll / math.max(1, totalLines - maxLines))
        gfx.rect(barX, barY, 3, barH, 0)
        gfx.rect(barX, thumbY, 3, thumbH, 7)
    end

    -- Bottom hint
    gfx.print("UP/DN:SCROLL  H:CLOSE", px + 6, py + ph - 10, 8)
end

----------------------------------------------------------------
-- DRAW
----------------------------------------------------------------
function tracker.draw()
    if not active then return end

    gfx.cls(0)
    drawTopBar()
    drawGrid()
    drawInstPanel()
    drawHelpPanel()
    drawBottomBar()

    if showHelp then
        drawHelpOverlay()
    end
end

----------------------------------------------------------------
-- OPEN / CLOSE / QUERY
----------------------------------------------------------------
function tracker.open()
    if active then return end
    active = true
    justClosedFlag = false
    showHelp = false
    helpScroll = 0
    if not song then
        song = newSong()
    end
    setMessage("TRACKER — H:HELP  ESC:EXIT")
end

function tracker.close()
    if not active then return end
    active = false
    justClosedFlag = true
    -- Stop playback when closing
    if music.isPlaying() then
        music.stop()
    end
end

function tracker.isActive()
    return active
end

function tracker.wasJustClosed()
    if justClosedFlag then
        justClosedFlag = false
        return true
    end
    return false
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------
function tracker.init(console)
    gfx     = console.gfx
    sfx     = console.sfx
    music   = console.music
    storage = console.storage
end

function tracker.getSong()
    return song
end

function tracker.setSong(newSong)
    song = newSong
end

return tracker

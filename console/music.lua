local music = {}

local sampleRate = 44100
local PI2 = math.pi * 2

----------------------------------------------------------------
-- Waveform generators (phase 0..1 -> sample -1..1)
----------------------------------------------------------------
local function waveSquare(phase)
    return phase < 0.5 and 1 or -1
end

local function waveTriangle(phase)
    if phase < 0.25 then return phase * 4
    elseif phase < 0.75 then return 2 - phase * 4
    else return phase * 4 - 4 end
end

local function waveSine(phase)
    return math.sin(PI2 * phase)
end

local function waveNoise()
    return math.random() * 2 - 1
end

local waveFuncs = {
    square   = waveSquare,
    triangle = waveTriangle,
    sine     = waveSine,
    noise    = waveNoise,
}

----------------------------------------------------------------
-- Note -> frequency conversion
----------------------------------------------------------------
local noteNames = {C=0, D=2, E=4, F=5, G=7, A=9, B=11}

local function noteToFreq(noteStr)
    if not noteStr or noteStr == "..." or noteStr == "---" then return nil end
    -- Format: "C-4", "D#4", "Eb4", etc.
    local letter = noteStr:sub(1,1):upper()
    local base = noteNames[letter]
    if not base then return nil end

    local idx = 2
    local mod = noteStr:sub(idx, idx)
    if mod == "#" or mod == "+" then
        base = base + 1
        idx = idx + 1
    elseif mod == "b" or mod == "-" then
        base = base - 1
        idx = idx + 1
    end

    local octave = tonumber(noteStr:sub(idx))
    if not octave then return nil end

    local midi = (octave + 1) * 12 + base
    return 440 * 2 ^ ((midi - 69) / 12)
end

----------------------------------------------------------------
-- ADSR envelope
----------------------------------------------------------------
local function adsr(t, dur, a, d, s, r)
    local relStart = dur - r
    if relStart < a + d then relStart = a + d end
    if t < a then
        return t / a
    elseif t < a + d then
        return 1.0 - (1.0 - s) * ((t - a) / d)
    elseif t < relStart then
        return s
    elseif t < dur then
        return s * (1.0 - (t - relStart) / r)
    else
        return 0
    end
end

----------------------------------------------------------------
-- Tone cache: generate and cache SoundData per (wave, freq, dur)
----------------------------------------------------------------
local toneSourceCache = {}

local function getToneSource(wave, freq, dur, vol, a, d, s, r)
    -- Round freq to nearest Hz for cache key
    local freqKey = math.floor(freq + 0.5)
    local durKey  = math.floor(dur * 1000) -- ms precision
    local key = wave .. ":" .. freqKey .. ":" .. durKey

    if not toneSourceCache[key] then
        local samples = math.floor(sampleRate * dur)
        if samples < 1 then samples = 1 end
        local sd = love.sound.newSoundData(samples, sampleRate, 16, 1)
        local wfn = waveFuncs[wave] or waveSquare
        local isNoise = (wave == "noise")
        local phase = 0
        local phaseInc = freq / sampleRate

        for i = 0, samples - 1 do
            local t = i / sampleRate
            local env = adsr(t, dur, a or 0.005, d or 0.04, s or 0.6, r or 0.06)
            local sample
            if isNoise then
                sample = wfn() * env
            else
                sample = wfn(phase) * env
                phase = phase + phaseInc
                if phase >= 1 then phase = phase - 1 end
            end
            if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
            sd:setSample(i, sample)
        end

        toneSourceCache[key] = love.audio.newSource(sd, "static")
    end

    return toneSourceCache[key]
end

local function playTone(wave, freq, dur, vol, a, d, s, r)
    local src = getToneSource(wave, freq, dur, 1.0, a, d, s, r)
    local clone = src:clone()
    clone:setVolume((vol or 0.3) * music.masterVol)
    clone:play()
end

----------------------------------------------------------------
-- Instrument definitions
----------------------------------------------------------------
local instruments = {
    bass = {
        wave = "triangle", vol = 0.35,
        attack = 0.005, decay = 0.08, sustain = 0.5, release = 0.06,
    },
    lead = {
        wave = "square", vol = 0.2,
        attack = 0.005, decay = 0.06, sustain = 0.55, release = 0.05,
    },
    arp = {
        wave = "square", vol = 0.15,
        attack = 0.003, decay = 0.04, sustain = 0.4, release = 0.03,
    },
    kick = {
        wave = "triangle", vol = 0.4,
        attack = 0.002, decay = 0.06, sustain = 0.1, release = 0.04,
        freq = 55,
    },
    snare = {
        wave = "noise", vol = 0.25,
        attack = 0.002, decay = 0.04, sustain = 0.2, release = 0.04,
        freq = 200,
    },
    hat = {
        wave = "noise", vol = 0.12,
        attack = 0.001, decay = 0.02, sustain = 0.1, release = 0.02,
        freq = 800,
    },
}

----------------------------------------------------------------
-- Pattern / Song data
-- Each pattern has rows; each row = { ch1, ch2, ch3, ch4 }
-- Channel entry: { note="C-4", inst="lead" } or nil for empty
-- Drums use inst name as note trigger (freq from instrument def)
----------------------------------------------------------------

-- Helper to build a row
local function N(note, inst)
    return { note = note, inst = inst }
end

-- Demo song patterns
local demoPatterns = {
    -- Pattern 1: intro / main theme
    {
        -- 32 rows, 4 channels: bass, lead, arp, drums
        { N("C-2","bass"), nil,             nil,             N(nil,"kick") },  -- 1
        { nil,             nil,             N("C-4","arp"),  nil },             -- 2
        { nil,             nil,             N("E-4","arp"),  N(nil,"hat") },    -- 3
        { nil,             nil,             N("G-4","arp"),  nil },             -- 4
        { N("C-2","bass"), N("E-4","lead"), nil,             N(nil,"snare") },  -- 5
        { nil,             nil,             N("C-4","arp"),  nil },             -- 6
        { nil,             nil,             N("E-4","arp"),  N(nil,"hat") },    -- 7
        { nil,             nil,             N("G-4","arp"),  nil },             -- 8
        { N("G-1","bass"), nil,             nil,             N(nil,"kick") },   -- 9
        { nil,             nil,             N("B-3","arp"),  nil },             -- 10
        { nil,             nil,             N("D-4","arp"),  N(nil,"hat") },    -- 11
        { nil,             nil,             N("G-4","arp"),  nil },             -- 12
        { N("G-1","bass"), N("D-4","lead"), nil,             N(nil,"snare") },  -- 13
        { nil,             nil,             N("B-3","arp"),  nil },             -- 14
        { nil,             nil,             N("D-4","arp"),  N(nil,"hat") },    -- 15
        { nil,             nil,             N("G-4","arp"),  nil },             -- 16
        { N("A-1","bass"), nil,             nil,             N(nil,"kick") },   -- 17
        { nil,             nil,             N("A-3","arp"),  nil },             -- 18
        { nil,             nil,             N("C-4","arp"),  N(nil,"hat") },    -- 19
        { nil,             nil,             N("E-4","arp"),  nil },             -- 20
        { N("A-1","bass"), N("C-4","lead"), nil,             N(nil,"snare") },  -- 21
        { nil,             nil,             N("A-3","arp"),  nil },             -- 22
        { nil,             nil,             N("C-4","arp"),  N(nil,"hat") },    -- 23
        { nil,             nil,             N("E-4","arp"),  nil },             -- 24
        { N("F-1","bass"), nil,             nil,             N(nil,"kick") },   -- 25
        { nil,             nil,             N("F-3","arp"),  nil },             -- 26
        { nil,             nil,             N("A-3","arp"),  N(nil,"hat") },    -- 27
        { nil,             nil,             N("C-4","arp"),  nil },             -- 28
        { N("G-1","bass"), N("B-3","lead"), nil,             N(nil,"snare") },  -- 29
        { nil,             nil,             N("G-3","arp"),  nil },             -- 30
        { nil,             nil,             N("B-3","arp"),  N(nil,"hat") },    -- 31
        { nil,             nil,             N("D-4","arp"),  nil },             -- 32
    },

    -- Pattern 2: variation
    {
        { N("E-1","bass"), nil,             nil,             N(nil,"kick") },
        { nil,             nil,             N("E-3","arp"),  nil },
        { nil,             N("G-4","lead"), N("G-3","arp"),  N(nil,"hat") },
        { nil,             nil,             N("B-3","arp"),  nil },
        { N("E-1","bass"), nil,             nil,             N(nil,"snare") },
        { nil,             nil,             N("E-3","arp"),  nil },
        { nil,             nil,             N("G-3","arp"),  N(nil,"hat") },
        { nil,             nil,             N("B-3","arp"),  nil },
        { N("A-1","bass"), nil,             nil,             N(nil,"kick") },
        { nil,             nil,             N("A-3","arp"),  nil },
        { nil,             N("E-4","lead"), N("C-4","arp"),  N(nil,"hat") },
        { nil,             nil,             N("E-4","arp"),  nil },
        { N("A-1","bass"), nil,             nil,             N(nil,"snare") },
        { nil,             nil,             N("A-3","arp"),  nil },
        { nil,             nil,             N("C-4","arp"),  N(nil,"hat") },
        { nil,             nil,             N("E-4","arp"),  nil },
        { N("D-1","bass"), nil,             nil,             N(nil,"kick") },
        { nil,             nil,             N("D-3","arp"),  nil },
        { nil,             N("F-4","lead"), N("F-3","arp"),  N(nil,"hat") },
        { nil,             nil,             N("A-3","arp"),  nil },
        { N("D-1","bass"), nil,             nil,             N(nil,"snare") },
        { nil,             nil,             N("D-3","arp"),  nil },
        { nil,             nil,             N("F-3","arp"),  N(nil,"hat") },
        { nil,             nil,             N("A-3","arp"),  nil },
        { N("G-1","bass"), nil,             nil,             N(nil,"kick") },
        { nil,             nil,             N("G-3","arp"),  nil },
        { nil,             N("D-4","lead"), N("B-3","arp"),  N(nil,"hat") },
        { nil,             nil,             N("D-4","arp"),  nil },
        { N("G-1","bass"), nil,             nil,             N(nil,"snare") },
        { nil,             nil,             N("B-3","arp"),  N(nil,"hat") },
        { nil,             N("G-4","lead"), N("D-4","arp"),  N(nil,"kick") },
        { nil,             nil,             nil,             N(nil,"hat") },
    },
}

-- Song = list of pattern indices (1-based)
local demoSong = { 1, 1, 2, 2 }

----------------------------------------------------------------
-- Sequencer state
----------------------------------------------------------------
local playing    = false
local bpm        = 120
local rowsPerBeat = 4
local currentSong     = demoSong
local currentPatterns = demoPatterns
local songPos    = 1   -- which pattern in the song order
local rowPos     = 0   -- current row within pattern
local rowTimer   = 0   -- time accumulator
local rowDur     = 0   -- seconds per row (computed from bpm)

-- Tracker integration state
local trackerSong        = nil
local trackerInstruments = nil
local trackerPatIdx      = 1
local trackerRowPos      = 0
local trackerSongOrdPos  = 1
local trackerPlayMode    = "pattern"
local useTrackerMode     = false

music.masterVol = 0.3

----------------------------------------------------------------
-- Compute row duration
----------------------------------------------------------------
local function calcRowDur()
    rowDur = 60 / bpm / rowsPerBeat
end

----------------------------------------------------------------
-- Trigger a single channel event
----------------------------------------------------------------
local function triggerEvent(event)
    if not event then return end
    local instName = event.inst
    local inst = instruments[instName]
    if not inst then return end

    local freq = inst.freq
    if event.note then
        local f = noteToFreq(event.note)
        if f then freq = f end
    end
    if not freq then return end

    local noteDur = rowDur * 0.9
    if noteDur < 0.02 then noteDur = 0.02 end

    playTone(inst.wave, freq, noteDur, inst.vol,
             inst.attack, inst.decay, inst.sustain, inst.release)
end

----------------------------------------------------------------
-- Tracker playback helpers
----------------------------------------------------------------
local function triggerTrackerEvent(cell)
    if not cell or not cell.inst then return end
    local inst = trackerInstruments[cell.inst]
    if not inst then return end

    local freq = inst.freq
    if cell.note then
        local f = noteToFreq(cell.note)
        if f then freq = f end
    end
    if not freq then return end

    local noteDur = rowDur * 0.9
    if noteDur < 0.02 then noteDur = 0.02 end

    local vol = inst.vol
    if cell.vol then
        vol = inst.vol * (cell.vol / 64)
    end

    playTone(inst.wave, freq, noteDur, vol,
             inst.attack, inst.decay, inst.sustain, inst.release)
end

local function updateTrackerPlayback()
    local pat = trackerSong.patterns[trackerPatIdx]
    if not pat then
        playing = false
        useTrackerMode = false
        return
    end

    trackerRowPos = trackerRowPos + 1
    local maxRows = trackerSong.rowsPerPattern or 32

    if trackerRowPos > maxRows then
        if trackerPlayMode == "pattern" then
            trackerRowPos = 1
        elseif trackerPlayMode == "song" then
            trackerRowPos = 1
            trackerSongOrdPos = trackerSongOrdPos + 1
            if trackerSongOrdPos > #trackerSong.order then
                trackerSongOrdPos = 1
            end
            trackerPatIdx = trackerSong.order[trackerSongOrdPos] or 1
            pat = trackerSong.patterns[trackerPatIdx]
            if not pat then
                playing = false
                useTrackerMode = false
                return
            end
        end
    end

    local row = pat.rows and pat.rows[trackerRowPos]
    if row then
        for ch = 1, (trackerSong.channels or 4) do
            triggerTrackerEvent(row[ch])
        end
    end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function music.init()
    calcRowDur()
    toneSourceCache = {}
end

function music.update(dt)
    if not playing then return end

    rowTimer = rowTimer + dt
    if rowTimer < rowDur then return end
    rowTimer = rowTimer - rowDur

    -- Tracker mode: use tracker song data
    if useTrackerMode and trackerSong then
        updateTrackerPlayback()
        return
    end

    -- Get current pattern
    local patIdx = currentSong[songPos]
    local pattern = currentPatterns[patIdx]
    if not pattern then
        -- Loop song
        songPos = 1
        rowPos = 0
        patIdx = currentSong[songPos]
        pattern = currentPatterns[patIdx]
        if not pattern then return end
    end

    rowPos = rowPos + 1
    if rowPos > #pattern then
        -- Advance to next pattern in song
        rowPos = 1
        songPos = songPos + 1
        if songPos > #currentSong then
            songPos = 1
        end
        patIdx = currentSong[songPos]
        pattern = currentPatterns[patIdx]
        if not pattern then return end
    end

    -- Trigger row events
    local row = pattern[rowPos]
    if row then
        for ch = 1, #row do
            triggerEvent(row[ch])
        end
    end
end

function music.play(songId)
    -- For now, only one built-in song
    currentSong = demoSong
    currentPatterns = demoPatterns
    songPos = 1
    rowPos = 0
    rowTimer = 0
    calcRowDur()
    playing = true
end

function music.stop()
    playing = false
    useTrackerMode = false
end

function music.toggle()
    if playing then
        music.stop()
    else
        music.play()
    end
    return playing
end

function music.isPlaying()
    return playing
end

function music.setBpm(newBpm)
    bpm = math.max(60, math.min(240, newBpm))
    calcRowDur()
end

function music.getBpm()
    return bpm
end

function music.setVolume(v)
    music.masterVol = math.max(0, math.min(1, v))
end

function music.getVolume()
    return music.masterVol
end

----------------------------------------------------------------
-- Tracker integration API
----------------------------------------------------------------

function music.setSong(songTable)
    trackerSong = songTable
    if songTable then
        bpm = songTable.bpm or 120
        calcRowDur()
        trackerInstruments = {}
        for i, inst in ipairs(songTable.instruments) do
            trackerInstruments[i] = {
                wave    = inst.wave,
                vol     = inst.vol,
                attack  = inst.env and inst.env.a or 0.005,
                decay   = inst.env and inst.env.d or 0.04,
                sustain = inst.env and inst.env.s or 0.6,
                release = inst.env and inst.env.r or 0.05,
                freq    = inst.freq,
            }
        end
    end
end

function music.playFrom(patIdx, rowIdx, mode)
    if not trackerSong then return end
    trackerPlayMode = mode or "pattern"
    trackerPatIdx = patIdx
    trackerRowPos = (rowIdx or 1) - 1
    rowTimer = 0
    playing = true
    useTrackerMode = true
end

function music.playSong(orderPos)
    if not trackerSong then return end
    trackerPlayMode = "song"
    trackerSongOrdPos = orderPos or 1
    trackerPatIdx = trackerSong.order[trackerSongOrdPos] or 1
    trackerRowPos = 0
    rowTimer = 0
    playing = true
    useTrackerMode = true
end

function music.getPosition()
    if not useTrackerMode or not playing then return nil, nil end
    return trackerPatIdx, trackerRowPos
end

function music.previewNote(noteStr, instDef)
    if not instDef then return end
    local freq = noteToFreq(noteStr)
    if not freq then freq = instDef.freq end
    if not freq then return end
    local dur = 0.15
    playTone(
        instDef.wave or "square",
        freq, dur,
        instDef.vol or 0.3,
        instDef.env and instDef.env.a or 0.005,
        instDef.env and instDef.env.d or 0.04,
        instDef.env and instDef.env.s or 0.6,
        instDef.env and instDef.env.r or 0.05
    )
end

return music

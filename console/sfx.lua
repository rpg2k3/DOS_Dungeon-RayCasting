local sfx = {}

local sounds = {}
local sampleRate = 44100
local masterVol  = 0.5

local PI2 = math.pi * 2

----------------------------------------------------------------
-- Waveform generators: return -1..1 for phase 0..1
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

local waveforms = {
    square   = waveSquare,
    triangle = waveTriangle,
    sine     = waveSine,
    noise    = waveNoise,
}

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
-- Tone generator
----------------------------------------------------------------
local toneCache = {}

local function makeTone(wave, freq, dur, vol, attack, decay, sustain, release)
    vol     = vol or 0.3
    attack  = attack or 0.005
    decay   = decay or 0.04
    sustain = sustain or 0.6
    release = release or 0.06
    dur     = dur or 0.1

    local samples = math.floor(sampleRate * dur)
    if samples < 1 then samples = 1 end
    local sd = love.sound.newSoundData(samples, sampleRate, 16, 1)
    local wfn = waveforms[wave] or waveSquare
    local isNoise = (wave == "noise")
    local phase = 0
    local phaseInc = freq / sampleRate

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local env = adsr(t, dur, attack, decay, sustain, release)
        local sample
        if isNoise then
            sample = wfn() * env * vol
        else
            sample = wfn(phase) * env * vol
            phase = phase + phaseInc
            if phase >= 1 then phase = phase - 1 end
        end
        -- Soft clip
        if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
        sd:setSample(i, sample)
    end

    return love.audio.newSource(sd, "static")
end

----------------------------------------------------------------
-- Multi-tone SFX builder: sequence of {wave, freq, dur, vol, ...}
----------------------------------------------------------------
local function makeMultiTone(parts)
    -- Calculate total duration
    local totalDur = 0
    for _, p in ipairs(parts) do
        totalDur = totalDur + (p.dur or 0.1)
    end

    local totalSamples = math.floor(sampleRate * totalDur)
    if totalSamples < 1 then totalSamples = 1 end
    local sd = love.sound.newSoundData(totalSamples, sampleRate, 16, 1)

    local offset = 0
    for _, p in ipairs(parts) do
        local wave = p.wave or "square"
        local freq = p.freq or 440
        local dur  = p.dur or 0.1
        local vol  = p.vol or 0.3
        local a    = p.attack or 0.005
        local d    = p.decay or 0.04
        local s    = p.sustain or 0.6
        local r    = p.release or 0.06

        local wfn = waveforms[wave] or waveSquare
        local isNoise = (wave == "noise")
        local samples = math.floor(sampleRate * dur)
        local phase = 0
        local phaseInc = freq / sampleRate

        for i = 0, samples - 1 do
            local idx = offset + i
            if idx >= totalSamples then break end
            local t = i / sampleRate
            local env = adsr(t, dur, a, d, s, r)
            local sample
            if isNoise then
                sample = wfn() * env * vol
            else
                sample = wfn(phase) * env * vol
                phase = phase + phaseInc
                if phase >= 1 then phase = phase - 1 end
            end
            if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
            sd:setSample(idx, sample)
        end

        offset = offset + samples
    end

    return love.audio.newSource(sd, "static")
end

-- Pitch-slide tone: freq sweeps from startFreq to endFreq over duration
local function makeSlideTone(wave, startFreq, endFreq, dur, vol, attack, decay, sustain, release)
    vol     = vol or 0.3
    attack  = attack or 0.005
    decay   = decay or 0.04
    sustain = sustain or 0.6
    release = release or 0.06

    local samples = math.floor(sampleRate * dur)
    if samples < 1 then samples = 1 end
    local sd = love.sound.newSoundData(samples, sampleRate, 16, 1)
    local wfn = waveforms[wave] or waveSquare
    local phase = 0

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local frac = i / samples
        local freq = startFreq + (endFreq - startFreq) * frac
        local env = adsr(t, dur, attack, decay, sustain, release)
        local phaseInc = freq / sampleRate
        local sample = wfn(phase) * env * vol
        phase = phase + phaseInc
        if phase >= 1 then phase = phase - 1 end
        if sample > 1 then sample = 1 elseif sample < -1 then sample = -1 end
        sd:setSample(i, sample)
    end

    return love.audio.newSource(sd, "static")
end

----------------------------------------------------------------
-- Generate SFX bank
----------------------------------------------------------------
function sfx.init()
    -- UI sounds
    sounds.ui_move = makeTone("square", 800, 0.06, 0.25,
        0.003, 0.02, 0.5, 0.02)

    sounds.ui_select = makeMultiTone({
        {wave="square", freq=600, dur=0.06, vol=0.3, attack=0.003, decay=0.02, sustain=0.7, release=0.02},
        {wave="square", freq=900, dur=0.08, vol=0.3, attack=0.003, decay=0.02, sustain=0.7, release=0.03},
    })

    -- Gameplay sounds
    sounds.step = makeTone("triangle", 100, 0.06, 0.25,
        0.002, 0.02, 0.4, 0.02)

    sounds.turn = makeTone("square", 200, 0.03, 0.15,
        0.002, 0.01, 0.3, 0.01)

    sounds.bump = makeMultiTone({
        {wave="noise", freq=80, dur=0.04, vol=0.3, attack=0.002, decay=0.02, sustain=0.5, release=0.01},
        {wave="triangle", freq=60, dur=0.08, vol=0.3, attack=0.002, decay=0.03, sustain=0.4, release=0.03},
    })

    sounds.door = makeMultiTone({
        {wave="square", freq=300, dur=0.05, vol=0.25, attack=0.003, decay=0.02, sustain=0.5, release=0.02},
        {wave="triangle", freq=150, dur=0.1, vol=0.3, attack=0.003, decay=0.04, sustain=0.4, release=0.04},
    })

    sounds.pickup = makeMultiTone({
        {wave="square", freq=880, dur=0.06, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.02},
        {wave="square", freq=1320, dur=0.08, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.03},
    })

    -- Editor sounds
    sounds.paint = makeTone("square", 1200, 0.03, 0.2,
        0.002, 0.01, 0.5, 0.01)

    sounds.save = makeMultiTone({
        {wave="square", freq=523, dur=0.08, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.02},
        {wave="square", freq=659, dur=0.08, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.02},
        {wave="square", freq=784, dur=0.12, vol=0.25, attack=0.003, decay=0.03, sustain=0.6, release=0.04},
    })

    sounds.load = makeMultiTone({
        {wave="triangle", freq=784, dur=0.08, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.02},
        {wave="triangle", freq=659, dur=0.08, vol=0.25, attack=0.003, decay=0.02, sustain=0.6, release=0.02},
        {wave="triangle", freq=523, dur=0.12, vol=0.25, attack=0.003, decay=0.03, sustain=0.6, release=0.04},
    })
end

function sfx.play(name)
    local s = sounds[name]
    if s then
        local clone = s:clone()
        clone:setVolume(masterVol)
        clone:play()
    end
end

function sfx.setVolume(v)
    masterVol = math.max(0, math.min(1, v))
end

function sfx.getVolume()
    return masterVol
end

return sfx

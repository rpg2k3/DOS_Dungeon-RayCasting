local sfx = {}

local sounds = {}
local sampleRate = 44100

----------------------------------------------------------------
-- tiny waveform helpers
----------------------------------------------------------------
local function squareWave(t, freq)
    return (math.sin(2 * math.pi * freq * t) >= 0) and 1 or -1
end

local function noiseVal()
    return math.random() * 2 - 1
end

local function makeSound(duration, genFunc)
    local samples = math.floor(sampleRate * duration)
    local sd = love.sound.newSoundData(samples, sampleRate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / sampleRate
        local env = 1 - (i / samples)
        sd:setSample(i, math.max(-1, math.min(1, genFunc(t, env))))
    end
    return love.audio.newSource(sd, "static")
end

----------------------------------------------------------------
-- Generate named sounds
----------------------------------------------------------------
function sfx.init()
    -- ui_move: short high blip
    sounds.ui_move = makeSound(0.06, function(t, env)
        return squareWave(t, 800) * env * 0.3
    end)

    -- ui_select: two-tone confirm
    sounds.ui_select = makeSound(0.15, function(t, env)
        local freq = t < 0.07 and 600 or 900
        return squareWave(t, freq) * env * 0.35
    end)

    -- step: low thud
    sounds.step = makeSound(0.08, function(t, env)
        return squareWave(t, 120) * env * 0.3
    end)

    -- bump: impact noise
    sounds.bump = makeSound(0.1, function(t, env)
        return (noiseVal() * 0.5 + squareWave(t, 80) * 0.5) * env * 0.35
    end)

    -- paint: tiny click
    sounds.paint = makeSound(0.03, function(t, env)
        return squareWave(t, 1200) * env * 0.25
    end)

    -- save: descending sweep
    sounds.save = makeSound(0.3, function(t, env)
        local freq = 900 - t * 2000
        if freq < 100 then freq = 100 end
        return squareWave(t, freq) * env * 0.3
    end)
end

function sfx.play(name)
    local s = sounds[name]
    if s then
        s:stop()
        s:play()
    end
end

return sfx

local gfx = {}

gfx.VIRT_W = 320
gfx.VIRT_H = 200
gfx.GLYPH_W = 5
gfx.GLYPH_H = 7
gfx.CHAR_W = 6
gfx.CHAR_H = 8

-- CGA/EGA-inspired 16-color palette (0-1 range)
gfx.palette = {
    [0]  = {0.00, 0.00, 0.00}, -- black
    [1]  = {0.00, 0.00, 0.67}, -- dark blue
    [2]  = {0.00, 0.67, 0.00}, -- dark green
    [3]  = {0.00, 0.67, 0.67}, -- dark cyan
    [4]  = {0.67, 0.00, 0.00}, -- dark red
    [5]  = {0.67, 0.00, 0.67}, -- dark magenta
    [6]  = {0.67, 0.33, 0.00}, -- brown
    [7]  = {0.67, 0.67, 0.67}, -- light gray
    [8]  = {0.33, 0.33, 0.33}, -- dark gray
    [9]  = {0.33, 0.33, 1.00}, -- blue
    [10] = {0.33, 1.00, 0.33}, -- green
    [11] = {0.33, 1.00, 1.00}, -- cyan
    [12] = {1.00, 0.33, 0.33}, -- red
    [13] = {1.00, 0.33, 1.00}, -- magenta
    [14] = {1.00, 1.00, 0.33}, -- yellow
    [15] = {1.00, 1.00, 1.00}, -- white
}

----------------------------------------------------------------
-- 5x7 bitmap font data. Each glyph = 7 rows, each row 5 bits.
-- bit4 = leftmost pixel, bit0 = rightmost.
----------------------------------------------------------------
local G = {}
-- ASCII 32-47: punctuation
G[32]  = {0,0,0,0,0,0,0}         -- (space)
G[33]  = {4,4,4,4,0,4,0}         -- !
G[34]  = {10,10,0,0,0,0,0}       -- "
G[35]  = {0,10,31,10,31,10,0}    -- #
G[36]  = {4,15,20,14,5,30,4}     -- $
G[37]  = {25,2,4,8,19,0,0}       -- %
G[38]  = {8,20,8,21,18,18,13}    -- &
G[39]  = {4,4,0,0,0,0,0}         -- '
G[40]  = {2,4,8,8,8,4,2}         -- (
G[41]  = {8,4,2,2,2,4,8}         -- )
G[42]  = {0,4,21,14,21,4,0}      -- *
G[43]  = {0,4,4,31,4,4,0}        -- +
G[44]  = {0,0,0,0,0,4,8}         -- ,
G[45]  = {0,0,0,14,0,0,0}        -- -
G[46]  = {0,0,0,0,0,4,0}         -- .
G[47]  = {1,2,4,8,16,0,0}        -- /
-- ASCII 48-57: digits
G[48]  = {14,17,19,21,25,17,14}  -- 0
G[49]  = {4,12,4,4,4,4,14}       -- 1
G[50]  = {14,17,1,6,8,16,31}     -- 2
G[51]  = {14,17,1,6,1,17,14}     -- 3
G[52]  = {2,6,10,18,31,2,2}      -- 4
G[53]  = {31,16,30,1,1,17,14}    -- 5
G[54]  = {14,16,16,30,17,17,14}  -- 6
G[55]  = {31,1,2,4,8,8,8}        -- 7
G[56]  = {14,17,17,14,17,17,14}  -- 8
G[57]  = {14,17,17,15,1,1,14}    -- 9
-- ASCII 58-64
G[58]  = {0,0,4,0,4,0,0}         -- :
G[59]  = {0,0,4,0,4,4,8}         -- ;
G[60]  = {2,4,8,16,8,4,2}        -- <
G[61]  = {0,0,31,0,31,0,0}       -- =
G[62]  = {16,8,4,2,4,8,16}       -- >
G[63]  = {14,17,1,6,4,0,4}       -- ?
G[64]  = {14,17,23,21,22,16,14}  -- @
-- ASCII 65-90: uppercase letters
G[65]  = {4,10,17,31,17,17,0}    -- A
G[66]  = {30,17,17,30,17,17,30}  -- B
G[67]  = {14,17,16,16,16,17,14}  -- C
G[68]  = {28,18,17,17,17,18,28}  -- D
G[69]  = {31,16,16,30,16,16,31}  -- E
G[70]  = {31,16,16,30,16,16,16}  -- F
G[71]  = {14,17,16,23,17,17,14}  -- G
G[72]  = {17,17,17,31,17,17,17}  -- H
G[73]  = {14,4,4,4,4,4,14}       -- I
G[74]  = {7,2,2,2,2,18,12}       -- J
G[75]  = {17,18,20,24,20,18,17}  -- K
G[76]  = {16,16,16,16,16,16,31}  -- L
G[77]  = {17,27,21,21,17,17,17}  -- M
G[78]  = {17,25,21,19,17,17,17}  -- N
G[79]  = {14,17,17,17,17,17,14}  -- O
G[80]  = {30,17,17,30,16,16,16}  -- P
G[81]  = {14,17,17,17,21,18,13}  -- Q
G[82]  = {30,17,17,30,20,18,17}  -- R
G[83]  = {14,17,16,14,1,17,14}   -- S
G[84]  = {31,4,4,4,4,4,4}        -- T
G[85]  = {17,17,17,17,17,17,14}  -- U
G[86]  = {17,17,17,17,17,10,4}   -- V
G[87]  = {17,17,17,21,21,14,10}  -- W
G[88]  = {17,17,10,4,10,17,17}   -- X
G[89]  = {17,17,10,4,4,4,4}      -- Y
G[90]  = {31,1,2,4,8,16,31}      -- Z
-- ASCII 91-96
G[91]  = {14,8,8,8,8,8,14}       -- [
G[92]  = {16,8,4,2,1,0,0}        -- backslash
G[93]  = {14,2,2,2,2,2,14}       -- ]
G[94]  = {4,10,17,0,0,0,0}       -- ^
G[95]  = {0,0,0,0,0,0,31}        -- _
G[96]  = {8,4,0,0,0,0,0}         -- `
-- ASCII 123-126
G[123] = {6,4,4,8,4,4,6}         -- {
G[124] = {4,4,4,4,4,4,4}         -- |
G[125] = {12,4,4,2,4,4,12}       -- }
G[126] = {0,0,8,21,2,0,0}        -- ~

----------------------------------------------------------------
-- Build font atlas image + quads at init
----------------------------------------------------------------
local fontImage, fontQuads

function gfx._buildFont()
    -- 16 columns x 6 rows grid, cell = 6x8
    local cols, rows = 16, 6
    local imgW, imgH = cols * gfx.CHAR_W, rows * gfx.CHAR_H
    local imgData = love.image.newImageData(imgW, imgH)

    for code = 32, 126 do
        local glyph = G[code]
        -- lowercase a-z -> uppercase A-Z
        if not glyph and code >= 97 and code <= 122 then
            glyph = G[code - 32]
        end
        if glyph then
            local idx = code - 32
            local col = idx % cols
            local row = math.floor(idx / cols)
            local ox = col * gfx.CHAR_W
            local oy = row * gfx.CHAR_H
            for r = 0, 6 do
                local bits = glyph[r + 1]
                for c = 0, 4 do
                    if bit.band(bits, bit.lshift(1, 4 - c)) ~= 0 then
                        imgData:setPixel(ox + c, oy + r, 1, 1, 1, 1)
                    end
                end
            end
        end
    end

    fontImage = love.graphics.newImage(imgData)
    fontImage:setFilter("nearest", "nearest")

    fontQuads = {}
    for code = 32, 126 do
        local idx = code - 32
        local col = idx % cols
        local row = math.floor(idx / cols)
        fontQuads[code] = love.graphics.newQuad(
            col * gfx.CHAR_W, row * gfx.CHAR_H,
            gfx.CHAR_W, gfx.CHAR_H,
            imgW, imgH
        )
    end
end

----------------------------------------------------------------
-- CRT post-process shader (LÖVE 11.5 GLSL)
-- Scanlines, vignette, chromatic aberration, barrel distortion,
-- subtle noise flicker
----------------------------------------------------------------
local crtShader

local CRT_GLSL = [[
extern vec2 inputSize;   // virtual canvas pixel dimensions
extern float time;       // elapsed seconds (for noise)

// barrel distortion strength
const float BARREL = 0.08;
// chromatic aberration offset (in UV space)
const float CHROMA = 0.0015;
// scanline darkness
const float SCANLINE = 0.18;
// vignette strength
const float VIGNETTE = 0.35;

// simple pseudo-random
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 barrelDistort(vec2 uv) {
    vec2 cc = uv - 0.5;
    float r2 = dot(cc, cc);
    return uv + cc * r2 * BARREL;
}

vec4 effect(vec4 color, Image tex, vec2 texCoord, vec2 pixCoord) {
    vec2 uv = barrelDistort(texCoord);

    // discard pixels outside barrel-distorted area
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return vec4(0.0, 0.0, 0.0, 1.0);

    // chromatic aberration: offset R and B channels slightly
    float r = Texel(tex, vec2(uv.x + CHROMA, uv.y)).r;
    float g = Texel(tex, uv).g;
    float b = Texel(tex, vec2(uv.x - CHROMA, uv.y)).b;
    vec3 col = vec3(r, g, b);

    // scanlines (darken every other virtual-pixel row)
    float scanY = uv.y * inputSize.y;
    float scanFactor = 1.0 - SCANLINE * step(0.5, fract(scanY * 0.5));
    col *= scanFactor;

    // vignette (darken edges)
    vec2 vig = uv - 0.5;
    float vigAmount = 1.0 - dot(vig, vig) * VIGNETTE * 4.0;
    col *= clamp(vigAmount, 0.0, 1.0);

    // subtle noise flicker
    float noise = rand(uv + vec2(time, 0.0)) * 0.04 - 0.02;
    col += noise;

    return vec4(clamp(col, 0.0, 1.0), 1.0) * color;
}
]]

local function buildCrtShader()
    local ok, shader = pcall(love.graphics.newShader, CRT_GLSL)
    if ok then
        return shader
    end
    return nil
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function gfx.init()
    gfx.canvas = love.graphics.newCanvas(gfx.VIRT_W, gfx.VIRT_H)
    gfx.canvas:setFilter("nearest", "nearest")
    gfx._buildFont()
    gfx._updateScale()
    crtShader = buildCrtShader()
end

function gfx._updateScale()
    local ww, wh = love.graphics.getDimensions()
    gfx.scale = math.max(1, math.min(math.floor(ww / gfx.VIRT_W), math.floor(wh / gfx.VIRT_H)))
    gfx.offsetX = math.floor((ww - gfx.VIRT_W * gfx.scale) / 2)
    gfx.offsetY = math.floor((wh - gfx.VIRT_H * gfx.scale) / 2)
end

function gfx.resize()
    gfx._updateScale()
end

function gfx.beginDraw()
    love.graphics.setCanvas(gfx.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setLineStyle("rough")
    love.graphics.setLineWidth(1)
end

function gfx.endDraw(crtEnabled)
    love.graphics.setCanvas()
    love.graphics.clear(0.05, 0.05, 0.05, 1)
    love.graphics.setColor(1, 1, 1, 1)

    if crtEnabled and crtShader then
        crtShader:send("inputSize", {gfx.VIRT_W, gfx.VIRT_H})
        crtShader:send("time", love.timer.getTime())
        love.graphics.setShader(crtShader)
    end

    love.graphics.draw(gfx.canvas, gfx.offsetX, gfx.offsetY, 0, gfx.scale, gfx.scale)

    if crtEnabled and crtShader then
        love.graphics.setShader()
    end
end

function gfx.setColor(index)
    local c = gfx.palette[index] or gfx.palette[15]
    love.graphics.setColor(c[1], c[2], c[3], 1)
end

function gfx.setColorRGBA(r, g, b, a)
    love.graphics.setColor(r, g, b, a or 1)
end

-- Print text with the bitmap font.  scale defaults to 1.
function gfx.print(text, x, y, colorIndex, scale)
    scale = scale or 1
    gfx.setColor(colorIndex or 15)
    local str = tostring(text)
    local cx = x
    for i = 1, #str do
        local code = string.byte(str, i)
        -- map lowercase to uppercase
        if code >= 97 and code <= 122 then code = code - 32 end
        local q = fontQuads[code]
        if q then
            love.graphics.draw(fontImage, q, math.floor(cx), math.floor(y), 0, scale, scale)
        end
        cx = cx + gfx.CHAR_W * scale
    end
end

-- Measure text width in pixels at given scale
function gfx.textWidth(text, scale)
    scale = scale or 1
    return #tostring(text) * gfx.CHAR_W * scale
end

-- Draw a 1px bordered rectangle (panel)
function gfx.panel(x, y, w, h, borderColor, fillColor)
    if fillColor then
        gfx.setColor(fillColor)
        love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
    end
    gfx.setColor(borderColor or 7)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

-- Filled rectangle
function gfx.rect(x, y, w, h, colorIndex)
    gfx.setColor(colorIndex or 15)
    love.graphics.rectangle("fill", x, y, w, h)
end

-- Outlined rectangle
function gfx.rectLine(x, y, w, h, colorIndex)
    gfx.setColor(colorIndex or 15)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

-- Line
function gfx.line(x1, y1, x2, y2, colorIndex)
    gfx.setColor(colorIndex or 15)
    love.graphics.line(x1, y1, x2, y2)
end

-- Pixel
function gfx.pixel(x, y, colorIndex)
    gfx.setColor(colorIndex or 15)
    love.graphics.rectangle("fill", x, y, 1, 1)
end

-- Clear to palette color
function gfx.cls(colorIndex)
    gfx.setColor(colorIndex or 0)
    love.graphics.rectangle("fill", 0, 0, gfx.VIRT_W, gfx.VIRT_H)
end

return gfx

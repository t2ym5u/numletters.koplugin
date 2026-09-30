local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- ---------------------------------------------------------------------------
-- Tile pools — weighted letter distributions (FR and EN)
-- ---------------------------------------------------------------------------

local TILES_FR_VOWELS     = "AAAAAAAAAEEEEEEEEEEEEEEEIIIIIIIIOOOOOOUU UUUUY"
local TILES_FR_CONSONANTS = "BBCCDDDFFFGGHHHJKLLLLLMMMNNNNNNPQRRRRRRSSSSSSTTTTTTVVWXZ"
local TILES_EN_VOWELS     = "AAAAAAAAAEEEEEEEEEEEEIIIIIIIIIOOOOOOOOOUUUU"
local TILES_EN_CONSONANTS = "BBCCDDDDFFFFFGGGHHJKLLLLMMNNNNNNPPQRRRRRRSSSTTTTTTTVVWWXYYYZ"

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------

local Board = {}
Board.__index = Board

function Board:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        lang    = opts.lang or "fr",
        phase   = "letters",  -- "letters" | "numbers"
        letters = {},         -- drawn letters (array of strings)
        numbers = {},         -- drawn numbers (array of ints)
        target  = 0,
        dict    = nil,
        solutions = nil,      -- computed after round end; nil = not yet computed
    }, self)
    obj:_loadDict()
    return obj
end

function Board:_loadDict()
    self.dict = nil
    if self.lang == "fr" then
        local path = _dir .. "words_fr.lua"
        local fn = loadfile(path)
        self.dict = fn and fn() or {}
    else
        local ok, d = pcall(require, "words_en")
        self.dict = ok and d or {}
    end
end

-- ---------------------------------------------------------------------------
-- Letters phase
-- ---------------------------------------------------------------------------

function Board:startLetters()
    self.phase    = "letters"
    self.letters  = {}
    self.solutions = nil
end

function Board:canDrawLetter()
    return #self.letters < 9
end

function Board:drawVowel()
    if not self:canDrawLetter() then return nil end
    local pool = self.lang == "fr" and TILES_FR_VOWELS or TILES_EN_VOWELS
    -- Remove already-drawn letters from the pool (approximate: just pick randomly)
    local i = math.random(#pool)
    local c = pool:sub(i, i)
    if c == " " then c = "E" end  -- fallback for spacing chars
    self.letters[#self.letters + 1] = c
    self.solutions = nil
    return c
end

function Board:drawConsonant()
    if not self:canDrawLetter() then return nil end
    local pool = self.lang == "fr" and TILES_FR_CONSONANTS or TILES_EN_CONSONANTS
    local i = math.random(#pool)
    local c = pool:sub(i, i)
    self.letters[#self.letters + 1] = c
    self.solutions = nil
    return c
end

-- Find all dictionary words formable from the drawn letters (multiset subset).
function Board:findSolutions()
    if self.solutions then return self.solutions end
    if not self.dict or #self.letters == 0 then self.solutions = {}; return {} end

    -- Availability map, keyed the way the dictionary stores words (lowercase),
    -- so the scan below never has to build an uppercase copy of each entry.
    -- That matters: this walks the whole dictionary, which is ~105k words in
    -- English, and one allocation per word dominated the round otherwise.
    local available = {}
    for _, l in ipairs(self.letters) do
        local k = l:lower()
        available[k] = (available[k] or 0) + 1
    end

    local max_len = #self.letters
    local results = {}
    for word in pairs(self.dict) do
        local len = #word
        if len >= 2 and len <= max_len then
            local used = {}
            local ok   = true
            for k = 1, len do
                local ch = word:sub(k, k)
                local n  = (used[ch] or 0) + 1
                if n > (available[ch] or 0) then
                    ok = false; break
                end
                used[ch] = n
            end
            if ok then results[#results + 1] = word end
        end
    end

    table.sort(results, function(a, b)
        if #a ~= #b then return #a > #b end
        return a < b
    end)
    self.solutions = results
    return results
end

-- ---------------------------------------------------------------------------
-- Numbers phase
-- ---------------------------------------------------------------------------

function Board:startNumbers()
    self.phase   = "numbers"
    self.numbers = {}
    self.target  = 0
    self.solutions = nil
    for _ = 1, 6 do
        self.numbers[#self.numbers + 1] = math.random(1, 100)
    end
    self.target = math.random(100, 999)
end

return Board

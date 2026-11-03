local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Blocklist = assert(loadfile(_dir .. "blocklist.lua"))()

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

-- Each list is loaded from this plugin's own folder, once. Not through
-- require("words_en"): that module name is shared with the other word games,
-- which put their own folder first on package.path, so require could hand
-- back another game's (different) English list.
local DICTS = {}

function Board:_loadDict()
    local lang = self.lang == "fr" and "fr" or "en"
    if not DICTS[lang] then
        local fn = loadfile(_dir .. "words_" .. lang .. ".lua")
        local ok, d = false, nil
        if fn then ok, d = pcall(fn) end
        DICTS[lang] = (ok and type(d) == "table") and d or {}
    end
    self.dict = DICTS[lang]
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

    -- The solutions are revealed (best words), so they leave out the
    -- family-friendly blocklist (blocklist.lua); a player's own word is still
    -- checked against the whole dictionary.
    local blocked = Blocklist.set(self.lang)
    local max_len = #self.letters
    local results = {}
    for word in pairs(self.dict) do
        local len = #word
        if len >= 2 and len <= max_len and not blocked[word:upper()] then
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

-- ---------------------------------------------------------------------------
-- Numbers solver (pure; used by the multiplayer mode)
--
-- Every value reachable from the drawn numbers with +, −, ×, ÷, each number
-- used at most once, intermediate results positive integers (the TV rules).
-- Subset dynamic programming: vals[mask] holds the values that use exactly
-- the numbers of `mask`, each with how it was made, so a solution can be
-- written back as steps. Disjoint subsets are combined once per unordered
-- pair; ×1 and ÷1 are skipped (they reach nothing a smaller subset doesn't).
-- Intermediate values are capped at VALUE_CAP: past it nothing useful for a
-- 3-digit target is lost in practice, and the tables stay small.
-- ---------------------------------------------------------------------------

local VALUE_CAP = 100000

local function popcount(m)
    local c = 0
    while m > 0 do
        if m % 2 == 1 then c = c + 1 end
        m = math.floor(m / 2)
    end
    return c
end

-- a's numbers are all in s (no bit library: busted runs plain Lua too).
local function isSubset(a, s)
    while a > 0 do
        if a % 2 == 1 and s % 2 == 0 then return false end
        a, s = math.floor(a / 2), math.floor(s / 2)
    end
    return true
end

-- Returns a solver table: { numbers, vals = { [mask] = { [v] = rec } },
-- masks (by size), reachable = { [v] = mask_with_fewest_numbers } }.
function Board.solveNumbers(numbers)
    local n = #numbers
    local full = math.floor(2 ^ n) - 1
    local vals = {}
    local by_size = {}
    for m = 1, full do
        local c = popcount(m)
        by_size[c] = by_size[c] or {}
        by_size[c][#by_size[c] + 1] = m
    end
    for i = 1, n do
        local m = math.floor(2 ^ (i - 1))
        vals[m] = { [numbers[i]] = { leaf = i } }
    end
    for size = 2, n do
        for _, s in ipairs(by_size[size] or {}) do
            local out = {}
            -- every split of s into two disjoint halves a, b with a < b
            for a = 1, s - 1 do
                local b = s - a
                if a < b and isSubset(a, s) then
                    local va, vb = vals[a], vals[b]
                    for x in pairs(va) do
                        for y in pairs(vb) do
                            local hi, lo, ma, mb = x, y, a, b
                            if y > x then hi, lo, ma, mb = y, x, b, a end
                            local r = hi + lo
                            if r <= VALUE_CAP and not out[r] then
                                out[r] = { op = "+", hi = hi, lo = lo, mhi = ma, mlo = mb }
                            end
                            if lo > 1 then
                                r = hi * lo
                                if r <= VALUE_CAP and not out[r] then
                                    out[r] = { op = "×", hi = hi, lo = lo, mhi = ma, mlo = mb }
                                end
                                if hi % lo == 0 then
                                    r = math.floor(hi / lo)
                                    if not out[r] then
                                        out[r] = { op = "÷", hi = hi, lo = lo, mhi = ma, mlo = mb }
                                    end
                                end
                            end
                            if hi > lo then
                                r = hi - lo
                                if not out[r] then
                                    out[r] = { op = "−", hi = hi, lo = lo, mhi = ma, mlo = mb }
                                end
                            end
                        end
                    end
                end
            end
            vals[s] = out
        end
    end
    -- Fewest numbers first, so a solution is as short as it can be.
    local reachable = {}
    for size = 1, n do
        for _, m in ipairs(by_size[size] or {}) do
            for v in pairs(vals[m]) do
                if not reachable[v] then reachable[v] = m end
            end
        end
    end
    return { numbers = numbers, vals = vals, reachable = reachable }
end

-- The steps that make value v (["100 + 6 = 106", "106 × 9 = 954", ...]),
-- or {} when v is one of the drawn numbers.
function Board.solutionSteps(solver, v)
    local m = solver.reachable[v]
    if not m then return nil end
    local steps = {}
    local function walk(mask, value)
        local rec = solver.vals[mask][value]
        if rec.leaf then return end
        walk(rec.mhi, rec.hi)
        walk(rec.mlo, rec.lo)
        steps[#steps + 1] = string.format("%d %s %d = %d", rec.hi, rec.op, rec.lo, value)
    end
    walk(m, v)
    return steps
end

-- The reachable value closest to target (the smaller one on a tie).
function Board.closestValue(solver, target)
    if solver.reachable[target] then return target, 0 end
    for d = 1, VALUE_CAP do
        if solver.reachable[target - d] then return target - d, d end
        if solver.reachable[target + d] then return target + d, d end
    end
    return nil
end

return Board

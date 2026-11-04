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

-- Each list is loaded from this plugin's own folder. Not through
-- require("words_en"): that module name is shared with the other word games,
-- which put their own folder first on package.path, so require could hand
-- back another game's (different) English list.
-- Only the language played is kept (switching language drops the other
-- one), it loads with the first board, not with the module, and
-- Board.release() (the screen closing) drops it: a list is ~5-10 MB once
-- loaded and reads again in a few tens of milliseconds on a desktop.
local DICTS = {}

function Board:_loadDict()
    local lang = self.lang == "fr" and "fr" or "en"
    if not DICTS[lang] then
        local fn = loadfile(_dir .. "words_" .. lang .. ".lua")
        local ok, d = false, nil
        if fn then ok, d = pcall(fn) end
        DICTS = { [lang] = (ok and type(d) == "table") and d or {} }
    end
    self.dict = DICTS[lang]
end

-- Drops the loaded dictionary (called when the game screen closes); the
-- next board reads its language's list again.
function Board.release()
    DICTS = {}
end

-- The languages whose dictionary is loaded now (for the specs).
function Board.loadedLanguages()
    local out = {}
    for lang in pairs(DICTS) do out[#out + 1] = lang end
    table.sort(out)
    return out
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

    -- Availability per letter byte, in the dictionary's case (lowercase).
    -- This walks the whole dictionary (~105k words in English, ~133k in
    -- French), so the per-word work is kept to byte reads and two small
    -- arrays reused across words: no table, substring or uppercase copy is
    -- allocated for a word that does not fit (that cost ~60 ms per round on a
    -- desktop, over a second on a reader).
    local byte = string.byte
    local available, used = {}, {}
    for b = 97, 122 do available[b], used[b] = 0, 0 end
    for _, l in ipairs(self.letters) do
        local b = byte(l:lower())
        if available[b] then available[b] = available[b] + 1 end
    end

    -- The solutions are revealed (best words), so they leave out the
    -- family-friendly blocklist (blocklist.lua); a player's own word is still
    -- checked against the whole dictionary.
    local blocked = Blocklist.set(self.lang)
    local max_len = #self.letters
    local results = {}
    for word in pairs(self.dict) do
        local len = #word
        if len >= 2 and len <= max_len then
            local ok, k = true, 1
            while k <= len do
                local b = byte(word, k)
                local n = (used[b] or 99) + 1
                if n > (available[b] or 0) then ok = false; break end
                used[b] = n
                k = k + 1
            end
            -- reset the counts of the letters seen
            for j = 1, (ok and len or k - 1) do used[byte(word, j)] = 0 end
            if ok and not blocked[word:upper()] then results[#results + 1] = word end
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

-- How each value was made, packed in one number instead of a table per
-- value (the tables were most of the solver's time: up to ~40 ms on a
-- desktop for six numbers, about a second on a reader):
--   rec = (op * 64 + mhi) * HI_SPAN + hi
-- op indexes OPS, hi is the larger operand and mhi the numbers it uses; the
-- other operand uses mask - mhi and is recovered from the value and hi. A
-- drawn number is stored as -i (its index).
local OPS = { "+", "×", "÷", "−" }
local HI_SPAN = 131072   -- > VALUE_CAP

local function packRec(op, mhi, hi)
    return (op * 64 + mhi) * HI_SPAN + hi
end

local function unpackRec(rec, value)
    local hi = rec % HI_SPAN
    local rest = (rec - hi) / HI_SPAN
    local mhi = rest % 64
    local op = (rest - mhi) / 64
    local lo
    if op == 1 then lo = value - hi
    elseif op == 2 then lo = value / hi
    elseif op == 3 then lo = hi / value
    else lo = hi - value end
    -- integer-valued floats would print as "3.0" under Lua 5.3+
    return OPS[op], hi, math.floor(lo + 0.5), mhi
end

-- Returns a solver table: { numbers, vals = { [mask] = { [v] = rec } },
-- reachable = { [v] = mask_with_fewest_numbers } }.
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
        vals[m] = { [numbers[i]] = -i }
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
                            local hi, lo, ma = x, y, a
                            if y > x then hi, lo, ma = y, x, b end
                            local r = hi + lo
                            if r <= VALUE_CAP and not out[r] then
                                out[r] = packRec(1, ma, hi)
                            end
                            if lo > 1 then
                                r = hi * lo
                                if r <= VALUE_CAP and not out[r] then
                                    out[r] = packRec(2, ma, hi)
                                end
                                if hi % lo == 0 then
                                    r = math.floor(hi / lo)
                                    if not out[r] then
                                        out[r] = packRec(3, ma, hi)
                                    end
                                end
                            end
                            if hi > lo then
                                r = hi - lo
                                if not out[r] then
                                    out[r] = packRec(4, ma, hi)
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
        if rec < 0 then return end
        local op, hi, lo, mhi = unpackRec(rec, value)
        walk(mhi, hi)
        walk(mask - mhi, lo)
        steps[#steps + 1] = string.format("%d %s %d = %d", hi, op, lo, value)
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

-- ---------------------------------------------------------------------------
-- Match — the multiplayer mode's rules (pure Lua, no UI, tested by busted).
--
-- A match is N rounds, letters and numbers alternating (letters first).
-- Players write on paper; once the time is up each player's answer is typed
-- in, and the round is scored the way the TV show does it:
--
--   Letters: the longest valid word(s) score their length; everyone else 0.
--            Ties all score. A valid word is in the dictionary and uses only
--            the drawn letters (each tile at most once).
--   Numbers: only the closest valid answer(s) score: exact 10, 1–5 away 7,
--            6–10 away 5, further 0. Ties all score. An answer the drawn
--            numbers cannot make at all scores nothing.
-- ---------------------------------------------------------------------------

local Party = require("party")

local Match = {}

Match.ROUND_CHOICES = { 4, 6, 8, 10 }
Match.TIME_CHOICES  = { 30, 45, 60 }
Match.DEFAULT_ROUNDS = 6
Match.DEFAULT_TIME   = 30
-- The numbers round gets this much more than the letters round (30 s → 45 s,
-- as on the show).
Match.NUMBERS_EXTRA_TIME = 15

-- Round k is a letters round when k is odd.
function Match.roundKind(k)
    return (k % 2 == 1) and "letters" or "numbers"
end

function Match.new(names, rounds)
    local m = {
        scores  = Party.newScores(names),
        rounds  = rounds or Match.DEFAULT_ROUNDS,
        entries = {},     -- this round's answers, one string per player
        results = nil,    -- this round's scored results, nil until scored
        finished = false,
    }
    Party.nextRound(m.scores)   -- round 1
    return m
end

function Match.current(m)
    return m.scores.round
end

function Match.isLastRound(m)
    return m.scores.round >= m.rounds
end

-- Moves to the next round; returns false when the match was already over.
function Match.advance(m)
    if m.finished or Match.isLastRound(m) then return false end
    Party.nextRound(m.scores)
    m.entries = {}
    m.results = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Letters
-- ---------------------------------------------------------------------------

-- French accents fold to the plain letter, as in the dictionaries.
local FOLD = {
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["í"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["ó"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u",
    ["ÿ"] = "y", ["ç"] = "c", ["ñ"] = "n", ["œ"] = "oe", ["æ"] = "ae",
    ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Á"] = "a",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["Î"] = "i", ["Ï"] = "i", ["Í"] = "i",
    ["Ô"] = "o", ["Ö"] = "o", ["Ó"] = "o",
    ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ú"] = "u",
    ["Ÿ"] = "y", ["Ç"] = "c", ["Ñ"] = "n", ["Œ"] = "oe", ["Æ"] = "ae",
}

-- Lowercase a–z form of a typed word, "" for an empty answer, or nil when it
-- has anything else in it (a digit, an apostrophe, a hyphen...).
function Match.normalizeWord(s)
    s = (s or ""):gsub("%s+", "")
    if s == "" then return "" end
    s = s:gsub("[\192-\247][\128-\191]*", function(ch) return FOLD[ch] or ch end)
    s = s:lower()
    if s:find("[^a-z]") then return nil end
    return s
end

-- status: "empty" | "invalid" (not letters) | "letters" (uses a tile that
-- wasn't drawn, or one too often) | "unknown" (not in the dictionary) | "ok".
-- letters: the drawn tiles (any case). dict: { [word] = true }.
function Match.checkWord(raw, letters, dict)
    local w = Match.normalizeWord(raw)
    if w == nil then return "invalid", nil end
    if w == "" then return "empty", "" end
    local avail = {}
    for _i, l in ipairs(letters) do
        local k = l:lower()
        avail[k] = (avail[k] or 0) + 1
    end
    for ch in w:gmatch(".") do
        if (avail[ch] or 0) == 0 then return "letters", w end
        avail[ch] = avail[ch] - 1
    end
    if not dict[w] then return "unknown", w end
    return "ok", w
end

-- entries[i]: player i's typed word (nil/"" = no answer).
-- Returns results[i] = { word, status, points }, and the best length.
function Match.scoreLetters(entries, n_players, letters, dict)
    local results, best = {}, 0
    for i = 1, n_players do
        local status, w = Match.checkWord(entries[i], letters, dict)
        results[i] = { word = w or entries[i], status = status, points = 0 }
        if status == "ok" and #w > best then best = #w end
    end
    if best > 0 then
        for i = 1, n_players do
            local r = results[i]
            if r.status == "ok" and #r.word == best then r.points = best end
        end
    end
    return results, best
end

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------

-- Points for the closest answer, by its distance to the target.
function Match.numbersPoints(dist)
    if dist == 0 then return 10 end
    if dist <= 5 then return 7 end
    if dist <= 10 then return 5 end
    return 0
end

-- entries[i]: player i's typed number (string or number; nil/"" = none).
-- reachable(v) → whether the drawn numbers can make v.
-- Returns results[i] = { value, status, dist, points }, status one of
-- "empty" | "invalid" | "impossible" | "ok".
function Match.scoreNumbers(entries, n_players, target, reachable)
    local results, best = {}, nil
    for i = 1, n_players do
        local e = entries[i]
        local s = e and tostring(e):gsub("%s+", "") or ""
        local r = { points = 0 }
        if s == "" then
            r.status = "empty"
        elseif not s:match("^%d+$") then
            r.status = "invalid"
        else
            r.value = tonumber(s)
            if not reachable(r.value) then
                r.status = "impossible"
            else
                r.status = "ok"
                r.dist = math.abs(r.value - target)
                if best == nil or r.dist < best then best = r.dist end
            end
        end
        results[i] = r
    end
    if best then
        local pts = Match.numbersPoints(best)
        for i = 1, n_players do
            local r = results[i]
            if r.status == "ok" and r.dist == best then r.points = pts end
        end
    end
    return results, best
end

-- Adds the round's points to the scores, and ends the match after the last
-- round. Scoring a round twice is a no-op.
function Match.applyResults(m, results)
    if m.results then return false end
    m.results = results
    for i, r in ipairs(results) do
        if r.points > 0 then Party.award(m.scores, i, r.points) end
    end
    if Match.isLastRound(m) then m.finished = true end
    return true
end

-- ---------------------------------------------------------------------------
-- Save / restore
-- ---------------------------------------------------------------------------

local function copyList(t)
    local c = {}
    for k, v in pairs(t or {}) do
        if type(v) == "table" then c[k] = copyList(v) else c[k] = v end
    end
    return c
end

function Match.serialize(m)
    return {
        scores   = Party.copyScores(m.scores),
        rounds   = m.rounds,
        entries  = copyList(m.entries),
        results  = m.results and copyList(m.results) or nil,
        finished = m.finished,
    }
end

function Match.restore(t)
    if type(t) ~= "table" then return nil end
    local scores = Party.restoreScores(t.scores)
    local rounds = tonumber(t.rounds)
    if not scores or not rounds or rounds < 1 or scores.round < 1 or scores.round > rounds then
        return nil
    end
    return {
        scores   = scores,
        rounds   = rounds,
        entries  = type(t.entries) == "table" and t.entries or {},
        results  = type(t.results) == "table" and t.results or nil,
        finished = t.finished == true,
    }
end

return Match

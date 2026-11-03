-- Spec for the multiplayer mode: scoring, rounds, save/restore, solver.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local Match = require("match")
local Board = require("board")

local LETTERS = { "M", "A", "I", "S", "O", "N", "S", "E", "T" }
local DICT = { maison = true, maisons = true, mais = true, saison = true, son = true }

describe("numletters multiplayer", function()
    describe("words", function()
        it("folds accents and case, rejects other characters", function()
            assert.are.equal("eleve", Match.normalizeWord(" Élève "))
            assert.are.equal("", Match.normalizeWord(""))
            assert.is_nil(Match.normalizeWord("l'eau"))
            assert.is_nil(Match.normalizeWord("abc1"))
        end)

        it("checks the drawn letters, then the dictionary", function()
            assert.are.equal("ok", (Match.checkWord("MAISONS", LETTERS, DICT)))
            assert.are.equal("letters", (Match.checkWord("saisons", LETTERS, DICT))) -- needs 3 S, 2 drawn
            assert.are.equal("unknown", (Match.checkWord("somian", LETTERS, DICT)))
            assert.are.equal("empty", (Match.checkWord("", LETTERS, DICT)))
            assert.are.equal("invalid", (Match.checkWord("mai-son", LETTERS, DICT)))
        end)
    end)

    describe("letters scoring", function()
        it("gives the longest valid word its length, ties all score", function()
            local r, best = Match.scoreLetters({ "maison", "maisons", "", "mais" }, 4, LETTERS, DICT)
            assert.are.equal(7, best)
            assert.are.same({ 0, 7, 0, 0 }, { r[1].points, r[2].points, r[3].points, r[4].points })
            r = Match.scoreLetters({ "saison", "maison" }, 2, LETTERS, DICT)
            assert.are.same({ 6, 6 }, { r[1].points, r[2].points })
        end)

        it("scores nobody when no word is valid", function()
            local r = Match.scoreLetters({ "zzz", nil }, 2, LETTERS, DICT)
            assert.are.same({ 0, 0 }, { r[1].points, r[2].points })
            assert.are.equal("empty", r[2].status)
        end)
    end)

    describe("numbers scoring", function()
        local function all() return true end
        it("follows the distance scale", function()
            assert.are.same({ 10, 7, 7, 5, 5, 0 }, {
                Match.numbersPoints(0), Match.numbersPoints(1), Match.numbersPoints(5),
                Match.numbersPoints(6), Match.numbersPoints(10), Match.numbersPoints(11) })
        end)

        it("only the closest score, ties all score", function()
            local r = Match.scoreNumbers({ "500", "497", "503", "" }, 4, 500, all)
            assert.are.same({ 10, 0, 0, 0 }, { r[1].points, r[2].points, r[3].points, r[4].points })
            r = Match.scoreNumbers({ "497", "503", "490" }, 3, 500, all)
            assert.are.same({ 7, 7, 0 }, { r[1].points, r[2].points, r[3].points })
        end)

        it("an impossible number scores nothing and doesn't block others", function()
            local r = Match.scoreNumbers({ "500", "480", "abc" }, 3, 500,
                function(v) return v ~= 500 end)
            assert.are.equal("impossible", r[1].status)
            assert.are.equal("invalid", r[3].status)
            assert.are.same({ 0, 0, 0 }, { r[1].points, r[2].points, r[3].points })
            r = Match.scoreNumbers({ "500", "495" }, 2, 500, function(v) return v ~= 500 end)
            assert.are.same({ 0, 7 }, { r[1].points, r[2].points })
        end)
    end)

    describe("solver", function()
        it("finds the classic 952 and writes valid steps", function()
            local s = Board.solveNumbers({ 100, 75, 50, 25, 6, 3 })
            assert.is_not_nil(s.reachable[952])
            local steps = Board.solutionSteps(s, 952)
            assert.is_true(#steps >= 1)
            assert.is_truthy(steps[#steps]:match("= 952$"))
        end)

        it("reports the closest value when the target is out of reach", function()
            local s = Board.solveNumbers({ 1, 1 })
            local v, d = Board.closestValue(s, 100)
            assert.are.equal(2, v)
            assert.are.equal(98, d)
            assert.is_nil(s.reachable[3])
        end)

        it("a drawn number on its own needs no step", function()
            local s = Board.solveNumbers({ 7, 50 })
            assert.are.same({}, Board.solutionSteps(s, 50))
        end)
    end)

    describe("match", function()
        it("alternates letters and numbers, and ends after the last round", function()
            local m = Match.new({ "A", "B" }, 2)
            assert.are.equal(1, Match.current(m))
            assert.are.equal("letters", Match.roundKind(1))
            assert.are.equal("numbers", Match.roundKind(2))
            assert.is_true(Match.applyResults(m, { { points = 5 }, { points = 0 } }))
            assert.is_false(Match.applyResults(m, { { points = 5 }, { points = 0 } }))
            assert.is_false(m.finished)
            assert.is_true(Match.advance(m))
            Match.applyResults(m, { { points = 0 }, { points = 10 } })
            assert.is_true(m.finished)
            assert.is_false(Match.advance(m))
            assert.are.same({ 5, 10 }, m.scores.points)
        end)

        it("survives save and restore, and refuses broken saves", function()
            local m = Match.new({ "A", "B" }, 4)
            m.entries = { "maison", "" }
            Match.applyResults(m, { { points = 6, status = "ok", word = "maison" }, { points = 0, status = "empty" } })
            local t = Match.restore(Match.serialize(m))
            assert.are.same(m.scores.points, t.scores.points)
            assert.are.equal(4, t.rounds)
            assert.are.equal("maison", t.entries[1])
            assert.are.equal(6, t.results[1].points)
            assert.is_nil(Match.restore({ scores = m.scores, rounds = 0 }))
            assert.is_nil(Match.restore("junk"))
        end)
    end)
end)

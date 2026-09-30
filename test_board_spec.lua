local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("NumLetters Board", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new", function()
        it("starts in the letters phase with an empty draw", function()
            local b = Board:new()
            assert.are.equal("letters", b.phase)
            assert.are.same({}, b.letters)
        end)
    end)

    describe("drawVowel / drawConsonant / canDrawLetter", function()
        it("draws up to 9 letters total, then refuses more", function()
            local b = Board:new()
            for i = 1, 9 do
                assert.is_true(b:canDrawLetter())
                local c = (i % 2 == 0) and b:drawConsonant() or b:drawVowel()
                assert.is_not_nil(c)
            end
            assert.is_false(b:canDrawLetter())
            assert.is_nil(b:drawVowel())
            assert.is_nil(b:drawConsonant())
            assert.are.equal(9, #b.letters)
        end)

        it("invalidates any cached solutions when a new letter is drawn", function()
            local b = Board:new()
            b:drawVowel()
            b.solutions = { "PLACEHOLDER" }
            b:drawConsonant()
            assert.is_nil(b.solutions)
        end)
    end)

    describe("findSolutions", function()
        it("only returns words fully formable from the drawn letters (multiset subset)", function()
            local b = Board:new({ lang = "en" })
            b.letters = { "C", "A", "T", "S" }
            local words = b:findSolutions()
            for _, word in ipairs(words) do
                local available = { C = 1, A = 1, T = 1, S = 1 }
                for i = 1, #word do
                    local ch = word:sub(i, i):upper()
                    available[ch] = (available[ch] or 0) - 1
                    assert.is_true(available[ch] >= 0, word .. " uses more " .. ch .. " than drawn")
                end
            end
        end)

        it("sorts results longest-first", function()
            local b = Board:new({ lang = "en" })
            b.letters = { "R", "E", "A", "D", "S", "T" }
            local words = b:findSolutions()
            for i = 2, #words do
                assert.is_true(#words[i-1] >= #words[i])
            end
        end)

        it("caches the result until letters change", function()
            local b = Board:new({ lang = "en" })
            b.letters = { "A", "T" }
            local first = b:findSolutions()
            assert.are.equal(first, b:findSolutions())
        end)
    end)

    describe("startNumbers", function()
        it("draws 6 numbers in [1,100] and a target in [100,999]", function()
            local b = Board:new()
            b:startNumbers()
            assert.are.equal("numbers", b.phase)
            assert.are.equal(6, #b.numbers)
            for _, n in ipairs(b.numbers) do
                assert.is_true(n >= 1 and n <= 100)
            end
            assert.is_true(b.target >= 100 and b.target <= 999)
        end)
    end)

    describe("startLetters", function()
        it("resets the letters draw", function()
            local b = Board:new()
            b:drawVowel()
            b:startLetters()
            assert.are.same({}, b.letters)
            assert.are.equal("letters", b.phase)
        end)
    end)
end)

describe("English dictionary", function()
    local DIR2 = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
    local W = assert(loadfile(DIR2 .. "words_en.lua"))()

    it("knows ordinary English words the old 1842-word stub did not", function()
        for _, word in ipairs({ "puzzle", "reader", "orange", "strength", "jazz",
                                "xylophone", "quiet", "knight", "rhythm",
                                "crossword", "elephant" }) do
            assert.is_true(W[word] == true, word .. " missing from the dictionary")
        end
    end)

    it("covers 3 to 9 letters -- numletters draws up to 9 tiles", function()
        local by_len = {}
        for word in pairs(W) do by_len[#word] = (by_len[#word] or 0) + 1 end
        for len = 3, 9 do
            assert.is_true((by_len[len] or 0) > 500,
                "only " .. (by_len[len] or 0) .. " words of length " .. len)
        end
        assert.is_nil(by_len[2])
        assert.is_nil(by_len[10])
    end)

    it("holds nothing but lowercase a-z", function()
        local checked = 0
        for word in pairs(W) do
            assert.is_nil(word:match("[^a-z]"), word .. " is not plain lowercase")
            checked = checked + 1
        end
        assert.is_true(checked > 100000)
    end)
end)


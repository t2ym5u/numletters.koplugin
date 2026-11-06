-- Family-friendly words: the game is also played at a family table, so the
-- best words it reveals after a letters round must never include
-- blocklist.lua's vulgar, sexual, scatological, slur or drug-related words.
-- A player's own word is still checked against the whole dictionary.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Blocklist = dofile(DIR .. "blocklist.lua")

describe("family-friendly solutions", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local DRAWS = {
        fr = { "MERDEACIO", "PUTAINSEX", "CACAPIPIE", "SALOPETRU" },
        en = { "SHITFUCKA", "WHORESEXY", "PORNCUNTE", "BITCHESAO" },
    }

    for lang, draws in pairs(DRAWS) do
        it("never lists a blocklisted " .. lang .. " word", function()
            local b = Board:new({ lang = lang })
            local blocked_in_dict = 0
            for _, d in ipairs(draws) do
                b.letters, b.solutions = {}, nil
                for c in d:gmatch(".") do b.letters[#b.letters + 1] = c end
                local sols = b:findSolutions()
                assert.is_true(#sols > 0)
                for _, w in ipairs(sols) do
                    assert.is_false(Blocklist.isBlocked(w, lang), w)
                end
            end
            for w in pairs(Blocklist.set(lang)) do
                if b.dict[w:lower()] then blocked_in_dict = blocked_in_dict + 1 end
            end
            -- The dictionary itself keeps them (players may still play them).
            assert.is_true(blocked_in_dict > 50)
        end)
    end
end)

-- "lynch" and its forms were missing from the shared blocklist: a game could
-- draw or reveal LYNCH (EN) or LYNCHAGE (FR). LYNCHPIN is another word.
describe("blocklist: lynch", function()
    it("blocks every English and French form, in any case", function()
        for _, w in ipairs({ "LYNCH", "lynched", "Lynches", "LYNCHING", "LYNCHER", "lynchers" }) do
            assert.is_true(Blocklist.isBlocked(w, "en"), w)
        end
        for _, w in ipairs({ "lyncher", "LYNCHAGE", "lynchee", "lyncheurs" }) do
            assert.is_true(Blocklist.isBlocked(w, "fr"), w)
        end
        assert.is_false(Blocklist.isBlocked("LYNCHPIN", "en"))
    end)
end)

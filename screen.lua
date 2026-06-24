local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable    = require("ui/widget/buttontable")
local Device         = require("device")
local Font           = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size           = require("ui/size")
local TextBoxWidget  = require("ui/widget/textboxwidget")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local VerticalGroup  = require("ui/widget/verticalgroup")
local VerticalSpan   = require("ui/widget/verticalspan")
local _              = require("gettext")

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local Board      = lrequire("board")

local DeviceScreen = Device.screen

local LETTERS_DURATION = 45
local NUMBERS_DURATION = 45

local RULES_EN = _([[
Chiffres et Lettres — Rules

LETTERS round:
Draw 9 letters by tapping Vowel or Consonant. When all 9 are drawn, the timer starts. Each player finds the longest possible word using each letter at most once. After time, tap Solutions to see all valid words.

NUMBERS round:
6 random numbers (1–100) are drawn and a 3-digit target is shown. Players combine numbers using +, −, ×, ÷ to reach (or get closest to) the target. Only tap Solutions after everyone has written their answer.
]])

local RULES_FR = [[
Chiffres et Lettres — Règles

Manche LETTRES :
Tirez 9 lettres en appuyant sur Voyelle ou Consonne. Quand les 9 sont tirées, le chrono démarre. Chaque joueur trouve le mot le plus long possible en utilisant chaque lettre au plus une fois. Après le temps, appuyez sur Solutions pour voir tous les mots valides.

Manche CHIFFRES :
6 nombres aléatoires (1–100) sont tirés et une cible à 3 chiffres est affichée. Les joueurs combinent les nombres avec +, −, ×, ÷ pour atteindre (ou approcher au plus près) la cible. Appuyez sur Solutions seulement après que tout le monde a écrit sa réponse.
]]

-- ---------------------------------------------------------------------------
-- CLScreen
-- ---------------------------------------------------------------------------

local CLScreen = ScreenBase:extend{}

function CLScreen:init()
    self.lang = self.plugin:getSetting("lang", "fr")
    self.board = Board:new{ lang = self.lang }
    -- phase within a round: "setup" | "playing" | "revealed"
    self.round_phase    = "setup"
    self.time_remaining = 0
    self.board:startLetters()
    ScreenBase.init(self)
end

-- ---------------------------------------------------------------------------
-- Timer
-- ---------------------------------------------------------------------------

function CLScreen:_startCountdown(duration)
    self.time_remaining = duration
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function CLScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function CLScreen:_onTick(gen)
    if gen ~= self._tick_gen then return end
    self.time_remaining = math.max(0, self.time_remaining - 1)
    if self.timer_widget then
        self.timer_widget:setText(self:_timerText())
        UIManager:setDirty(self, function() return "fast", self.dimen end)
    end
    if self.time_remaining <= 0 then
        -- Timer ended: switch to revealed state automatically
        self:_onTimerEnd()
    else
        UIManager:scheduleIn(1, function() self:_onTick(gen) end)
    end
end

function CLScreen:_timerText()
    local m = math.floor(self.time_remaining / 60)
    local s = self.time_remaining % 60
    return string.format("%d:%02d", m, s)
end

function CLScreen:_onTimerEnd()
    self:_stopCountdown()
    self.round_phase = "revealed"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function CLScreen:onDrawVowel()
    self.board:drawVowel()
    if not self.board:canDrawLetter() then self:_startLetterTimer() end
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:onDrawConsonant()
    self.board:drawConsonant()
    if not self.board:canDrawLetter() then self:_startLetterTimer() end
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:_startLetterTimer()
    self.round_phase = "playing"
    self:_startCountdown(LETTERS_DURATION)
end

function CLScreen:onRevealLetters()
    self:_stopCountdown()
    self.round_phase = "revealed"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:onNewLetters()
    self:_stopCountdown()
    self.board:startLetters()
    self.round_phase = "setup"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:onNewNumbers()
    self:_stopCountdown()
    self.board:startNumbers()
    self.round_phase = "playing"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    self:_startCountdown(NUMBERS_DURATION)
end

function CLScreen:onRevealNumbers()
    self:_stopCountdown()
    self.round_phase = "revealed"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = "Language / Langue",
        items      = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(lang)
            self.lang      = lang
            self.plugin:saveSetting("lang", lang)
            self.board.lang = lang
            self.board:_loadDict()
            self:onNewLetters()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Layout dispatcher
-- ---------------------------------------------------------------------------

function CLScreen:buildLayout()
    local phase = self.board.phase
    if phase == "letters" then
        self:_buildLettersLayout()
    else
        self:_buildNumbersLayout()
    end
    self[1] = self.layout
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Letters layout
-- ---------------------------------------------------------------------------

function CLScreen:_buildLettersLayout()
    local sw    = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_fr = self.lang == "fr"
    local btn_w = math.floor(sw * 0.92)

    -- Drawn letter tiles
    local tiles_widget = self:_buildLetterTiles(sw)

    -- Buttons depend on round_phase
    local btn_rows = {}
    if self.round_phase == "setup" then
        local drawn = #self.board.letters
        local v_text = is_fr and string.format("Voyelle (%d)", drawn) or string.format("Vowel (%d)", drawn)
        local c_text = is_fr and string.format("Consonne (%d)", drawn) or string.format("Consonant (%d)", drawn)
        btn_rows = {{
            { text = v_text, callback = function() self:onDrawVowel() end },
            { text = c_text, callback = function() self:onDrawConsonant() end },
        }, {
            { text = is_fr and "Manche chiffres" or "Numbers round",
              callback = function() self:onNewNumbers() end },
            { id = "lang_btn", text = self.lang == "fr" and "FR" or "EN",
              callback = function() self:openLangMenu() end },
            self:makeRulesButtonConfig(RULES_EN, RULES_FR),
            self:makeCloseButtonConfig(),
        }}
    elseif self.round_phase == "playing" then
        btn_rows = {{
            { text = is_fr and "Solutions" or "Solutions",
              callback = function() self:onRevealLetters() end },
            { text = is_fr and "Nouvelle manche" or "New round",
              callback = function() self:onNewLetters() end },
        }}
    else  -- revealed
        btn_rows = {{
            { text = is_fr and "Nouvelle manche lettres" or "New letters round",
              callback = function() self:onNewLetters() end },
            { text = is_fr and "Manche chiffres" or "Numbers round",
              callback = function() self:onNewNumbers() end },
        }}
    end

    local buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_w,
        buttons = btn_rows,
    }

    -- Timer (only when playing)
    local timer_group = VerticalGroup:new{ align = "center" }
    self.timer_widget = nil
    if self.round_phase == "playing" then
        local timer_fs = math.max(20, math.floor(math.min(sw, sh) * 0.10))
        self.timer_widget = TextWidget:new{
            text = self:_timerText(),
            face = Font:getFace("cfont", timer_fs),
        }
        timer_group[#timer_group + 1] = self.timer_widget
        timer_group[#timer_group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end

    -- Solutions (only when revealed)
    local solutions_group = VerticalGroup:new{ align = "center" }
    if self.round_phase == "revealed" and #self.board.letters == 9 then
        local sols = self.board:findSolutions()
        local sol_text
        if #sols == 0 then
            sol_text = is_fr and "Aucun mot trouvé." or "No words found."
        else
            -- Group by length
            local by_len = {}
            for _, w in ipairs(sols) do
                local l = #w
                by_len[l] = by_len[l] or {}
                by_len[l][#by_len[l] + 1] = w
            end
            local lines = {}
            local max_l = 0
            for l in pairs(by_len) do if l > max_l then max_l = l end end
            for l = max_l, 2, -1 do
                local words = by_len[l]
                if words then
                    local label = is_fr
                        and string.format("%d lettres (%d) : ", l, #words)
                        or  string.format("%d letters (%d): ",  l, #words)
                    lines[#lines + 1] = label .. table.concat(words, ", ")
                end
            end
            lines[#lines + 1] = ""
            lines[#lines + 1] = is_fr
                and string.format("Total : %d mot%s", #sols, #sols > 1 and "s" or "")
                or  string.format("Total: %d word%s",  #sols, #sols > 1 and "s" or "")
            sol_text = table.concat(lines, "\n")
        end

        local sol_w = TextBoxWidget:new{
            text  = sol_text,
            face  = Font:getFace("smallinfofont"),
            width = math.floor(sw * 0.88),
            height = math.floor(sh * 0.4),
        }
        solutions_group[#solutions_group + 1] = sol_w
    end

    -- Instruction when setup
    local instr_group = VerticalGroup:new{ align = "center" }
    if self.round_phase == "setup" then
        local drawn = #self.board.letters
        local instr = is_fr
            and (drawn == 0 and "Tirez 9 lettres (voyelles et consonnes)"
                 or string.format("Encore %d lettre%s", 9 - drawn, 9 - drawn > 1 and "s" or ""))
            or  (drawn == 0 and "Draw 9 letters (vowels and consonants)"
                 or string.format("%d more letter%s", 9 - drawn, 9 - drawn > 1 and "s" or ""))
        instr_group[#instr_group + 1] = TextWidget:new{
            text = instr,
            face = Font:getFace("smallinfofont"),
        }
    end

    local vs = VerticalSpan:new{ width = Size.span.vertical_large }

    self.layout = VerticalGroup:new{
        align = "center",
        vs,
        buttons,
        vs,
        instr_group,
        vs,
        tiles_widget,
        vs,
        timer_group,
        solutions_group,
    }
end

function CLScreen:_buildLetterTiles(sw)
    -- Display letters as large tiles in a row (or two rows for 9)
    local letters = self.board.letters
    if #letters == 0 then
        return VerticalSpan:new{ width = Size.span.vertical_large }
    end

    local cols = math.min(#letters, 9)
    local cell = math.floor(math.min(sw * 0.85, sw * 0.85) / cols)
    cell = math.max(cell, 30)
    local fs = math.max(14, math.floor(cell * 0.55))
    local face = Font:getFace("cfont", fs)

    local row = HorizontalGroup:new{ align = "center" }
    for _, l in ipairs(letters) do
        local tile = FrameContainer:new{
            padding = math.floor(cell * 0.08),
            margin  = math.floor(cell * 0.04),
            TextWidget:new{ text = l, face = face },
        }
        row[#row + 1] = tile
    end
    return row
end

-- ---------------------------------------------------------------------------
-- Numbers layout
-- ---------------------------------------------------------------------------

function CLScreen:_buildNumbersLayout()
    local sw    = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_fr = self.lang == "fr"
    local btn_w = math.floor(sw * 0.92)

    -- Buttons
    local btn_rows
    if self.round_phase == "playing" then
        btn_rows = {{
            { text = is_fr and "Solutions" or "Solutions",
              callback = function() self:onRevealNumbers() end },
            { text = is_fr and "Manche lettres" or "Letters round",
              callback = function() self:onNewLetters() end },
        }}
    else
        btn_rows = {{
            { text = is_fr and "Nouveaux chiffres" or "New numbers",
              callback = function() self:onNewNumbers() end },
            { text = is_fr and "Manche lettres" or "Letters round",
              callback = function() self:onNewLetters() end },
        }}
    end

    local buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_w,
        buttons = btn_rows,
    }

    -- Timer
    local timer_group = VerticalGroup:new{ align = "center" }
    self.timer_widget = nil
    if self.round_phase == "playing" then
        local timer_fs = math.max(20, math.floor(math.min(sw, sh) * 0.10))
        self.timer_widget = TextWidget:new{
            text = self:_timerText(),
            face = Font:getFace("cfont", timer_fs),
        }
        timer_group[#timer_group + 1] = self.timer_widget
        timer_group[#timer_group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end

    -- Numbers display
    local nums     = self.board.numbers
    local target   = self.board.target
    local short    = math.min(sw, sh)

    local num_fs = math.max(18, math.floor(short * 0.07))
    local nums_text = table.concat(nums, "   ")
    local nums_w = TextWidget:new{
        text = nums_text,
        face = Font:getFace("cfont", num_fs),
    }

    local target_fs = math.max(28, math.floor(short * 0.13))
    local target_label = is_fr and "Cible : " or "Target: "
    local target_w = TextWidget:new{
        text = target_label .. tostring(target),
        face = Font:getFace("cfont", target_fs),
    }

    local sep_w = TextWidget:new{
        text = string.rep("─", 24),
        face = Font:getFace("smallinfofont"),
    }

    -- Solutions hint (after reveal: just show the numbers + target again prominently)
    local sol_group = VerticalGroup:new{ align = "center" }
    if self.round_phase == "revealed" then
        local hint = is_fr
            and "Comparez vos calculs et désignez le gagnant."
            or  "Compare your calculations and name the winner."
        sol_group[#sol_group + 1] = VerticalSpan:new{ width = Size.span.vertical_large * 2 }
        sol_group[#sol_group + 1] = TextWidget:new{
            text = hint,
            face = Font:getFace("smallinfofont"),
        }
    end

    local vs = VerticalSpan:new{ width = Size.span.vertical_large }
    local vs2 = VerticalSpan:new{ width = Size.span.vertical_large * 3 }

    self.layout = VerticalGroup:new{
        align = "center",
        vs,
        buttons,
        vs,
        timer_group,
        vs2,
        nums_w,
        vs2,
        sep_w,
        vs2,
        target_w,
        sol_group,
    }
end

-- ---------------------------------------------------------------------------
-- Status / close
-- ---------------------------------------------------------------------------

function CLScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local is_fr  = self.lang == "fr"
    local phase  = self.board.phase
    local status
    if phase == "letters" then
        status = is_fr
            and string.format("LETTRES — %d/9 tirées", #self.board.letters)
            or  string.format("LETTERS — %d/9 drawn", #self.board.letters)
    else
        status = is_fr
            and string.format("CHIFFRES — Cible : %d", self.board.target)
            or  string.format("NUMBERS — Target: %d",  self.board.target)
    end
    ScreenBase.updateStatus(self, status)
end

function CLScreen:onClose()
    self:_stopCountdown()
    ScreenBase.onClose(self)
end

return CLScreen

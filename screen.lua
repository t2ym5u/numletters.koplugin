local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer       = require("ffi/blitbuffer")
local Device           = require("device")
local Font             = require("ui/font")
local Geom             = require("ui/geometry")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local RenderText       = require("ui/rendertext")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size             = require("ui/size")
local TextBoxWidget    = require("ui/widget/textboxwidget")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local Widget           = require("ui/widget/widget")
local _                = require("i18n")
local T                = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local Board      = lrequire("board")

local DeviceScreen = Device.screen

local LETTERS_DURATION = 45
local NUMBERS_DURATION = 45

local GAME_RULES_EN = _([[
Numbers and Letters — Rules

LETTERS round:
Draw 9 letters by tapping Vowel or Consonant. When all 9 are drawn, the timer starts. Each player finds the longest possible word using each letter at most once. After time, tap Solutions to see all valid words.

NUMBERS round:
6 random numbers (1–100) are drawn and a 3-digit target is shown. Players combine numbers using +, −, ×, ÷ to reach (or get closest to) the target. Only tap Solutions after everyone has written their answer.
]])

local GAME_RULES_FR = [[
Chiffres et Lettres — Règles

Manche LETTRES :
Tirez 9 lettres en appuyant sur Voyelle ou Consonne. Quand les 9 sont tirées, le chrono démarre. Chaque joueur trouve le mot le plus long possible en utilisant chaque lettre au plus une fois. Après le temps, appuyez sur Solutions pour voir tous les mots valides.

Manche CHIFFRES :
6 nombres aléatoires (1–100) sont tirés et une cible à 3 chiffres est affichée. Les joueurs combinent les nombres avec +, −, ×, ÷ pour atteindre (ou approcher au plus près) la cible. Appuyez sur Solutions seulement après que tout le monde a écrit sa réponse.
]]

-- ---------------------------------------------------------------------------
-- TileRow — a row of equal square tiles, one per letter or number. Empty
-- slots (letters not drawn yet) are drawn as light outlines.
-- ---------------------------------------------------------------------------

-- Font:getFace() scales its size by the screen DPI; this takes a pixel size.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000
local function pxFace(px)
    return Font:getFace("cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

local TileRow = Widget:extend{
    values   = nil,   -- list of strings
    slots    = 9,
    width    = 300,
    max_cell = 100,
}

function TileRow:init()
    local slots = math.max(1, self.slots)
    local gap   = math.max(2, math.floor(self.width / 100))
    local cell  = math.floor((self.width - (slots - 1) * gap) / slots)
    cell = math.max(16, math.min(cell, self.max_cell))
    self.cell, self.gap = cell, gap
    self.dimen = Geom:new{ x = 0, y = 0, w = slots * cell + (slots - 1) * gap, h = cell }

    -- One face for the whole row: the largest whose widest label fits a
    -- tile. Measured without a width cap, ink height = y_top + y_bottom.
    local px = math.floor(cell * 0.6)
    while true do
        local face = pxFace(px)
        local fits = true
        for _, v in ipairs(self.values or {}) do
            local m = RenderText:sizeUtf8Text(0, cell * 10, face, v, true, false)
            if m.x > cell * 0.85 or (m.y_top + m.y_bottom) > cell * 0.7 then
                fits = false
                break
            end
        end
        if fits or px <= 8 then self.face = face break end
        px = px - 2
    end
end

function TileRow:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local cell, gap = self.cell, self.gap
    local thick = Size.border.thick
    for i = 1, self.slots do
        local tx = x + (i - 1) * (cell + gap)
        local v  = self.values and self.values[i]
        if v then
            bb:paintBorder(tx, y, cell, cell, thick, Blitbuffer.COLOR_BLACK)
            local m  = RenderText:sizeUtf8Text(0, cell * 10, self.face, v, true, false)
            local lx = tx + math.floor((cell - m.x) / 2)
            local ly = y + math.floor(cell / 2 + (m.y_top - m.y_bottom) / 2)
            RenderText:renderUtf8Text(bb, lx, ly, self.face, v, true, false, Blitbuffer.COLOR_BLACK)
        else
            bb:paintBorder(tx, y, cell, cell, Size.border.default, Blitbuffer.COLOR_GRAY)
        end
    end
end

-- ---------------------------------------------------------------------------
-- CLScreen
-- ---------------------------------------------------------------------------

local CLScreen = ScreenBase:extend{}

function CLScreen:init()
    local sys_lang = require("i18n").lang()
    self.lang = self.plugin:getSetting("lang", (sys_lang == "fr") and "fr" or "en")
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
    -- Start before building, so the timer shows the full duration rather
    -- than whatever the previous round left in time_remaining.
    self:_startCountdown(NUMBERS_DURATION)
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:onRevealNumbers()
    self:_stopCountdown()
    self.round_phase = "revealed"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
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
-- Layout
-- ---------------------------------------------------------------------------

function CLScreen:buildLayout()
    local is_landscape = self:isLandscape()
    local is_letters   = self.board.phase == "letters"

    local title_bar = self:buildTitleBar(_("Numbers and Letters"), function()
        return {
            { text = _("New game"), callback = function() self:onNewLetters() end },
            { text = T(_("Language: %1"), self.lang:upper()),
              callback = function() self:openLangMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(is_letters and self:_lettersButtons() or self:_numbersButtons()),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local board = is_letters and self:_buildLettersBoard(budget_w, budget_h)
                              or self:_buildNumbersBoard(budget_w, budget_h)

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self[1] = self.layout
    self:updateStatus()
end

-- Large countdown shown while a round is being played, or nil.
function CLScreen:_buildTimer(budget_w, budget_h)
    self.timer_widget = nil
    if self.round_phase ~= "playing" then return nil end
    self.timer_widget = TextWidget:new{
        text      = self:_timerText(),
        face      = pxFace(math.min(budget_w, budget_h) * 0.10),
        max_width = budget_w,
    }
    return self.timer_widget
end

-- ---------------------------------------------------------------------------
-- Letters round
-- ---------------------------------------------------------------------------

function CLScreen:_lettersButtons()
    if self.round_phase == "setup" then
        return {{
            { text = _("Vowel"),
              callback = function() self:onDrawVowel() end },
            { text = _("Consonant"),
              callback = function() self:onDrawConsonant() end },
        }, {
            { text = _("Numbers round"),
              callback = function() self:onNewNumbers() end },
        }}
    elseif self.round_phase == "playing" then
        return {{
            { text = _("Solutions"),
              callback = function() self:onRevealLetters() end },
            { text = _("New round"),
              callback = function() self:onNewLetters() end },
        }}
    end
    return {{
        { text = _("New letters round"),
          callback = function() self:onNewLetters() end },
        { text = _("Numbers round"),
          callback = function() self:onNewNumbers() end },
    }}
end

function CLScreen:_solutionsText()
    local sols = self.board:findSolutions()
    if #sols == 0 then
        return _("No words found.")
    end
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
            local label = T(_("%1 letters (%2): "), l, #words)
            lines[#lines + 1] = label .. table.concat(words, ", ")
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = #sols == 1 and _("Total: 1 word") or T(_("Total: %1 words"), #sols)
    return table.concat(lines, "\n")
end

-- Nine letter slots, always all drawn so the round's shape is visible from
-- the first tap; above them the instruction (setup) or the timer (playing),
-- below them the solutions once revealed.
function CLScreen:_buildLettersBoard(budget_w, budget_h)
    local vs    = Size.span.vertical_large
    local tiles = TileRow:new{
        values   = self.board.letters,
        slots    = 9,
        width    = budget_w,
        max_cell = math.floor(budget_h * 0.3),
    }

    local head
    if self.round_phase == "setup" then
        local drawn = #self.board.letters
        local instr = drawn == 0 and _("Draw 9 letters (vowels and consonants)")
            or T(_("%1 more letter(s)"), 9 - drawn)
        head = TextBoxWidget:new{
            text      = instr,
            face      = Font:getFace("infofont"),
            width     = budget_w,
            alignment = "center",
        }
        self.timer_widget = nil
    else
        head = self:_buildTimer(budget_w, budget_h)
    end

    local group = VerticalGroup:new{ align = "center" }
    if head then
        group[#group + 1] = head
        group[#group + 1] = VerticalSpan:new{ width = 2 * vs }
    end
    group[#group + 1] = tiles

    if self.round_phase == "revealed" and #self.board.letters == 9 then
        local used = group:getSize().h + 2 * vs
        group[#group + 1] = VerticalSpan:new{ width = 2 * vs }
        group[#group + 1] = ScrollTextWidget:new{
            text   = self:_solutionsText(),
            face   = Font:getFace("smallinfofont"),
            width  = budget_w,
            height = math.max(Font:getFace("smallinfofont").size * 3, budget_h - used),
            dialog = self,
        }
        -- getSize() above cached the group's height; drop it so the layout
        -- sees the solutions box too.
        group:resetLayout()
    end
    return group
end

-- ---------------------------------------------------------------------------
-- Numbers round
-- ---------------------------------------------------------------------------

function CLScreen:_numbersButtons()
    if self.round_phase == "playing" then
        return {{
            { text = _("Solutions"),
              callback = function() self:onRevealNumbers() end },
            { text = _("Letters round"),
              callback = function() self:onNewLetters() end },
        }}
    end
    return {{
        { text = _("New numbers"),
          callback = function() self:onNewNumbers() end },
        { text = _("Letters round"),
          callback = function() self:onNewLetters() end },
    }}
end

function CLScreen:_buildNumbersBoard(budget_w, budget_h)
    local vs    = Size.span.vertical_large
    local nums  = {}
    for i, n in ipairs(self.board.numbers) do nums[i] = tostring(n) end

    local group = VerticalGroup:new{ align = "center" }
    local timer = self:_buildTimer(budget_w, budget_h)
    if timer then
        group[#group + 1] = timer
        group[#group + 1] = VerticalSpan:new{ width = 3 * vs }
    end
    group[#group + 1] = TileRow:new{
        values   = nums,
        slots    = #nums,
        width    = budget_w,
        max_cell = math.floor(budget_h * 0.25),
    }
    group[#group + 1] = VerticalSpan:new{ width = 3 * vs }
    group[#group + 1] = TextWidget:new{
        text      = T(_("Target: %1"), self.board.target),
        face      = pxFace(math.min(budget_w, budget_h) * 0.13),
        max_width = budget_w,
    }

    -- After reveal: the numbers and target stay up for the comparison.
    if self.round_phase == "revealed" then
        group[#group + 1] = VerticalSpan:new{ width = 2 * vs }
        group[#group + 1] = TextBoxWidget:new{
            text      = _("Compare your calculations and name the winner."),
            face      = Font:getFace("smallinfofont"),
            width     = budget_w,
            alignment = "center",
        }
    end
    return group
end

-- ---------------------------------------------------------------------------
-- Status / close
-- ---------------------------------------------------------------------------

function CLScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local status
    if self.board.phase == "letters" then
        status = self:joinStatus(_("Letters"), T(_("Drawn: %1/9"), #self.board.letters))
    else
        status = self:joinStatus(_("Numbers"), T(_("Target: %1"), self.board.target))
    end
    ScreenBase.updateStatus(self, status)
end

function CLScreen:onClose()
    self:_stopCountdown()
    ScreenBase.onClose(self)
end

return CLScreen

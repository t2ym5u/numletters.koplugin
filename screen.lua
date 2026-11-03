local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer       = require("ffi/blitbuffer")
local ButtonTable      = require("ui/widget/buttontable")
local Device           = require("device")
local Font             = require("ui/font")
local Geom             = require("ui/geometry")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local InputDialog      = require("ui/widget/inputdialog")
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
local Party      = require("party")
local ScreenBase = require("screen_base")
local Board      = lrequire("board")
local Match      = lrequire("match")

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

local PARTY_RULES_EN = [[
Numbers and Letters · multiplayer — Rules

Lay the reader in the middle of the table: it shows the letters, the numbers and the clock, checks the answers and keeps the scores. Everyone needs paper and a pen.

SETUP
In the menu: Players (2 to 8) and Player names, Rounds (4, 6, 8 or 10), Time (30, 45 or 60 s; the numbers round gets 15 s more) and Language (the dictionary used to check the words).

HOW A MATCH GOES
Rounds alternate: letters first, then numbers, and so on.

Letters round: anyone taps Vowel or Consonant until 9 letters are drawn; the clock starts by itself. Everyone writes the longest word they can make with the drawn letters, each letter used at most once.

Numbers round: 6 numbers and a 3-digit target appear with the clock. Everyone combines the numbers with +, −, ×, ÷ (each number at most once, only whole positive results along the way) to get as close as possible to the target, writing the calculation down.

When the time is up (or after Enter answers), tap each player's name and type their word or the number they reached; leave it empty if they have nothing. Then tap Check answers. In the numbers round, players read their calculation out loud so the others can check it.

SCORING
Letters: the word must be in the dictionary and use only the drawn letters. The longest valid word scores one point per letter (a 7-letter word: 7 points); everyone else scores 0.
Numbers: only the answer closest to the target scores: exact 10 points, 1 to 5 away 7 points, 6 to 10 away 5 points, further 0. A number that cannot be made from the drawn numbers scores 0.
Ties: every player with the best word length, or equally close, scores the full points.
After each round the screen shows everyone's result, the best possible words or a solution, and the scores.

END OF THE MATCH
After the last round the player with the most points wins; equal totals are a tie. New game starts a new match.
]]

local PARTY_RULES_FR = [[
Chiffres et Lettres · à plusieurs — Règles

Posez la liseuse au milieu de la table : elle affiche les lettres, les chiffres et le chrono, vérifie les réponses et tient les scores. Chacun a besoin d'un papier et d'un crayon.

PRÉPARATION
Dans le menu : Joueurs (2 à 8) et Noms des joueurs, Manches (4, 6, 8 ou 10), Durée (30, 45 ou 60 s ; la manche chiffres a 15 s de plus) et Langue (le dictionnaire qui vérifie les mots).

DÉROULEMENT
Les manches alternent : lettres d'abord, puis chiffres, et ainsi de suite.

Manche lettres : n'importe qui touche Voyelle ou Consonne jusqu'à 9 lettres ; le chrono démarre tout seul. Chacun écrit le mot le plus long possible avec les lettres tirées, chaque lettre au plus une fois.

Manche chiffres : 6 nombres et une cible à 3 chiffres s'affichent avec le chrono. Chacun combine les nombres avec +, −, ×, ÷ (chaque nombre au plus une fois, uniquement des résultats entiers positifs en cours de route) pour approcher au plus près la cible, en notant son calcul.

À la fin du temps (ou après Saisir les réponses), touchez le nom de chaque joueur et saisissez son mot ou le nombre obtenu ; laissez vide s'il n'a rien. Touchez ensuite Vérifier les réponses. En manche chiffres, chacun lit son calcul à voix haute pour que les autres le vérifient.

POINTS
Lettres : le mot doit être dans le dictionnaire et n'utiliser que les lettres tirées. Le mot valide le plus long marque un point par lettre (un mot de 7 lettres : 7 points) ; les autres marquent 0.
Chiffres : seule la réponse la plus proche de la cible marque : compte exact 10 points, à 1 à 5 près 7 points, à 6 à 10 près 5 points, au-delà 0. Un nombre impossible à obtenir avec les nombres tirés marque 0.
Égalités : tous les joueurs ayant le mot le plus long, ou aussi proches, marquent tous les points.
Après chaque manche, l'écran montre le résultat de chacun, les meilleurs mots possibles ou une solution, et les scores.

FIN DE PARTIE
Après la dernière manche, le joueur qui a le plus de points gagne ; à total égal, c'est une égalité. Nouvelle partie lance une nouvelle partie.
]]

local MODE_RULES = {
    solo  = { GAME_RULES_EN, GAME_RULES_FR },
    party = { PARTY_RULES_EN, PARTY_RULES_FR },
}

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
-- TimerBox — the countdown text, remembering where it was painted so a tick
-- refreshes only its own rectangle.
-- ---------------------------------------------------------------------------

local TimerBox = Widget:extend{ text_widget = nil }

function TimerBox:getSize()
    return self.text_widget:getSize()
end

function TimerBox:setText(text)
    self.text_widget:setText(text)
end

function TimerBox:paintTo(bb, x, y)
    local sz = self.text_widget:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = sz.w, h = sz.h }
    self.text_widget:paintTo(bb, x, y)
end

function TimerBox:free()
    self.text_widget:free()
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
    self.party = self.plugin.launch_mode == "party"
    if self.party then self:_initParty() end
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
        local box = self.timer_widget.dimen
        UIManager:setDirty(self, function() return "fast", box or self.dimen end)
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
    if self.party then
        self:_toEntry()
        return
    end
    self.round_phase = "revealed"
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function CLScreen:onDrawVowel()
    self.board:drawVowel()
    if not self.board:canDrawLetter() then self:_startLetterTimer()
    elseif self.party then self:_saveParty() end
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:onDrawConsonant()
    self.board:drawConsonant()
    if not self.board:canDrawLetter() then self:_startLetterTimer()
    elseif self.party then self:_saveParty() end
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:_startLetterTimer()
    self.round_phase = "playing"
    self:_startCountdown(self.party and self:_partyTime() or LETTERS_DURATION)
    if self.party then self:_saveParty() end
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
            if self.party then
                self:_startPartyRound()
            else
                self:onNewLetters()
            end
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
        if self.party then return self:_partyMenu() end
        return {
            { text = _("New game"), callback = function() self:onNewLetters() end },
            { text = T(_("Language: %1"), self.lang:upper()),
              callback = function() self:openLangMenu() end },
            self:_modeMenuItem(),
            self:makeModeRulesButtonConfig(MODE_RULES),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self.party and self:_partyButtons()
            or (is_letters and self:_lettersButtons() or self:_numbersButtons())),
    }

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local board
    if self.party and (self.round_phase == "entry" or self.round_phase == "revealed") then
        board = self:_buildPartyBoard(budget_w, budget_h)
    else
        board = is_letters and self:_buildLettersBoard(budget_w, budget_h)
                            or self:_buildNumbersBoard(budget_w, budget_h)
    end

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
    self.timer_widget = TimerBox:new{ text_widget = TextWidget:new{
        text      = self:_timerText(),
        face      = pxFace(math.min(budget_w, budget_h) * (self.party and 0.14 or 0.10)),
        max_width = budget_w,
    } }
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
    if self.party and self.match then
        ScreenBase.updateStatus(self, self:joinStatus(
            T(_("Round %1/%2"), Match.current(self.match), self.match.rounds),
            Party.statusText(self.match.scores)))
        return
    end
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

function CLScreen:closeScreen()
    self:_stopCountdown()
    if self.party then self:_saveParty() end
    ScreenBase.closeScreen(self)
end

-- ---------------------------------------------------------------------------
-- Mode (solo / multiplayer)
-- ---------------------------------------------------------------------------

function CLScreen:_modeMenuItem()
    return {
        text = T(_("Mode: %1"), self.party and _("Multiplayer") or _("Solo")),
        callback = function()
            MenuHelper.openPickerMenu{
                title      = _("Mode"),
                items      = { { id = "solo", text = _("Solo") },
                               { id = "party", text = _("Multiplayer") } },
                current_id = self.party and "party" or "solo",
                parent     = self,
                on_select  = function(mode) self:setMode(mode) end,
            }
        end,
    }
end

-- Switches mode and starts a new game in it.
function CLScreen:setMode(mode)
    self:_stopCountdown()
    if self.party then self:_saveParty() end
    self.plugin.launch_mode = mode
    self.party = mode == "party"
    if self.party then
        self:_newMatch()
    else
        self.match = nil
        self.board:startLetters()
        self.round_phase = "setup"
        self:buildLayout()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
end

-- ---------------------------------------------------------------------------
-- Multiplayer: match flow
-- ---------------------------------------------------------------------------

function CLScreen:_partyTime()
    local t = tonumber(self.plugin:getSetting("party_time", Match.DEFAULT_TIME)) or Match.DEFAULT_TIME
    return t
end

function CLScreen:_partyRounds()
    return tonumber(self.plugin:getSetting("party_rounds", Match.DEFAULT_ROUNDS)) or Match.DEFAULT_ROUNDS
end

-- Restores a saved match, or starts a new one. Runs before the first layout.
function CLScreen:_initParty()
    local saved = self.plugin:loadState("party_state")
    local m = saved and Match.restore(saved.match)
    if m and type(saved.board) == "table" then
        local b = saved.board
        self.match = m
        if b.lang and b.lang ~= self.board.lang then
            self.lang = b.lang
            self.board.lang = b.lang
            self.board:_loadDict()
        end
        self.board.phase   = b.phase == "numbers" and "numbers" or "letters"
        self.board.letters = type(b.letters) == "table" and b.letters or {}
        self.board.numbers = type(b.numbers) == "table" and b.numbers or {}
        self.board.target  = tonumber(b.target) or 0
        self.board.solutions = nil
        local rp = saved.round_phase
        if rp ~= "setup" and rp ~= "playing" and rp ~= "entry" and rp ~= "revealed" then
            rp = "setup"
        end
        if rp == "revealed" and not m.results then rp = "entry" end
        self.round_phase = rp
        if rp == "playing" then
            local left = tonumber(saved.time_remaining) or 0
            if left > 0 then
                self:_startCountdown(left)
            else
                self.round_phase = "entry"
            end
        end
        return
    end
    self:_newMatch(true)
end

-- A fresh match with the current players. no_layout: called from init.
function CLScreen:_newMatch(no_layout)
    local names = Party.loadPlayers(self.plugin, Party.loadCount(self.plugin))
    self.match = Match.new(names, self:_partyRounds())
    self:_startPartyRound(no_layout)
end

-- (Re)starts the current round: a letters draw, or numbers and the clock.
function CLScreen:_startPartyRound(no_layout)
    self:_stopCountdown()
    self._solver = nil
    self.match.entries = {}
    self.match.results = nil
    if Match.roundKind(Match.current(self.match)) == "letters" then
        self.board:startLetters()
        self.round_phase = "setup"
    else
        self.board:startNumbers()
        self.round_phase = "playing"
        self:_startCountdown(self:_partyTime() + Match.NUMBERS_EXTRA_TIME)
    end
    self:_saveParty()
    if not no_layout then
        self:buildLayout()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
end

function CLScreen:onNewGame()
    if self.party then self:_newMatch() else self:onNewLetters() end
end

function CLScreen:onNextRound()
    if not Match.advance(self.match) then return end
    self:_startPartyRound()
end

-- Time is up (or stopped early): type in everyone's answer.
function CLScreen:_toEntry()
    self:_stopCountdown()
    self.round_phase = "entry"
    self:_saveParty()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function CLScreen:_getSolver()
    if not self._solver then
        self._solver = Board.solveNumbers(self.board.numbers)
    end
    return self._solver
end

function CLScreen:onCheckAnswers()
    local m = self.match
    local n = #m.scores.names
    local results
    if self.board.phase == "letters" then
        results = Match.scoreLetters(m.entries, n, self.board.letters, self.board.dict or {})
    else
        local solver = self:_getSolver()
        results = Match.scoreNumbers(m.entries, n, self.board.target,
            function(v) return solver.reachable[v] ~= nil end)
    end
    Match.applyResults(m, results)
    self.round_phase = "revealed"
    self:_saveParty()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if m.finished then
        Party.showScoreboard(m.scores, { final = true })
    end
end

function CLScreen:isRoundOver()
    return self.party and self.match ~= nil and self.match.finished
        and self.round_phase == "revealed"
end

function CLScreen:_saveParty()
    if not self.match then return end
    local b = self.board
    self.plugin:saveState({
        match = Match.serialize(self.match),
        board = {
            lang = b.lang, phase = b.phase, letters = b.letters,
            numbers = b.numbers, target = b.target,
        },
        round_phase    = self.round_phase,
        time_remaining = self.time_remaining,
    }, "party_state")
end

-- Player i's answer, typed in after the round.
function CLScreen:editEntry(i)
    local m = self.match
    local numbers = self.board.phase == "numbers"
    local dialog
    dialog = InputDialog:new{
        title      = m.scores.names[i],
        input      = m.entries[i] or "",
        input_hint = numbers and _("Number reached") or _("Word"),
        input_type = numbers and "number" or nil,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dialog)
            end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local s = dialog:getInputText() or ""
                UIManager:close(dialog)
                self:setEntry(i, s)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CLScreen:setEntry(i, s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    self.match.entries[i] = s
    self:_saveParty()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Multiplayer: menu
-- ---------------------------------------------------------------------------

local function pickNumber(screen, title, values, current, fmt, on_pick)
    local items = {}
    for _i, v in ipairs(values) do items[#items + 1] = { id = v, text = fmt(v) } end
    MenuHelper.openPickerMenu{
        title = title, items = items, current_id = current,
        parent = screen, on_select = on_pick,
    }
end

local function secs(v) return T(_("%1 s"), v) end

function CLScreen:_partyMenu()
    return {
        { text = _("New game"), callback = function() self:_newMatch() end },
        { text = T(_("Players: %1"), #self.match.scores.names), callback = function()
            Party.pickCount(self.plugin, function() self:_newMatch() end, self)
        end },
        { text = _("Player names"), callback = function()
            Party.editPlayers(self.plugin, self.match.scores.names, function()
                self:_saveParty()
                self:updateStatus()
                self:buildLayout()
                UIManager:setDirty(self, function() return "ui", self.dimen end)
            end, self)
        end },
        { text = T(_("Rounds: %1"), self.match.rounds), callback = function()
            pickNumber(self, _("Rounds"), Match.ROUND_CHOICES, self.match.rounds, tostring,
                function(n)
                    self.plugin:saveSetting("party_rounds", n)
                    self:_newMatch()
                end)
        end },
        { text = T(_("Time: %1"), secs(self:_partyTime())), callback = function()
            pickNumber(self, _("Time"), Match.TIME_CHOICES, self:_partyTime(), secs,
                function(n) self.plugin:saveSetting("party_time", n) end)
        end },
        { text = T(_("Language: %1"), self.lang:upper()),
          callback = function() self:openLangMenu() end },
        self:_modeMenuItem(),
        self:makeModeRulesButtonConfig(MODE_RULES),
    }
end

-- ---------------------------------------------------------------------------
-- Multiplayer: action bar and board
-- ---------------------------------------------------------------------------

function CLScreen:_partyButtons()
    local rp = self.round_phase
    if rp == "setup" then
        return { {
            { text = _("Vowel"),     callback = function() self:onDrawVowel() end },
            { text = _("Consonant"), callback = function() self:onDrawConsonant() end },
        } }
    elseif rp == "playing" then
        return { { { text = _("Enter answers"), callback = function() self:_toEntry() end } } }
    elseif rp == "entry" then
        return { { { text = _("Check answers"), callback = function() self:onCheckAnswers() end } } }
    end
    return { { { text = _("Next round"), callback = function() self:onNextRound() end } } }
end

-- The round's content, smaller than during play: tiles, or numbers + target.
function CLScreen:_buildPartyContent(budget_w, budget_h)
    local group = VerticalGroup:new{ align = "center" }
    if self.board.phase == "letters" then
        group[1] = TileRow:new{
            values = self.board.letters, slots = 9, width = budget_w,
            max_cell = math.floor(budget_h * 0.12),
        }
    else
        local nums = {}
        for i, n in ipairs(self.board.numbers) do nums[i] = tostring(n) end
        group[1] = TileRow:new{
            values = nums, slots = #nums, width = budget_w,
            max_cell = math.floor(budget_h * 0.10),
        }
        group[2] = VerticalSpan:new{ width = Size.span.vertical_default }
        group[3] = TextWidget:new{
            text      = T(_("Target: %1"), self.board.target),
            face      = pxFace(math.min(budget_w, budget_h) * 0.07),
            max_width = budget_w,
        }
    end
    return group
end

local function upper(s) return (s or ""):upper() end

-- One line per player for the revealed round.
function CLScreen:_resultLines()
    local m, lines = self.match, {}
    local letters = self.board.phase == "letters"
    for i, name in ipairs(m.scores.names) do
        local r = m.results[i] or { status = "empty", points = 0 }
        local line
        if r.status == "empty" then
            line = T(_("%1 — no answer"), name)
        elseif letters then
            local reason
            if r.status == "ok" then reason = "+" .. r.points
            elseif r.status == "unknown" then reason = _("not in the dictionary")
            elseif r.status == "letters" then reason = _("letters not drawn")
            else reason = _("not a word") end
            line = T(_("%1 — %2 — %3"), name, upper(r.word or m.entries[i]), reason)
        else
            local what
            if r.status == "ok" then
                what = r.dist == 0 and T(_("%1 (exact)"), r.value)
                    or T(_("%1 (%2 away)"), r.value, r.dist)
                line = T(_("%1 — %2 — %3"), name, what, "+" .. r.points)
            else
                line = T(_("%1 — %2 — %3"), name, m.entries[i] or "",
                    r.status == "impossible" and _("impossible with these numbers")
                    or _("not a number"))
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- What the best players could have done.
function CLScreen:_bestText()
    if self.board.phase == "letters" then
        local sols = self.board:findSolutions()
        if #sols == 0 then return _("No words found.") end
        local best, words = #sols[1], {}
        for _i, w in ipairs(sols) do
            if #w ~= best or #words >= 8 then break end
            words[#words + 1] = w:upper()
        end
        return T(_("Best words (%1 letters): %2"), best, table.concat(words, ", "))
    end
    local solver = self:_getSolver()
    local v = Board.closestValue(solver, self.board.target)
    if not v then return "" end
    local steps = Board.solutionSteps(solver, v)
    local how = #steps > 0 and table.concat(steps, " · ") or tostring(v)
    return T(_("Solution (%1): %2"), v, how)
end

function CLScreen:_entryButtons(width)
    local m, rows, row = self.match, {}, {}
    local numbers = self.board.phase == "numbers"
    for i, name in ipairs(m.scores.names) do
        local e = m.entries[i]
        local shown = (e and e ~= "") and (numbers and e or e:upper()) or "…"
        row[#row + 1] = {
            text = T(_("%1: %2"), name, shown),
            font_size = math.floor(24 * math.max(1, width / 730)),
            callback = function() self:editEntry(i) end,
        }
        if #row == 2 then rows[#rows + 1] = row; row = {} end
    end
    if #row > 0 then rows[#rows + 1] = row end
    return ButtonTable:new{ width = width, buttons = rows }
end

function CLScreen:_buildPartyBoard(budget_w, budget_h)
    self.timer_widget = nil
    local vs = Size.span.vertical_large
    local group = VerticalGroup:new{ align = "center" }
    group[#group + 1] = self:_buildPartyContent(budget_w, budget_h)
    group[#group + 1] = VerticalSpan:new{ width = 2 * vs }
    -- Results text sized from the screen, readable from across the table.
    local face = Font:getFace("infofont", math.max(20, math.floor(
        math.min(budget_w / 18, budget_h / 22) / DPI_SCALE)))
    if self.round_phase == "entry" then
        group[#group + 1] = TextBoxWidget:new{
            text = _("Tap each player to type their answer (leave empty if none)."),
            face = Font:getFace("smallinfofont"), width = budget_w, alignment = "center",
        }
        group[#group + 1] = VerticalSpan:new{ width = vs }
        group[#group + 1] = self:_entryButtons(budget_w)
        return group
    end
    -- The round, what could have been done, then the standings (the status
    -- line only has room for a few players).
    local scores = self.match.scores
    local standings = _("Scores") .. "\n" .. table.concat(Party.scoreLines(scores), "\n")
    local round = table.concat(self:_resultLines(), "\n") .. "\n\n" .. self:_bestText()
    local text
    if self.match.finished then
        -- Match over: the winner and the final standings come first.
        local leaders = Party.leaders(scores)
        local head = #leaders == 1 and T(_("%1 wins!"), scores.names[leaders[1]])
            or _("It's a tie!")
        text = head .. "\n" .. table.concat(Party.scoreLines(scores), "\n") .. "\n\n" .. round
    else
        text = round .. "\n\n" .. standings
    end
    local used = group:getSize().h
    group[#group + 1] = ScrollTextWidget:new{
        text   = text,
        face   = face,
        width  = budget_w,
        height = math.max(face.size * 3, budget_h - used),
        dialog = self,
    }
    group:resetLayout()
    return group
end

return CLScreen

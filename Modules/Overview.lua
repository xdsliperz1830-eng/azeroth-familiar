-- Azeroth Familiar - Modules/Overview.lua
-- The landing page: a few cards of at-a-glance information and shortcuts.
-- Cards can be switched off on the Interface page. Refreshes once a second while open.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local O = {}
AA.Overview = O
local I = "Interface\\Icons\\"

local function pct(c, m) return string.format("%d%%", c / m * 100 + 0.5) end

-- id, title, icon, value() -> text
O.CARDS = {
  { id = "character", title = "Character", icon = function() return St.RaceIcon("player") end, value = function()
      local u = St.Unit("player")
      return string.format("%s  -  level %s %s %s", u.name or "?", tostring(u.level or "?"), u.race or "", u.class or "")
    end },
  { id = "location", title = "Location", icon = I .. "INV_Misc_Map_01", value = function()
      local zone, sub = St.Zone()
      local xy = St.CoordText()
      return (sub and (sub .. ", ") or "") .. (zone or "Unknown") .. (xy and ("  (" .. xy .. ")") or "")
    end },
  { id = "vitals", title = "Health and mana", icon = I .. "INV_Potion_54", value = function()
      local name, color = St.PowerLook("player")
      local health = St.HEALTH_COLOR .. "Health %s|r"
      local text, shown = St.VitalsText("player", health .. "    " .. color .. name .. " %s|r", health, true)
      if shown then return text end
      return W.GREY .. St.VitalsHidden() .. "|r"
    end },
  { id = "gold", title = "Gold", icon = I .. "INV_Misc_Coin_02", value = function()
      local s = St.SessionSummary()
      local net = s.net
      return St.MoneyText(St.Money()) .. (net ~= 0 and ("   " .. W.GREY .. "session|r " .. (net > 0 and "+" or "") .. St.MoneyText(net)) or "")
    end },
  { id = "durability", title = "Durability", icon = I .. "Trade_BlackSmithing", value = function()
      local p, list = St.Durability()
      if not p then return W.GREY .. "nothing to repair|r" end
      local color = p < 25 and AA.C.bad or p < 50 and AA.C.warn or AA.C.good
      local worst = list[1]
      return color .. string.format("%d%%|r", p) .. (worst and worst.pct < 100 and string.format("   lowest %d%%", worst.pct) or "")
    end },
  { id = "bags", title = "Bag space", icon = I .. "INV_Misc_Bag_08", value = function()
      local free, total = St.Bags()
      if not free then return "n/a" end
      local color = free <= 3 and AA.C.warn or ""
      return color .. free .. " free|r of " .. total
    end },
  { id = "performance", title = "Performance", icon = I .. "INV_Misc_PocketWatch_01", value = function()
      local fps = St.SampleFPS()
      local home, world = St.Latency()
      return (fps and string.format("%d fps", fps + 0.5) or "n/a") ..
        (world and string.format("   %d ms world", world) or "") .. (home and string.format("   %d ms home", home) or "")
    end },
  { id = "status", title = "Azeroth Familiar " .. AA.VERSION, icon = "Interface\\AddOns\\AzerothAssistant\\Media\\Logo", value = function()
      local comp = AA.Companion and AA.Companion.Detected() and (AA.C.good .. "Companion on|r") or (W.GREY .. "Companion off|r")
      local q = AA.Questie and AA.Questie.DB and AA.Questie.DB() and (AA.C.good .. "Questie data|r") or (W.GREY .. "no Questie|r")
      return comp .. "   " .. q
    end },
}

local cards = {}
local page, short = nil, {}

-- Card grid: fills the page. Two columns, or three once each card can be at least
-- CARD_MIN wide. The rows share the visible height (cards from CARD_H up to CARD_MAX_H
-- tall), with bigger icons and text on tall cards, and the value wraps onto more lines
-- (two lines at most) instead of being cut off. Shortcuts sit right under the cards.
local CARD_MIN, CARD_H, CARD_MAX_H, CARD_GAP, ROW_GAP = 230, 46, 84, 8, 6
local SHORTCUTS_H = 24 + 28 + 19 + 16      -- header, buttons, note and bottom margin
local lastW, lastH

-- Icon, fonts and text lines for a card of height ch.
local function styleCard(f, ch)
  local big = ch >= 80
  local s = math.max(30, math.min(44, ch - 20))
  f.icon:SetSize(s, s)
  f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", 8 + (big and 4 or 0), 0)
  local x = 8 + (big and 4 or 0) + s + 10
  f.title:SetFontObject(big and GameFontNormal or GameFontNormalSmall)
  f.value:SetFontObject(GameFontHighlight)                -- value text stays normal size
  local titleH, lineH = big and 14 or 11, 14
  local lines = math.max(1, math.min(2, math.floor((ch - titleH - 16) / lineH)))
  local top = math.max(5, math.floor((ch - (titleH + 4 + lines * lineH)) / 2))
  f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT", x, -top)
  f.value:ClearAllPoints(); f.value:SetPoint("TOPLEFT", x, -(top + titleH + 4))
  f.value:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  f.value:SetJustifyV("TOP")
  if f.value.SetWordWrap then f.value:SetWordWrap(lines > 1) end
  if f.value.SetMaxLines then f.value:SetMaxLines(lines) end
end
local SHORTCUTS = {
  { "Graphics", 84, function() AA.Shell.Show("graphics") end, "Graphics", "Presets and individual graphics settings." },
  { "Bags", 64, function() AA.Shell.Show("inventory") end, "Bags", "Bag space, grey items and bag search." },
  { "Save this spot", 110, function()
      local ok, msg = AA.World.SaveHere()
      AA.Shell.Flash(msg, ok)
    end, "Save this spot", "Adds where you're standing to your saved locations (World page)." },
  { "Ask the assistant", 130, function() AA.Shell.Show("assistant") end, "Assistant", "Ask about items, quests and your bags." },
}

local function layout(width, height)
  if not page then return end
  width = tonumber(width) or lastW or tonumber(page:GetWidth()) or 480
  height = tonumber(height) or lastH
  lastW, lastH = width, height
  local avail = math.max(CARD_MIN, width - 20)
  local cols = (avail >= 3 * CARD_MIN + 2 * CARD_GAP) and 3 or 2
  local cw = math.floor((avail - (cols - 1) * CARD_GAP) / cols)
  local top = O.top or -32
  local count = 0
  for _, c in ipairs(cards) do if c.frame:IsShown() then count = count + 1 end end
  local rows = math.max(1, math.ceil(count / cols))
  -- share the visible height between the rows of cards
  local ch = CARD_H
  if height then
    local room = height + top - SHORTCUTS_H - 4 - (rows - 1) * ROW_GAP
    ch = math.max(CARD_H, math.min(CARD_MAX_H, math.floor(room / rows)))
  end
  local pitch = ch + ROW_GAP
  local shown = 0
  for _, c in ipairs(cards) do
    if c.frame:IsShown() then
      c.frame:ClearAllPoints()
      c.frame:SetSize(cw, ch)
      c.frame:SetPoint("TOPLEFT", 10 + (shown % cols) * (cw + CARD_GAP), top - math.floor(shown / cols) * pitch)
      if c.styled ~= ch then styleCard(c.frame, ch); c.styled = ch end
      shown = shown + 1
    end
  end
  local y = top - rows * pitch - 4
  -- "Shortcuts" header, same look as L:Header
  short.head:ClearAllPoints(); short.head:SetPoint("TOPLEFT", 10, y - 2)
  short.line:ClearAllPoints(); short.line:SetPoint("TOPLEFT", 10, y - 19)
  short.line:SetPoint("RIGHT", page, "RIGHT", -10, 0)
  y = y - 24
  -- buttons share the extra room evenly, each up to 1.8x its normal width
  local base, n = 0, #SHORTCUTS
  for _, d in ipairs(SHORTCUTS) do base = base + d[2] end
  local free = math.max(0, avail - base - 6 * (n - 1))
  local x = 10
  for i, d in ipairs(SHORTCUTS) do
    local b = short.buttons[i]
    local w = math.floor(math.min(d[2] * 1.8, d[2] + free / n))
    b:SetWidth(w)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, y)
    x = x + w + 6
  end
  y = y - 28
  short.note:ClearAllPoints(); short.note:SetPoint("TOPLEFT", 12, y)
  short.note:SetPoint("RIGHT", page, "RIGHT", -12, 0)
  page:SetHeight(-(y - 19) + 12)
end

local function build(L, p)
  page = p
  L:Header("Overview")
  O.top = L:Row(0)
  for _, def in ipairs(O.CARDS) do
    local icon = def.icon
    if type(icon) == "function" then
      local ok, path = pcall(icon)
      icon = ok and path or nil
    end
    local c = W.Card(p, icon, def.title, 236, CARD_H)
    cards[#cards + 1] = { def = def, frame = c }
  end
  short.head = W.Text(p, "Shortcuts", "GameFontNormal")
  short.line = p:CreateTexture(nil, "ARTWORK")
  short.line:SetColorTexture(0.45, 0.36, 0.18, 0.7)
  short.line:SetHeight(1)
  short.buttons = {}
  for i, d in ipairs(SHORTCUTS) do
    short.buttons[i] = W.Button(p, d[1], d[2], d[3], d[4], d[5])
  end
  short.note = W.Text(p, "Choose which cards show here on the Interface page.", "GameFontHighlightSmall")
  short.note:SetJustifyV("TOP")
end

local function refresh()
  for _, c in ipairs(cards) do
    if AA.db.settings.dash[c.def.id] == false then
      c.frame:Hide()
    else
      -- text may be a secret string (health/mana): hand it over, never test or compare it
      local ok, text = pcall(c.def.value)
      if ok then c.frame.value:SetText(text) else c.frame.value:SetText("n/a") end
      if type(c.def.icon) == "function" and c.frame.icon then
        local okI, path = pcall(c.def.icon)
        if okI and path and path ~= c.iconPath then
          c.iconPath = path
          c.frame.icon:SetTexture(path)
        end
      end
      c.frame:Show()
    end
  end
  layout()
end

AA.Shell.Register({
  id = "overview", title = "Overview", order = 10, icon = I .. "INV_Misc_Book_09",
  subtitle = "Your character at a glance.",
  build = build, refresh = refresh, interval = 1,
  resize = function(_, width, height) layout(width, height) end,
})

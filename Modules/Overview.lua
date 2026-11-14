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
      local text, shown = St.VitalsText("player", "HP %s / %s   MP %s / %s", "HP %s / %s")
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

local function build(L, p)
  L:Header("Overview")
  O.top = L:Row(0)
  for _, def in ipairs(O.CARDS) do
    local icon = def.icon
    if type(icon) == "function" then
      local ok, path = pcall(icon)
      icon = ok and path or nil
    end
    local c = W.Card(p, icon, def.title, 236, 46)
    cards[#cards + 1] = { def = def, frame = c }
  end
  -- room for four rows of cards
  L:Row(4 * 52 + 4)
  L:Header("Shortcuts")
  L:Buttons({
    { "Graphics", 84, function() AA.Shell.Show("graphics") end, "Graphics", "Presets and individual graphics settings." },
    { "Bags", 64, function() AA.Shell.Show("inventory") end, "Bags", "Bag space, grey items and bag search." },
    { "Save this spot", 110, function()
        local ok, msg = AA.World.SaveHere()
        AA.Shell.Flash(msg, ok)
      end, "Save this spot", "Adds where you're standing to your saved locations (World page)." },
    { "Ask the assistant", 130, function() AA.Shell.Show("assistant") end, "Assistant", "Ask about items, quests and your bags." },
  })
  L:Note("Choose which cards show here on the Interface page.", 1)
end

local function refresh()
  local shown = 0
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
      c.frame:ClearAllPoints()
      c.frame:SetPoint("TOPLEFT", 10 + (shown % 2) * 244, (O.top or -32) - math.floor(shown / 2) * 52)
      c.frame:Show()
      shown = shown + 1
    end
  end
end

AA.Shell.Register({
  id = "overview", title = "Overview", order = 10, icon = I .. "INV_Misc_Book_09",
  subtitle = "Your character at a glance.",
  build = build, refresh = refresh, interval = 1,
})

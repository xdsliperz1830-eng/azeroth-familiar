-- Azeroth Familiar - Modules/Character.lua
-- Character page: level and experience, session numbers, durability and your target.
-- Read-only. Refreshes once a second while open.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local I = "Interface\\Icons\\"
local v = {}

local KIND = { elite = "Elite", rare = "Rare", rareelite = "Rare elite", worldboss = "Boss" }

local function build(L, p)
  L:Header("Character")
  v.who = L:KV("Character")
  v.vitals = L:KV("Health / power")
  v.xp = L:KV("Experience")
  v.rested = L:KV("Rested bonus")
  v.where = L:KV("Location")
  v.gold = L:KV("Gold")

  L:Header("This session")
  v.len = L:KV("Length")
  v.sxp = L:KV("Experience gained")
  v.rate = L:KV("Per hour")
  v.eta = L:KV("Next level in about")
  v.sgold = L:KV("Gold")
  L:Buttons({
    { "Start a new session", 150, function() St.ResetSession(); AA.Shell.Flash("Session numbers reset.", true); AA.Shell.Refresh() end,
      "Start a new session", "Sets the session clock, experience and gold counters back to zero. A session also restarts by itself after 15 minutes away." },
  })

  L:Header("Durability")
  v.dur = L:KV("Overall")
  v.worn = L:Note("", 6)

  L:Header("Target")
  v.target = L:KV("Target")
  v.thealth = L:KV("Health")
  L:Note("Reminders for low durability, full bags, vendors and level-ups are on the Interface page.", 1)
end

local function refresh()
  local u = St.Unit("player")
  v.who:SetText(string.format("%s, level %s %s %s", u.name or "?", tostring(u.level or "?"), u.race or "", u.class or ""))
  local vitals, shown = St.VitalsText("player", "%s / %s     %s / %s", "%s / %s")
  if shown then v.vitals:SetText(vitals) else v.vitals:SetText(W.GREY .. St.VitalsHidden() .. "|r") end
  local cur, max, rested = St.XP()
  if cur then
    v.xp:SetText(string.format("%d / %d  (%d%%), %d to go", cur, max, cur / max * 100, max - cur))
    v.rested:SetText(rested and string.format("%d XP (%d%% of a level)", rested, rested / max * 100) or "none")
  else
    v.xp:SetText(W.GREY .. "none to gain (max level, or hidden)|r")
    v.rested:SetText("-")
  end
  local zone, sub = St.Zone()
  local xy = St.CoordText()
  v.where:SetText((sub and (sub .. ", ") or "") .. (zone or "Unknown") .. (xy and ("  (" .. xy .. ")") or ""))
  v.gold:SetText(St.MoneyText(St.Money()))

  local s = St.SessionSummary()
  v.len:SetText(St.Duration(s.length))
  v.sxp:SetText(s.xp .. " XP" .. (s.levels > 0 and (", " .. s.levels .. " level" .. (s.levels == 1 and "" or "s")) or ""))
  v.rate:SetText(s.xpPerHour and string.format("%d XP", s.xpPerHour) or "-")
  v.eta:SetText(s.toLevel and St.Duration(s.toLevel) or "-")
  v.sgold:SetText("earned " .. St.MoneyText(s.goldIn) .. "   spent " .. St.MoneyText(s.goldOut) ..
    "   net " .. (s.net > 0 and "+" or "") .. St.MoneyText(s.net))

  local pct, list = St.Durability()
  v.dur:SetText(pct and string.format("%d%%", pct) or W.GREY .. "nothing with durability equipped|r")
  local lines = {}
  for i = 1, math.min(6, #list) do
    if list[i].pct < 100 then
      lines[#lines + 1] = string.format("%d%%  %s", list[i].pct, list[i].link or ("slot " .. list[i].slot))
    end
  end
  v.worn:SetText(#lines > 0 and table.concat(lines, "\n") or (pct and "Everything is fully repaired." or ""))

  local t = St.Target()
  if t then
    local kind = t.kind and KIND[t.kind]
    local lvl = t.level and (t.level < 0 and "??" or t.level) or "?"
    v.target:SetText((t.name or "?") .. ", level " .. tostring(lvl) ..
      (kind and (" " .. kind) or "") .. (t.isPlayer and (" " .. (t.race or "") .. " " .. (t.class or "")) or (t.creature and (" " .. t.creature) or "")))
    v.thealth:SetText(t.healthPct and string.format("%d%%", t.healthPct) or W.GREY .. "hidden in combat|r")
  else
    v.target:SetText(W.GREY .. "no target|r")
    v.thealth:SetText("-")
  end
end

AA.Shell.Register({
  id = "character", title = "Character", order = 40, icon = function() return AA.Stats.RaceIcon("player") end,
  subtitle = "Experience, session numbers, durability and your target.",
  build = build, refresh = refresh, interval = 1,
})

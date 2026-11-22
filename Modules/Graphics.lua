-- Azeroth Familiar - Modules/Graphics.lua
-- Graphics page: presets, the three original tweaks, and the game's own quality sliders.
-- All changes go through Tweaks.lua (read-back, originals remembered, no changes in combat).

local ADDON, AA = ...
local W, T = AA.W, AA.Tweaks
local I = "Interface\\Icons\\"

local rows, presetLine, originalLine = {}, nil, nil

local function refreshList(list)
  for _, r in ipairs(list) do
    local ok = T.Available(r.s)
    if r.icon.SetDesaturated then r.icon:SetDesaturated(not ok) end
    r.icon:SetAlpha(ok and 1 or 0.5)
    if r.check then
      if ok then r.check:Enable() else r.check:Disable() end
    end
    if r.status then r.status:SetText(ok and T.Status(r.s) or (W.GREY .. "not in this client|r")) end
  end
end

local function refreshRows()
  refreshList(rows)
  local m = T.MatchingPreset()
  presetLine:SetText("Current: " .. (m and (W.GOLD .. m.label .. "|r") or "Custom"))
  local n = T.OriginalCount()
  originalLine:SetText(n > 0 and (n .. " game setting" .. (n == 1 and "" or "s") .. " changed by Azeroth Familiar; your earlier values are remembered.")
    or "Azeroth Familiar hasn't changed any game setting yet.")
end

local function done(ok, msg)
  AA.Shell.Flash(msg, ok)
  AA.Shell.Refresh()
end

-- Shared by the Graphics and Gameplay pages: one row per setting (icon, control, tooltip
-- with the matching /console command). Returns the rows for refreshing.
function AA.SettingRows(L, p, list, out, showStatus)
  for _, s in ipairs(list) do
    if s.kind == "toggle" then
      local y = L:Row(showStatus and 40 or 30)
      local icon = W.Icon(p, s.icon, showStatus and 30 or 24)
      icon:SetPoint("TOPLEFT", 12, y + 1)
      local cb = W.Check(p, s.label,
        function() return T.Available(s) and T.IsOn(s) end,
        function(v) done(T.Set(s, v)) end,
        s.label, s.tip, function() return T.Commands(s) end)
      cb:SetPoint("TOPLEFT", showStatus and 48 or 42, y)
      L:Track(cb)
      local status
      if showStatus then
        status = W.Text(p, "", "GameFontDisableSmall")
        status:SetPoint("TOPLEFT", 76, y - 22)
        status:SetPoint("RIGHT", p, "RIGHT", -10, 0)
      end
      out[#out + 1] = { s = s, icon = icon, check = cb, status = status }
    else
      local y = L:Row(32)
      local icon = W.Icon(p, s.icon, 24)
      icon:SetPoint("TOPLEFT", 12, y)
      local label = W.Text(p, s.label)
      label:SetPoint("TOPLEFT", 44, y - 5)
      W.Hover(p, 10, y, 236, 26, s.label, s.tip, function() return T.Commands(s) end)
      local st = W.Stepper(p, {
        get = function() return T.Value(s) end,
        set = function(v) done(T.SetValue(s, v)) end,
        min = s.min, max = function() return T.Max(s) end, step = s.step or 1,
        fmt = function(v) return T.Format(s, v) end,
      })
      L:Column(st, y, 250)              -- right-hand column, follows the page width
      L:Track(st)
      out[#out + 1] = { s = s, icon = icon }
    end
  end
  return out
end
AA.RefreshSettingRows = refreshList

local function build(L, p)
  L:Header("Graphics presets")
  local list = {}
  for _, pr in ipairs(T.PRESETS) do
    local id = pr.id
    list[#list + 1] = { pr.label, 84, function() done(T.ApplyPreset(id)) end, pr.label, pr.tip }
  end
  L:Buttons(list)
  presetLine = L:Note("", 1)
  L:Note("A preset only changes the settings on this page. You can still adjust each one afterwards. Most apply at once; " ..
    "if one doesn't seem to, the game may need a /reload or restart for it (not confirmed per setting).", 3)

  L:Header("Enhancements")
  AA.SettingRows(L, p, T.ByGroup("graphics", "toggle"), rows, true)
  L:Header("Quality settings")
  AA.SettingRows(L, p, T.ByGroup("graphics", "range"), rows, false)

  L:Header("Undo")
  originalLine = L:Note("", 2)
  L:Buttons({
    { "Restore my original settings", 200, function() done(T.RestoreOriginals()) end,
      "Restore my original settings", "Puts back every game setting Azeroth Familiar has changed (graphics and gameplay) to the value it had before." },
    { "Game defaults", 110, function() done(T.ApplyPreset("default")) end,
      "Game defaults", "Sets the graphics settings on this page to the game's own defaults." },
  })
end

AA.Shell.Register({
  id = "graphics", title = "Graphics", order = 20, icon = I .. "INV_Misc_Spyglass_03",
  subtitle = "Presets and visual enhancements. Untick or use Undo to go back.",
  build = build, refresh = refreshRows,
})

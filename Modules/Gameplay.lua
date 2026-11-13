-- Azeroth Familiar - Modules/Gameplay.lua
-- Gameplay page: the game's own convenience options, gathered in one place.
-- These are ordinary game settings (console variables), changed only when you click.
-- Nothing here presses keys, casts, loots, targets or plays for you.

local ADDON, AA = ...
local T = AA.Tweaks
local I = "Interface\\Icons\\"
local rows = {}

local function pick(ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = T.Find(id) end
  return out
end

local function build(L, p)
  L:Header("Looting and quests")
  AA.SettingRows(L, p, pick({ "autoloot", "lootmouse", "questtext" }), rows)
  L:Header("Combat")
  AA.SettingRows(L, p, pick({ "selfcast", "fct" }), rows)
  L:Header("Nameplates")
  AA.SettingRows(L, p, pick({ "npEnemy", "npFriend", "npAll" }), rows)
  L:Header("Camera and interface size")
  AA.SettingRows(L, p, pick({ "camera", "useUiScale", "uiScale" }), rows)
  L:Note("A greyed-out option isn't available in this client. Changes are refused during combat. " ..
    "\"Restore my original settings\" on the Graphics page also undoes changes made here.", 3)
end

AA.Shell.Register({
  id = "gameplay", title = "Gameplay", order = 70, icon = I .. "INV_Misc_Gear_01",
  subtitle = "The game's own convenience options in one place.",
  build = build, refresh = function() AA.RefreshSettingRows(rows) end,
})

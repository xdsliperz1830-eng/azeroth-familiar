-- Azeroth Familiar - Tweaks.lua
-- The console-variable (CVar) engine behind the Graphics and Gameplay pages.
-- Everything here is the same as typing /console <name> <value>, and only happens when
-- you click something. The game saves CVars itself, so nothing is re-applied at login.
--
-- Safety rules:
--   * A variable the client doesn't have is reported as unavailable (never created).
--   * After setting a value it is read back; if the game kept something else, we say so.
--   * The value from before Azeroth Familiar first touched a variable is remembered,
--     so "Restore my original settings" can put everything back.
--   * Nothing changes during combat.
--
-- Verification (WoW Forever 1.60.1, from this install's Config.wtf, 2026-11-12):
--   seen there, so they exist: ResampleAlwaysSharpen, groundEffectDensity/Fade/Dist,
--   weatherDensity, graphicsViewDistance, graphicsEnvironmentDetail, graphicsGroundClutter,
--   graphicsShadowQuality, graphicsLiquidDetail, graphicsParticleDensity, graphicsSpellDensity,
--   graphicsSSAO, graphicsDepthEffects, uiScale, useUiScale.
--   NOT seen there (the file only lists changed values): graphicsTextureFiltering and all
--   gameplay variables. Those are checked at run time and greyed out if missing.
--   The upper limits below are assumptions; the read-back catches a wrong one.

local ADDON, AA = ...
local T = {}
AA.Tweaks = T

local I = "Interface\\Icons\\"

T.SETTINGS = {
  -- Graphics: on/off bundles ---------------------------------------------------
  { id = "sharpen", group = "graphics", kind = "toggle", icon = I .. "Ability_Hunter_EagleEye",
    label = "Sharper image",
    tip = "Turns on sharpening even at 100% render scale. Looks clearer, but adds no texture detail. If edges look harsh, lower Resample Sharpness in Graphics settings.",
    cvars = { { "ResampleAlwaysSharpen", "1", "0" } } },
  { id = "grass", group = "graphics", kind = "toggle", icon = I .. "Spell_Nature_StrangleVines",
    label = "More grass, visible further away",
    tip = "Denser ground plants that stay visible at longer range. Can cost frame rate in grassy zones.",
    cvars = { { "groundEffectDensity", "256" }, { "groundEffectFade", "370" }, { "groundEffectDist", "500" } } },
  { id = "weather", group = "graphics", kind = "toggle", icon = I .. "Spell_Frost_IceStorm",
    label = "Stronger weather effects",
    tip = "Denser rain, snow and sandstorms. Changes atmosphere, not sharpness.",
    cvars = { { "weatherDensity", "3" } } },
  -- Graphics: the game's own quality sliders (0 = lowest) ------------------------
  { id = "view", group = "graphics", kind = "range", icon = I .. "INV_Misc_Spyglass_03",
    label = "View distance", cvar = "graphicsViewDistance", min = 0, max = 9, level = true,
    tip = "How far away terrain and buildings are drawn. Big effect on frame rate in cities." },
  { id = "env", group = "graphics", kind = "range", icon = I .. "INV_Misc_Flower_02",
    label = "Environment detail", cvar = "graphicsEnvironmentDetail", min = 0, max = 9, level = true,
    tip = "How far away trees, rocks and props are drawn." },
  { id = "clutter", group = "graphics", kind = "range", icon = I .. "INV_Misc_Herb_07",
    label = "Ground clutter", cvar = "graphicsGroundClutter", min = 0, max = 9, level = true,
    tip = "Grass and small ground plants. Moving this slider resets the \"More grass\" values above." },
  { id = "shadows", group = "graphics", kind = "range", icon = I .. "Spell_Shadow_Twilight",
    label = "Shadows", cvar = "graphicsShadowQuality", min = 0, max = 5, level = true,
    tip = "Shadow quality. One of the most expensive settings." },
  { id = "water", group = "graphics", kind = "range", icon = I .. "Spell_Frost_SummonWaterElemental",
    label = "Water", cvar = "graphicsLiquidDetail", min = 0, max = 3, level = true,
    tip = "Water and lava detail (reflections, ripples)." },
  { id = "particles", group = "graphics", kind = "range", icon = I .. "Spell_Fire_FlameBolt",
    label = "Particle density", cvar = "graphicsParticleDensity", min = 0, max = 5, level = true,
    tip = "How many particles spells and effects draw." },
  { id = "spells", group = "graphics", kind = "range", icon = I .. "Spell_Nature_Lightning",
    label = "Spell effect visibility", cvar = "graphicsSpellDensity", min = 0, max = 5, level = true,
    tip = "How many of other players' spell effects are drawn. Lower helps in crowded fights." },
  { id = "ssao", group = "graphics", kind = "range", icon = I .. "Spell_Shadow_Shadowform",
    label = "Ambient shading (SSAO)", cvar = "graphicsSSAO", min = 0, max = 4, level = true,
    tip = "Soft shading in corners and under objects." },
  { id = "depth", group = "graphics", kind = "range", icon = I .. "Spell_Arcane_Blink",
    label = "Depth effects", cvar = "graphicsDepthEffects", min = 0, max = 3, level = true,
    tip = "Depth-based effects such as soft particle edges." },
  { id = "filtering", group = "graphics", kind = "range", icon = I .. "INV_Misc_Gem_Crystal_02",
    label = "Texture filtering", cvar = "graphicsTextureFiltering", min = 0, max = 5, level = true,
    tip = "Keeps ground textures sharp at a distance. Cheap on most graphics cards." },

  -- Gameplay -------------------------------------------------------------------
  { id = "autoloot", group = "gameplay", kind = "toggle", icon = I .. "INV_Misc_Coin_02",
    label = "Auto-loot", tip = "Pick up everything when you open a corpse or chest. This is the game's own option.",
    cvars = { { "autoLootDefault", "1", "0" } } },
  { id = "lootmouse", group = "gameplay", kind = "toggle", icon = I .. "INV_Misc_Bag_10",
    label = "Open the loot window at the mouse", tip = "The loot window appears under your cursor.",
    cvars = { { "lootUnderMouse", "1", "0" } } },
  { id = "questtext", group = "gameplay", kind = "toggle", icon = I .. "INV_Misc_Book_08",
    label = "Instant quest text", tip = "Quest text appears at once instead of scrolling in.",
    cvars = { { "instantQuestText", "1", "0" } } },
  { id = "selfcast", group = "gameplay", kind = "toggle", icon = I .. "Spell_Holy_Heal",
    label = "Auto self-cast", tip = "Helpful spells go on you when you have no friendly target.",
    cvars = { { "autoSelfCast", "1", "0" } } },
  { id = "fct", group = "gameplay", kind = "toggle", icon = I .. "Ability_Warrior_Rampage",
    label = "Floating combat text on me", tip = "Damage and healing you take scroll above your character.",
    cvars = { { "enableFloatingCombatText", "1", "0" } } },
  { id = "npEnemy", group = "gameplay", kind = "toggle", icon = I .. "Ability_Warrior_Challange",
    label = "Enemy nameplates", tip = "Health bars above enemies.",
    cvars = { { "nameplateShowEnemies", "1", "0" } } },
  { id = "npFriend", group = "gameplay", kind = "toggle", icon = I .. "Spell_Holy_PrayerOfHealing",
    label = "Friendly nameplates", tip = "Health bars above friendly players and NPCs.",
    cvars = { { "nameplateShowFriends", "1", "0" } } },
  { id = "npAll", group = "gameplay", kind = "toggle", icon = I .. "Ability_Hunter_SniperShot",
    label = "Always show nameplates", tip = "Show nameplates all the time, not only in combat.",
    cvars = { { "nameplateShowAll", "1", "0" } } },
  { id = "camera", group = "gameplay", kind = "range", icon = I .. "INV_Misc_Spyglass_02",
    label = "Maximum camera distance", cvar = "cameraDistanceMaxZoomFactor", min = 1.0, max = 4.0, step = 0.2,
    tip = "How far you can zoom out with the mouse wheel. The game caps this; the number shown is what it accepted." },
  { id = "useUiScale", group = "gameplay", kind = "toggle", icon = I .. "INV_Misc_Gear_01",
    label = "Use a custom UI scale", tip = "Lets the UI scale below apply. Off means the game picks the scale.",
    cvars = { { "useUiScale", "1", "0" } } },
  { id = "uiScale", group = "gameplay", kind = "range", icon = I .. "INV_Misc_Gear_02",
    label = "UI scale", cvar = "uiScale", min = 0.64, max = 1.15, step = 0.05,
    tip = "Size of the whole game interface. Only applies while \"Use a custom UI scale\" is on." },
}

-- Graphics presets. Values are the game's quality-slider levels (0 = lowest).
-- "default" is special: every graphics variable goes back to the game's default.
T.PRESETS = {
  { id = "default", label = "Default", tip = "Every graphics setting on this page goes back to the game's own default." },
  { id = "low", label = "Low", tip = "Low Performance: for crowded cities and raids, or an older PC.",
    values = { graphicsViewDistance = 2, graphicsEnvironmentDetail = 2, graphicsGroundClutter = 1, graphicsShadowQuality = 0,
      graphicsLiquidDetail = 0, graphicsParticleDensity = 1, graphicsSSAO = 0, graphicsDepthEffects = 0, weatherDensity = 1 } },
  { id = "balanced", label = "Balanced", tip = "Middle of every slider.",
    values = { graphicsViewDistance = 5, graphicsEnvironmentDetail = 5, graphicsGroundClutter = 5, graphicsShadowQuality = 2,
      graphicsLiquidDetail = 2, graphicsParticleDensity = 3, graphicsSSAO = 2, graphicsDepthEffects = 2, weatherDensity = 2 } },
  { id = "high", label = "High", tip = "High Quality: near the top of every slider.",
    values = { graphicsViewDistance = 8, graphicsEnvironmentDetail = 8, graphicsGroundClutter = 8, graphicsShadowQuality = 4,
      graphicsLiquidDetail = 3, graphicsParticleDensity = 4, graphicsSSAO = 4, graphicsDepthEffects = 3, weatherDensity = 2 } },
  { id = "immersive", label = "Immersive", tip = "Everything at the top, plus sharpening, extra grass and heavy weather.",
    values = { graphicsViewDistance = 9, graphicsEnvironmentDetail = 9, graphicsGroundClutter = 9, graphicsShadowQuality = 5,
      graphicsLiquidDetail = 3, graphicsParticleDensity = 5, graphicsSSAO = 4, graphicsDepthEffects = 3, weatherDensity = 3,
      ResampleAlwaysSharpen = 1, groundEffectDensity = 256, groundEffectFade = 370, groundEffectDist = 500 } },
}
-- Order matters: the clutter slider rewrites the grass variables, so those go last.
local PRESET_ORDER = { "graphicsViewDistance", "graphicsEnvironmentDetail", "graphicsGroundClutter", "graphicsShadowQuality",
  "graphicsLiquidDetail", "graphicsParticleDensity", "graphicsSSAO", "graphicsDepthEffects", "graphicsTextureFiltering",
  "graphicsSpellDensity", "weatherDensity", "ResampleAlwaysSharpen", "groundEffectDensity", "groundEffectFade", "groundEffectDist" }

-- Low-level access -----------------------------------------------------------
local function getCVar(name)
  local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, name)
  if ok and v ~= nil then return tostring(v) end
  return nil
end

local function getDefault(name)
  local fn = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, name)
  if ok and v ~= nil then return tostring(v) end
  return nil
end

local function setCVar(name, value)
  local fn = (C_CVar and C_CVar.SetCVar) or SetCVar
  if type(fn) ~= "function" then return false end
  return (pcall(fn, name, tostring(value)))
end

local function same(a, b)
  if a == nil or b == nil then return false end
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return math.abs(na - nb) < 0.001 end
  return tostring(a) == tostring(b)
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end
local COMBAT_MSG = "Not during combat. Try again when the fight is over."

-- Original values, from before this addon first changed each variable.
local function saved()
  AA.db.tweaks = type(AA.db.tweaks) == "table" and AA.db.tweaks or {}
  local tw = AA.db.tweaks
  tw.saved = type(tw.saved) == "table" and tw.saved or {}
  if not tw.cleaned then
    -- A hand-typed value such as "256\" is kept by the game as text; keep only the number.
    for k, v in pairs(tw.saved) do
      local n = tostring(v):match("^%-?[%d%.]+")
      tw.saved[k] = n or nil
    end
    tw.cleaned = true
  end
  return tw.saved
end

local function remember(name)
  local keep = saved()
  if keep[name] == nil then keep[name] = getCVar(name) end
end

-- Learned upper limits ---------------------------------------------------------
-- The maxima in T.SETTINGS are guesses. When you RAISE a slider and the game keeps a lower
-- value, that value is this client's real top for the slider. It is saved, and forgotten
-- when the game build changes (a patch may raise it). Lowering a slider never teaches a
-- limit, and a value you can see in the game is never above the limit (self-correcting).
local RANGE_BY_CVAR = {}
for _, s in ipairs(T.SETTINGS) do
  if s.kind == "range" then RANGE_BY_CVAR[s.cvar] = s end
end

local function clientBuild()
  if type(GetBuildInfo) ~= "function" then return "?" end
  local ok, version, build = pcall(GetBuildInfo)
  return ok and (tostring(version) .. "." .. tostring(build)) or "?"
end

local function limits()
  AA.db.tweaks = type(AA.db.tweaks) == "table" and AA.db.tweaks or {}
  local tw = AA.db.tweaks
  local b = clientBuild()
  -- "ceilings" replaces the first version's "limits", which could learn a wrong top while
  -- you clicked a slider down quickly; those values are dropped.
  tw.limits = nil
  if type(tw.ceilings) ~= "table" or tw.ceilings.build ~= b then tw.ceilings = { build = b } end
  return tw.ceilings
end

-- Forget every learned top (used by the Default preset and by restoring your settings).
function T.ForgetLimits()
  if AA.db and type(AA.db.tweaks) == "table" then AA.db.tweaks.ceilings = nil end
end

-- The highest value a range setting can really take on this client.
function T.Max(s)
  local learned = tonumber(limits()[s.cvar])
  if learned and learned >= s.min and learned < s.max then
    local cur = tonumber(getCVar(s.cvar))
    if cur and cur > learned then        -- the game shows more than we "learned": we were wrong
      limits()[s.cvar] = nil
      return s.max
    end
    return learned
  end
  return s.max
end

-- Called after raising a setting from `before` to `asked` and reading back `now`.
-- Only an increase the game didn't keep teaches a top.
local function learn(name, before, asked, now)
  local s = RANGE_BY_CVAR[name]
  local b, a, n = tonumber(before), tonumber(asked), tonumber(now)
  if s and b and a and n and a > b and n < a and n >= b then
    limits()[name] = n
  end
end

-- A preset's target, never above the learned top of its slider.
local function capped(name, value)
  local s = RANGE_BY_CVAR[name]
  local v = tonumber(value)
  if s and v and v > T.Max(s) then return T.Max(s) end
  return value
end

-- Sets one variable and reads it back. Returns ok, valueNow.
local function apply(name, value)
  if value == nil then return false, getCVar(name) end
  remember(name)
  local before = getCVar(name)
  setCVar(name, value)
  local now = getCVar(name)
  local ok = same(now, value)
  if not ok then learn(name, before, value, now) end
  return ok, now
end

local changes = {}   -- [cvar] = number of the latest change, so a stale re-check does nothing

-- Lookup ---------------------------------------------------------------------
function T.Find(id)
  for _, s in ipairs(T.SETTINGS) do if s.id == id then return s end end
end

function T.ByGroup(group, kind)
  local out = {}
  for _, s in ipairs(T.SETTINGS) do
    if s.group == group and (kind == nil or s.kind == kind) then out[#out + 1] = s end
  end
  return out
end

local function names(s)
  local out = {}
  if s.kind == "range" then out[1] = s.cvar
  else for _, cv in ipairs(s.cvars) do out[#out + 1] = cv[1] end end
  return out
end

function T.Available(s)
  for _, n in ipairs(names(s)) do
    if getCVar(n) == nil then return false end
  end
  return true
end

function T.IsOn(s)
  for _, cv in ipairs(s.cvars) do
    if not same(getCVar(cv[1]), cv[2]) then return false end
  end
  return true
end

-- Current number of a range setting, or nil when unavailable.
function T.Value(s)
  return tonumber(getCVar(s.cvar))
end

-- How a range value is shown: quality sliders read "8 of 10", others as the raw number.
function T.Format(s, v)
  if s.level then return string.format("%d of %d", v - s.min + 1, T.Max(s) - s.min + 1) end
  return string.format("%.2f", v)
end

function T.Status(s)
  local parts = {}
  for _, n in ipairs(names(s)) do
    local v = getCVar(n)
    parts[#parts + 1] = n .. (v and (" = " .. v) or ": not in this client")
  end
  return table.concat(parts, ", ")
end

-- The equivalent chat commands, for tooltips.
function T.Commands(s)
  local out = {}
  if s.kind == "range" then
    out[1] = "/console " .. s.cvar .. " <" .. s.min .. " to " .. T.Max(s) .. ">"
  else
    for _, cv in ipairs(s.cvars) do out[#out + 1] = "/console " .. cv[1] .. " " .. cv[2] end
  end
  return out
end

-- Changing things ------------------------------------------------------------
-- Toggle. Returns ok, message.
function T.Set(s, on)
  if inCombat() then return false, COMBAT_MSG end
  if not T.Available(s) then
    return false, "This client doesn't have that setting (" .. T.Status(s) .. ")."
  end
  local keep = saved()
  local failed = {}
  for _, cv in ipairs(s.cvars) do
    local name, target = cv[1], cv[2]
    if not on then
      target = cv[3]
      if target == nil then
        -- back to what you had; if that was already the "on" value, the game default
        target = keep[name]
        if target == nil or same(target, cv[2]) then target = getDefault(name) end
      end
    end
    local ok, now = apply(name, target)
    if not ok then failed[#failed + 1] = name .. " (now " .. tostring(now) .. ")" end
  end
  if #failed > 0 then
    return false, "The game didn't accept: " .. table.concat(failed, ", ") .. "."
  end
  return true, s.label .. (on and ": on" or ": off")
end

-- Range. Returns ok, message.
function T.SetValue(s, v)
  if inCombat() then return false, COMBAT_MSG end
  if not T.Available(s) then
    return false, "This client doesn't have that setting (" .. s.cvar .. ")."
  end
  local top = T.Max(s)
  if v < s.min then v = s.min elseif v > top then v = top end
  local before = tonumber(getCVar(s.cvar))
  changes[s.cvar] = (changes[s.cvar] or 0) + 1
  local seq = changes[s.cvar]
  local ok, now = apply(s.cvar, v)
  local n = tonumber(now)
  if not ok then
    if n and n < v and T.Max(s) == n then
      return false, s.label .. ": " .. T.Format(s, n) .. " is the highest this game allows."
    end
    return false, s.label .. ": the game kept " .. (n and T.Format(s, n) or tostring(now)) .. "."
  end
  -- Some settings may be accepted at first and lowered by the game a moment later.
  -- After a raise, look again shortly; if it dropped (and you haven't clicked this slider
  -- since), learn the real top and redraw the page.
  if C_Timer and C_Timer.After and before and v > before then
    local asked = v
    C_Timer.After(1, function()
      if changes[s.cvar] ~= seq then return end      -- you changed it again since: not the game
      local later = tonumber(getCVar(s.cvar))
      if later and later < asked and later >= before then
        learn(s.cvar, before, asked, later)
        if AA.Shell and AA.Shell.Refresh then pcall(AA.Shell.Refresh) end
        if AA.Shell and AA.Shell.Flash then
          pcall(AA.Shell.Flash, s.label .. ": " .. T.Format(s, later) .. " is the highest this game allows.", false)
        end
      end
    end)
  end
  return true, s.label .. ": " .. T.Format(s, n)
end

function T.FindPreset(id)
  for _, p in ipairs(T.PRESETS) do if p.id == id then return p end end
end

local function presetTarget(p, name)
  if p.id == "default" then return getDefault(name) end
  return capped(name, p.values[name])
end

-- Returns ok, message. Only touches the variables listed for that preset.
function T.ApplyPreset(id)
  local p = T.FindPreset(id)
  if not p then return false, "Unknown preset." end
  if inCombat() then return false, COMBAT_MSG end
  local applied, adjusted, missing = 0, {}, 0
  for _, name in ipairs(PRESET_ORDER) do
    local target = presetTarget(p, name)
    if target ~= nil then
      if getCVar(name) == nil then
        missing = missing + 1
      else
        local ok, now = apply(name, target)
        if ok then applied = applied + 1 else adjusted[#adjusted + 1] = name .. " = " .. tostring(now) end
      end
    end
  end
  AA.db.tweaks.preset = id
  if id == "default" then T.ForgetLimits() end
  local msg = p.label .. ": " .. applied .. " settings applied"
  if #adjusted > 0 then msg = msg .. "; the game kept its own value for " .. table.concat(adjusted, ", ") end
  if missing > 0 then msg = msg .. "; " .. missing .. " not in this client" end
  return #adjusted == 0, msg .. "."
end

-- Which preset the current values match, or nil ("Custom").
function T.MatchingPreset()
  for _, p in ipairs(T.PRESETS) do
    local all, any = true, false
    for _, name in ipairs(PRESET_ORDER) do
      local target = presetTarget(p, name)
      local cur = getCVar(name)
      if target ~= nil and cur ~= nil then
        any = true
        if not same(cur, target) then all = false break end
      end
    end
    if all and any then return p end
  end
end

function T.OriginalCount()
  local n = 0
  for _ in pairs(saved()) do n = n + 1 end
  return n
end

-- Puts back every value this addon ever changed (graphics and gameplay). Returns ok, message.
function T.RestoreOriginals()
  if inCombat() then return false, COMBAT_MSG end
  T.ForgetLimits()
  local keep = saved()
  local done, failed = 0, {}
  -- grass variables last, for the same reason as PRESET_ORDER
  local order, seen = {}, {}
  for _, name in ipairs(PRESET_ORDER) do if keep[name] ~= nil then order[#order + 1] = name; seen[name] = true end end
  local rest = {}
  for name in pairs(keep) do if not seen[name] then rest[#rest + 1] = name end end
  table.sort(rest)
  for i = #rest, 1, -1 do table.insert(order, 1, rest[i]) end
  for _, name in ipairs(order) do
    local target = keep[name]
    if getCVar(name) ~= nil then
      setCVar(name, target)
      if same(getCVar(name), target) then
        done = done + 1
        keep[name] = nil
      else
        failed[#failed + 1] = name
      end
    else
      keep[name] = nil
    end
  end
  AA.db.tweaks.preset = nil
  if #failed > 0 then
    return false, "Restored " .. done .. "; the game refused " .. table.concat(failed, ", ") .. "."
  end
  if done == 0 then return true, "Nothing to restore: Azeroth Familiar hasn't changed any game setting." end
  return true, "Restored " .. done .. " settings to what they were before Azeroth Familiar changed them."
end

-- Used by /aa diag: which of the variables above this client really has.
function T.Probe()
  local have, lack = {}, {}
  for _, s in ipairs(T.SETTINGS) do
    for _, n in ipairs(names(s)) do
      local v = getCVar(n)
      if v ~= nil then have[#have + 1] = n .. "=" .. v .. " (default " .. tostring(getDefault(n)) .. ")"
      else lack[#lack + 1] = n end
    end
  end
  return have, lack
end

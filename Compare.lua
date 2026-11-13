-- Azeroth Familiar - Compare.lua
-- Factual item comparison. Shows stat differences first, then special effects verbatim.
-- Deliberately has NO damage formula or single "score": WoW Forever's stat conversions
-- and talent effects are not verified yet, and a heuristic is not a simulation.

local ADDON, AA = ...
local P = {}
AA.Compare = P

-- Item data loading -----------------------------------------------------------
-- Calls cb() once all items have data, or after a timeout (cb(true) = some missing).
function P.EnsureLoaded(links, cb)
  local pending = 0
  local done = false
  local function finish(timedOut)
    if done then return end
    done = true
    cb(timedOut)
  end
  local hasMixin = type(Item) == "table" and type(Item.CreateFromItemLink) == "function"
  for _, l in ipairs(links) do
    local ok, name = AA.Try(AA.Api("C_Item", "GetItemInfo"), l)
    if not (ok and name) then
      pending = pending + 1
      if hasMixin then
        local plainID = (not tostring(l):find("|H", 1, true)) and tonumber(tostring(l):match("item:(%d+)")) or nil
        local okM, obj
        if plainID and type(Item.CreateFromItemID) == "function" then
          okM, obj = pcall(Item.CreateFromItemID, Item, plainID)
        else
          okM, obj = pcall(Item.CreateFromItemLink, Item, l)
        end
        if okM and obj and obj.ContinueOnItemLoad then
          obj:ContinueOnItemLoad(function()
            pending = pending - 1
            if pending <= 0 then finish(false) end
          end)
        end
      else
        local id = tonumber(tostring(l):match("item:(%d+)"))
        if id then AA.Try(AA.Api("C_Item", "RequestLoadItemDataByID"), id) end
      end
    end
  end
  if pending == 0 then finish(false) return end
  C_Timer.After(hasMixin and 3 or 1.5, function() finish(true) end)
end

-- Item facts --------------------------------------------------------------------
local EQUIP_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
  INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
P.EQUIP_SLOTS = EQUIP_SLOTS

local GROUPS = {
  { label = "Melee offense", keys = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_MELEE_ATTACK_POWER_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" } },
  { label = "Survival", keys = {
    "ITEM_MOD_STAMINA_SHORT", "RESISTANCE0_NAME", "ITEM_MOD_DODGE_RATING_SHORT",
    "ITEM_MOD_PARRY_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_HEALTH_SHORT", "ITEM_MOD_HEALTH_REGEN_SHORT",
    "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME", "RESISTANCE4_NAME",
    "RESISTANCE5_NAME", "RESISTANCE6_NAME" } },
  { label = "Mana / caster", keys = {
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_MANA_SHORT",
    "ITEM_MOD_POWER_REGEN0_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_CRIT_RATING_SHORT",
    "ITEM_MOD_SPELL_HIT_RATING_SHORT" } },
}
local GROUP_OF = {}
for gi, g in ipairs(GROUPS) do for _, k in ipairs(g.keys) do GROUP_OF[k] = gi end end

local function statLabel(key)
  local g = _G[key]
  if type(g) == "string" and g ~= "" then return g end
  return (key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower())
end
P.StatLabel = statLabel

local function triggerPrefixes()
  return {
    { text = (type(ITEM_SPELL_TRIGGER_ONEQUIP) == "string" and ITEM_SPELL_TRIGGER_ONEQUIP) or "Equip:", kind = "Equip" },
    { text = (type(ITEM_SPELL_TRIGGER_ONUSE) == "string" and ITEM_SPELL_TRIGGER_ONUSE) or "Use:", kind = "Use" },
    { text = (type(ITEM_SPELL_TRIGGER_ONPROC) == "string" and ITEM_SPELL_TRIGGER_ONPROC) or "Chance on hit:", kind = "Proc" },
  }
end

local CONDITIONAL_WORDS = { "Humanoid", "Undead", "Demon", "Beast", "Elemental", "Dragonkin", "Giant", "Mechanical" }

-- Reads tooltip lines through C_TooltipInfo (no visible tooltip is used).
local function tooltipFacts(link)
  local facts = { effects = {}, redLines = {}, descLines = {} }
  local ok, data = AA.Try(AA.Api("C_TooltipInfo", "GetHyperlink"), link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return facts end
  local prefixes = triggerPrefixes()
  for i, line in ipairs(data.lines) do
    local left = AA.Str(line.leftText)
    local right = AA.Str(line.rightText)
    if left and i > 1 then
      for _, p in ipairs(prefixes) do
        if left:sub(1, #p.text) == p.text then
          local e = { kind = p.kind, text = left }
          for _, w in ipairs(CONDITIONAL_WORDS) do
            if left:find(w, 1, true) then e.conditional = w break end
          end
          facts.effects[#facts.effects + 1] = e
          break
        end
      end
      if left:sub(1, 1) == "\"" and #facts.descLines < 2 then facts.descLines[#facts.descLines + 1] = left end
      local lo, hi = left:match("^(%d+)%s*%-%s*(%d+)")
      if lo and right then
        local spd = right:match("(%d+[%.,]%d+)")
        if spd then
          facts.minDmg, facts.maxDmg = tonumber(lo), tonumber(hi)
          facts.speed = tonumber((spd:gsub(",", ".")))
        end
      end
      local c = line.leftColor
      if type(c) == "table" and AA.Num(c.r) and AA.Num(c.g) and AA.Num(c.b) then
        if c.r > 0.9 and c.g < 0.3 and c.b < 0.3 then facts.redLines[#facts.redLines + 1] = left end
      end
    end
  end
  return facts
end

-- Everything we can read about one item, from the client only.
function P.ItemFacts(link)
  local f = { link = link }
  local ok, name, fullLink, quality, ilvl, reqLevel, itemType, subType, _, equipLoc =
    AA.Try(AA.Api("C_Item", "GetItemInfo"), link)
  if ok and name then
    f.name, f.link, f.quality = name, fullLink or link, quality
    f.ilvl, f.reqLevel, f.itemType, f.subType, f.equipLoc = ilvl, reqLevel, itemType, subType, equipLoc
  else
    f.name = link:match("|h%[(.-)%]|h")
    f.uncached = true
  end
  if not f.equipLoc or f.equipLoc == "" then
    local okI, _, _, _, loc = AA.Try(AA.Api("C_Item", "GetItemInfoInstant"), link)
    if okI and loc and loc ~= "" then f.equipLoc = loc end
  end
  local okS, stats = AA.Try(AA.Api("C_Item", "GetItemStats"), link)
  f.stats = {}
  if okS and type(stats) == "table" then
    for k, v in pairs(stats) do
      if AA.Num(v) then f.stats[k] = v end
    end
  end
  local t = tooltipFacts(link)
  f.effects, f.redLines, f.descLines = t.effects, t.redLines, t.descLines
  f.minDmg, f.maxDmg, f.speed = t.minDmg, t.maxDmg, t.speed
  f.dps = f.stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
  if not f.dps and f.minDmg and f.speed and f.speed > 0 then
    f.dps = (f.minDmg + f.maxDmg) / 2 / f.speed
  end
  f.id = tonumber(link:match("item:(%d+)"))
  return f
end

local function fmtNum(n)
  if math.floor(n) == n then return tostring(n) end
  return string.format("%.1f", n)
end

local function signed(n)
  if n > 0 then return AA.C.good .. "+" .. fmtNum(n) .. "|r" end
  if n < 0 then return AA.C.bad .. fmtNum(n) .. "|r" end
  return "0"
end

-- Sums the stats of several items (used for 2H vs main hand + off hand).
function P.Combine(factsList)
  local c = { stats = {}, effects = {}, names = {} }
  for _, f in ipairs(factsList) do
    for k, v in pairs(f.stats) do c.stats[k] = (c.stats[k] or 0) + v end
    for _, e in ipairs(f.effects) do c.effects[#c.effects + 1] = e end
    c.names[#c.names + 1] = f.link or f.name
  end
  if #factsList == 1 then
    local f = factsList[1]
    c.dps, c.speed, c.minDmg, c.maxDmg = f.dps, f.speed, f.minDmg, f.maxDmg
  end
  return c
end

local function effectLines(prefix, effects)
  local out = {}
  for _, e in ipairs(effects) do
    local tag = e.kind == "Proc" and " (proc rate unknown)" or ""
    if e.conditional then tag = tag .. " " .. AA.C.warn .. "(only vs " .. e.conditional .. ")|r" end
    out[#out + 1] = prefix .. AA.PlainText(e.text) .. tag
  end
  return out
end

-- A vs B. a and b are combined-facts tables (P.Combine). Returns display lines.
function P.Diff(aLabel, a, bLabel, b)
  local lines = {}
  lines[#lines + 1] = AA.C.head .. "Stat changes going from " .. bLabel .. " to " .. aLabel .. ":|r"
  local keys, seen = {}, {}
  for k in pairs(a.stats) do if not seen[k] then seen[k] = true keys[#keys + 1] = k end end
  for k in pairs(b.stats) do if not seen[k] then seen[k] = true keys[#keys + 1] = k end end
  local byGroup = {}
  for _, k in ipairs(keys) do
    if k ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
      local gi = GROUP_OF[k] or (#GROUPS + 1)
      byGroup[gi] = byGroup[gi] or {}
      local d = (a.stats[k] or 0) - (b.stats[k] or 0)
      if d ~= 0 then byGroup[gi][#byGroup[gi] + 1] = signed(d) .. " " .. statLabel(k) end
    end
  end
  local any = false
  for gi = 1, #GROUPS + 1 do
    local list = byGroup[gi]
    if list and #list > 0 then
      table.sort(list)
      local label = GROUPS[gi] and GROUPS[gi].label or "Other"
      lines[#lines + 1] = label .. ": " .. table.concat(list, ", ")
      any = true
    end
  end
  if not any then lines[#lines + 1] = "No difference in listed stats." end
  if a.dps or b.dps then
    local s = "Weapon DPS: " .. (a.dps and fmtNum(a.dps) or "?") .. " vs " .. (b.dps and fmtNum(b.dps) or "?")
    if a.dps and b.dps then s = s .. " (" .. signed(a.dps - b.dps) .. ")" end
    if a.speed or b.speed then
      s = s .. "; speed " .. (a.speed and string.format("%.2f", a.speed) or "?") .. " vs " .. (b.speed and string.format("%.2f", b.speed) or "?")
    end
    lines[#lines + 1] = s
  end
  local ea = effectLines(aLabel .. " has: ", a.effects)
  local eb = effectLines(bLabel .. " has: ", b.effects)
  for _, l in ipairs(ea) do lines[#lines + 1] = l end
  for _, l in ipairs(eb) do lines[#lines + 1] = l end
  if #ea + #eb > 0 then
    lines[#lines + 1] = AA.C.src .. "Special effects are listed as written; I can't value them without verified proc rates or formulas.|r"
  end
  return lines
end

-- Plain-language guidance, clearly labeled. Not a simulation.
function P.Guidance(a, b, aLabel, bLabel)
  local pref = AA.db and AA.db.settings.preference or "melee"
  local function sumGroup(f, gi)
    local t = 0
    for k, v in pairs(f.stats) do if GROUP_OF[k] == gi and k ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then t = t + v end end
    return t
  end
  local out = {}
  local meleeA, meleeB = sumGroup(a, 1), sumGroup(b, 1)
  local survA, survB = sumGroup(a, 2), sumGroup(b, 2)
  if a.dps and b.dps and math.abs(a.dps - b.dps) >= 0.1 then
    out[#out + 1] = (a.dps > b.dps and aLabel or bLabel) .. " has the higher weapon DPS, which matters most for auto-attack melee leveling."
  end
  if meleeA ~= meleeB then
    out[#out + 1] = (meleeA > meleeB and aLabel or bLabel) .. " carries more melee stat points (raw total, not weighted)."
  end
  if survA ~= survB then
    out[#out + 1] = (survA > survB and aLabel or bLabel) .. " carries more survival stat points."
  end
  if pref == "survival" then
    out[#out + 1] = AA.C.src .. "Your preference is set to survival: weigh the survival line more heavily.|r"
  end
  out[#out + 1] = AA.C.src .. "These are factual tradeoffs, not a damage simulation. Forever's stat conversions are not verified yet.|r"
  return out
end

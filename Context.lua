-- Azeroth Familiar - Context.lua
-- Gathers character information on request only. Never reads name, realm, guild,
-- chat or account data. Refuses during combat (values may be secret then).

local ADDON, AA = ...
local C = {}
AA.Context = C

C.SLOTS = {
  { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
  { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
  { 11, "Ring 1" }, { 12, "Ring 2" }, { 13, "Trinket 1" }, { 14, "Trinket 2" },
  { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged/Relic" },
}
C.SLOT_NAME = {}
for _, s in ipairs(C.SLOTS) do C.SLOT_NAME[s[1]] = s[2] end

local function inCombat()
  return InCombatLockdown and InCombatLockdown()
end

function C.Basic()
  local level = AA.Num(UnitLevel("player"))
  local className = AA.Str((UnitClass("player")))
  local raceName = AA.Str((UnitRace("player")))
  return { level = level, class = className, race = raceName }
end

function C.Equipment()
  local out = {}
  for _, s in ipairs(C.SLOTS) do
    local link = GetInventoryItemLink("player", s[1])
    if link and not AA.IsSecret(link) then
      out[#out + 1] = { slot = s[1], slotName = s[2], link = link, name = link:match("|h%[(.-)%]|h") }
    end
  end
  return out
end

function C.Stats()
  if inCombat() then return nil, "in combat" end
  local st = {}
  local names = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
  for i = 1, 5 do
    local ok, base, eff = pcall(UnitStat, "player", i)
    if ok then st[names[i]] = AA.Num(eff) or AA.Num(base) end
  end
  local ok, base, pos, neg = AA.Try(AA.Api("UnitAttackPower"), "player")
  if ok and AA.Num(base) then st["Attack power"] = base + (AA.Num(pos) or 0) + (AA.Num(neg) or 0) end
  local okC, crit = AA.Try(AA.Api("GetCritChance"))
  if okC and AA.Num(crit) then st["Melee crit %"] = string.format("%.2f", crit) end
  local okH, hit = AA.Try(AA.Api("GetHitModifier"))
  if okH and AA.Num(hit) then st["Hit % from gear/talents"] = hit end
  local okA, aBase, aEff = AA.Try(AA.Api("UnitArmor"), "player")
  if okA then st["Armor"] = AA.Num(aEff) or AA.Num(aBase) end
  local okS, mh, oh = AA.Try(AA.Api("UnitAttackSpeed"), "player")
  if okS and AA.Num(mh) then st["Main-hand speed"] = string.format("%.2f", mh) end
  if okS and AA.Num(oh) then st["Off-hand speed"] = string.format("%.2f", oh) end
  local okM, mana = AA.Try(AA.Api("UnitPowerMax"), "player", 0)
  if okM and AA.Num(mana) then st["Max mana"] = mana end
  local okHP, hp = AA.Try(AA.Api("UnitHealthMax"), "player")
  if okHP and AA.Num(hp) then st["Max health"] = hp end
  return st
end

function C.Professions()
  local out = {}
  local getProfs, getInfo = AA.Api("GetProfessions"), AA.Api("GetProfessionInfo")
  if not (getProfs and getInfo) then return out, "profession API not available" end
  local res = { pcall(getProfs) }
  if not res[1] then return out, "profession API failed" end
  for i = 2, table.maxn(res) do
    local idx = res[i]
    if idx then
      local ok, name, _, rank, maxRank = pcall(getInfo, idx)
      if ok and AA.Str(name) then
        out[#out + 1] = { name = name, rank = AA.Num(rank), max = AA.Num(maxRank) }
      end
    end
  end
  return out
end

-- Quest log (cached; rebuilt lazily after QUEST_LOG_UPDATE) ---------------------
local questCache, questDirty = nil, true

AA:On("QUEST_LOG_UPDATE", function() questDirty = true end)
AA:On("QUEST_ACCEPTED", function() questDirty = true end)
AA:On("QUEST_REMOVED", function() questDirty = true end)

function C.QuestLog()
  if questCache and not questDirty then return questCache end
  local out = {}
  local getNum = AA.Api("C_QuestLog", "GetNumQuestLogEntries")
  local getInfo = AA.Api("C_QuestLog", "GetInfo")
  local getObj = AA.Api("C_QuestLog", "GetQuestObjectives")
  local isComplete = AA.Api("C_QuestLog", "IsComplete")
  if not (getNum and getInfo) then return out, "quest log API not available" end
  local ok, n = pcall(getNum)
  n = ok and AA.Num(n) or 0
  local header
  for i = 1, n do
    local okI, info = pcall(getInfo, i)
    if okI and type(info) == "table" then
      if info.isHeader then
        header = AA.Str(info.title)
      elseif not info.isHidden and info.questID then
        local q = {
          index = i, questID = info.questID, title = AA.Str(info.title) or ("Quest " .. tostring(info.questID)),
          level = AA.Num(info.level), zone = header, objectives = {},
        }
        if isComplete then
          local okC, c = pcall(isComplete, info.questID)
          q.complete = okC and c and true or false
        end
        if getObj then
          local okO, objs = pcall(getObj, info.questID)
          if okO and type(objs) == "table" then
            for _, o in ipairs(objs) do
              q.objectives[#q.objectives + 1] = {
                text = AA.Str(o.text) or "", finished = o.finished and true or false,
                have = AA.Num(o.numFulfilled), need = AA.Num(o.numRequired), type = o.type,
              }
            end
          end
        end
        out[#out + 1] = q
      end
    end
  end
  questCache, questDirty = out, false
  return out
end

function C.FindQuest(questID)
  for _, q in ipairs(C.QuestLog()) do
    if q.questID == questID then return q end
  end
  return nil
end

-- Description text for a quest in the log. Passes the log index directly, so the
-- player's selected quest is not changed.
function C.QuestText(q)
  if not q or not q.index then return nil end
  local ok, desc, objText = AA.Try(AA.Api("GetQuestLogQuestText"), q.index)
  if not ok then return nil end
  return AA.Str(desc), AA.Str(objText)
end

-- Full snapshot used by previews and AI packets. opts decide which sections are read.
function C.Gather(opts)
  opts = opts or {}
  if inCombat() then return nil, "You're in combat. Character context is gathered only out of combat." end
  local ctx = { basic = C.Basic(), observed = date("%Y-%m-%d %H:%M") }
  if opts.equipment then ctx.equipment = C.Equipment() end
  if opts.stats then ctx.stats = C.Stats() end
  if opts.professions then ctx.professions = C.Professions() end
  if opts.quests then ctx.quests = C.QuestLog() end
  ctx.buildNote = AA.db and AA.db.settings.buildNote or nil
  return ctx
end

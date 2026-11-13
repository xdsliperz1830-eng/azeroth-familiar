-- Azeroth Familiar - Integrations/Questie.lua
-- Optional adapter for Questie's database provider (the "QuestieDB" addon that ships with
-- Questie). Nothing from Questie is copied or bundled: this file only READS the player's
-- installed database at runtime through its documented public API:
--   LibQuestieDB.RequireContract(n)      contract check (Questie 12.x on Forever uses 4)
--   LibQuestieDB.Item/Npc/Object/Quest.Get(id, field)
--   LibQuestieDB.Item/Npc.IdsByName(exactName)
-- Field names come from Questie's own type declarations (.types/QuestieDB/*.t.lua).
-- Coordinates are zone-map percentages (0-100) keyed by AreaID, as Questie draws them.
-- Every call is wrapped in pcall; if anything is missing, the addon behaves as without Questie.

local ADDON, AA = ...
local Q = {}
AA.Questie = Q

Q.CONTRACT = 4
Q.MAX_LIST = 6

function Q.IsLoaded()
  local isLoaded = AA.Api("C_AddOns", "IsAddOnLoaded") or AA.Api("IsAddOnLoaded")
  if not isLoaded then return false end
  local ok, loaded = pcall(isLoaded, "Questie")
  return ok and loaded and true or false
end

-- Returns the provider table, or nil + reason.
function Q.DB()
  local db = rawget(_G, "LibQuestieDB")
  if type(db) ~= "table" or type(db.RequireContract) ~= "function" then
    return nil, Q.IsLoaded() and "Questie is loaded but its database provider isn't available yet" or "Questie isn't loaded"
  end
  if Q.contractOK == nil then
    local ok, supported, err = pcall(db.RequireContract, Q.CONTRACT)
    Q.contractOK = ok and supported == true
    Q.contractError = (not Q.contractOK) and tostring(err or supported) or nil
  end
  if not Q.contractOK then
    return nil, "Questie's database doesn't support contract " .. Q.CONTRACT .. " (" .. tostring(Q.contractError) .. ")"
  end
  for _, kind in ipairs({ "Item", "Npc", "Object", "Quest" }) do
    if type(db[kind]) ~= "table" or type(db[kind].Get) ~= "function" then
      return nil, "Questie's database is missing " .. kind .. ".Get"
    end
  end
  return db
end

function Q.Available()
  return Q.DB() ~= nil
end

local function get(kind, id, field)
  local db = Q.DB()
  if not db or not id then return nil end
  local ok, v = pcall(db[kind].Get, id, field)
  if ok then return v end
  return nil
end
Q.Get = get

-- Zone names come from the game client, not from Questie.
function Q.ZoneName(areaId)
  if not areaId or areaId == 0 then return nil end
  local ok, name = AA.Try(AA.Api("C_Map", "GetAreaInfo"), areaId)
  if ok and AA.Str(name) and name ~= "" then return name end
  return "zone #" .. tostring(areaId)
end

local function playerFactionLetter()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
  return nil
end

-- Picks the best zone and up to two spawn points for an NPC or object.
local function placeOf(kind, id)
  local spawns = get(kind, id, "spawns")
  local zoneId = get(kind, id, "zoneID")
  local coords = {}
  local count = 0
  if type(spawns) == "table" then
    if not (zoneId and spawns[zoneId]) then
      local best, bestN = nil, 0
      for z, list in pairs(spawns) do
        if type(list) == "table" and #list > bestN then best, bestN = z, #list end
      end
      zoneId = best or zoneId
    end
    local list = zoneId and spawns[zoneId]
    if type(list) == "table" then
      count = #list
      for i = 1, math.min(2, #list) do
        local c = list[i]
        if type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and c[1] >= 0 and c[2] >= 0 then
          coords[#coords + 1] = string.format("%.1f, %.1f", c[1], c[2])
        end
      end
    end
  end
  return { zoneId = zoneId, zone = Q.ZoneName(zoneId), coords = coords, spawnCount = count }
end

local function describe(kind, id)
  local name = get(kind, id, "name")
  if type(name) ~= "string" then return nil end
  local e = { kind = kind, id = id, name = name }
  if kind == "Npc" then
    e.subName = get("Npc", id, "subName")
    e.friendly = get("Npc", id, "friendlyToFaction")
    e.minLevel = get("Npc", id, "minLevel")
    e.maxLevel = get("Npc", id, "maxLevel")
  end
  local p = placeOf(kind, id)
  e.zone, e.zoneId, e.coords, e.spawnCount = p.zone, p.zoneId, p.coords, p.spawnCount
  return e
end
Q.Describe = describe

-- Sorts entries so the player's current zone comes first, then by zone name.
local function sortByZone(list)
  local here = GetRealZoneText and GetRealZoneText() or nil
  table.sort(list, function(a, b)
    local ao, bo = a.otherFaction and 1 or 0, b.otherFaction and 1 or 0
    if ao ~= bo then return ao < bo end
    local ah, bh = (a.zone == here) and 0 or 1, (b.zone == here) and 0 or 1
    if ah ~= bh then return ah < bh end
    if (a.zone or "") ~= (b.zone or "") then return (a.zone or "~") < (b.zone or "~") end
    return a.name < b.name
  end)
end

local function entryLine(e)
  local s = e.name
  if type(e.subName) == "string" and e.subName ~= "" then s = s .. " <" .. e.subName .. ">" end
  if e.minLevel and e.maxLevel and e.minLevel > 0 then
    s = s .. (e.minLevel == e.maxLevel and (" (level " .. e.minLevel .. ")") or (" (level " .. e.minLevel .. "-" .. e.maxLevel .. ")"))
  end
  if e.zone then s = s .. " - " .. e.zone end
  if #e.coords > 0 then
    s = s .. " @ " .. table.concat(e.coords, " / ")
    if e.spawnCount > #e.coords then s = s .. " (+" .. (e.spawnCount - #e.coords) .. " more spawns)" end
  end
  if e.factionNote then s = s .. " " .. e.factionNote end
  return s
end
Q.EntryLine = entryLine

local function collect(kind, ids, opts)
  local out = {}
  if type(ids) ~= "table" then return out, 0 end
  local mine = playerFactionLetter()
  -- Cap the work for very common items (cloth, leather) that hundreds of creatures drop.
  for i = 1, math.min(#ids, 60) do
    local id = ids[i]
    local e = describe(kind, id)
    if e then
      if opts and opts.vendor and mine and type(e.friendly) == "string" and not e.friendly:find(mine, 1, true) then
        e.factionNote = AA.C.warn .. "(other faction)|r"
        e.otherFaction = true
      end
      out[#out + 1] = e
    end
  end
  sortByZone(out)
  return out, #ids
end

-- Where an item comes from, according to Questie's database.
function Q.ItemSources(itemId)
  if not Q.DB() then return nil end
  local s = {}
  s.name = get("Item", itemId, "name")
  s.vendors = collect("Npc", get("Item", itemId, "vendors"), { vendor = true })
  s.drops, s.dropTotal = collect("Npc", get("Item", itemId, "npcDrops"))
  s.objects, s.objectTotal = collect("Object", get("Item", itemId, "objectDrops"))
  s.containers = {}
  for _, cid in ipairs(get("Item", itemId, "itemDrops") or {}) do
    local n = get("Item", cid, "name")
    if n then s.containers[#s.containers + 1] = { id = cid, name = n } end
  end
  s.rewards = {}
  for _, qid in ipairs(get("Item", itemId, "questRewards") or {}) do
    local n = get("Quest", qid, "name")
    if n then s.rewards[#s.rewards + 1] = { id = qid, name = n } end
  end
  s.startQuest = get("Item", itemId, "startQuest")
  s.known = s.name ~= nil
  return s
end

-- Display lines for ItemSources. Returns lines and whether anything was found.
function Q.ItemSourceLines(itemId)
  local s = Q.ItemSources(itemId)
  if not s then return {}, false end
  local lines, found = {}, false
  local function block(title, list, total)
    if #list == 0 then return end
    found = true
    lines[#lines + 1] = AA.C.head .. title .. "|r"
    for i = 1, math.min(#list, Q.MAX_LIST) do lines[#lines + 1] = "  " .. entryLine(list[i]) end
    local extra = (total or #list) - math.min(#list, Q.MAX_LIST)
    if extra > 0 then lines[#lines + 1] = AA.C.src .. "  ...and " .. extra .. " more|r" end
  end
  block("Sold by:", s.vendors)
  block("Dropped by:", s.drops, s.dropTotal)
  block("Found in (objects):", s.objects, s.objectTotal)
  if #s.containers > 0 then
    found = true
    local names = {}
    for i = 1, math.min(#s.containers, Q.MAX_LIST) do names[i] = s.containers[i].name end
    lines[#lines + 1] = AA.C.head .. "Comes from containers:|r " .. table.concat(names, ", ")
  end
  if #s.rewards > 0 then
    found = true
    local names = {}
    for i = 1, math.min(#s.rewards, Q.MAX_LIST) do names[i] = s.rewards[i].name .. " (quest:" .. s.rewards[i].id .. ")" end
    lines[#lines + 1] = AA.C.head .. "Quest reward from:|r " .. table.concat(names, "; ")
  end
  if s.startQuest then
    found = true
    lines[#lines + 1] = AA.C.head .. "Starts a quest:|r " .. (get("Quest", s.startQuest, "name") or ("quest " .. s.startQuest))
  end
  if found then
    if #s.drops > 0 then lines[#lines + 1] = AA.C.src .. "Drop rates aren't shown: I don't have a verified source for them.|r" end
    lines[#lines + 1] = AA.C.src .. "Coordinates are zone-map percentages (same as the world map), from Questie's database.|r"
  end
  return lines, found
end

-- Quest giver / turn-in / prerequisites, according to Questie.
function Q.QuestLines(questId)
  if not Q.DB() or not questId then return {}, false end
  local lines, found = {}, false
  local function people(title, by)
    if type(by) ~= "table" then return end
    local list = {}
    for _, id in ipairs(by[1] or {}) do local e = describe("Npc", id); if e then list[#list + 1] = e end end
    for _, id in ipairs(by[2] or {}) do local e = describe("Object", id); if e then list[#list + 1] = e end end
    for _, id in ipairs(by[3] or {}) do
      local n = get("Item", id, "name")
      if n then list[#list + 1] = { name = "item: " .. n, coords = {}, spawnCount = 0 } end
    end
    if #list == 0 then return end
    found = true
    lines[#lines + 1] = AA.C.head .. title .. "|r"
    for i = 1, math.min(#list, 3) do lines[#lines + 1] = "  " .. entryLine(list[i]) end
  end
  people("Quest giver:", get("Quest", questId, "startedBy"))
  people("Turn in to:", get("Quest", questId, "finishedBy"))
  local req = get("Quest", questId, "requiredLevel")
  if tonumber(req) and req > 0 then lines[#lines + 1] = "Required level: " .. req; found = true end
  local pre = {}
  for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
    for _, pid in ipairs(get("Quest", questId, field) or {}) do
      local n = get("Quest", pid, "name")
      if n then pre[#pre + 1] = n end
    end
  end
  if #pre > 0 then
    found = true
    lines[#lines + 1] = "Prerequisite quests: " .. table.concat(pre, ", ", 1, math.min(#pre, 5))
  end
  if found then
    lines[#lines + 1] = AA.C.src .. "From Questie's database. Coordinates are zone-map percentages; Questie's map pins show objectives.|r"
  end
  return lines, found
end

-- Exact-name lookups (Questie builds its name index on first use, which can take a moment).
local SMALL = { ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true, ["and"] = true, ["in"] = true,
  ["on"] = true, ["to"] = true, ["for"] = true, ["from"] = true, ["with"] = true, ["de"] = true }

local function nameVariants(name)
  name = AA.Trim(name or "")
  local out, seen = {}, {}
  local function add(s) if s ~= "" and not seen[s] then seen[s] = true out[#out + 1] = s end end
  add(name)
  local all, title = {}, {}
  local i = 0
  for word in name:gmatch("%S+") do
    i = i + 1
    local cap = word:sub(1, 1):upper() .. word:sub(2):lower()
    all[#all + 1] = cap
    title[#title + 1] = (i > 1 and SMALL[word:lower()]) and word:lower() or cap
  end
  add(table.concat(title, " "))
  add(table.concat(all, " "))
  return out
end
Q.NameVariants = nameVariants

function Q.IdsByName(kind, name)
  local db = Q.DB()
  if not db or type(db[kind].IdsByName) ~= "function" then return nil end
  for _, variant in ipairs(nameVariants(name)) do
    local ok, ids = pcall(db[kind].IdsByName, variant)
    if ok and type(ids) == "table" and #ids > 0 then return ids, variant end
  end
  return nil
end

function Q.LocationHint()
  if Q.IsLoaded() then
    return "Questie is loaded: its world-map pins and quest tooltips show objective locations."
  end
  return nil
end

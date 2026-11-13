-- Azeroth Familiar - Modules/Stats.lua
-- Read-only character, bag, location and performance facts, plus session tracking.
-- Event-driven: nothing here runs per frame. Every API is looked up with AA.Api and
-- called through pcall, so a missing one shows as "n/a" instead of raising an error.
-- Health and power can be "secret" during combat on this engine; AA.Num turns those
-- into nil and the pages show "hidden in combat".
-- None of these calls has been confirmed in the WoW Forever client yet (see /aa diag).

local ADDON, AA = ...
local St = {}
AA.Stats = St

local function call(ns, fn, ...)
  local f
  if fn == nil then f = AA.Api(ns) else f = AA.Api(ns, fn) end
  if not f then return false end
  return pcall(f, ...)
end
-- global function with arguments: g("UnitXP", "player")
local function g(name, ...)
  local f = AA.Api(name)
  if not f then return false end
  return pcall(f, ...)
end

-- Money ----------------------------------------------------------------------
function St.Money()
  local ok, m = g("GetMoney")
  return ok and AA.Num(m) or nil
end

function St.MoneyText(c)
  c = tonumber(c)
  if not c then return "n/a" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local gold, silver, copper = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = "|cffffd100" .. gold .. "g|r" end
  if silver > 0 or gold > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. "s|r" end
  parts[#parts + 1] = "|cffeda55f" .. copper .. "c|r"
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- Durability -----------------------------------------------------------------
-- Returns overall percent (or nil if nothing has durability), and a list of
-- { slot, link, pct } sorted most-worn first.
function St.Durability()
  local f = AA.Api("GetInventoryItemDurability")
  if not f then return nil, {} end
  local cur, max, list = 0, 0, {}
  for slot = 1, 19 do
    local ok, c, m = pcall(f, slot)
    c, m = ok and AA.Num(c), ok and AA.Num(m)
    if c and m and m > 0 then
      cur, max = cur + c, max + m
      local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
      list[#list + 1] = { slot = slot, link = link, pct = c / m * 100 }
    end
  end
  table.sort(list, function(a, b) return a.pct < b.pct end)
  if max == 0 then return nil, list end
  return cur / max * 100, list
end

-- Bags -----------------------------------------------------------------------
-- Returns free, total for the backpack and the four bag slots.
function St.Bags()
  local numSlots = AA.Api("C_Container", "GetContainerNumSlots")
  local numFree = AA.Api("C_Container", "GetContainerNumFreeSlots")
  if not (numSlots and numFree) then return nil, nil end
  local free, total = 0, 0
  for bag = 0, (tonumber(NUM_BAG_SLOTS) or 4) do
    local ok, n = pcall(numSlots, bag)
    local ok2, f = pcall(numFree, bag)
    total = total + ((ok and AA.Num(n)) or 0)
    free = free + ((ok2 and AA.Num(f)) or 0)
  end
  return free, total
end

-- Poor-quality (grey) items with a vendor price. Returns list, totalCopper.
function St.Junk()
  local out, total = {}, 0
  local getInfo = AA.Api("C_Container", "GetContainerItemInfo")
  local itemInfo = AA.Api("C_Item", "GetItemInfo")
  if not (getInfo and AA.Search) then return out, 0 end
  for _, e in ipairs((AA.Search.ScanBags())) do
    local ok, info = pcall(getInfo, e.bag, e.slot)
    if ok and type(info) == "table" and info.quality == 0 and not info.hasNoValue then
      local price = 0
      if itemInfo and e.link then
        local okP, _, _, _, _, _, _, _, _, _, _, sell = pcall(itemInfo, e.link)
        price = (okP and AA.Num(sell)) or 0
      end
      local value = price * (e.count or 1)
      total = total + value
      out[#out + 1] = { name = e.name or "?", link = e.link, count = e.count or 1, value = value }
    end
  end
  table.sort(out, function(a, b) return a.value > b.value end)
  return out, total
end

-- Location -------------------------------------------------------------------
function St.Zone()
  local ok, zone = g("GetRealZoneText")
  local ok2, sub = g("GetSubZoneText")
  zone = ok and AA.Str(zone) or nil
  sub = ok2 and AA.Str(sub) or nil
  if sub == "" or sub == zone then sub = nil end
  return zone, sub
end

-- Returns mapID, x, y (0-100), mapName. x/y are nil where the game gives no position
-- (inside dungeons, for example).
function St.Coords()
  local ok, mapID = call("C_Map", "GetBestMapForUnit", "player")
  mapID = ok and AA.Num(mapID) or nil
  if not mapID then return nil end
  local name
  local okI, info = call("C_Map", "GetMapInfo", mapID)
  if okI and type(info) == "table" then name = AA.Str(info.name) end
  local okP, pos = call("C_Map", "GetPlayerMapPosition", mapID, "player")
  if okP and pos and pos.GetXY then
    local okX, x, y = pcall(pos.GetXY, pos)
    x, y = okX and AA.Num(x), okX and AA.Num(y)
    if x and y then return mapID, x * 100, y * 100, name end
  end
  return mapID, nil, nil, name
end

function St.CoordText()
  local _, x, y = St.Coords()
  if not x then return nil end
  return string.format("%.1f, %.1f", x, y)
end

-- Performance ----------------------------------------------------------------
function St.FPS()
  local ok, f = g("GetFramerate")
  return ok and AA.Num(f) or nil
end

-- Returns home, world latency in ms.
function St.Latency()
  local ok, _, _, home, world = g("GetNetStats")
  if not ok then return nil, nil end
  return AA.Num(home), AA.Num(world)
end

-- Rolling FPS average over the last minute of samples (taken only while something
-- that shows FPS is on screen).
local samples, sampleAt = {}, 0
function St.SampleFPS()
  local now = GetTime and GetTime() or 0
  local fps = St.FPS()
  if fps and now - sampleAt >= 0.9 then
    sampleAt = now
    samples[#samples + 1] = fps
    if #samples > 60 then table.remove(samples, 1) end
  end
  return fps
end
function St.AverageFPS()
  if #samples < 5 then return nil end
  local sum = 0
  for i = 1, #samples do sum = sum + samples[i] end
  return sum / #samples, #samples
end

-- Character ------------------------------------------------------------------
function St.Unit(unit)
  local okN, name = g("UnitName", unit)
  local okL, level = g("UnitLevel", unit)
  local okC, class = g("UnitClass", unit)
  local okR, race = g("UnitRace", unit)
  return {
    name = okN and AA.Str(name) or nil,
    level = okL and AA.Num(level) or nil,
    class = okC and AA.Str(class) or nil,
    race = okR and AA.Str(race) or nil,
  }
end

-- Head icon matching a unit's race and gender (the game's own "head" item icons:
-- _01 male, _02 female). Unknown races fall back to the human head.
local RACE_HEADS = {
  Human = "Human", Dwarf = "Dwarf", Gnome = "Gnome", NightElf = "Elf",
  Orc = "Orc", Troll = "Troll", Tauren = "Tauren", Scourge = "Undead", Undead = "Undead",
}
function St.RaceIcon(unit)
  unit = unit or "player"
  local okR, _, raceFile = g("UnitRace", unit)
  local okS, sex = g("UnitSex", unit)
  local head = okR and RACE_HEADS[AA.Str(raceFile) or ""] or "Human"
  local female = okS and AA.Num(sex) == 3
  return "Interface\\Icons\\INV_Misc_Head_" .. head .. (female and "_02" or "_01")
end

-- Returns cur, max or nil when hidden (combat) or unavailable.
function St.Health(unit)
  local ok, c = g("UnitHealth", unit or "player")
  local ok2, m = g("UnitHealthMax", unit or "player")
  c, m = ok and AA.Num(c), ok2 and AA.Num(m)
  if c and m and m > 0 then return c, m end
end
function St.Power(unit)
  local ok, c = g("UnitPower", unit or "player")
  local ok2, m = g("UnitPowerMax", unit or "player")
  c, m = ok and AA.Num(c), ok2 and AA.Num(m)
  if c and m and m > 0 then return c, m end
end

-- Returns cur, max, rested (rested may be nil). nil at max level.
function St.XP()
  local ok, c = g("UnitXP", "player")
  local ok2, m = g("UnitXPMax", "player")
  c, m = ok and AA.Num(c), ok2 and AA.Num(m)
  if not (c and m) or m <= 0 then return nil end
  local ok3, r = g("GetXPExhaustion")
  return c, m, ok3 and AA.Num(r) or nil
end

function St.Target()
  local ok, exists = g("UnitExists", "target")
  if not ok or AA.IsSecret(exists) or not exists then return nil end
  local t = St.Unit("target")
  local okP, isPlayer = g("UnitIsPlayer", "target")
  t.isPlayer = okP and not AA.IsSecret(isPlayer) and isPlayer and true or false
  local okK, kind = g("UnitClassification", "target")
  t.kind = okK and AA.Str(kind) or nil
  local okT, ctype = g("UnitCreatureType", "target")
  t.creature = okT and AA.Str(ctype) or nil
  local c, m = St.Health("target")
  t.healthPct = c and m and (c / m * 100) or nil
  return t
end

function St.Duration(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
  if h > 0 then return string.format("%dh %02dm", h, m) end
  if m > 0 then return string.format("%dm", m) end
  return sec .. "s"
end

-- Session --------------------------------------------------------------------
-- Stored per character. A /reload (the companion uses them) or a short break keeps
-- the same session; more than 15 minutes away starts a new one.
local SESSION_GAP = 15 * 60
local lastMoney, lastXP, lastXPMax

local function newSession()
  return { start = time(), lastSeen = time(), xp = 0, levels = 0, goldIn = 0, goldOut = 0 }
end

function St.Session()
  local c = AA.charDB
  if type(c.session) ~= "table" then c.session = newSession() end
  return c.session
end

function St.ResetSession()
  AA.charDB.session = newSession()
  lastMoney = St.Money()
  lastXP, lastXPMax = St.XP()
end

-- Summary numbers for the pages.
function St.SessionSummary()
  local s = St.Session()
  local len = math.max(1, time() - (tonumber(s.start) or time()))
  local perHour = s.xp > 0 and (s.xp / len * 3600) or nil
  local cur, max = St.XP()
  local toLevel
  if perHour and cur and max and perHour > 0 then toLevel = (max - cur) / perHour * 3600 end
  return { length = len, xp = s.xp, levels = s.levels, xpPerHour = perHour, toLevel = toLevel,
    goldIn = s.goldIn, goldOut = s.goldOut, net = s.goldIn - s.goldOut }
end

AA:On("PLAYER_LOGIN", function()
  local s = AA.charDB.session
  if type(s) ~= "table" or (time() - (tonumber(s.lastSeen) or 0)) > SESSION_GAP then
    AA.charDB.session = newSession()
  end
  lastMoney = St.Money()
  lastXP, lastXPMax = St.XP()
end)

-- Gold and experience can still read as zero at login, so the starting points are taken
-- again once the world has loaded. Zoning never changes either, so nothing is missed.
AA:On("PLAYER_ENTERING_WORLD", function()
  lastMoney = St.Money()
  lastXP, lastXPMax = St.XP()
end)

AA:On("PLAYER_LOGOUT", function()
  if AA.charDB and type(AA.charDB.session) == "table" then AA.charDB.session.lastSeen = time() end
end)

AA:On("PLAYER_MONEY", function()
  local now = St.Money()
  if now and lastMoney then
    local s = St.Session()
    if now > lastMoney then s.goldIn = s.goldIn + (now - lastMoney)
    elseif now < lastMoney then s.goldOut = s.goldOut + (lastMoney - now) end
  end
  lastMoney = now or lastMoney
end)

AA:On("PLAYER_XP_UPDATE", function()
  local cur, max = St.XP()
  if not cur then return end
  local s = St.Session()
  if lastXP then
    if cur >= lastXP and max == lastXPMax then
      s.xp = s.xp + (cur - lastXP)
    elseif lastXPMax then
      s.xp = s.xp + (lastXPMax - lastXP) + cur -- levelled up: rest of the old bar + the new one
    end
  end
  lastXP, lastXPMax = cur, max
end)

AA:On("PLAYER_LEVEL_UP", function()
  local s = St.Session()
  s.levels = s.levels + 1
end)

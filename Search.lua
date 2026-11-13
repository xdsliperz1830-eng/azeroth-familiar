-- Azeroth Familiar - Search.lua
-- Searches only what the client exposes right now: bags, equipped items, quest log,
-- and recipe lists the player has opened (snapshotted with a timestamp).
-- Bags are scanned lazily: events only mark the cache dirty, nothing runs per frame.

local ADDON, AA = ...
local S = {}
AA.Search = S

local bagCache, bagDirty, bagScannedAt = nil, true, nil

AA:On("BAG_UPDATE_DELAYED", function() bagDirty = true end)
AA:On("PLAYER_ENTERING_WORLD", function() bagDirty = true end)

local function bagRange()
  local last = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
  if last < 4 then last = 4 end
  return 0, last
end

local function nameFromLink(link)
  return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

function S.ItemName(itemID, link)
  local n = nameFromLink(link)
  if n then return n end
  local ok, name = AA.Try(AA.Api("C_Item", "GetItemNameByID"), itemID)
  if ok and AA.Str(name) then return name end
  return nil
end

function S.ScanBags()
  if bagCache and not bagDirty then return bagCache, bagScannedAt end
  local numSlots = AA.Api("C_Container", "GetContainerNumSlots")
  local getInfo = AA.Api("C_Container", "GetContainerItemInfo")
  local list = {}
  if not (numSlots and getInfo) then return list, nil, "bag API not available" end
  local first, last = bagRange()
  for bag = first, last do
    local ok, n = pcall(numSlots, bag)
    n = ok and AA.Num(n) or 0
    for slot = 1, n do
      local okI, info = pcall(getInfo, bag, slot)
      if okI and type(info) == "table" and info.itemID then
        list[#list + 1] = {
          bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
          count = AA.Num(info.stackCount) or 1,
          name = S.ItemName(info.itemID, info.hyperlink),
        }
      end
    end
  end
  bagCache, bagDirty, bagScannedAt = list, false, time()
  return list, bagScannedAt
end

function S.BagCount(itemID)
  local total = 0
  for _, e in ipairs((S.ScanBags())) do
    if e.itemID == itemID then total = total + e.count end
  end
  return total
end

-- query: { itemID = n } or { term = "medium leather" }
-- Returns grouped results: { {itemID, name, link, count, stacks}, ... }
function S.FindInBags(query)
  local groups, order = {}, {}
  local term = query.term and query.term:lower() or nil
  for _, e in ipairs((S.ScanBags())) do
    local match = false
    if query.itemID then
      match = (e.itemID == query.itemID)
    elseif term and e.name then
      match = e.name:lower():find(term, 1, true) ~= nil
    end
    if match then
      local g = groups[e.itemID]
      if not g then
        g = { itemID = e.itemID, name = e.name, link = e.link, count = 0, stacks = 0 }
        groups[e.itemID] = g
        order[#order + 1] = g
      end
      g.count = g.count + e.count
      g.stacks = g.stacks + 1
    end
  end
  table.sort(order, function(a, b) return (a.name or "") < (b.name or "") end)
  return order
end

function S.FindEquipped(query)
  local out = {}
  local term = query.term and query.term:lower() or nil
  for _, e in ipairs(AA.Context.Equipment()) do
    local id = tonumber(e.link:match("item:(%d+)"))
    if (query.itemID and id == query.itemID) or (term and e.name and e.name:lower():find(term, 1, true)) then
      out[#out + 1] = e
    end
  end
  return out
end

function S.FindQuests(term)
  local out = {}
  term = term and term:lower() or ""
  if term == "" then return out end
  for _, q in ipairs(AA.Context.QuestLog()) do
    local hit = q.title:lower():find(term, 1, true)
    if not hit then
      for _, o in ipairs(q.objectives) do
        if o.text:lower():find(term, 1, true) then hit = true break end
      end
    end
    if hit then out[#out + 1] = q end
  end
  return out
end

-- Recipe snapshots -------------------------------------------------------------
-- The client only lists recipes while a profession window is open. When that happens
-- we save the known recipes and their reagents per character, with the time observed.
-- These calls follow the modern C_TradeSkillUI API and are UNVERIFIED on Forever;
-- every call is guarded and failures are recorded instead of raising errors.

local snapshotPending = false

local function snapshotRecipes()
  snapshotPending = false
  if not AA.charDB then return end
  local getIDs = AA.Api("C_TradeSkillUI", "GetAllRecipeIDs")
  local getInfo = AA.Api("C_TradeSkillUI", "GetRecipeInfo")
  if not (getIDs and getInfo) then
    AA.charDB.recipeError = "C_TradeSkillUI recipe API not available"
    return
  end
  local okB, base = AA.Try(AA.Api("C_TradeSkillUI", "GetBaseProfessionInfo"))
  local prof = okB and type(base) == "table" and AA.Str(base.professionName) or nil
  local okIDs, ids = pcall(getIDs)
  if not okIDs or type(ids) ~= "table" then
    AA.charDB.recipeError = "GetAllRecipeIDs failed"
    return
  end
  local getSchem = AA.Api("C_TradeSkillUI", "GetRecipeSchematic")
  local getOut = AA.Api("C_TradeSkillUI", "GetRecipeOutputItemData")
  local list = {}
  for i = 1, math.min(#ids, 800) do
    local rid = ids[i]
    local ok, info = pcall(getInfo, rid)
    if ok and type(info) == "table" and info.learned and AA.Str(info.name) then
      local r = { id = rid, name = info.name, reagents = {} }
      if getOut then
        local okO, out = pcall(getOut, rid)
        if okO and type(out) == "table" then r.outputItemID = out.itemID end
      end
      if getSchem then
        local okS, sch = pcall(getSchem, rid, false)
        if okS and type(sch) == "table" then
          r.outputItemID = r.outputItemID or sch.outputItemID
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local first = slot.reagents and slot.reagents[1]
            if first and first.itemID then
              r.reagents[#r.reagents + 1] = { itemID = first.itemID, qty = AA.Num(slot.quantityRequired) or 1 }
            end
          end
        end
      end
      list[#list + 1] = r
    end
  end
  if #list > 0 then
    prof = prof or "Profession"
    AA.charDB.recipes[prof] = { observed = time(), list = list }
    AA.charDB.recipeError = nil
  end
end

local function queueSnapshot()
  if snapshotPending then return end
  snapshotPending = true
  C_Timer.After(1.0, function()
    local ok, err = pcall(snapshotRecipes)
    if not ok and AA.charDB then AA.charDB.recipeError = tostring(err) end
  end)
end

AA:On("TRADE_SKILL_SHOW", queueSnapshot)
AA:On("TRADE_SKILL_LIST_UPDATE", queueSnapshot)

-- Finds a known recipe by output item ID or by name.
function S.FindRecipe(itemID, term)
  if not AA.charDB then return nil end
  term = term and term:lower() or nil
  for prof, snap in pairs(AA.charDB.recipes) do
    for _, r in ipairs(snap.list or {}) do
      if (itemID and r.outputItemID == itemID) or (term and term ~= "" and r.name:lower():find(term, 1, true)) then
        return r, prof, snap.observed
      end
    end
  end
  return nil
end

function S.RecipeSummary()
  local out = {}
  if not AA.charDB then return out end
  for prof, snap in pairs(AA.charDB.recipes) do
    out[#out + 1] = { prof = prof, count = #(snap.list or {}), observed = snap.observed }
  end
  return out
end

-- Azeroth Familiar - Assistant.lua
-- Deterministic question router for the offline assistant. Every answer is labeled
-- with its source. Questions the client can't answer get an honest "not available
-- offline" plus a Wowhead link and an [Ask AI] option.

local ADDON, AA = ...
local A = {}
AA.Assistant = A

local MAX_QUESTION = 500

local function kw(w, list)
  for _, word in ipairs(list) do
    if w:find("%f[%w]" .. word .. "%f[%W]") then return true end
  end
  return false
end

local K = {
  help = { "help", "what can you do", "commands" },
  search = { "search", "find", "my bags", "in bags", "inventory", "do i have", "how many", "have i got", "carrying" },
  source = { "vendor", "vendors", "sells", "sold", "buy", "drops", "drop", "farm", "where can i get",
    "where do i get", "where to get", "where can i find", "where do i find", "where to find", "where can i buy",
    "how do i get", "how to get", "price", "cost", "auction", "trainer", "learn", "comes from", "come from" },
  craft = { "craft", "crafting", "materials", "mats", "reagents", "reagent", "make", "recipe", "need to make" },
  upgrade = { "upgrade", "better", "equipped", "equip", "compare", "vs", "versus", "worth", "replace", "should i use" },
  where = { "where", "go", "location", "coords", "coordinates", "find", "turn in" },
  quest = { "quest", "quests", "objective", "objectives", "quest log" },
  profession = { "profession", "professions", "skill", "skills", "recipes" },
  purpose = { "what is this for", "what is it for", "what's this for", "whats this for", "used for", "use for",
    "use it for", "use this for", "what does it do", "what does this do", "what is this", "what is it", "uses",
    "good for", "need this", "need it", "keep this", "keep it", "sell this", "vendor this" },
  npc = { "where is", "where's", "wheres", "location of", "find npc" },
  -- words that point back at links from the previous question
  pronoun = { "this", "that", "it", "these", "those", "them", "they", "both", "one" },
}

local STOP = {}
for _, w in ipairs({ "search", "find", "look", "for", "my", "in", "inventory", "do", "i", "have",
  "how", "many", "any", "the", "a", "an", "of", "got", "is", "there", "are", "items", "item", "show", "me",
  "carrying", "quest", "quests", "log", "list", "about", "what", "which", "please", "can", "you",
  "this", "that", "it", "these", "those", "them", "they", "its", "does", "used", "use", "with", "to", "where",
  "go", "get", "should", "be", "was", "why", "who", "when", "or", "and", "on", "at", "need", "good", "whats",
  "s", "one", "both", "tell", "explain" }) do
  STOP[w] = true
end

-- extra: additional words to drop (e.g. "bags" when searching, but not from item names like "Sleeping Bag")
local function termFrom(w, extra)
  local kept = {}
  for word in w:gmatch("%S+") do
    if not STOP[word] and not (extra and extra[word]) then kept[#kept + 1] = word end
  end
  return table.concat(kept, " ")
end
local SEARCH_EXTRA = { bags = true, bag = true, backpack = true }

local function askLink() return AA.Quests.AskLink() end

-- Item helpers -------------------------------------------------------------------
local function itemHeader(label, f)
  local parts = {}
  if f.ilvl then parts[#parts + 1] = "item level " .. f.ilvl end
  if f.reqLevel and f.reqLevel > 0 then
    local myLevel = AA.Num(UnitLevel("player"))
    local s = "requires level " .. f.reqLevel
    if myLevel and f.reqLevel > myLevel then s = AA.C.bad .. s .. "|r" end
    parts[#parts + 1] = s
  end
  if f.subType and f.subType ~= "" then parts[#parts + 1] = f.subType end
  local slotName = f.equipLoc and f.equipLoc ~= "" and _G[f.equipLoc]
  if type(slotName) == "string" then parts[#parts + 1] = slotName end
  local line = (label and (AA.C.head .. label .. "|r = ") or "") .. (f.link or f.name or "?")
  if #parts > 0 then line = line .. " - " .. table.concat(parts, ", ") end
  local out = { line }
  if f.uncached then out[#out + 1] = AA.C.warn .. "Item data is still loading from the server; ask again in a moment for full stats.|r" end
  for _, r in ipairs(f.redLines or {}) do
    out[#out + 1] = AA.C.bad .. "Tooltip shows an unmet requirement: " .. AA.PlainText(r) .. "|r"
  end
  return out
end

local function append(dst, src) for _, l in ipairs(src) do dst[#dst + 1] = l end end

-- Offline "what is this used for": known recipes that use it, and quest-log objectives
-- that mention it. Everything else needs an external source.
local function usageLines(f)
  local lines = {}
  local recipes = {}
  if f.id and AA.charDB then
    for prof, snap in pairs(AA.charDB.recipes) do
      for _, r in ipairs(snap.list or {}) do
        for _, rg in ipairs(r.reagents or {}) do
          if rg.itemID == f.id then
            recipes[#recipes + 1] = r.name .. " (" .. prof .. ", needs " .. rg.qty .. ")"
            break
          end
        end
      end
    end
  end
  table.sort(recipes)
  if #recipes > 0 then
    local shown = {}
    for i = 1, math.min(#recipes, 8) do shown[i] = recipes[i] end
    lines[#lines + 1] = AA.C.head .. "Used in recipes you know:|r " .. table.concat(shown, "; ") ..
      (#recipes > 8 and (" and " .. (#recipes - 8) .. " more") or "")
  end
  local name = f.name and f.name:lower()
  if name then
    for _, q in ipairs(AA.Context.QuestLog()) do
      for _, o in ipairs(q.objectives) do
        if o.text:lower():find(name, 1, true) then
          lines[#lines + 1] = AA.C.head .. "Needed for a quest in your log:|r " .. q.title .. " - " .. AA.PlainText(o.text)
          break
        end
      end
    end
  end
  if #lines == 0 then
    lines[#lines + 1] = "None of your known recipes or current quests use it" ..
      ((AA.charDB and next(AA.charDB.recipes)) and "." or " (I haven't seen your recipe lists yet; open each profession window once).")
  end
  lines[#lines + 1] = AA.C.warn .. "Other uses (class spells, recipes you don't know, quests you don't have) aren't visible to addons.|r"
  return lines
end

local function itemSummary(link, withUsage)
  AA.Compare.EnsureLoaded({ link.link }, function()
    local f = AA.Compare.ItemFacts(link.link)
    local lines = itemHeader(nil, f)
    for _, d in ipairs(f.descLines or {}) do lines[#lines + 1] = AA.C.src .. AA.PlainText(d) .. "|r" end
    local stats = {}
    for k, v in pairs(f.stats) do
      if k ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then stats[#stats + 1] = "+" .. v .. " " .. AA.Compare.StatLabel(k) end
    end
    table.sort(stats)
    if #stats > 0 then lines[#lines + 1] = "Stats: " .. table.concat(stats, ", ") end
    if f.dps then
      lines[#lines + 1] = string.format("Weapon: %.1f DPS%s", f.dps, f.speed and string.format(", speed %.2f", f.speed) or "")
    end
    for _, e in ipairs(f.effects) do
      lines[#lines + 1] = AA.PlainText(e.text) .. (e.kind == "Proc" and " (proc rate unknown)" or "") ..
        (e.conditional and (AA.C.warn .. " (only vs " .. e.conditional .. ")|r") or "")
    end
    if f.id then
      local n = AA.Search.BagCount(f.id)
      if n > 0 then lines[#lines + 1] = "You carry " .. n .. " in your bags." end
    end
    if withUsage then
      for _, l in ipairs(usageLines(f)) do lines[#lines + 1] = l end
    end
    if f.id then lines[#lines + 1] = AA.Wowhead.Link("item", f.id, f.name) .. "  " .. askLink() end
    if not withUsage then
      lines[#lines + 1] = AA.C.src .. "Tip: ask \"is this an upgrade?\" or \"what is this for?\" - I'll remember the item you just linked.|r"
    end
    AA:Reply(withUsage and "Offline - item data, your recipes and quest log" or "Offline - item data from your game client", lines)
  end)
end

local function compareTwo(l1, l2)
  AA.Compare.EnsureLoaded({ l1.link, l2.link }, function()
    local fa, fb = AA.Compare.ItemFacts(l1.link), AA.Compare.ItemFacts(l2.link)
    local lines = {}
    append(lines, itemHeader("A", fa))
    append(lines, itemHeader("B", fb))
    if fa.equipLoc and fb.equipLoc and fa.equipLoc ~= fb.equipLoc then
      lines[#lines + 1] = AA.C.warn .. "These go in different slots, so the comparison is only partly meaningful.|r"
    end
    local a, b = AA.Compare.Combine({ fa }), AA.Compare.Combine({ fb })
    append(lines, AA.Compare.Diff("A", a, "B", b))
    append(lines, AA.Compare.Guidance(a, b, "A", "B"))
    AA:Reply("Offline - item data from your game client", lines)
  end)
end

local function compareEquipped(link)
  AA.Compare.EnsureLoaded({ link.link }, function()
    local f = AA.Compare.ItemFacts(link.link)
    local slots = f.equipLoc and AA.Compare.EQUIP_SLOTS[f.equipLoc]
    local lines = itemHeader("New", f)
    if not slots then
      lines[#lines + 1] = "This item isn't equippable, or the client didn't report its slot."
      AA:Reply("Offline - item data from your game client", lines)
      return
    end
    local function equippedFacts(slot)
      local l = GetInventoryItemLink("player", slot)
      if not l or AA.IsSecret(l) then return nil end
      return AA.Compare.ItemFacts(l)
    end
    local comparisons = {}
    if f.equipLoc == "INVTYPE_2HWEAPON" then
      local mh, oh = equippedFacts(16), equippedFacts(17)
      local list = {}
      if mh then list[#list + 1] = mh end
      if oh then list[#list + 1] = oh end
      comparisons[#comparisons + 1] = { label = oh and "main hand + off hand" or "main hand", list = list }
      if oh then lines[#lines + 1] = AA.C.warn .. "A two-hander replaces both your main hand and off hand, so both are counted.|r" end
    else
      for _, slot in ipairs(slots) do
        local e = equippedFacts(slot)
        comparisons[#comparisons + 1] = { label = AA.Context.SLOT_NAME[slot] or ("slot " .. slot), list = e and { e } or {} }
        if f.equipLoc == "INVTYPE_WEAPON" then break end -- one-hander: compare with main hand
      end
      if f.equipLoc == "INVTYPE_WEAPON" or f.equipLoc == "INVTYPE_WEAPONMAINHAND" then
        local mh = equippedFacts(16)
        if mh and mh.equipLoc == "INVTYPE_2HWEAPON" then
          lines[#lines + 1] = AA.C.warn .. "You're using a two-hander now; a one-hander also frees the off-hand slot (shield or off-hand weapon, if your class can use one).|r"
        end
      end
    end
    local new = AA.Compare.Combine({ f })
    for _, c in ipairs(comparisons) do
      if #c.list == 0 then
        lines[#lines + 1] = "Your " .. c.label .. " slot is empty, so any usable item there adds its full stats."
      else
        local cur = AA.Compare.Combine(c.list)
        local names = {}
        for _, x in ipairs(c.list) do names[#names + 1] = x.link or x.name end
        lines[#lines + 1] = AA.C.head .. "Current " .. c.label .. ":|r " .. table.concat(names, " + ")
        append(lines, AA.Compare.Diff("New", new, "Current", cur))
        append(lines, AA.Compare.Guidance(new, cur, "New", "Current"))
      end
    end
    AA:Reply("Offline - item data and your equipped gear, live", lines)
  end)
end

local function searchAnswer(items, w)
  local q
  if items[1] then q = { itemID = items[1].id } else q = { term = termFrom(w, SEARCH_EXTRA) } end
  if not q.itemID and (not q.term or q.term == "") then
    AA:Reply("Offline", "What should I search for? Example: \"search my bags for Medium Leather\", or shift-click an item into the box.")
    return
  end
  local bag = AA.Search.FindInBags(q)
  local eq = AA.Search.FindEquipped(q)
  local lines = {}
  for _, g in ipairs(bag) do
    lines[#lines + 1] = (g.link or g.name or ("item:" .. g.itemID)) .. " x" .. g.count ..
      (g.stacks > 1 and (" (" .. g.stacks .. " stacks)") or "") .. " - bags"
  end
  for _, e in ipairs(eq) do lines[#lines + 1] = e.link .. " - equipped (" .. e.slotName .. ")" end
  local label = items[1] and (items[1].name or ("item " .. items[1].id)) or ("\"" .. q.term .. "\"")
  if #lines == 0 then
    lines[1] = "No match for " .. label .. " in your bags or equipped items."
  end
  lines[#lines + 1] = AA.C.src .. "Bank, mail and other characters aren't searched in this version.|r"
  AA:Reply("Offline - bags and equipped items, live", lines)
end

-- Hands a question the addon can't answer offline to the desktop companion (if it's set up).
-- Returns true if the question was sent (the UI reloads right after).
local PERSONAL = { "my", "me", "i", "talent", "talents", "spec", "build", "gear", "upgrade", "level", "should" }
local function escalate(intro)
  if not (AA.Companion and AA.Companion.AutoEnabled()) then return false end
  local text = A.currentText or ""
  local lines = { (intro and (intro .. " ") or "") .. "Asking Mrgl (Azeroth Companion)... your UI reloads once to send it; the answer pops up in the companion window." }
  if not AA.db.settings.allowContext and kw(" " .. AA.Links.StripLinks(text):lower() .. " ", PERSONAL) then
    lines[#lines + 1] = AA.C.src .. "Tip: turn on \"AI questions: include my character\" in Settings so Mrgl knows your level and gear.|r"
  end
  AA:Reply("Sending to the companion", lines)
  return AA.Companion.SendNow(text, A.currentLinks)
end
A.Escalate = escalate

local function craftAnswer(items, w)
  local id = items[1] and items[1].id
  local term = not id and termFrom(w):gsub("%f[%w]craft%f[%W]", ""):gsub("%f[%w]materials%f[%W]", "") or nil
  local r, prof, observed = AA.Search.FindRecipe(id, term and AA.Trim(term) or nil)
  local lines = {}
  if r then
    lines[#lines + 1] = AA.C.head .. r.name .. "|r (" .. prof .. ", recipe list saved " .. date("%Y-%m-%d %H:%M", observed) .. ")"
    if #r.reagents == 0 then
      lines[#lines + 1] = "The client didn't report reagents for this recipe."
    end
    for _, rg in ipairs(r.reagents) do
      local have = AA.Search.BagCount(rg.itemID)
      local name = AA.Search.ItemName(rg.itemID) or ("item:" .. rg.itemID)
      local color = have >= rg.qty and AA.C.good or AA.C.warn
      lines[#lines + 1] = string.format("%s x%d - %syou have %d|r", name, rg.qty, color, have)
    end
    AA:Reply("Offline - your saved recipe list + bags", lines)
    return
  end
  if escalate("I don't know this recipe.") then return end
  lines[#lines + 1] = "I don't have this recipe. I can only see recipes your character knows, and only after you've opened that profession window once."
  local saved = AA.Search.RecipeSummary()
  if #saved > 0 then
    local parts = {}
    for _, s in ipairs(saved) do parts[#parts + 1] = s.prof .. " (" .. s.count .. ")" end
    lines[#lines + 1] = AA.C.src .. "Saved recipe lists: " .. table.concat(parts, ", ") .. "|r"
  end
  if AA.charDB and AA.charDB.recipeError then
    lines[#lines + 1] = AA.C.warn .. "Recipe reading problem on this client: " .. AA.charDB.recipeError .. "|r"
  end
  if id then lines[#lines + 1] = AA.Companion.SendLink() .. "  " .. AA.Wowhead.Link("item", id, items[1].name) .. "  " .. askLink()
  else lines[#lines + 1] = AA.Companion.SendLink() .. "  " .. AA.Wowhead.SearchLink(term or "") .. "  " .. askLink() end
  AA:Reply("Not available offline", lines)
end

-- Turns a typed item name into an item ID: your bags first, then the game's item cache,
-- then Questie's database (exact name, tried in a few capitalizations).
local function resolveItemByName(term)
  term = AA.Trim(term or "")
  if #term < 3 then return nil end
  local lower = term:lower()
  local bag = AA.Search.FindInBags({ term = lower })
  for _, g in ipairs(bag) do
    if g.name and g.name:lower() == lower then
      return { id = g.itemID, name = g.name, link = g.link, via = "your bags" }
    end
  end
  if #bag == 1 then return { id = bag[1].itemID, name = bag[1].name, link = bag[1].link, via = "your bags" } end
  for _, v in ipairs(AA.Questie.NameVariants(term)) do
    local ok, name, link = AA.Try(AA.Api("C_Item", "GetItemInfo"), v)
    if ok and AA.Str(name) and AA.Str(link) then
      local id = tonumber(link:match("item:(%d+)"))
      if id then return { id = id, name = name, link = link, via = "the game's item cache" } end
    end
  end
  local ids, variant = AA.Questie.IdsByName("Item", term)
  if ids then
    return { id = ids[1], name = variant, via = "Questie's database", others = #ids - 1 }
  end
  return nil
end

local function remember(target)
  local link = target.link
  if not link then
    local ok, _, l = AA.Try(AA.Api("C_Item", "GetItemInfo"), target.id)
    if ok and AA.Str(l) then link = l end
  end
  A.lastLinks = { { type = "item", id = target.id, name = target.name, link = link or ("item:" .. target.id) } }
end

local function sourceAnswer(items, w)
  local target
  if items[1] then
    target = { id = items[1].id, name = items[1].name, link = (not items[1].typed) and items[1].link or nil }
  else
    target = resolveItemByName(termFrom(w))
    if target then remember(target) end
  end
  local term = termFrom(w)
  if not target then
    if #term >= 3 and escalate("I couldn't find \"" .. term .. "\" offline.") then return end
    local lines = {}
    if #term >= 3 then
      lines[1] = "I couldn't find an item named \"" .. term .. "\" in your bags, the game's item cache" ..
        (AA.Questie.Available() and ", or Questie's database" or "") .. ". Check the spelling, or shift-click the item into the box."
      lines[2] = AA.Companion.SendLink() .. "  " .. AA.Wowhead.SearchLink(term) .. "  " .. askLink()
    else
      lines[1] = "Which item? Shift-click it into the box, or type its exact name."
    end
    AA:Reply("Offline", lines)
    return
  end
  target.name = target.name or AA.Questie.Get("Item", target.id, "name") or ("item " .. target.id)
  local lines = { AA.C.head .. (target.link or target.name) .. "|r" ..
    (target.via and (AA.C.src .. " (found in " .. target.via .. ")|r") or "") }
  if target.others and target.others > 0 then
    lines[#lines + 1] = AA.C.warn .. "There are " .. (target.others + 1) .. " items with this name; showing the first. Shift-click the exact one to be sure.|r"
  end
  local src
  if AA.Questie.Available() then
    local ql, found = AA.Questie.ItemSourceLines(target.id)
    if found then
      append(lines, ql)
      src = "Questie database (installed addon)"
    else
      if escalate("Questie has no source for " .. (target.link or target.name) .. ".") then return end
      lines[#lines + 1] = "Questie's database lists no vendor, drop, container or quest source for this item (it may be crafted, or new to Forever)."
      src = "Questie database - no source listed"
    end
  else
    if escalate() then return end
    local _, why = AA.Questie.DB()
    lines[#lines + 1] = "The game client doesn't tell addons where items come from, and Questie's database isn't available (" .. tostring(why) .. ")."
    src = "Not available offline"
  end
  if kw(w, { "price", "cost", "auction", "worth" }) then
    lines[#lines + 1] = AA.C.src .. "Auction prices: no verified live data source, so I won't guess one.|r"
  end
  lines[#lines + 1] = AA.Wowhead.Link("item", target.id, target.name) .. "  " .. askLink()
  AA:Reply(src, lines)
end

-- "where is <NPC>" through Questie's database.
local function npcAnswer(term)
  local ids, variant = AA.Questie.IdsByName("Npc", term)
  if not ids then return false end
  local lines = {}
  for i = 1, math.min(#ids, 3) do
    local e = AA.Questie.Describe("Npc", ids[i])
    if e then lines[#lines + 1] = AA.Questie.EntryLine(e) end
  end
  if #ids > 3 then lines[#lines + 1] = AA.C.src .. "...and " .. (#ids - 3) .. " more with this name.|r" end
  lines[#lines + 1] = AA.C.src .. "Coordinates are zone-map percentages (same as the world map).|r"
  lines[#lines + 1] = AA.Wowhead.Link("npc", ids[1], variant)
  AA:Reply("Questie database (installed addon)", lines)
  return true
end

local function professionAnswer()
  local lines = {}
  local profs = AA.Context.Professions()
  for _, p in ipairs(profs) do
    lines[#lines + 1] = p.name .. " " .. tostring(p.rank or "?") .. "/" .. tostring(p.max or "?")
  end
  if #lines == 0 then lines[1] = "The client reported no professions." end
  for _, s in ipairs(AA.Search.RecipeSummary()) do
    lines[#lines + 1] = AA.C.src .. s.prof .. ": " .. s.count .. " known recipes saved " .. date("%Y-%m-%d", s.observed) .. "|r"
  end
  AA:Reply("Offline - professions, live", lines)
end

local HELP_LINES = {
  "I answer from what your game client shows me. Talk to me here or in the Assistant chat tab. Try:",
  "- shift-click an item into the box, then ask \"is this an upgrade?\"",
  "- link two items: \"which is better for me?\"",
  "- \"search my bags for Medium Leather\"",
  "- shift-click a quest from your quest log: \"where do I go?\"",
  "- \"my quests\", \"quests wolf\", \"my professions\"",
  "- link a crafted item: \"what materials do I need?\" (after opening that profession once)",
  "- \"where can I get Medium Leather?\" or \"where is Innkeeper Firebrew?\" (uses Questie's database if installed)",
  "- follow-ups like \"what is this for?\" reuse the item you linked last",
  "- start with \"ai\" to always ask the AI, e.g. \"ai what talents should I take next?\"",
  "Anything I can't answer offline goes to the Azeroth Companion app if you run it; otherwise you get a Wowhead link and [Ask AI].",
}

-- Router -------------------------------------------------------------------------
function A.Route(text)
  -- "ai <question>" always goes to the AI (companion if set up, else the Ask AI box).
  local forced = text:match("^[Aa][Ii][:%s]+(.+)$") or text:match("^@[Aa][Ii][:%s]*(.+)$")
  if forced then
    A.currentText, A.currentLinks = forced, AA.Links.Extract(forced)
    if escalate() then return end
    if AA.UI then AA.UI.ShowAsk(forced) end
    return
  end
  local links = AA.Links.Extract(text)
  local w = AA.Links.StripLinks(text):lower()
  w = " " .. AA.Trim((w:gsub("[%?%!%.,;:\"]", " "))) .. " "
  -- Follow-up questions ("what is this for?") reuse the links from the previous question.
  if #links == 0 and A.lastLinks and kw(w, K.pronoun) then
    links = A.lastLinks
    local names = {}
    for _, l in ipairs(links) do
      names[#names + 1] = (l.link and l.link:find("|H", 1, true)) and l.link or ("[" .. (l.name or (l.type .. " " .. tostring(l.id))) .. "]")
    end
    AA:System("   (about " .. table.concat(names, ", ") .. " from your last question)")
  elseif #links > 0 then
    A.lastLinks = links
  end
  local items = AA.Links.OfType(links, "item")
  local quests = AA.Links.OfType(links, "quest")
  A.currentText, A.currentLinks = text, links

  if (#links == 0 and kw(w, K.help)) or AA.Trim(w) == "?" or AA.Trim(w) == "" and #links == 0 then
    AA:Reply("Offline - help", HELP_LINES)
    return
  end
  if #quests > 0 then
    for _, ql in ipairs(quests) do
      local src, lines = AA.Quests.Answer(ql, kw(w, K.where))
      AA:Reply(src, lines)
    end
    return
  end
  if kw(w, K.source) then
    sourceAnswer(items, w)
    return
  end
  if kw(w, K.search) and not kw(w, K.upgrade) and not kw(w, K.craft) then
    searchAnswer(items, w)
    return
  end
  if #items == 0 and kw(w, K.npc) and AA.Questie.Available() then
    local term = termFrom(w)
    if #term >= 3 then
      if npcAnswer(term) then return end
      local target = resolveItemByName(term)
      if target then remember(target); sourceAnswer({ { type = "item", id = target.id, name = target.name, link = target.link } }, w) return end
    end
  end
  if #items == 0 and kw(w, K.purpose) then
    local target = resolveItemByName(termFrom(w))
    if target then
      remember(target)
      itemSummary({ link = target.link or ("item:" .. target.id) }, true)
      return
    end
  end
  if kw(w, K.craft) then
    craftAnswer(items, w)
    return
  end
  if #items >= 2 then
    compareTwo(items[1], items[2])
    if #items > 2 then AA:Reply("Offline", "I compared the first two items; link at most two at a time.") end
    return
  end
  if #items == 1 then
    if kw(w, K.upgrade) then compareEquipped(items[1])
    else itemSummary(items[1], kw(w, K.purpose)) end
    return
  end
  if kw(w, K.profession) then
    professionAnswer()
    return
  end
  if kw(w, K.quest) then
    local src, lines = AA.Quests.Overview(termFrom(w))
    AA:Reply(src, lines)
    return
  end
  if escalate("I can't answer that offline.") then return end
  local term = termFrom(w)
  local lines = { "I can't answer that from game-client data alone." }
  lines[#lines + 1] = "Running the Azeroth Companion app? Click " .. AA.Companion.SendLink() .. " to send it there."
  if #term >= 3 then lines[#lines + 1] = "Or try a Wowhead search: " .. AA.Wowhead.SearchLink(term) end
  lines[#lines + 1] = "Or click " .. askLink() .. " to build a question you can paste into any AI chat."
  lines[#lines + 1] = AA.C.src .. "Type \"help\" to see what I can answer offline.|r"
  AA:Reply("Not available offline", lines)
end

function A.Ask(text)
  text = AA.Trim(text or "")
  if text == "" then return end
  if #text > MAX_QUESTION then text = text:sub(1, MAX_QUESTION) end
  -- A chat command typed into the assistant box is not a question: never send it to the companion.
  if text:sub(1, 1) == "/" then
    local cmd, rest = text:match("^/(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "aa" or cmd == "azerothassistant" then
      AA:Slash(rest)
    elseif cmd == "reload" or cmd == "rl" or cmd == "reloadui" then
      AA.Try(AA.Api("ReloadUI"))
    else
      AA:Reply("Not a question", "\"/" .. cmd .. "\" is a chat command, so I didn't look it up or send it anywhere. " ..
        "Type it in the normal chat box (click another chat tab first).")
    end
    return
  end
  A.lastQuestion = text
  AA:UserSays(text)
  local ok, err = pcall(A.Route, text)
  if not ok then
    AA:Reply("Error", AA.C.bad .. "Something went wrong answering that: " .. tostring(err) .. "|r")
  end
end

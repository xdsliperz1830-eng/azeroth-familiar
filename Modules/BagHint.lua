-- Azeroth Familiar - Modules/BagHint.lua
-- While a loot window is open and every bag slot is full, finds the item stack worth the
-- least (vendor price, or the auction price from Auctionator when that is higher) and makes its bag slot hard to miss (pulsing glow, red tint and a
-- bouncing "DROP" label), adds a line to its tooltip and prints one chat line, so you know
-- what to drop to pick up the loot. Opens the bags for that if they were closed, and
-- closes them again with the loot window.
-- Works with the default bag frames and with Bagnon (BagBrother).
-- Read-only: nothing is sold, deleted or moved for you.
-- Never picked: items with no vendor price (quest items, hearthstone and the like),
-- and profession or class tools (skinning knife, mining pick, fishing poles, ...).

local ADDON, AA = ...
local H = {}
AA.BagHint = H

local QUEST_CLASS = 12   -- Enum.ItemClass.Questitem
local WEAPON_CLASS = 2   -- Enum.ItemClass.Weapon
local FISHING_POLE = 20  -- Enum.ItemWeaponSubclass.Fishingpole

-- Profession and class tools that recipes or abilities need while in the bags.
local TOOLS = {}
for _, id in ipairs({
  7005, 12709, 19901,                         -- skinning knives
  2901, 9465, 20723, 40892, 40893,            -- mining picks
  5956,                                       -- blacksmith hammer
  6219, 10498,                                -- arclight spanner, gyromatic micro-adjustor
  40772,                                      -- gnomish army knife
  6218, 6339, 11130, 11145, 16207,            -- runed enchanting rods
  22461, 22462, 22463, 44452,
  9149,                                       -- philosopher's stone
  20815, 20824,                               -- jeweler's kit, simple grinder
  4471,                                       -- flint and tinder
  5060,                                       -- thieves' tools
  39505,                                      -- virtuoso inking set
  6256, 6365, 6366, 6367, 12225, 19022, 19970, -- fishing poles
  25978, 44050, 45858, 45991, 45992,
}) do TOOLS[id] = true end

-- Name fallback (English client) for tools missing from the list above.
local TOOL_NAMES = {
  "Skinning Knife", "Skinner", "Mining Pick", "Blacksmith Hammer", "Fishing Pole", "Fishing Rod",
  "Runed %a+ Rod", "Arclight Spanner", "Micro%-Adjustor", "Army Knife", "Philosopher's Stone",
  "Jeweler's Kit", "Flint and Tinder", "Thieves' Tools", "Inking Set",
}

local function isTool(itemID, name, classID, subclassID)
  if itemID and TOOLS[itemID] then return true end
  if classID == WEAPON_CLASS and subclassID == FISHING_POLE then return true end
  if type(name) == "string" then
    for _, pat in ipairs(TOOL_NAMES) do
      if name:find(pat) then return true end
    end
  end
  return false
end

local target        -- { bag, slot, link, count, value } or nil
local announced     -- true once the chat line was printed for the current "bags full" spell
local overlays = {} -- [button] = overlay frame
local bagnonButtons = setmetatable({}, { __mode = "k" })

local function enabled() return AA.db and AA.db.settings.remind.cheapest end

-- Auction price of one item, in copper, from Auctionator's public API; nil without data.
-- Soulbound items can't be auctioned, so they never get one.
local function auctionPrice(link, bound)
  if bound or type(link) ~= "string" then return nil end
  local api = type(Auctionator) == "table" and type(Auctionator.API) == "table" and Auctionator.API.v1
  local fn = type(api) == "table" and api.GetAuctionPriceByItemLink
  if type(fn) ~= "function" then return nil end
  local ok, price = pcall(fn, "Azeroth Familiar", link)
  price = ok and AA.Num(price) or nil
  return (price and price > 0) and price or nil
end

-- Cheapest stack in the bags, or nil. A stack is worth its vendor price or its auction
-- price, whichever is higher, times the stack size.
function H.FindCheapest()
  local getInfo = AA.Api("C_Container", "GetContainerItemInfo")
  local questInfo = AA.Api("C_Container", "GetContainerItemQuestInfo")
  local itemInfo = AA.Api("C_Item", "GetItemInfo")
  if not (getInfo and itemInfo and AA.Search) then return nil end
  local best
  for _, e in ipairs((AA.Search.ScanBags())) do
    local ok, info = pcall(getInfo, e.bag, e.slot)
    if ok and type(info) == "table" and not info.hasNoValue then
      local okP, name, _, _, _, _, _, _, _, _, _, sell, classID, subclassID = pcall(itemInfo, e.link or e.itemID)
      sell = okP and AA.Num(sell) or 0
      local skip = okP and (classID == QUEST_CLASS or isTool(e.itemID, name or e.name, classID, subclassID))
      if not skip and questInfo then
        local okQ, q = pcall(questInfo, e.bag, e.slot)
        skip = okQ and type(q) == "table" and (q.isQuestItem or q.questID) and true or false
      end
      if sell > 0 and not skip then
        local count = e.count or 1
        local vendor = sell * count
        local ah = auctionPrice(e.link, info.isBound)
        local auction = ah and ah * count or nil
        local value = math.max(vendor, auction or 0)
        local quality = AA.Num(info.quality) or 1
        if not best or value < best.value or (value == best.value and quality < best.quality) then
          best = { bag = e.bag, slot = e.slot, link = e.link, name = e.name, count = count, value = value,
                   vendor = vendor, auction = auction, quality = quality }
        end
      end
    end
  end
  return best
end

-- The highlight -----------------------------------------------------------------
local function colorTexture(t, r, g, b, a)
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
end

local function overlayFor(b)
  local o = overlays[b]
  if o then return o end
  o = CreateFrame("Frame", nil, b)
  o:SetAllPoints(b)

  -- Red tint over the icon.
  local tint = o:CreateTexture(nil, "ARTWORK")
  tint:SetAllPoints(b)
  colorTexture(tint, 1, 0.15, 0, 0.45)
  tint:SetBlendMode("ADD")

  -- Two stacked glows for a thick, bright border.
  local glows = {}
  for i = 1, 2 do
    local g = o:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.25 + i * 0.1, 0.05)
    g:SetPoint("CENTER")
    glows[i] = g
  end
  o.glows = glows

  -- Bouncing label above the slot.
  local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label:SetPoint("BOTTOM", b, "TOP", 0, 2)
  label:SetText("DROP")
  label:SetTextColor(1, 0.3, 0.1)
  pcall(function()
    local font, size = label:GetFont()
    if font then label:SetFont(font, (size or 16), "THICKOUTLINE") end
  end)
  o.label = label

  pcall(function()
    local ag = o:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.45)
    o.pulse = ag
  end)
  pcall(function()
    local ag = label:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local t = ag:CreateAnimation("Translation")
    t:SetOffset(0, 6)
    t:SetDuration(0.4)
    o.bounce = ag
  end)
  o:Hide()
  overlays[b] = o
  return o
end

local function setGlow(b, on)
  if not on then
    local o = overlays[b]
    if o and o:IsShown() then
      o:Hide()
      if o.pulse then o.pulse:Stop() end
      if o.bounce then o.bounce:Stop() end
    end
    return
  end
  local o = overlayFor(b)
  o:SetFrameLevel(b:GetFrameLevel() + 20)
  local w = b:GetWidth()
  if not w or w < 10 then w = 37 end
  o.glows[1]:SetSize(w * 1.9, w * 1.9)
  o.glows[2]:SetSize(w * 2.2, w * 2.2)
  if not o:IsShown() then
    o:Show()
    if o.pulse then o.pulse:Play() end
    if o.bounce then o.bounce:Play() end
  end
end

-- Which bag and slot a button shows, or nil when it shows something else
-- (another character's bags in Bagnon, the bank, an empty proxy).
local function buttonBagSlot(b)
  if bagnonButtons[b] then
    if b.IsCached then
      local ok, cached = pcall(b.IsCached, b)
      if ok and cached then return nil end
    end
    local ok, bag = pcall(b.GetBag, b)
    return ok and bag or b.bag, b:GetID()
  end
  local bag
  if b.GetBagID then
    local ok, id = pcall(b.GetBagID, b)
    bag = ok and id or nil
  end
  if bag == nil then
    local p = b:GetParent()
    bag = p and p.GetID and p:GetID()
  end
  return bag, b:GetID()
end

-- No IsShown check: Bagnon updates a button before showing it, and the overlay is a
-- child of the button, so it is hidden whenever the button is.
local function matches(b)
  if not target then return false end
  local bag, slot = buttonBagSlot(b)
  return bag == target.bag and slot == target.slot
end

local function eachBlizzardButton(fn)
  local function fromFrame(f, name)
    if not (f and f:IsShown()) then return end
    if f.EnumerateValidItems then
      local ok, iter, state, start = pcall(f.EnumerateValidItems, f)
      if ok and iter then
        for _, b in iter, state, start do fn(b) end
        return
      end
    end
    if name then
      for j = 1, 64 do
        local b = _G[name .. "Item" .. j]
        if not b then break end
        fn(b)
      end
    end
  end
  for i = 1, (tonumber(NUM_CONTAINER_FRAMES) or 13) do
    fromFrame(_G["ContainerFrame" .. i], "ContainerFrame" .. i)
  end
  fromFrame(_G.ContainerFrameCombinedBags, nil)
end

-- Bagnon loads the shared BagBrother code under its own name, so its namespace is the
-- global "Bagnon"; "BagBrother" is checked too for other packagings.
local function bagnonNS()
  for _, n in ipairs({ "Bagnon", "BagBrother" }) do
    local t = _G[n]
    if type(t) == "table" and (type(t.ContainerItem) == "table" or type(t.Frames) == "table") then return t end
  end
end

-- Bagnon (BagBrother): bag slots are pooled ContainerItem buttons. Bagnon copies its
-- methods onto each button when creating it ("Bind", for secure frames), so hooking
-- the class does nothing; each button's own Update is hooked instead.
local function onBagnonUpdate(b) setGlow(b, matches(b)) end

local function collectBagnon()
  local BB = bagnonNS()
  local cls = type(BB) == "table" and BB.ContainerItem
  local pool = type(cls) == "table" and rawget(cls, "__frames")
  if type(pool) ~= "table" or type(hooksecurefunc) ~= "function" then return end
  for k, v in pairs(pool) do
    local b = (type(k) == "table" and k) or (type(v) == "table" and v) or nil
    if b and not bagnonButtons[b] and type(b.Update) == "function" and type(b.GetID) == "function" then
      bagnonButtons[b] = true
      hooksecurefunc(b, "Update", onBagnonUpdate)
    end
  end
end

function H.Apply()
  pcall(collectBagnon)
  local lit = {}
  local function check(b)
    if matches(b) then lit[b] = true; setGlow(b, true) end
  end
  eachBlizzardButton(check)
  for b in pairs(bagnonButtons) do check(b) end
  for b in pairs(overlays) do
    if not lit[b] then setGlow(b, false) end
  end
end

local function applySoon()
  if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(H.Apply) end) else pcall(H.Apply) end
end

-- State -------------------------------------------------------------------------
local lootOpen, openedBags

-- Bags: Bagnon's inventory window when Bagnon handles it, otherwise the default bags.
local function bagnonInventory()
  local ns = bagnonNS()
  local F = ns and ns.Frames
  if type(F) ~= "table" or type(F.IsEnabled) ~= "function" then return nil end
  local ok, on = pcall(F.IsEnabled, F, "inventory")
  return ok and on and F or nil
end

local function bagsShown()
  local F = bagnonInventory()
  if F then
    local ok, shown = pcall(F.IsShown, F, "inventory")
    return ok and shown and true or false
  end
  local c = _G.ContainerFrameCombinedBags
  if c and c:IsShown() then return true end
  local f = _G.ContainerFrame1
  return f and f:IsShown() or false
end

local function openBags()
  local F = bagnonInventory()
  if F then return pcall(F.Show, F, "inventory") end
  if type(OpenAllBags) == "function" then return pcall(OpenAllBags) end
end

local function closeBags()
  local F = bagnonInventory()
  if F then return pcall(F.Hide, F, "inventory") end
  if type(CloseAllBags) == "function" then return pcall(CloseAllBags) end
end

function H.Update()
  local free = AA.Stats and AA.Stats.Bags()
  if enabled() and free == 0 and lootOpen then
    target = H.FindCheapest()
  else
    target = nil
    if free and free > 0 then announced = nil end
  end
  if target and not announced then
    announced = true
    AA:Print(AA.C.warn .. "Bags full.|r To make room for the loot, drop " ..
      (target.count > 1 and (target.count .. "x ") or "") .. (target.link or target.name or "an item") ..
      " (" .. H.WorthText(target) .. "). It is marked DROP in your bags.")
  end
  applySoon()
end

function H.Target() return target end

-- "worth 15c at a vendor" / "worth 1s 20c at auction (15c at a vendor)", for the whole stack.
function H.WorthText(t)
  local M = AA.Stats.MoneyText
  if t.auction and t.auction > t.vendor then
    return "worth " .. M(t.auction) .. " at auction (" .. M(t.vendor) .. " at a vendor)"
  end
  return "worth " .. M(t.vendor or t.value) .. " at a vendor"
end

AA:On("BAG_UPDATE_DELAYED", function() if lootOpen then H.Update() end end)
AA:On("LOOT_OPENED", function()
  lootOpen = true
  H.Update()
  if target and not bagsShown() then
    openedBags = openBags() and true or nil
  end
end)
AA:On("LOOT_CLOSED", function()
  lootOpen = nil
  H.Update()
  if openedBags then
    openedBags = nil
    closeBags()
  end
end)

-- Hooks ---------------------------------------------------------------------------
-- Bagnon: re-check when its windows open (its buttons are created on first open).
local bagnonHooked
local function hookBagnon()
  if bagnonHooked or type(hooksecurefunc) ~= "function" then return end
  local BB = bagnonNS()
  local frames = type(BB) == "table" and BB.Frames
  if type(frames) ~= "table" then return end
  bagnonHooked = true
  for _, m in ipairs({ "Show", "Toggle", "ShowBag", "ToggleBag" }) do
    if type(frames[m]) == "function" then hooksecurefunc(frames, m, applySoon) end
  end
end

-- /aa bagcheck: what this feature sees right now.
function H.Report()
  local free, total = AA.Stats.Bags()
  local nBagnon, nLit = 0, 0
  pcall(H.Apply)
  for _ in pairs(bagnonButtons) do nBagnon = nBagnon + 1 end
  for _, o in pairs(overlays) do if o:IsVisible() then nLit = nLit + 1 end end
  local t = target or (free == 0 and H.FindCheapest()) or nil
  AA:Print(string.format("Bag check: %s free of %s; option %s; loot window %s; cheapest %s; Bagnon %s (%d slots seen, hooks %s); marks shown %d.",
    tostring(free), tostring(total), enabled() and "on" or "off", lootOpen and "open" or "closed (marks show only while looting)",
    t and string.format("%s in bag %s slot %s (%s)", t.link or t.name or "?", tostring(t.bag), tostring(t.slot), AA.Stats.MoneyText(t.value)) or "none",
    bagnonNS() and "found" or "not found", nBagnon, bagnonHooked and "on" or "off", nLit))
end

local hooked
local function hookAll()
  if hooked or type(hooksecurefunc) ~= "function" then return end
  hooked = true
  for _, fn in ipairs({ "ContainerFrame_Update", "OpenBag", "ToggleBag", "OpenAllBags", "ToggleAllBags",
    "OpenBackpack", "ToggleBackpack" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, applySoon) end
  end
  local combined = _G.ContainerFrameCombinedBags
  if combined then
    if type(combined.UpdateItems) == "function" then hooksecurefunc(combined, "UpdateItems", applySoon) end
    combined:HookScript("OnShow", applySoon)
  end
  for i = 1, (tonumber(NUM_CONTAINER_FRAMES) or 13) do
    local f = _G["ContainerFrame" .. i]
    if f then f:HookScript("OnShow", applySoon) end
  end
  if GameTooltip and type(GameTooltip.SetBagItem) == "function" then
    hooksecurefunc(GameTooltip, "SetBagItem", function(tt, bag, slot)
      if target and bag == target.bag and slot == target.slot then
        tt:AddLine("Azeroth Familiar: cheapest item - drop it to make room for loot", 1, 0.5, 0.3)
        tt:AddLine(H.WorthText(target), 1, 0.82, 0.6)
        tt:Show()
      end
    end)
  end
end

AA:On("PLAYER_LOGIN", function()
  pcall(hookAll)
  pcall(hookBagnon)
end)
AA:On("ADDON_LOADED", function(_, name)
  if name == "BagBrother" or name == "Bagnon" then pcall(hookBagnon) end
end)

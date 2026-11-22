-- Azeroth Familiar - Modules/Inventory.lua
-- Bags page: space, gold, grey items worth selling, and a bag search.
-- Read-only: nothing is sold, destroyed, moved or bought. Sell the grey items yourself.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local I = "Interface\\Icons\\"
local v = {}
local lastSearch
local page, resultsTop, pageH = nil, nil, nil
local LINE = 13

-- The search results are the last thing on the page, so they can grow: as many lines as
-- fit the page's visible height (at least 12), and the page scrolls past that.
local function resultLimit()
  if not (pageH and resultsTop) then return 12 end
  return math.max(12, math.floor((pageH + resultsTop - 24) / LINE))
end

local function fitPage()
  if page and resultsTop and v.results then
    page:SetHeight(-resultsTop + (tonumber(v.results:GetStringHeight()) or LINE) + 20)
  end
end

local function runSearch(text)
  text = AA.Trim(text or "")
  lastSearch = text ~= "" and text or nil
  if not lastSearch then
    v.results:SetText(W.GREY .. "Type part of an item name and press Enter.|r")
    fitPage()
    return
  end
  local found = AA.Search.FindInBags({ term = lastSearch })
  if #found == 0 then
    v.results:SetText("Nothing in your bags matches \"" .. lastSearch .. "\".")
    fitPage()
    return
  end
  local limit = resultLimit()
  local lines = {}
  for i = 1, math.min(limit, #found) do
    local g = found[i]
    lines[#lines + 1] = string.format("%dx  %s%s", g.count, g.link or g.name or "?", g.stacks > 1 and ("  (" .. g.stacks .. " stacks)") or "")
  end
  if #found > limit then lines[#lines + 1] = W.GREY .. "...and " .. (#found - limit) .. " more|r" end
  v.results:SetText(table.concat(lines, "\n"))
  fitPage()
end

local function build(L, p)
  page = p
  L:Header("Bags and gold")
  v.space = L:KV("Bag space")
  v.gold = L:KV("Gold")
  v.session = L:KV("This session")

  L:Header("Grey items to sell")
  v.junk = L:Note("", 9)
  L:Note("Azeroth Familiar never sells anything for you. Visit a vendor and sell these yourself.", 1)

  L:Header("Search your bags")
  L:Note("To compare gear, shift-click items into the Assistant page and ask \"which is better?\".", 1)
  local y = L:Row(28)
  local box = W.Input(p, 60)
  box:SetPoint("TOPLEFT", 16, y)
  box:SetWidth(240)
  box:SetScript("OnEnterPressed", function(self) runSearch(self:GetText()); self:ClearFocus() end)
  local go = W.Button(p, "Search", 70, function() runSearch(box:GetText()) end)
  go:SetPoint("LEFT", box, "RIGHT", 8, 0)
  resultsTop = L.y
  v.results = L:Note(W.GREY .. "Type part of an item name and press Enter.|r", 1)
end

local function refresh()
  local free, total = St.Bags()
  v.space:SetText(free and ((free <= 3 and AA.C.warn or "") .. free .. " free|r of " .. total .. " slots") or "n/a")
  v.gold:SetText(St.MoneyText(St.Money()))
  local s = St.SessionSummary()
  v.session:SetText("earned " .. St.MoneyText(s.goldIn) .. "   spent " .. St.MoneyText(s.goldOut))
  local junk, value = St.Junk()
  if #junk == 0 then
    v.junk:SetText(W.GREY .. "No grey items with a vendor price in your bags.|r")
  else
    local lines = { #junk .. " stack" .. (#junk == 1 and "" or "s") .. ", worth " .. St.MoneyText(value) .. " at a vendor:" }
    for i = 1, math.min(7, #junk) do
      local j = junk[i]
      lines[#lines + 1] = string.format("  %dx %s  %s", j.count, j.link or j.name, St.MoneyText(j.value))
    end
    if #junk > 7 then lines[#lines + 1] = W.GREY .. "  ...and " .. (#junk - 7) .. " more|r" end
    v.junk:SetText(table.concat(lines, "\n"))
  end
  if lastSearch then runSearch(lastSearch) end
end

-- Refreshed when opened and when bags change while it is open (no timer).
AA:On("BAG_UPDATE_DELAYED", function()
  if AA.Shell.Current() == "inventory" then AA.Shell.Refresh() end
end)

AA.Shell.Register({
  id = "inventory", title = "Bags", order = 50, icon = I .. "INV_Misc_Bag_08",
  subtitle = "Bag space, gold, grey items and bag search.",
  build = build, refresh = refresh,
  resize = function(_, _, height)
    local old = pageH
    pageH = tonumber(height)
    if lastSearch and old ~= pageH then runSearch(lastSearch) else fitPage() end
  end,
})

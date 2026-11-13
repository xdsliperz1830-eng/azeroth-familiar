-- Azeroth Familiar - Modules/Inventory.lua
-- Bags page: space, gold, grey items worth selling, and a bag search.
-- Read-only: nothing is sold, destroyed, moved or bought. Sell the grey items yourself.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local I = "Interface\\Icons\\"
local v = {}
local lastSearch

local function runSearch(text)
  text = AA.Trim(text or "")
  lastSearch = text ~= "" and text or nil
  if not lastSearch then
    v.results:SetText(W.GREY .. "Type part of an item name and press Enter.|r")
    return
  end
  local found = AA.Search.FindInBags({ term = lastSearch })
  if #found == 0 then
    v.results:SetText("Nothing in your bags matches \"" .. lastSearch .. "\".")
    return
  end
  local lines = {}
  for i = 1, math.min(12, #found) do
    local g = found[i]
    lines[#lines + 1] = string.format("%dx  %s%s", g.count, g.link or g.name or "?", g.stacks > 1 and ("  (" .. g.stacks .. " stacks)") or "")
  end
  if #found > 12 then lines[#lines + 1] = W.GREY .. "...and " .. (#found - 12) .. " more|r" end
  v.results:SetText(table.concat(lines, "\n"))
end

local function build(L, p)
  L:Header("Bags and gold")
  v.space = L:KV("Bag space")
  v.gold = L:KV("Gold")
  v.session = L:KV("This session")

  L:Header("Grey items to sell")
  v.junk = L:Note("", 9)
  L:Note("Azeroth Familiar never sells anything for you. Visit a vendor and sell these yourself.", 1)

  L:Header("Search your bags")
  local y = L:Row(28)
  local box = W.Input(p, 60)
  box:SetPoint("TOPLEFT", 16, y)
  box:SetWidth(240)
  box:SetScript("OnEnterPressed", function(self) runSearch(self:GetText()); self:ClearFocus() end)
  local go = W.Button(p, "Search", 70, function() runSearch(box:GetText()) end)
  go:SetPoint("LEFT", box, "RIGHT", 8, 0)
  v.results = L:Note(W.GREY .. "Type part of an item name and press Enter.|r", 13)
  L:Note("To compare gear, shift-click items into the Assistant page and ask \"which is better?\".", 1)
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
})

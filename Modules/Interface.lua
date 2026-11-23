-- Azeroth Familiar - Modules/Interface.lua
-- Interface page: how Azeroth Familiar itself looks and behaves.

local ADDON, AA = ...
local W = AA.W
local I = "Interface\\Icons\\"

local function S() return AA.db.settings end
local function applied(msg)
  AA.UI.ApplySettings()
  AA.Shell.Flash(msg, true)
end

-- Puts window, navigation, dashboard and reminder choices back to their defaults.
-- Leaves your conversation, saved places, AI options and game settings alone.
function AA.ResetInterfaceSettings()
  local s = S()
  s.windowScale, s.windowAlpha, s.compactNav, s.startPage, s.fontSize = 1, 92, false, "overview", 13
  s.dash = {}
  s.remind = { durability = true, bags = true, cheapest = true, vendor = true, levelup = true }
  s.perfDisplay, s.perfLatency = false, true
  s.minimap.hide = false
  s.border = "faction"
  if AA.UI.ApplyBorder then pcall(AA.UI.ApplyBorder) end
  AA.db.frame = {}
  AA.db.perfFrame = nil
  if AA.Minimap then pcall(AA.Minimap.Refresh) end
  if AA.Performance then pcall(AA.Performance.RefreshMini) end
  AA.Shell.ApplyLayout()
  AA.UI.ApplySettings()
end

local function build(L, p)
  L:Header("Window")
  L:Stepper("Window size", {
    get = function() return S().windowScale end,
    set = function(x) S().windowScale = x; applied(string.format("Window size %d%%", x * 100)) end,
    min = 0.7, max = 1.3, step = 0.05, fmt = function(x) return string.format("%d%%", x * 100 + 0.5) end,
  }, "Window size", "Makes the whole Azeroth Familiar window bigger or smaller.")
  L:Stepper("Background opacity", {
    get = function() return S().windowAlpha end,
    set = function(x) S().windowAlpha = x; applied("Background opacity " .. x .. "%") end,
    min = 40, max = 100, step = 5, fmt = function(x) return x .. "%" end,
  }, "Background opacity", "Lower values let the game show through the window.")
  L:Stepper("Assistant text size", {
    get = function() return S().fontSize end,
    set = function(x) S().fontSize = x; applied("Assistant text size " .. x) end,
    min = 9, max = 20, step = 1,
  }, "Assistant text size", "Text size of the conversation on the Assistant page.")
  L:Check("Compact navigation (icons only)",
    function() return S().compactNav end,
    function(x) S().compactNav = x; AA.Shell.ApplyLayout() end,
    "Compact navigation", "Shows only the icons on the left, leaving more room for the page.")
  L:Check("Lock window position",
    function() return S().lockWindow end,
    function(x) S().lockWindow = x end,
    "Lock window position", "When ticked, the window can't be dragged. Untick to move it again by dragging the title bar or any empty part of the window. /fam center puts it back in the middle.")
  L:Check("Minimap button",
    function() return not S().minimap.hide end,
    function(x) S().minimap.hide = not x; if AA.Minimap then AA.Minimap.Refresh() end end)
  do
    local y = L:Row(28)
    local l = W.Text(p, "Open the window on")
    l:SetPoint("TOPLEFT", 14, y - 5)
    local c = W.Choice(p, 150, { { "overview", "Overview" }, { "assistant", "Assistant" }, { "last", "The last page used" } },
      function() return S().startPage end,
      function(x) S().startPage = x end,
      "Open the window on", "Which page shows first when you open Azeroth Familiar. Click to change.")
    L:Column(c, y, 220)                 -- right-hand column, follows the page width
    L:Track(c)
  end
  do
    local y = L:Row(28)
    local l = W.Text(p, "Window border")
    l:SetPoint("TOPLEFT", 14, y - 5)
    local c = W.Choice(p, 150, { { "faction", "Faction colours" }, { "gold", "Gold" }, { "plain", "Plain line" } },
      function() return S().border or "faction" end,
      function(x)
        S().border = x
        if AA.UI.ApplyBorder then AA.UI.ApplyBorder() end
        AA.Shell.Flash("Window border: " .. (x == "faction" and "faction colours" or x == "gold" and "gold" or "plain line"), true)
      end,
      "Window border", "Faction colours: a red Horde frame or a blue Alliance frame, matching your character. Gold: the gold and gem frame. Plain line: the original thin border, with the most room for the pages. Click to change.")
    L:Column(c, y, 220)
    L:Track(c)
  end

  L:Header("Reminders in chat")
  local function remind(key, label, tip)
    L:Check(label, function() return S().remind[key] end, function(x) S().remind[key] = x end, label, tip)
  end
  remind("durability", "Low durability", "One line when an equipped item drops below " .. AA.Reminders.DURABILITY_PCT .. "%.")
  remind("bags", "Bags nearly full", "One line when " .. AA.Reminders.BAG_SLOTS .. " or fewer bag slots are free.")
  L:Check("Looting with full bags: mark what to drop",
    function() return S().remind.cheapest end,
    function(x) S().remind.cheapest = x; if AA.BagHint then AA.BagHint.Update() end end,
    "Looting with full bags: mark what to drop",
    "When you open a loot window with no bag slots left, the stack worth the least is marked DROP (vendor price, or the Auctionator auction price when higher) in your bags (default bags or Bagnon) and named in chat. Closed bags open for it and close again with the loot window. Items with no vendor price and profession tools are never picked. Nothing is sold or deleted for you.")
  L:Check("Crate tooltips: highlight the cheapest bundle",
    function() return S().crates.tooltip ~= false end,
    function(x) if AA.Crates and AA.Crates.Tooltip then AA.Crates.Tooltip:SetEnabled(x) else S().crates.tooltip = x end end,
    "Crate tooltips: highlight the cheapest bundle",
    "Hovering a supported Waylaid Crate adds a short Crates summary and colors its cheapest bundle line: green when confirmed by a fresh AH scan or already owned, amber when it is only a cached estimate. See the Crates page.")
  remind("vendor", "At a vendor: grey items and repair cost", "One line when you open a vendor with grey items to sell or repairs to make. Nothing is sold or repaired for you.")
  remind("levelup", "Level-up summary", "One line with your session length and experience per hour when you level.")

  L:Header("Overview cards")
  for _, def in ipairs(AA.Overview.CARDS) do
    local id = def.id
    L:Check(def.title, function() return S().dash[id] ~= false end, function(x) S().dash[id] = x and true or false end)
  end

  L:Header("Reset")
  L:Buttons({
    { "Assistant settings", 130, function() AA.UI.ShowSettings() end, "Assistant settings", "Companion, AI and privacy options for the Assistant page." },
    { "Diagnostics", 90, function() AA:RunDiagnostics(true) end, "Diagnostics", "Checks which game features this client has and saves the result for troubleshooting." },
  })
  L:Buttons({
    { "Reset interface settings", 180, function()
        AA.ResetInterfaceSettings()
        AA.Shell.Flash("Interface settings are back to their defaults.", true)
        AA.Shell.Refresh()
      end, "Reset interface settings", "Window size, opacity, navigation, cards and reminders go back to default. Your conversation, saved places and game settings are kept." },
    { "Erase all data", 110, function() AA.UI.ConfirmReset() end, "Erase all data", "Erases everything Azeroth Familiar has saved. Asks first." },
  })
end

AA.Shell.Register({
  id = "interface", title = "Interface", order = 80, icon = I .. "Trade_Engineering",
  subtitle = "How Azeroth Familiar looks and behaves.",
  build = build,
})

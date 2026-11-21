-- Azeroth Familiar - Modules/Crates.lua
-- Crates page (formerly the Crate Scout addon): compare the cash needed to fill one
-- Waylaid Crate, or buy one empty crate and fill it. Presentation and event wiring only;
-- recipes, validation, scanning and costs live in Crates\*.lua (AA.Crates).
-- Nothing is bought or used. Scans start only when Scan Auction House is clicked.

local ADDON, AA = ...
local W = AA.W
local C = AA.Crates
local G = C.Color
local P = {}            -- the page (also C.UI, which the crate engine notifies)
C.UI = P
P.expanded, P.widgets = {}, {}

local ROW_H, SUB_H = 26, 22
-- Table geometry. Fixed columns keep numbers aligned; the crate and bundle columns
-- share what is left of the page width (recomputed when the window is resized), so
-- names get the room instead of empty gaps.
local GAP = 10
local LEAD = 40            -- expander + crate icon
local FIXED = { level = 30, need = 34, cost = 70, status = 108 }
local BADGE_W = 34
local ACCENT = {
  ready = { 0.30, 1, 0.30 }, live = { 0.30, 1, 0.30 }, estimate = { 1, 0.72, 0.30 },
  unpriced = { 0.45, 0.45, 0.45 }, unsupported = { 0.85, 0.30, 0.30 }, info = { 0.8, 0.65, 0.25 },
}

local function settings() return AA.db.settings.crates end

function P.Columns(width)
  width = math.max(440, tonumber(width) or 560)
  local narrow = width < 540                       -- smallest window: tighter number columns
  local cost, status = narrow and 62 or FIXED.cost, narrow and 84 or FIXED.status
  local flex = width - LEAD - FIXED.level - FIXED.need - cost - status - GAP * 5 - 4
  local crate = math.max(70, math.floor(flex * 0.42))
  local bundle = math.max(100, flex - crate)
  local c, x = {}, LEAD
  for _, spec in ipairs({ { "crate", crate }, { "level", FIXED.level }, { "bundle", bundle },
                          { "need", FIXED.need }, { "cost", cost }, { "status", status } }) do
    c[spec[1]] = { x = x, w = spec[2] }
    x = x + spec[2] + GAP
  end
  c.width = width
  return c
end

local function text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT"); fs:SetJustifyV("MIDDLE")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetHeight(16)
  return fs
end
local function place(fs, parent, x, w)
  fs:ClearAllPoints(); fs:SetPoint("LEFT", parent, "LEFT", x, 0); fs:SetWidth(math.max(1, w))
end
local function solid(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(r, g, b, a)
  return t
end
local function hideTip() GameTooltip:Hide() end
local function iconButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints(); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetScript("OnEnter", function(self)
    if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", hideTip)
  b:SetScript("OnClick", function() if parent.onClick then parent.onClick() end end)
  return b
end
local function setIcon(b, id)
  b.itemID = id
  b.tex:SetTexture((id and C.ItemIcon(id)) or C.CRATE_ICON)
  b:Show()
end
-- Small gold text link (fits a 22 px row, unlike the big red panel button).
local function link(parent, label, onClick, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(40, 16)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetAllPoints(); fs:SetJustifyH("LEFT"); fs:SetText(label)
  b.label = fs
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.15)
  b:SetScript("OnClick", onClick)
  W.Tip(b, tip and tip[1], tip and tip[2])
  return b
end
local function bundleText(b) return b.quantity .. " " .. C.ItemName(b.itemID, b.name) end

-- Short, colored price status for one cost result.
function P.StatusLabel(r)
  if not r then return G.red .. "Unsupported|r" end
  if r.kind == "owned" then return G.green .. "Ready to fill|r" end
  if r.kind == "live" then return G.white .. "AH · " .. C.Age(r.age) .. "|r" end
  if r.kind == "estimate" then return r.stale and (G.orange .. "Stale estimate|r") or (G.amber .. "Estimate|r") end
  local s = r.status or ""
  if s:find("^Incomplete") then return G.orange .. "Incomplete scan|r" end
  if s:find("^Expired") then return G.orange .. "Expired · rescan|r" end
  if s:find("Insufficient") then return G.red .. "Not enough on AH|r" end
  return G.grey .. "No price|r"
end
-- Badge beside the recommended bundle: the same rules as the tooltip highlight.
function P.Badge(rec)
  if not rec then return nil end
  if rec.state == "ready" then return rec.tie and "TIE" or "READY", ACCENT.ready end
  if rec.state == "live" then return (rec.tie and "TIE" or "BEST") .. (rec.partial and "*" or ""), ACCENT.live end
  if rec.state == "estimate" then return "EST", ACCENT.estimate end
end

-- Building ------------------------------------------------------------------
function P.Make(host)
  local f = CreateFrame("Frame", nil, host)
  P.frame = f

  -- Row 1: view tabs, then the one view option right beside them (never off the edge)
  P.tabs = {}
  for i, mode in ipairs({ "My Crates", "All Crates", "Buy & Fill" }) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(92, 24); b:SetPoint("TOPLEFT", 8 + (i - 1) * 96, -6)
    b.bg = solid(b, "BACKGROUND", 0.1, 0.1, 0.11, 0.9); b.bg:SetAllPoints()
    b.line = solid(b, "ARTWORK", 1, 0.82, 0, 1); b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(2)
    b.text = text(b, "GameFontNormalSmall", "CENTER"); b.text:SetAllPoints()
    b.text:SetText(mode)
    local hl = solid(b, "HIGHLIGHT", 1, 0.82, 0, 0.12); hl:SetAllPoints()
    b.mode = mode
    b:SetScript("OnClick", function() C.mode = mode; P:Refresh() end)
    P.tabs[i] = b
  end
  P.own = W.Check(f, "Count owned",
    function() return C.countOwned end,
    function(x) C.countOwned = x; settings().countOwned = x; P:Refresh() end,
    "Count owned materials", "All Crates: deduct materials already in your bags. My Crates always does; Buy & Fill never does.")
  P.own:SetPoint("TOPLEFT", 8 + 3 * 96 + 8, -6)

  -- Row 2: scan controls and a short AH state
  P.scanButton = W.Button(f, "Scan Auction House", 146, function() C.Scan:Start() end,
    "Scan Auction House", "Searches the AH for this view's materials (and empty crates in Buy & Fill). Needs the AH open. Never buys anything.")
  P.scanButton:SetPoint("TOPLEFT", 8, -38)
  P.cancelButton = W.Button(f, "Cancel", 62, function() C.Scan:Cancel() end, "Cancel scan", "Stops safely. Items already scanned stay usable while the AH is open.")
  P.cancelButton:SetPoint("LEFT", P.scanButton, "RIGHT", 4, 0)
  P.verifyButton = W.Button(f, "Verify", 62, function() C.Inventory:Read(); C.Inventory:ValidateCatalog(); C.Changed() end,
    "Verify recipes", "Re-checks every crate recipe against this client's own item tooltip. Unverified crates stay unsupported.")
  P.verifyButton:SetPoint("LEFT", P.cancelButton, "RIGHT", 4, 0)
  P.ahNote = text(f, "GameFontHighlightSmall")
  P.ahNote:SetPoint("LEFT", P.verifyButton, "RIGHT", 10, 0); P.ahNote:SetPoint("RIGHT", f, "RIGHT", -8, 0)

  -- Row 3: progress and the latest message
  P.progress = CreateFrame("StatusBar", nil, f)
  P.progress:SetSize(110, 12); P.progress:SetPoint("TOPLEFT", 10, -70)
  P.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  P.progress:SetStatusBarColor(0.85, 0.65, 0.15); P.progress:SetMinMaxValues(0, 1)
  solid(P.progress, "BACKGROUND", 0, 0, 0, 0.6):SetAllPoints()
  P.progressText = text(P.progress, "GameFontHighlightSmall", "CENTER"); P.progressText:SetAllPoints()
  P.status = text(f, "GameFontHighlightSmall"); P.status:SetHeight(26); P.status:SetJustifyV("TOP")
  if P.status.SetWordWrap then P.status:SetWordWrap(true) end

  -- Column header (same geometry as the rows)
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 6, -100); head:SetPoint("TOPRIGHT", -26, -100); head:SetHeight(20)
  solid(head, "BACKGROUND", 0.14, 0.11, 0.04, 0.9):SetAllPoints()
  P.headFrame = head
  P.head = {}
  for _, spec in ipairs({ { "crate", "Crate" }, { "level", "Lvl", "RIGHT" }, { "bundle", "Best bundle" },
                          { "need", "Need", "RIGHT" }, { "cost", "Cost", "RIGHT" }, { "status", "Status" } }) do
    P.head[spec[1]] = text(head, "GameFontNormalSmall", spec[3])
    P.head[spec[1]]:SetText(spec[2])
  end

  local scroll = CreateFrame("ScrollFrame", "AzerothFamiliarCratesScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -122); scroll:SetPoint("BOTTOMRIGHT", -26, 46)
  P.scroll = scroll
  local content = CreateFrame("Frame", nil, scroll); content:SetSize(560, 1)
  scroll:SetScrollChild(content); P.content = content
  scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w); P:Refresh() end end)
  P.empty = text(content, "GameFontDisable", "CENTER"); P.empty:SetPoint("TOP", content, "TOP", 0, -30)
  P.empty:SetWidth(420); P.empty:SetHeight(60)
  if P.empty.SetWordWrap then P.empty:SetWordWrap(true) end

  -- Footer: manual search handoff, coverage, legend
  local sl = text(f, "GameFontNormalSmall"); sl:SetPoint("BOTTOMLEFT", 10, 26); sl:SetWidth(64); sl:SetText("AH search")
  P.searchBox = W.Input(f, 80); P.searchBox:SetSize(170, 20); P.searchBox:SetPoint("LEFT", sl, "RIGHT", 6, 0)
  P.coverage = text(f, "GameFontDisableSmall", "RIGHT")
  P.coverage:SetPoint("LEFT", P.searchBox, "RIGHT", 10, 0); P.coverage:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  P.legend = text(f, "GameFontDisableSmall")
  P.legend:SetPoint("BOTTOMLEFT", 10, 8); P.legend:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  P.legend:SetText(G.green .. "Green|r confirmed  ·  " .. G.amber .. "amber|r estimate  ·  * cheapest of priced  ·  each row is one crate on its own, no combined total")
  return f
end

function P:Widget(index)
  local w = self.widgets[index]
  if not w then
    w = CreateFrame("Button", nil, self.content)
    w.bg = solid(w, "BACKGROUND", 0.1, 0.1, 0.12, 0.8); w.bg:SetAllPoints()
    w.tint = solid(w, "BORDER", 0.2, 0.6, 0.2, 0.16); w.tint:SetAllPoints()
    w.hl = solid(w, "HIGHLIGHT", 1, 0.82, 0, 0.07); w.hl:SetAllPoints()
    w.accent = solid(w, "ARTWORK", 1, 1, 1, 1)
    w.expander = text(w, "GameFontNormal", "CENTER"); w.expander:SetPoint("LEFT", 4, 0); w.expander:SetWidth(12)
    w.crateIcon = iconButton(w, 18); w.crateIcon:SetPoint("LEFT", 18, 0)
    w.bundleIcon = iconButton(w, 16)
    w.fields = {}
    for _, key in ipairs({ "crate", "level", "bundle", "need", "cost", "status" }) do
      w.fields[key] = text(w, "GameFontHighlightSmall", (key == "level" or key == "need" or key == "cost") and "RIGHT" or "LEFT")
    end
    w.crate = w.fields.crate
    w.badge = text(w, "GameFontNormalSmall", "RIGHT"); w.badge:SetWidth(BADGE_W)
    w.search = link(w, "Search", function() if w.itemID then C.Model:SearchItem(w.itemID) end end,
      { "Search the AH", "Opens Auctionator's exact search when it is loaded, otherwise puts the name in the AH search box below." })
    w:SetScript("OnClick", function() if w.onClick then w.onClick() end end)
    w:SetScript("OnEnter", function(self)
      if not self.hover then return end
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      for i, line in ipairs(self.hover) do
        if i == 1 then GameTooltip:SetText(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
      end
      GameTooltip:Show()
    end)
    w:SetScript("OnLeave", hideTip)
    self.widgets[index] = w
  end
  w:Show(); w.search:Hide(); w.itemID = nil; w.onClick = nil; w.hover = nil; w.badgeOn = nil
  w.crateIcon:Hide(); w.bundleIcon:Hide(); w.tint:Hide(); w.badge:SetText(""); w.expander:SetText("")
  for _, fs in pairs(w.fields) do fs:SetText("") end
  return w
end

-- Lays the columns out for one row. kind: "crate", "sub" (alternative / breakdown line,
-- indented under its crate) or "plan" (purchase step, indented under the bundle).
function P:Layout(w, kind)
  local c = self.cols
  local subIndent = kind == "crate" and 0 or 14
  if kind == "sub" and w.search:IsShown() then
    w.search:ClearAllPoints(); w.search:SetPoint("LEFT", w, "LEFT", c.crate.x - 22, 0)
    place(w.fields.crate, w, c.crate.x + 22, c.crate.w + c.level.w + GAP - 22)
  else
    place(w.fields.crate, w, c.crate.x + subIndent, (kind == "crate" and c.crate.w or (c.crate.w + c.level.w + GAP)) - subIndent)
  end
  place(w.fields.level, w, c.level.x, c.level.w)
  local bx = c.bundle.x + (kind == "plan" and 20 or 0)
  w.bundleIcon:ClearAllPoints(); w.bundleIcon:SetPoint("LEFT", w, "LEFT", bx, 0)
  local textX = bx + (kind == "plan" and 0 or 20)
  local textW = c.bundle.x + c.bundle.w - textX - (w.badgeOn and (BADGE_W + 4) or 0)
  place(w.fields.bundle, w, textX, textW)
  place(w.badge, w, c.bundle.x + c.bundle.w - BADGE_W, BADGE_W)
  place(w.fields.need, w, c.need.x, c.need.w)
  place(w.fields.cost, w, c.cost.x, c.cost.w)
  place(w.fields.status, w, c.status.x, c.status.w)
end

local function setBadge(w, badge, color)
  w.badgeOn = badge and true or nil
  w.badge:SetText(badge or "")
  if color then w.badge:SetTextColor(color[1], color[2], color[3]) end
end

function P:Line(kind, accent)
  self.index = self.index + 1
  local w = self:Widget(self.index)
  local h = kind == "crate" and ROW_H or SUB_H
  w:ClearAllPoints(); w:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.y); w:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
  w:SetHeight(h)
  self.y = self.y + h + (kind == "crate" and 2 or 0)
  local c = accent or ACCENT.info
  w.accent:ClearAllPoints()
  if kind == "crate" then
    self.stripe = not self.stripe
    local v = self.stripe and 0.11 or 0.085
    w.bg:SetColorTexture(v, v, v + 0.015, 0.9)
    w.accent:SetPoint("TOPLEFT"); w.accent:SetPoint("BOTTOMLEFT"); w.accent:SetWidth(3)
    w.accent:SetColorTexture(c[1], c[2], c[3], 0.9)
    w.fields.crate:SetFontObject("GameFontHighlight")
  else
    w.bg:SetColorTexture(0.055, 0.055, 0.065, 0.95)
    -- the crate's accent continues, indented, so these lines read as part of it
    w.accent:SetPoint("TOPLEFT", 10, 0); w.accent:SetPoint("BOTTOMLEFT", 10, 0); w.accent:SetWidth(2)
    w.accent:SetColorTexture(c[1], c[2], c[3], 0.45)
    w.fields.crate:SetFontObject("GameFontHighlightSmall")
  end
  w.kind = kind
  return w
end

-- Call after a row's content is set (search link and badge change the layout).
function P:Finish(w) self:Layout(w, w.kind) end

function P:Alternatives(row, accent)
  local rec = row.rec
  for i, r in ipairs(row.alternatives or {}) do
    local w = self:Line("sub", accent)
    local win = rec and rec.winners[r.bundle.itemID] and rec.state ~= "unpriced"
    w.crate:SetText(G.muted .. "Bundle " .. i .. "  ·  own " .. r.owned .. "/" .. r.bundle.quantity .. "|r")
    setIcon(w.bundleIcon, r.bundle.itemID)
    w.fields.bundle:SetText((win and (rec.state == "estimate" and G.amber or G.green) or "") .. bundleText(r.bundle) .. (win and "|r" or ""))
    w.fields.need:SetText(tostring(r.missing))
    w.fields.cost:SetText(C.Coins(r.cost))
    w.fields.status:SetText(P.StatusLabel(r))
    if win then
      setBadge(w, P.Badge(rec))
      if rec.state ~= "estimate" then w.tint:SetColorTexture(0.2, 0.6, 0.2, 0.16) else w.tint:SetColorTexture(0.6, 0.45, 0.15, 0.14) end
      w.tint:Show()
    end
    w.itemID = r.bundle.itemID; w.search:Show()
    w.hover = { bundleText(r.bundle) .. " (#" .. r.bundle.itemID .. ")",
      "Required " .. r.bundle.quantity .. " · owned " .. r.owned .. " · missing " .. r.missing,
      "Cost: " .. C.Money(r.cost), r.status or "" }
    if r.kind == "estimate" then w.hover[#w.hover + 1] = "Cached estimate only, not an available buyout. Scan the AH for real listings." end
    w.hover[#w.hover + 1] = "This bundle alone fills the crate; materials are never mixed."
    w.onClick = row.toggle
    self:Finish(w)
    if r.plan then
      local n = #r.plan.buys
      for j, buy in ipairs(r.plan.buys) do
        local p = self:Line("plan", accent)
        p.fields.bundle:SetText(G.muted .. (buy.unitPrice and ("Buy " .. buy.quantity .. " at " .. C.Coins(buy.unitPrice) .. G.muted .. " each")
          or ("Buy stack of " .. buy.quantity)) .. "|r")
        p.fields.need:SetText(G.muted .. buy.quantity .. "|r")
        p.fields.cost:SetText(C.Coins(buy.cost))
        if j == n then p.fields.status:SetText(r.plan.leftover > 0 and (G.muted .. "+" .. r.plan.leftover .. " extra|r") or (G.grey .. "no leftover|r")) end
        p.hover = { "Purchase plan", buy.unitPrice and ("Buy " .. buy.quantity .. " at " .. C.Money(buy.unitPrice) .. " each")
          or ("Buy the whole stack of " .. buy.quantity .. " (auction " .. tostring(buy.auctionID) .. ")"),
          "Observed listing, not reserved. Check it before buying." }
        p.onClick = row.toggle
        self:Finish(p)
      end
    end
  end
end

function P:BuyAndFill(row, accent)
  local cp = row.cratePrice or {}
  local w = self:Line("sub", accent)
  w.crate:SetText(G.muted .. "Empty crate|r")
  setIcon(w.bundleIcon, row.id)
  w.fields.bundle:SetText("1 empty crate")
  w.fields.need:SetText("1"); w.fields.cost:SetText(C.Coins(cp.cost))
  w.fields.status:SetText(P.StatusLabel(cp))
  w.itemID = row.id; w.search:Show(); w.onClick = row.toggle
  w.hover = { "Empty crate cost", cp.status or "", cp.kind == "estimate" and "A cached unit price cannot establish whole-stack cash." or nil }
  self:Finish(w)
  if cp.plan then
    for _, buy in ipairs(cp.plan.buys) do
      local p = self:Line("plan", accent)
      p.fields.bundle:SetText(G.muted .. (buy.unitPrice and ("Buy " .. buy.quantity .. " at " .. C.Coins(buy.unitPrice)) or ("Buy stack of " .. buy.quantity .. " crates")) .. "|r")
      p.fields.need:SetText(G.muted .. buy.quantity .. "|r"); p.fields.cost:SetText(C.Coins(buy.cost)); p.onClick = row.toggle
      self:Finish(p)
    end
    local e = self:Line("plan", accent)
    e.fields.bundle:SetText(G.muted .. "Extra crates from whole stacks|r"); e.fields.need:SetText(tostring(cp.plan.leftover)); e.onClick = row.toggle
    self:Finish(e)
  end
  local m = self:Line("sub", accent)
  m.crate:SetText(G.muted .. "Materials|r")
  if row.best then setIcon(m.bundleIcon, row.best.bundle.itemID); m.fields.bundle:SetText(bundleText(row.best.bundle)); m.fields.need:SetText(tostring(row.best.missing)) end
  m.fields.cost:SetText(C.Coins(row.fillCost)); m.fields.status:SetText(P.StatusLabel(row.best)); m.onClick = row.toggle
  self:Finish(m)
  local t = self:Line("sub", accent)
  t.crate:SetText(G.gold .. "Total cash for this crate|r")
  t.fields.cost:SetText(row.cost and (G.white .. C.Coins(row.cost) .. "|r") or (G.grey .. "--|r"))
  t.fields.status:SetText(row.cost and (G.muted .. "crate + materials|r") or (G.grey .. "needs both prices|r"))
  t.hover = { "Total cash for this crate", "Empty crate " .. C.Money(cp.cost) .. " + materials " .. C.Money(row.fillCost), "Only this row: no total across crates." }
  t.onClick = row.toggle
  self:Finish(t)
end

local EMPTY = {
  ["My Crates"] = "No Waylaid Crates in your bags.\nOpen All Crates to compare every recipe, or Buy & Fill to price buying one.",
  ["All Crates"] = "No crate recipes to show.",
  ["Buy & Fill"] = "No crate recipes to show.",
}

function P:Chrome()
  for _, b in ipairs(self.tabs) do
    local on = b.mode == C.mode
    b.bg:SetColorTexture(on and 0.45 or 0.1, on and 0.10 or 0.1, on and 0.06 or 0.11, 0.9)
    if on then b.line:Show(); b.text:SetTextColor(1, 1, 1) else b.line:Hide(); b.text:SetTextColor(1, 0.82, 0) end
  end
  local p = C.Scan.pending
  local capable, why = C.Scan:Capabilities()
  if p then
    self.progress:Show()
    self.progress:SetValue(math.max(0, p.index - 1) / math.max(1, #p.ids))
    self.progressText:SetText(p.index .. " / " .. #p.ids)
    self.status:ClearAllPoints(); self.status:SetPoint("TOPLEFT", self.progress, "TOPRIGHT", 8, 2)
  else
    self.progress:Hide()
    self.status:ClearAllPoints(); self.status:SetPoint("TOPLEFT", 10, -68)
  end
  self.status:SetPoint("RIGHT", self.frame, "RIGHT", -8, 0)
  self.status:SetText(C.message or "Click a crate to compare its bundles. Costs are cash needed, not market value.")
  if p then self.ahNote:SetText(G.gold .. "Scanning…|r")
  elseif not capable then self.ahNote:SetText(G.red .. (why or "Scanning unavailable") .. "|r")
  elseif not C.Scan.open then self.ahNote:SetText(G.orange .. "AH closed: open it to scan|r")
  else self.ahNote:SetText(G.green .. "AH open|r") end
  self.scanButton:SetEnabled(not p and C.Scan.open and capable and true or false)
  self.cancelButton:SetEnabled(p and true or false)
  self.own:Refresh()
  if C.mode == "All Crates" then self.own:Show(); self.own.label:Show() else self.own:Hide(); self.own.label:Hide() end
  local verified, total = C.Inventory:Coverage()
  self.coverage:SetText((verified < total and G.orange or "") .. verified .. "/" .. total .. " recipes verified" .. (verified < total and "|r" or ""))
  -- header follows the same geometry as the rows
  local c = self.cols
  for key, fs in pairs(self.head) do
    local x, w = c[key].x, c[key].w
    place(fs, self.headFrame, x, w)
  end
  self.head.cost:SetText(C.mode == "Buy & Fill" and "Total" or "Cost")
end

function P:Refresh()
  if not self.frame or not self.frame:IsVisible() then return end
  local sw = self.scroll:GetWidth()
  if sw and sw > 0 then self.content:SetWidth(sw) end
  self.cols = P.Columns(sw and sw > 0 and sw or self.content:GetWidth())
  self:Chrome()
  self.index, self.y, self.stripe = 0, 0, false
  local rows = C.Model:Rows()
  self.empty:SetText(#rows == 0 and EMPTY[C.mode] or "")
  for _, row in ipairs(rows) do
    local id, rec, best = row.id, row.rec, row.best
    local state = rec and rec.state or "unsupported"
    local accent = ACCENT[state] or ACCENT.info
    row.toggle = function() self.expanded[id] = not self.expanded[id]; self:Refresh() end
    local w = self:Line("crate", accent)
    w.onClick = row.toggle
    w.expander:SetText(self.expanded[id] and "-" or "+")
    setIcon(w.crateIcon, id)
    local name = (row.crate.name or ("Item " .. id)):gsub("^Waylaid Crate: ", "")
    w.crate:SetText(name .. ((C.mode == "My Crates" and row.count > 1) and (G.grey .. " x" .. row.count .. "|r") or ""))
    if row.crate.level then w.fields.level:SetText(row.locked and (G.red .. row.crate.level .. "|r") or (G.grey .. row.crate.level .. "|r")) end
    local hover = { row.crate.name or ("Item " .. id),
      "Item ID " .. id .. (row.crate.level and (" · requires level " .. row.crate.level) or "") .. (row.locked and (" · " .. G.red .. "your level is too low|r") or "") }
    if best then
      local win = state ~= "unpriced"
      local color = state == "estimate" and G.amber or G.green
      setIcon(w.bundleIcon, best.bundle.itemID)
      local label = rec.tie and (#rec.winnerList .. " tied bundles") or bundleText(best.bundle)
      w.fields.bundle:SetText(win and (color .. label .. "|r") or (G.grey .. bundleText(best.bundle) .. "|r"))
      setBadge(w, P.Badge(rec))
      w.fields.need:SetText(tostring(best.missing))
      local status = P.StatusLabel(best)
      if rec.partial then status = status .. G.grey .. " " .. rec.priced .. "/" .. rec.total .. "|r" end
      if row.cratePrice and row.cratePrice.kind ~= "live" then status = status .. G.orange .. " · crate " .. (row.cratePrice.kind == "estimate" and "est." or "--") .. "|r" end
      w.fields.status:SetText(status)
      hover[#hover + 1] = (rec.partial and "Cheapest of priced bundles: " or (rec.tie and "Tied cheapest: " or "Recommended: ")) .. bundleText(best.bundle)
      hover[#hover + 1] = "Owned " .. best.owned .. " · need " .. best.missing
      hover[#hover + 1] = row.status
      if state == "estimate" then hover[#hover + 1] = "Cached estimate only, not an available buyout. Scan the AH to confirm." end
    else
      w.fields.bundle:SetText(G.red .. "Not verified|r")
      w.fields.need:SetText(G.grey .. "--|r")
      w.fields.status:SetText(G.red .. "Unsupported|r")
      hover[#hover + 1] = row.status
    end
    w.fields.cost:SetText(row.cost and C.Coins(row.cost) or (G.grey .. "--|r"))
    w.hover = hover
    self:Finish(w)
    if self.expanded[id] then
      if not row.alternatives then
        local u = self:Line("sub", accent)
        local why = (row.crate and row.crate.validation) or row.status or "Tooltip unverified"
        u.crate:SetText(G.red .. "Not verified:|r " .. why)
        u.hover = { "Unsupported crate", row.status or "", "Unknown or unverified recipes are never priced." }; u.onClick = row.toggle
        self:Finish(u)
        place(u.fields.crate, u, self.cols.crate.x + 14, self.cols.width - self.cols.crate.x - 22)
      else
        if row.cratePrice then self:BuyAndFill(row, accent) end
        self:Alternatives(row, accent)
      end
    end
  end
  for i = self.index + 1, #self.widgets do self.widgets[i]:Hide() end
  self.content:SetHeight(math.max(1, self.y))
end

-- The engine calls C.UI:Toggle() for "inspect": open the page.
function P:Toggle() if AA.UI then AA.UI.ShowPage("crates") end end

-- Events ---------------------------------------------------------------------
local queued = false
local function refreshData(validate)
  C.Inventory:Read()
  if validate then C.Inventory:ValidateCatalog() end
  C.Changed()
end
local function queueRefresh()
  if queued then return end
  queued = true
  C_Timer.After(0.5, function() queued = false; refreshData(true) end)
end
C.RefreshData = refreshData

AA:On("PLAYER_LOGIN", function()
  local s = settings()
  C.countOwned = s.countOwned == true
  C.Scan:InstallHooks()
  C.Tooltip:Install()
  refreshData(true)
end)
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP" }) do AA:On(ev, queueRefresh) end
for _, ev in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED" }) do
  AA:On(ev, function(event, arg)
    local ok, err = pcall(C.Scan.Event, C.Scan, event, arg)
    if not ok then C.Scan:Cancel("Scan error: " .. tostring(err)) end
  end)
end

-- /fam crates [verify | cancel | inspect ITEMID]
function P.Slash(rest)
  rest = AA.Trim(rest or ""):lower()
  if rest == "verify" then
    refreshData(true)
    local n, t = C.Inventory:Coverage()
    AA:Print("Crates: " .. n .. "/" .. t .. " recipes verified against this client's tooltips.")
  elseif rest == "cancel" then
    C.Scan:Cancel()
  elseif rest:match("^inspect %d+$") then
    local id = tonumber(rest:match("%d+")); C.unsupported[id] = C.ItemName(id); P:Toggle()
  else
    refreshData(true); P:Toggle()
  end
end

-- /cratescout keeps working for former Crate Scout users.
SLASH_AZEROTHASSISTANTCRATES1 = "/cratescout"
SlashCmdList.AZEROTHASSISTANTCRATES = function(msg) P.Slash(msg) end

AA.Shell.Register({
  id = "crates", title = "Crates", order = 55,
  icon = function() return C.ItemIcon(248685) or C.CRATE_ICON end,
  subtitle = "Waylaid Crates: cheapest bundle to fill one, and AH cash to buy and fill.",
  interval = 5, -- snapshot ages and 120 s expiry
  makeFrame = function(host) return P.Make(host) end,
  refresh = function() P:Refresh() end,
})

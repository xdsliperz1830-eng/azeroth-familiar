-- Azeroth Familiar - UI/Shell.lua
-- The main window's navigation and page host. Each feature registers a page; a page is
-- built the first time it is opened, inside pcall, so one broken page can't take the
-- window (or the other pages) down with it. Only the page on screen is refreshed, on a
-- slow timer that stops when the window is hidden.

local ADDON, AA = ...
local Sh = {}
AA.Shell = Sh
local W = AA.W

Sh.defs = {}   -- id -> definition
Sh.order = {}  -- sorted list of definitions
local state = {} -- id -> { frame, layout, built, broken }
local nav, host, navButtons, modeText, current, shellFrame
local NAV_W, NAV_COMPACT = 128, 36

-- Space taken by the window's frame on each side (set by UI.lua; 1 px for the plain border).
local function frameInsets()
  return (shellFrame and shellFrame.aaInsets) or { l = 1, t = 1, r = 1, b = 1, curl = 0 }
end
local flashToken = 0

-- def: { id, title, icon, order, subtitle, build(L, page), refresh(L), interval, frame, onShow }
function Sh.Register(def)
  Sh.defs[def.id] = def
  Sh.order[#Sh.order + 1] = def
  table.sort(Sh.order, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

local function settings() return AA.db.settings end

local function pageState(def)
  local st = state[def.id]
  if st then return st end
  st = {}
  state[def.id] = st
  -- makeFrame(host): a page that draws its own frame (the Crates table), built the first
  -- time it is opened. If it fails, the page shows the usual error note instead.
  local ok, err = true, nil
  if not def.frame and def.makeFrame then
    local made
    ok, made = pcall(def.makeFrame, host)
    if ok and made then def.frame = made
    elseif ok then ok, err = false, "page frame missing"
    else err = made end
  end
  if def.frame then
    st.frame = def.frame
    st.frame:SetAllPoints(host)
    st.built = true
    return st
  end
  local sf, child = W.Scroll(host)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -4, 4)
  st.frame = sf
  st.child = child
  st.layout = W.Layout(child)
  if ok then ok, err = pcall(def.build, st.layout, child) end
  if ok then
    st.built = true
    st.layout:Finish()
  else
    st.broken = tostring(err)
    AA.pageErrors = AA.pageErrors or {}
    AA.pageErrors[def.id] = st.broken
    local fs = W.Text(child, AA.C.warn .. "This page hit an error and was switched off:|r\n" .. st.broken)
    fs:SetPoint("TOPLEFT", 12, -12)
    fs:SetPoint("RIGHT", child, "RIGHT", -12, 0)
  end
  return st
end

local function refreshPage(def)
  local st = state[def.id]
  if not st or not st.built or st.broken then return end
  if st.layout or def.refresh then
    local ok, err = pcall(function()
      if st.layout then st.layout:Refresh() end
      if def.refresh then def.refresh(st.layout) end
    end)
    if not ok then
      -- Keep the page; it is tried again on the next refresh. The text is kept for /aa diag.
      AA.pageErrors = AA.pageErrors or {}
      AA.pageErrors[def.id] = tostring(err)
    end
  end
end

function Sh.Current() return current end

function Sh.Refresh()
  local def = current and Sh.defs[current]
  if def then refreshPage(def) end
end

-- Resizing: when the page area changes size, the current page lays itself out again for
-- the new width and height: the layout's right-hand column (L:Column), then the page's own
-- def.resize(L, width, height) if it has one. While the window is being dragged this runs
-- at most ten times a second; Sh.Relayout(true) runs it right away (when the drag ends).
local relayoutQueued = false

-- Page zoom: on a window bigger than the default, a page scales up evenly (text, icons,
-- rows, buttons), from 100% at the default page area (about ZOOM_W x ZOOM_H) up to
-- ZOOM_MAX, in 5% steps so dragging doesn't jitter. The page is then laid out again in
-- its zoomed size, so it still fills the width. Pages with def.zoom == false (Overview,
-- which sizes its own cards) stay at 100%.
local ZOOM_W, ZOOM_H, ZOOM_MAX = 600, 430, 1.3
local function pageZoom(def)
  if def.zoom == false or not host then return 1 end
  local w, h = tonumber(host:GetWidth()) or 0, tonumber(host:GetHeight()) or 0
  if w <= 0 or h <= 0 then return 1 end
  local z = math.min(w / ZOOM_W, h / ZOOM_H)
  return math.max(1, math.min(ZOOM_MAX, math.floor(z * 20 + 0.5) / 20))
end

function Sh.Relayout(now)
  if not now then
    if relayoutQueued then return end
    relayoutQueued = true
    if C_Timer and C_Timer.After then
      C_Timer.After(0.1, function() relayoutQueued = false; Sh.Relayout(true) end)
      return
    end
    relayoutQueued = false
  end
  pcall(Sh.LayoutNav)
  local def = current and Sh.defs[current]
  local st = def and state[def.id]
  if not st or not st.built or st.broken then return end
  local z = pageZoom(def)
  if st.zoom ~= z then
    st.zoom = z
    st.frame:SetScale(z)
    Sh.Relayout()          -- measure again once the zoomed page has its new size
  end
  local w = st.child and tonumber(st.child:GetWidth()) or tonumber(st.frame:GetWidth())
  local h = tonumber(st.frame:GetHeight())
  if not w or w < 50 then return end
  local ok, err = pcall(function()
    if st.layout and st.layout.Reflow then st.layout:Reflow(w) end
    if def.resize then def.resize(st.layout, w, h) end
  end)
  if not ok then
    AA.pageErrors = AA.pageErrors or {}
    AA.pageErrors[def.id] = tostring(err)
  end
end

local function paintNav()
  for id, b in pairs(navButtons or {}) do
    local on = (id == current)
    b.sel:SetAlpha(on and 1 or 0)
    b.text:SetText((on and "|cffffffff" or W.GOLD) .. Sh.defs[id].title .. "|r")
  end
end

function Sh.Show(id)
  if not host then return end
  local def = Sh.defs[id] or Sh.defs.overview or Sh.order[1]
  if not def then return end
  for otherId, st in pairs(state) do
    if otherId ~= def.id and st.frame then st.frame:Hide() end
  end
  local st = pageState(def)
  current = def.id
  settings().lastPage = def.id
  st.frame:Show()
  if modeText then modeText:SetText(def.subtitle or "") end
  paintNav()
  refreshPage(def)
  Sh.Relayout(true)
  Sh.Relayout()          -- again once a first-time page has its size
  if def.onShow then pcall(def.onShow) end
end

-- Page to open first: the user's choice in Interface settings.
function Sh.StartPage()
  local s = settings()
  local id = s.startPage
  if id == "last" then id = s.lastPage end
  if not Sh.defs[id] then id = "overview" end
  return id
end

-- Short feedback in the title bar after a setting changes.
function Sh.Flash(msg, good)
  if not modeText then return end
  flashToken = flashToken + 1
  local mine = flashToken
  modeText:SetText((good == false and AA.C.warn or AA.C.good) .. tostring(msg) .. "|r")
  if C_Timer and C_Timer.After then
    C_Timer.After(8, function()
      if mine == flashToken and modeText and current and Sh.defs[current] then
        modeText:SetText(Sh.defs[current].subtitle or "")
      end
    end)
  end
end

function Sh.ApplyLayout()
  if not nav then return end
  local compact = settings().compactNav and true or false
  local w = compact and NAV_COMPACT or NAV_W
  -- inside the left, top (below the 24 px title bar) and bottom bands of the current
  -- border; 2 px clear of the side ornaments
  local nins = frameInsets()
  nav:ClearAllPoints()
  nav:SetPoint("TOPLEFT", nins.l + 2, -(nins.t + 25))
  nav:SetPoint("BOTTOMLEFT", nins.l + 2, nins.b)
  nav:SetWidth(w)
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 1, 0)
  -- inside the right and bottom bands, and above the bottom-right corner curl
  local ins = frameInsets()
  host:SetPoint("BOTTOMRIGHT", -ins.r, ins.b + ins.curl)
  for _, b in pairs(navButtons) do
    b:SetWidth(w - 2)
    if compact then b.text:Hide() else b.text:Show() end
  end
  Sh.LayoutNav()
end

-- Menu rows share the menu's height: 28 px each on a short window, up to 36 px with
-- slightly bigger icons on a tall one, so the menu has no empty lower half.
function Sh.LayoutNav()
  if not nav or not navButtons then return end
  local n = #Sh.order
  if n == 0 then return end
  local compact = settings().compactNav and true or false
  local h = tonumber(nav:GetHeight()) or 0
  local bh = math.max(28, math.min(36, math.floor((h - 12) / n) - 2))
  local big = false                       -- keep the regular menu font
  local icon = math.min(26, bh - 6)
  local y = -6
  for _, def in ipairs(Sh.order) do
    local b = navButtons[def.id]
    if b then
      b:SetHeight(bh)
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 1, y)
      if b.icon then b.icon:SetSize(icon, icon) end
      b.text:SetFontObject(big and GameFontNormal or GameFontNormalSmall)
      b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 6 + icon + 8, 0)
      y = y - bh - 2
    end
  end
  paintNav()
end

-- Called once by UI.lua when the window is created.
function Sh.Attach(frame, mode)
  modeText = mode
  shellFrame = frame
  local ins = frameInsets()
  nav = CreateFrame("Frame", nil, frame)
  -- inside the left, top (below the 24 px title bar) and bottom bands; 2 px clear of the side gems
  nav:SetPoint("TOPLEFT", ins.l + 2, -(ins.t + 25))
  nav:SetPoint("BOTTOMLEFT", ins.l + 2, ins.b)
  nav:SetWidth(NAV_W)
  W.Bg(nav, 0.08, 0.08, 0.10, 1)
  local edge = nav:CreateTexture(nil, "BORDER")
  edge:SetColorTexture(0.45, 0.36, 0.18, 0.8)
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT")

  host = CreateFrame("Frame", nil, frame)
  host:SetScript("OnSizeChanged", function() Sh.Relayout() end)
  navButtons = {}
  local y = -6
  for _, def in ipairs(Sh.order) do
    local b = CreateFrame("Button", nil, nav)
    b:SetSize(NAV_W - 2, 28)
    b:SetPoint("TOPLEFT", 1, y)
    y = y - 30
    local sel = b:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetColorTexture(0.45, 0.10, 0.06, 0.85)
    sel:SetAlpha(0)
    b.sel = sel
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)
    local icon = def.icon
    if type(icon) == "function" then     -- e.g. the Character page's race-matched head
      local ok, path = pcall(icon)
      icon = ok and path or nil
    end
    local ic = W.Icon(b, icon, 22)
    ic:SetPoint("LEFT", 6, 0)
    b.icon = ic
    b.text = W.Text(b, def.title, "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 34, 0)
    local id = def.id
    b:SetScript("OnClick", function() Sh.Show(id) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(def.title)
      if def.subtitle then GameTooltip:AddLine(def.subtitle, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    navButtons[id] = b
  end
  Sh.ApplyLayout()

  -- One slow timer for whichever page is on screen. Stops when the window is hidden.
  local acc = 0
  host:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (tonumber(elapsed) or 0)
    local def = current and Sh.defs[current]
    if def and def.interval and acc >= def.interval then
      acc = 0
      refreshPage(def)
    elseif acc > 60 then
      acc = 0
    end
  end)
  return host
end

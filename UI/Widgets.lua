-- Azeroth Familiar - UI/Widgets.lua
-- Shared look and reusable controls for every page. Plain (non-secure) frames only.
-- Templates used: UIPanelButtonTemplate, UICheckButtonTemplate, InputBoxTemplate; each
-- falls back to a plain frame if the client lacks it. No dropdown or slider templates
-- (not verified on WoW Forever): choices use a cycle button, numbers use a -/+ stepper.

local ADDON, AA = ...
local W = {}
AA.W = W

W.GOLD = "|cffffd100"
W.GREY = "|cff9d9d9d"

function W.Template(ftype, parent, template)
  local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
  if ok and f then return f, true end
  return CreateFrame(ftype, nil, parent), false
end

function W.Bg(f, r, g, b, a)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r, g, b, a)
  return t
end

-- Thin metallic edge: dark bronze by default.
function W.Border(f, r, g, b, a)
  r, g, b, a = r or 0.45, g or 0.36, b or 0.18, a or 1
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, a)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
end

-- Ornate frames ---------------------------------------------------------------------
-- Each style's texture holds the whole frame artwork at half size (768x512 of a 1024x512
-- texture). It is drawn as a 9-slice: corners keep their shape, plain strips of each band
-- stretch, and the centre ornaments stay centred and unstretched. Numbers are in source
-- pixels of the 1536x1024 originals.
--   O*  transparent margin outside the outer edge of the band
--   I*  band thickness (outer edge to inner edge)
--   CURL how far the corners reach inside the band
--   C   corner piece size; strips = { x or y of a plain 8 px slice, ... }
--   top/bottom/side = ornament rects { x, y, w, h }; gemY = side gems' offset above centre
local MEDIA = "Interface\\AddOns\\AzerothAssistant\\Media\\"
W.FRAME_STYLES = {
  gold = {
    tex = MEDIA .. "Frame",
    OL = 16, OT = 20, OR = 16, OB = 26, IL = 45, IT = 71, IR = 45, IB = 63,
    CURL = 74, C = 240, stripX = 300, stripY = 300, edgeH = 110, edgeW = 80,
    top = { 496, 0, 544, 110 }, bottom = { 576, 914, 384, 110 }, side = { 410, 168 }, gemY = 15,
  },
  horde = {
    tex = MEDIA .. "FrameHorde",
    OL = 36, OT = 48, OR = 37, OB = 55, IL = 54, IT = 77, IR = 54, IB = 78,
    CURL = 82, C = 290, stripX = 280, stripY = 296, edgeH = 200, edgeW = 140,
    top = { 548, 0, 444, 200 }, bottom = { 548, 824, 444, 200 }, side = { 420, 140 }, gemY = 18,
  },
  alliance = {
    tex = MEDIA .. "FrameAlliance",
    OL = 18, OT = 37, OR = 17, OB = 35, IL = 60, IT = 74, IR = 60, IB = 81,
    CURL = 36, C = 200, stripX = 300, stripY = 300, edgeH = 164, edgeW = 120,
    top = { 520, 0, 496, 150 }, bottom = { 520, 860, 496, 164 }, side = { 420, 140 }, gemY = 26,
  },
}
W.FRAME_TEX = W.FRAME_STYLES.gold.tex
-- Every style is drawn so its side bands are as thick as the gold frame's at the same s.
local function styleOf(name) return W.FRAME_STYLES[name or "gold"] or W.FRAME_STYLES.gold end
local function norm(G) return 45 / G.IL end

local function frameTex(holder, G, sx, sy, sw, sh, s, sub)
  local t = holder:CreateTexture(nil, "ARTWORK", nil, sub or 0)
  local ok = t:SetTexture(G.tex)
  t:SetTexCoord(sx / 2048, (sx + sw) / 2048, sy / 1024, (sy + sh) / 1024)
  t:SetSize(sw * s, sh * s)
  return t, ok
end

-- Draws the frame on f at scale s (screen px per source px of the gold frame).
-- opts.style: "gold" (default), "horde" or "alliance".
-- opts.outside: put the frame around the outside of f, with the corners in a gap filled
--   with opts.bg ({r, g, b, a}), so nothing inside f moves.
-- Otherwise the band's outer edge is f's edge and the bands lie inside it.
-- Returns the inside insets { l, t, r, b, curl } (all 0 when outside), or nil when the
-- texture can't be used (callers then keep their plain border).
function W.OrnateFrame(f, s, opts)
  opts = opts or {}
  local G = styleOf(opts.style)
  s = s * norm(G)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints(f)
  holder:SetFrameLevel(f:GetFrameLevel() + 30)   -- ornaments sit over the edge of the content
  local push = { l = 0, t = 0, r = 0, b = 0 }
  if opts.outside then
    local gap = G.CURL * s
    push = { l = G.IL * s + gap, t = G.IT * s + gap, r = G.IR * s + gap, b = G.IB * s + gap }
    local bg = opts.bg or { 0.04, 0.04, 0.06, 0.97 }
    -- on f itself, at the lowest layer, so it stays behind everything in f
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    fill:SetPoint("TOPLEFT", -(push.l - G.IL * s * 0.5), push.t - G.IT * s * 0.5)
    fill:SetPoint("BOTTOMRIGHT", push.r - G.IR * s * 0.5, -(push.b - G.IB * s * 0.5))
    holder.fill = fill
  end
  local art = holder
  local C = G.C
  local tl, ok = frameTex(art, G, 0, 0, C, C, s, 1)
  if ok == false then holder:Hide(); if holder.fill then holder.fill:Hide() end; return nil end
  tl:SetPoint("TOPLEFT", f, "TOPLEFT", -(G.OL * s + push.l), G.OT * s + push.t)
  local tr = frameTex(art, G, 1536 - C, 0, C, C, s, 1)
  tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", G.OR * s + push.r, G.OT * s + push.t)
  local bl = frameTex(art, G, 0, 1024 - C, C, C, s, 1)
  bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -(G.OL * s + push.l), -(G.OB * s + push.b))
  local br = frameTex(art, G, 1536 - C, 1024 - C, C, C, s, 1)
  br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", G.OR * s + push.r, -(G.OB * s + push.b))
  -- plain strips between the corners
  local top = frameTex(art, G, G.stripX, 0, 8, G.edgeH, s)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
  local bottom = frameTex(art, G, G.stripX, 1024 - G.edgeH, 8, G.edgeH, s)
  bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = frameTex(art, G, 0, G.stripY, G.edgeW, 8, s)
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
  local right = frameTex(art, G, 1536 - G.edgeW, G.stripY, G.edgeW, 8, s)
  right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  -- centred ornaments (the window's centre lines up with the artwork's centre)
  local midX = (push.r - push.l) / 2
  local midY = ((push.t - push.b) / 2) + G.gemY * s
  local o = frameTex(art, G, G.top[1], G.top[2], G.top[3], G.top[4], s, 2)
  o:SetPoint("TOP", f, "TOP", midX, G.OT * s + push.t)
  o = frameTex(art, G, G.bottom[1], G.bottom[2], G.bottom[3], G.bottom[4], s, 2)
  o:SetPoint("BOTTOM", f, "BOTTOM", midX, -(G.OB * s + push.b))
  o = frameTex(art, G, 0, G.side[1], G.edgeW, G.side[2], s, 2)
  o:SetPoint("LEFT", f, "LEFT", -(G.OL * s + push.l), midY)
  o = frameTex(art, G, 1536 - G.edgeW, G.side[1], G.edgeW, G.side[2], s, 2)
  o:SetPoint("RIGHT", f, "RIGHT", G.OR * s + push.r, midY)
  f.ornate = holder
  if opts.outside then return { l = 0, t = 0, r = 0, b = 0, curl = 0 } end
  return { l = G.IL * s, t = G.IT * s, r = G.IR * s, b = G.IB * s, curl = math.max(0, G.CURL - 5) * s }
end

-- Removes a frame drawn by W.OrnateFrame (to switch style, or go back to a plain border).
function W.RemoveOrnateFrame(f)
  local h = f and f.ornate
  if h then
    h:Hide()
    if h.fill then h.fill:Hide() end
    f.ornate = nil
  end
end

-- How far a frame drawn with opts.outside reaches past each side of its window.
function W.OrnateReach(s, style)
  local G = styleOf(style)
  return (G.OL + G.IL + G.CURL) * s * norm(G)
end

-- Tooltip on hover. extra: optional list of grey lines (or a function returning one).
function W.Tip(f, title, text, extra)
  if not title then return end
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    local more = type(extra) == "function" and extra() or extra
    if type(more) == "table" then
      for _, l in ipairs(more) do GameTooltip:AddLine(l, 0.6, 0.6, 0.6, true) end
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Invisible hover area that shows a tooltip (for a label or icon, which can't have one).
function W.Hover(parent, x, y, w, h, title, text, extra)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", x, y)
  f:SetSize(w, h)
  f:EnableMouse(true)
  W.Tip(f, title, text, extra)
  return f
end

function W.Text(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

function W.Icon(parent, texture, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size or 24, size or 24)
  t:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return t
end

function W.Button(parent, text, width, onClick, tipTitle, tipText)
  local b, templated = W.Template("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width or 80, 22)
  if not templated then
    W.Bg(b, 0.45, 0.08, 0.06, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
  end
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  W.Tip(b, tipTitle, tipText)
  return b
end

function W.Check(parent, label, getter, setter, tipTitle, tipText, tipExtra)
  local cb, templated = W.Template("CheckButton", parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  if not templated then W.Bg(cb, 0.2, 0.2, 0.2, 1) end
  local fs = W.Text(parent, label)
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label = fs
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Refresh = function(self) self:SetChecked(getter() and true or false) end
  W.Tip(cb, tipTitle, tipText, tipExtra)
  return cb
end

function W.Input(parent, maxLetters)
  local eb, templated = W.Template("EditBox", parent, "InputBoxTemplate")
  if not templated then
    W.Bg(eb, 0, 0, 0, 0.6)
    eb:SetTextInsets(6, 6, 0, 0)
  end
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetHeight(22)
  eb:SetMaxLetters(maxLetters or 60)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return eb
end

-- [-] value [+]. opts: get() -> number or nil, set(v), min, max, step, fmt(v) -> text
-- max may be a function, for limits learned while the game runs.
function W.Stepper(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(150, 22)
  local value = W.Text(f, "", "GameFontHighlight")
  local function top()
    if type(opts.max) == "function" then return tonumber(opts.max()) end
    return opts.max
  end
  local function clamp(v)
    local hi = top()
    if opts.min and v < opts.min then v = opts.min end
    if hi and v > hi then v = hi end
    return v
  end
  local function bump(dir)
    local cur = tonumber(opts.get())
    if not cur then return end
    local step = opts.step or 1
    -- snap to the step grid so 0.75 + 0.05 doesn't drift
    local v = clamp(math.floor((cur + dir * step) / step + 0.5) * step)
    opts.set(v)
    f:Refresh()
  end
  local minus = W.Button(f, "-", 24, function() bump(-1) end)
  minus:SetPoint("LEFT", 0, 0)
  value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
  value:SetWidth(74)
  value:SetJustifyH("CENTER")
  local plus = W.Button(f, "+", 24, function() bump(1) end)
  plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
  function f:Refresh()
    local cur = opts.get()
    local n = tonumber(cur)
    if n == nil then
      value:SetText(W.GREY .. "n/a|r")
      minus:Disable(); plus:Disable()
    else
      value:SetText(opts.fmt and opts.fmt(n) or tostring(n))
      local hi, eps = top(), (opts.step or 1) / 2
      if opts.min and n <= opts.min + eps * 0.01 then minus:Disable() else minus:Enable() end
      if hi and n >= hi - eps * 0.01 then plus:Disable() else plus:Enable() end
    end
  end
  return f
end

-- Cycle button: click to move to the next choice. options = { { value, label }, ... }
function W.Choice(parent, width, options, get, set, tipTitle, tipText)
  local b
  local function index()
    local cur = get()
    for i, o in ipairs(options) do if o[1] == cur then return i end end
    return 1
  end
  b = W.Button(parent, "", width, function()
    local i = index() % #options + 1
    set(options[i][1])
    b:Refresh()
  end, tipTitle, tipText)
  function b:Refresh() self:SetText(options[index()][2]) end
  return b
end

-- Information card: icon, small gold title, value text.
function W.Card(parent, icon, title, w, h)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(w or 236, h or 46)
  W.Bg(c, 0.10, 0.10, 0.13, 0.95)
  W.Border(c, 0.28, 0.24, 0.14, 1)
  local ic = W.Icon(c, icon, 30)
  ic:SetPoint("LEFT", 8, 0)
  local t = W.Text(c, title, "GameFontNormalSmall")
  t:SetPoint("TOPLEFT", 46, -7)
  local v = W.Text(c, "", "GameFontHighlight")
  v:SetPoint("TOPLEFT", 46, -22)
  v:SetPoint("RIGHT", c, "RIGHT", -6, 0)
  if v.SetWordWrap then v:SetWordWrap(false) end
  c.value = v
  c.icon = ic
  c.title = t
  return c
end

-- Vertical scrolling area. Returns the scroll frame and its content child.
function W.Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(480, 10)
  sf:SetScrollChild(child)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = tonumber(self:GetVerticalScrollRange()) or 0
    local cur = tonumber(self:GetVerticalScroll()) or 0
    self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 40)))
  end)
  sf:SetScript("OnSizeChanged", function(self, w)
    w = tonumber(w) or tonumber(self:GetWidth())
    if w and w > 50 then child:SetWidth(w) end
  end)
  return sf, child
end

-- Top-to-bottom layout helper for a page. All rows share the same spacing.
function W.Layout(p)
  local L = { y = -8, p = p, refreshers = {}, columns = {} }
  local function track(w) L.refreshers[#L.refreshers + 1] = w; return w end

  -- Right-hand column: a control placed at the right edge of the page (16 px in), but
  -- never left of minX, its old fixed spot. L:Reflow(width) moves the column when the
  -- page gets wider or narrower (the page shell calls it on resize).
  local function placeColumn(c, width)
    local w = tonumber(c.widget:GetWidth()) or 150
    local x = math.max(c.minX, math.floor((width or 0) - 16 - w))
    c.widget:ClearAllPoints()
    c.widget:SetPoint("TOPLEFT", p, "TOPLEFT", x, c.y)
  end
  function L:Column(widget, y, minX)
    local c = { widget = widget, y = y, minX = minX or 220 }
    self.columns[#self.columns + 1] = c
    placeColumn(c, tonumber(p:GetWidth()))
    return widget
  end
  function L:Reflow(width)
    for _, c in ipairs(self.columns) do placeColumn(c, width) end
  end

  function L:Row(h) local y = self.y; self.y = self.y - h; return y end
  function L:Space(h) self.y = self.y - (h or 8) end

  function L:Header(text)
    local y = self:Row(24)
    local fs = W.Text(p, text, "GameFontNormal")
    fs:SetPoint("TOPLEFT", 10, y - 2)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.45, 0.36, 0.18, 0.7)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 10, y - 19)
    line:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    return fs
  end

  -- Small grey wrapped note. lines = how many text lines to reserve.
  function L:Note(text, lines)
    local y = self:Row(13 * (lines or 1) + 6)
    local fs = W.Text(p, text, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 12, y)
    fs:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    fs:SetJustifyV("TOP")
    return fs
  end

  -- "Label      value" line; returns the value font string.
  function L:KV(label, labelWidth)
    local y = self:Row(18)
    local l = W.Text(p, label, "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 12, y)
    local v = W.Text(p, "", "GameFontHighlightSmall")
    v:SetPoint("TOPLEFT", 12 + (labelWidth or 120), y)
    v:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    if v.SetWordWrap then v:SetWordWrap(false) end
    return v
  end

  function L:Check(label, getter, setter, tipTitle, tipText, tipExtra)
    local cb = W.Check(p, label, getter, setter, tipTitle, tipText, tipExtra)
    cb:SetPoint("TOPLEFT", 10, self:Row(26))
    return track(cb)
  end

  -- Label on the left, stepper on the right of it.
  function L:Stepper(label, opts, tipTitle, tipText)
    local y = self:Row(28)
    local l = W.Text(p, label)
    l:SetPoint("TOPLEFT", 14, y - 5)
    local s = W.Stepper(p, opts)
    self:Column(s, y, 220)
    if tipTitle then W.Hover(p, 10, y, 200, 24, tipTitle, tipText) end
    return track(s)
  end

  -- list = { { text, width, onClick, tipTitle, tipText }, ... }
  function L:Buttons(list)
    local y = self:Row(28)
    local x, out = 10, {}
    for _, d in ipairs(list) do
      local b = W.Button(p, d[1], d[2], d[3], d[4], d[5])
      b:SetPoint("TOPLEFT", x, y)
      x = x + d[2] + 6
      out[#out + 1] = b
    end
    return out
  end

  function L:Track(w) return track(w) end
  function L:Refresh()
    for _, w in ipairs(self.refreshers) do w:Refresh() end
  end
  function L:Finish() p:SetHeight(-self.y + 12) end
  return L
end

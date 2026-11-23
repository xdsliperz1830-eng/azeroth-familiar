-- Azeroth Familiar - UI.lua
-- Plain (non-secure) frames only: safe to open in combat, no protected actions.
-- Templates used: UIPanelButtonTemplate, UIPanelCloseButton, UICheckButtonTemplate,
-- InputBoxTemplate. Each one falls back to a plain frame if the client lacks it.

local ADDON, AA = ...
local UI = {}
AA.UI = UI

local MIN_W, MIN_H = 670, 470   -- room for the frame bands; pages keep their old space
-- Size of the ornate frame (screen px per px of the frame artwork): main window, dialogs,
-- and the Assistant's Settings panel.
UI.FRAME_SCALE, UI.DIALOG_FRAME_SCALE, UI.PANEL_FRAME_SCALE = 0.25, 0.2, 0.12

local function tryTemplate(ftype, parent, template)
  local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
  if ok and f then return f, true end
  return CreateFrame(ftype, nil, parent), false
end

local function addBackground(f, r, g, b, a)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r, g, b, a)
  return t
end

-- The original plain border: a 1 px bronze line. Kept on f.plainBorder so it can be
-- shown or hidden when the window border style changes.
local function addBorder(f)
  local c = { 0.45, 0.36, 0.18, 1 } -- bronze, matches UI/Widgets.lua
  local edges = {}
  local function edge(p1, p2, w, h)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(c))
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    edges[#edges + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
  f.plainBorder = edges
  return edges
end

-- Window border style ------------------------------------------------------------------
-- Setting "border": "faction" (default: red Horde frame or blue Alliance frame, the gold
-- frame for anyone else), "gold", or "plain" (the original 1 px line).
function UI.BorderStyle()
  local pick = AA.db and AA.db.settings and AA.db.settings.border or "faction"
  if pick == "plain" or pick == "gold" then return pick end
  local ok, faction = pcall(UnitFactionGroup, "player")
  if ok and faction == "Horde" then return "horde" end
  if ok and faction == "Alliance" then return "alliance" end
  return "gold"
end

-- Every window with a border: { f, scale, outside, bg, onInsets(ins) }. ins is nil when the
-- plain line is shown (by choice, or because the frame texture couldn't be used).
local framed = {}
local function frameWindow(e, style)
  if AA.W.RemoveOrnateFrame then AA.W.RemoveOrnateFrame(e.f) end
  local ins
  if style ~= "plain" and AA.W.OrnateFrame then
    ins = AA.W.OrnateFrame(e.f, e.scale, { style = style, outside = e.outside, bg = e.bg })
  end
  if not e.f.plainBorder then addBorder(e.f) end
  for _, t in ipairs(e.f.plainBorder) do t:SetShown(not ins) end
  if e.onInsets then e.onInsets(ins) end
end

local function addFramed(e)
  framed[#framed + 1] = e
  if not UI.borderStyle then UI.borderStyle = UI.BorderStyle() end
  frameWindow(e, UI.borderStyle)
end

-- The faction is certain once the character is in the world: re-check then (a window
-- built earlier may have used the gold fallback).
AA:On("PLAYER_ENTERING_WORLD", function()
  if #framed > 0 and UI.BorderStyle() ~= UI.borderStyle then UI.ApplyBorder() end
end)

-- Re-applies the border to every window (after the setting changes, or once the
-- character's faction is known).
function UI.ApplyBorder()
  local style = UI.BorderStyle()
  UI.borderStyle = style
  for _, e in ipairs(framed) do frameWindow(e, style) end
end

local function makeButton(parent, text, width, onClick)
  local b, templated = tryTemplate("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  if not templated then
    addBackground(b, 0.25, 0.2, 0.1, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
  end
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function makeCheck(parent, label, getter, setter)
  local cb, templated = tryTemplate("CheckButton", parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  if not templated then addBackground(cb, 0.2, 0.2, 0.2, 1) end
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(label)
  cb.label = fs
  cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
  cb.Refresh = function(self) self:SetChecked(getter() and true or false) end
  return cb
end

local function makeInput(parent)
  local eb, templated = tryTemplate("EditBox", parent, "InputBoxTemplate")
  if not templated then
    addBackground(eb, 0, 0, 0, 0.6)
    eb:SetTextInsets(6, 6, 0, 0)
  end
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetHeight(24)
  return eb
end

local function S() return AA.db.settings end

-- Scrolling multi-line edit box inside a dark panel.
local function makeScrollEdit(parent, width)
  local box = CreateFrame("Frame", nil, parent)
  addBackground(box, 0, 0, 0, 0.6)
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -6, 6)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(width)
  eb:SetHeight(40)
  eb:SetMaxLetters(8000)
  sf:SetScrollChild(eb)
  sf:EnableMouse(true)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 30)))
  end)
  eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
    y = -y
    local top, height = sf:GetVerticalScroll(), sf:GetHeight()
    if y < top then sf:SetVerticalScroll(y)
    elseif y + h > top + height then sf:SetVerticalScroll(y + h - height) end
  end)
  box.edit = eb
  return box, eb
end

local function makeDialogFrame(name, w, h, title)
  local d = CreateFrame("Frame", name, UIParent)
  d:SetSize(w, h)
  d:SetPoint("CENTER")
  d:SetFrameStrata("DIALOG")
  d:SetMovable(true)
  d:EnableMouse(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:SetClampedToScreen(true)
  addBackground(d, 0.04, 0.04, 0.06, 0.97)
  -- The small ornate frame goes around the outside, so nothing inside the box moves.
  addFramed({ f = d, scale = UI.DIALOG_FRAME_SCALE, outside = true, bg = { 0.04, 0.04, 0.06, 0.97 } })
  d:Hide()
  d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.title:SetPoint("TOPLEFT", 10, -8)
  d.title:SetText(title or "")
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, name) end
  return d
end

local function label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

-- Read-only copy box (Wowhead links, privacy preview) --------------------------
local copyDialog
local copyState = {}

local function createCopyDialog()
  local d = makeDialogFrame("AzerothAssistantCopyFrame", 520, 260)
  d.note = label(d, "", "GameFontHighlightSmall")
  d.note:SetPoint("TOPLEFT", 10, -28)
  d.note:SetPoint("TOPRIGHT", -10, -28)
  local box, eb = makeScrollEdit(d, 488)
  box:SetPoint("TOPLEFT", 10, -50)
  box:SetPoint("BOTTOMRIGHT", -10, 40)
  eb:SetScript("OnEscapePressed", function() d:Hide() end)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(copyState.text or ""); self:HighlightText() end -- read-only
  end)
  d.edit = eb
  local close = makeButton(d, CLOSE or "Close", 80, function() d:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -10, 10)
  return d
end

function UI.ShowCopy(title, note, text)
  copyDialog = copyDialog or createCopyDialog()
  copyState.text = text or ""
  copyDialog.title:SetText(title)
  copyDialog.note:SetText(note or "")
  copyDialog.edit:SetText(copyState.text)
  copyDialog:Show()
  copyDialog.edit:SetFocus()
  copyDialog.edit:HighlightText()
end

function UI.ShowContextPreview()
  local lines, note = AA.Export.ContextLines(true)
  UI.ShowCopy("What \"Include my character\" shares", note ..
    " Name, realm, guild, chat and account details are never included.",
    #lines > 0 and table.concat(lines, "\n") or "(nothing to show)")
end

-- Ask AI: one box, two steps ----------------------------------------------------
-- Top: the question, already selected (click it, Ctrl+C). Bottom: paste the reply.
local askDialog
local askState = {} -- question, links, packet (kept off the frame on purpose)

local function createAskDialog()
  local d = makeDialogFrame("AzerothAssistantAskFrame", 520, 420, "Ask AI")
  local hint = label(d, "Copy/paste it yourself, or let the desktop companion do it:", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 70, -10)
  local send = makeButton(d, "Send to Companion", 140, function()
    local entry, why = AA.Companion.Queue(askState.question, askState.links)
    if not entry then AA:Reply("Companion", AA.C.warn .. why .. "|r") return end
    AA:Reply("Companion", "Sent to Azeroth Companion. Your UI reloads now; when the companion says the answer is ready, click " ..
      AA.Companion.CheckLink() .. ".")
    if not AA.Companion.Reload() then
      AA:Reply("Companion", "The question is queued; type /reload when you can.")
    end
  end)
  send:SetPoint("TOPRIGHT", -10, -6)
  send:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Send to Azeroth Companion")
    GameTooltip:AddLine("Needs the desktop app running. Reloads your UI so the game saves the question to disk; the companion asks Claude and you click \"Check for answer\" when it's ready.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  send:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local step1 = label(d, "1.  Click the text, press |cffffd100Ctrl+C|r, and paste it into Claude (or any AI chat).")
  step1:SetPoint("TOPLEFT", 10, -32)
  step1:SetWidth(500)
  local qbox, qedit = makeScrollEdit(d, 488)
  qbox:SetPoint("TOPLEFT", 10, -52)
  qbox:SetPoint("TOPRIGHT", -10, -52)
  qbox:SetHeight(130)
  qedit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  qedit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(askState.packet or ""); self:HighlightText() end -- read-only
  end)
  qedit:SetScript("OnEscapePressed", function() d:Hide() end)
  d.qedit = qedit

  local include = makeCheck(d, "Include my character (level, gear, stats, professions, quests)",
    function() return S().allowContext end,
    function(v) S().allowContext = v; UI.RefreshAsk() end)
  include:SetPoint("TOPLEFT", qbox, "BOTTOMLEFT", 0, -4)
  d.include = include

  local step2 = label(d, "2.  Paste the AI's reply below (|cffffd100Ctrl+V|r), then click Show answer.")
  step2:SetPoint("TOPLEFT", qbox, "BOTTOMLEFT", 0, -34)
  step2:SetWidth(500)
  local abox, aedit = makeScrollEdit(d, 488)
  abox:SetPoint("TOPLEFT", qbox, "BOTTOMLEFT", 0, -54)
  abox:SetPoint("BOTTOMRIGHT", -10, 40)
  aedit:SetMaxLetters(AA.MAX_IMPORT_CHARS * 2)
  aedit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  d.aedit = aedit

  local show = makeButton(d, "Show answer", 110, function()
    local text = aedit:GetText()
    if AA.Trim(text) == "" then aedit:SetFocus() return end
    AA.Export.Import(text)
    aedit:SetText("")
    d:Hide()
    UI.ShowAssistant()
  end)
  show:SetPoint("BOTTOMLEFT", 10, 10)
  local note = label(d, "Shown as plain text, marked as external, never run as code.", "GameFontDisableSmall")
  note:SetPoint("LEFT", show, "RIGHT", 8, 0)
  local close = makeButton(d, CLOSE or "Close", 80, function() d:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -10, 10)
  return d
end

function UI.RefreshAsk()
  if not askDialog then return end
  askState.packet = AA.Export.BuildPacket(askState.question, askState.links)
  askDialog.qedit:SetText(askState.packet)
  askDialog.include:Refresh()
  askDialog.qedit:SetFocus()
  askDialog.qedit:HighlightText()
end

function UI.ShowAsk(question)
  question = AA.Trim(question or "")
  local links
  if question == "" then
    question = AA.Assistant.lastQuestion or ""
    links = AA.Assistant.lastLinks
  end
  if question == "" then
    AA:Reply("Ask AI", "Type your question in the box first (you can shift-click items or quests into it), then click Ask AI.")
    return
  end
  askDialog = askDialog or createAskDialog()
  askState.question = question
  askState.links = links
  askDialog:Show()
  UI.RefreshAsk()
end

-- Main window -------------------------------------------------------------------
local frame

local function savePosition()
  if not frame or not AA.db then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  AA.db.frame = { point = point, relPoint = relPoint, x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight() }
end

local function restorePosition()
  local p = AA.db and AA.db.frame
  frame:ClearAllPoints()
  if p and p.point then
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    frame:SetSize(math.max(MIN_W, p.w or 750), math.max(MIN_H, p.h or 540))
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetSize(750, 540)
  end
end

-- Handles our own addon:AzerothAssistant:... links (from this window or the chat window).
function UI.HandleAddonLink(data)
  if data == "addon:AzerothAssistant:ask" then UI.ShowAsk() return end
  if data == "addon:AzerothAssistant:check" then AA.Companion.Reload() return end
  if data == "addon:AzerothAssistant:cancel" then AA.Companion.CancelAll() return end
  if data == "addon:AzerothAssistant:stopauto" then AA.Companion.StopAuto() return end
  if data == "addon:AzerothAssistant:open" then UI.ShowAssistant() return end
  if data == "addon:AzerothAssistant:sendlast" then
    local A = AA.Assistant
    local q = A.currentText or A.lastQuestion
    if q and q ~= "" then
      AA:Reply("Sending to the companion", "Asking Mrgl (Azeroth Companion)... your UI reloads once to send it; the answer pops up in the companion window.")
      AA.Companion.SendNow(q, A.currentLinks)
    end
    return
  end
  local url = AA.Wowhead.FromLinkData(data) or AA.Companion.URLFromLinkData(data)
  if url then
    UI.ShowCopy("Web link", "Press Ctrl+C to copy, then paste it into your web browser. (Addons can't open websites.)", url)
  end
end

local function hyperlinkClick(self, data, text, button)
  if type(data) ~= "string" then return end
  if data:find("^addon:AzerothAssistant:") then
    UI.HandleAddonLink(data)
    return
  end
  if type(SetItemRef) == "function" then pcall(SetItemRef, data, text, button, self) end
end

local function hyperlinkEnter(self, data)
  if type(data) ~= "string" then return end
  if data:find("^item:") or data:find("^quest:") or data:find("^spell:") then
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, data) then GameTooltip:Show() else GameTooltip:Hide() end
  end
end

local function buildSettings(parent)
  local p = CreateFrame("Frame", nil, parent)
  addBackground(p, 0.06, 0.06, 0.09, 0.98)
  p:Hide()
  p:EnableMouse(true)
  local y = -8
  local function row(h) local cur = y; y = y - h; return cur end

  local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  head:SetPoint("TOPLEFT", 8, row(20))
  head:SetText("Settings")

  p.checks = {}
  local mm = makeCheck(p, "Minimap button",
    function() return not S().minimap.hide end,
    function(v) S().minimap.hide = not v; if AA.Minimap then AA.Minimap.Refresh() end end)
  mm:SetPoint("TOPLEFT", 200, -4)
  p.checks[#p.checks + 1] = mm
  local function check(label, key, indent)
    local cb = makeCheck(p, label, function() return S()[key] end, function(v) S()[key] = v end)
    cb:SetPoint("TOPLEFT", 8 + (indent or 0), row(24))
    p.checks[#p.checks + 1] = cb
  end
  check("Ask the companion automatically when I can't answer", "autoCompanion")
  do
    local y = row(24)
    local cb = makeCheck(p, "Assistant chat tab",
      function() return S().chatTab end,
      function(v) S().chatTab = v; if v and AA.ChatTab then AA.ChatTab.Recreate() end end)
    cb:SetPoint("TOPLEFT", 8, y)
    p.checks[#p.checks + 1] = cb
  end
  check("AI questions: include my character", "allowContext")
  local function pair(l1, k1, l2, k2)
    local y = row(24)
    local a = makeCheck(p, l1, function() return S()[k1] end, function(v) S()[k1] = v end)
    a:SetPoint("TOPLEFT", 28, y)
    local b = makeCheck(p, l2, function() return S()[k2] end, function(v) S()[k2] = v end)
    b:SetPoint("TOPLEFT", 190, y)
    p.checks[#p.checks + 1] = a
    p.checks[#p.checks + 1] = b
  end
  pair("Equipped items", "ctxEquipment", "Stats", "ctxStats")
  pair("Professions", "ctxProfessions", "Quest log", "ctxQuests")
  local surv = makeCheck(p, "Comparisons: I care more about survival than damage",
    function() return S().preference == "survival" end,
    function(v) S().preference = v and "survival" or "melee" end)
  surv:SetPoint("TOPLEFT", 8, row(28))
  p.checks[#p.checks + 1] = surv

  local noteLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  noteLabel:SetPoint("TOPLEFT", 10, row(16))
  noteLabel:SetText("Your build/goal note (sent to the AI when character info is on):")
  local note = makeInput(p)
  note:SetPoint("TOPLEFT", 14, row(28))
  note:SetPoint("RIGHT", p, "RIGHT", -12, 0)
  note:SetMaxLetters(120)
  note:SetScript("OnTextChanged", function(self, userInput) if userInput then S().buildNote = self:GetText() end end)
  note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.note = note

  local fontLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  local fy = row(28)
  fontLabel:SetPoint("TOPLEFT", 10, fy - 4)
  p.fontLabel = fontLabel
  local minus = makeButton(p, "-", 24, function() S().fontSize = math.max(9, S().fontSize - 1); UI.ApplySettings() end)
  minus:SetPoint("TOPLEFT", 120, fy)
  local plus = makeButton(p, "+", 24, function() S().fontSize = math.min(20, S().fontSize + 1); UI.ApplySettings() end)
  plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  local by = row(28)
  local preview = makeButton(p, "Preview", 66, function() UI.ShowContextPreview() end)
  preview:SetPoint("TOPLEFT", 8, by)
  preview:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("See exactly what \"include my character\" would share")
    GameTooltip:Show()
  end)
  preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local diag = makeButton(p, "Diagnostics", 84, function() p:Hide(); AA:RunDiagnostics(true) end)
  diag:SetPoint("LEFT", preview, "RIGHT", 6, 0)
  local wipeBtn = makeButton(p, "Erase data", 84, function() UI.ConfirmReset() end)
  wipeBtn:SetPoint("LEFT", diag, "RIGHT", 6, 0)
  local done = makeButton(p, "Done", 54, function() p:Hide() end)
  done:SetPoint("LEFT", wipeBtn, "RIGHT", 6, 0)

  return p
end

local function create()
  frame = CreateFrame("Frame", "AzerothAssistantFrame", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(MIN_W, MIN_H, 1200, 1000)
  elseif frame.SetMinResize then frame:SetMinResize(MIN_W, MIN_H) end
  frame:EnableMouse(true)
  UI.bg = addBackground(frame, 0.05, 0.05, 0.07, 0.92)
  -- The border (faction, gold or plain) is applied at the end of create(), once the title
  -- bar and grip exist. Until then the window has the plain border's 1 px insets.
  frame.aaInsets = { l = 1, t = 1, r = 1, b = 1, curl = 0 }
  restorePosition()
  frame:Hide()

  -- Title bar (drag to move), just inside the top band (placed by placeChrome below)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetHeight(24)
  addBackground(bar, 0.10, 0.08, 0.06, 1)
  -- Moving: drag the title bar, the gold frame, or any empty part of the window (buttons,
  -- rows and boxes keep their own clicks). "Lock window position" on the Interface page
  -- turns this off.
  local function startMove()
    if S().lockWindow then return end
    frame:StartMoving()
  end
  local function stopMove() frame:StopMovingOrSizing(); savePosition() end
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", startMove)
  frame:SetScript("OnDragStop", stopMove)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", startMove)
  bar:SetScript("OnDragStop", stopMove)
  bar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Azeroth Familiar")
    if S().lockWindow then
      GameTooltip:AddLine("Window locked. Unlock it on the Interface page.", 1, 1, 1, true)
    else
      GameTooltip:AddLine("Drag here, or on any empty part of the window, to move it.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("/fam center puts it back in the middle of the screen.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetText("Azeroth Familiar")
  local mode = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  mode:SetJustifyH("LEFT")
  if mode.SetWordWrap then mode:SetWordWrap(false) end
  mode:SetText("")
  local close, templated = tryTemplate("Button", bar, "UIPanelCloseButton")
  if not templated then
    close:SetSize(20, 20)
    local fs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER"); fs:SetText("x")
  end
  close:SetScript("OnClick", function() frame:Hide() end)

  -- Navigation + page host (UI/Shell.lua). The assistant chat below is one of the pages.
  local host = AA.Shell.Attach(frame, mode)
  local chat = CreateFrame("Frame", nil, host)
  chat:SetAllPoints(host)
  chat:Hide()
  UI.chat = chat
  AA.Shell.defs.assistant.frame = chat

  -- Toolbar
  local x = 8
  local function tool(text, w, fn)
    local b = makeButton(chat, text, w, fn)
    b:SetPoint("TOPLEFT", x, -5)
    x = x + w + 4
    return b
  end
  local ask = tool("Ask AI", 70, function()
    local text = UI.input:GetText()
    if AA.Trim(text) ~= "" then
      UI.input:SetText("")
      AA.Assistant.Ask(text) -- show the offline answer too, then open the AI box for it
      UI.ShowAsk(text)
    else
      UI.ShowAsk()
    end
  end)
  ask:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Ask an AI")
    GameTooltip:AddLine("Sends the question in the box (or your last question) to the copy/paste AI box.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  ask:SetScript("OnLeave", function() GameTooltip:Hide() end)
  tool("Settings", 66, function()
    if UI.settings:IsShown() then UI.settings:Hide() else UI.ApplySettings(); UI.settings:Show() end
  end)
  tool("Clear", 52, function() AA:ClearHistory() end)
  UI.checkButton = tool("Show answer here", 118, function() AA.Companion.Reload() end)
  UI.checkButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Check for the companion's answer")
    GameTooltip:AddLine("Reloads your UI so the game reads the answer file the companion wrote.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  UI.checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.checkButton:Hide()

  -- Conversation
  local msg = CreateFrame("ScrollingMessageFrame", nil, chat)
  msg:SetPoint("TOPLEFT", 10, -33)
  msg:SetPoint("BOTTOMRIGHT", -10, 42)
  msg:SetFontObject(ChatFontNormal)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(AA.MAX_HISTORY_LINES + 50)
  if msg.SetIndentedWordWrap then msg:SetIndentedWordWrap(true) end
  msg:SetHyperlinksEnabled(true)
  msg:EnableMouseWheel(true)
  msg:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
      if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
    else
      if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
    end
  end)
  msg:SetScript("OnHyperlinkClick", hyperlinkClick)
  msg:SetScript("OnHyperlinkEnter", hyperlinkEnter)
  msg:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  UI.messages = msg

  -- Settings overlay sits on top of the conversation area
  UI.settings = buildSettings(chat)
  UI.settings:SetFrameLevel(msg:GetFrameLevel() + 5)
  -- With a frame, it is inset by the small frame's reach, so the frame drawn around it stays
  -- over the conversation area and never covers the toolbar or the input box.
  addFramed({ f = UI.settings, scale = UI.PANEL_FRAME_SCALE, outside = true, bg = { 0.06, 0.06, 0.09, 0.98 },
    onInsets = function(ins)
      UI.settings:ClearAllPoints()
      if ins then
        local reach = AA.W.OrnateReach(UI.PANEL_FRAME_SCALE, UI.borderStyle)
        UI.settings:SetPoint("TOPLEFT", msg, "TOPLEFT", reach, -reach)
        UI.settings:SetPoint("BOTTOMRIGHT", msg, "BOTTOMRIGHT", -reach, reach)
      else
        UI.settings:SetAllPoints(msg)
      end
    end })

  -- Input
  local input = makeInput(chat)
  input:SetPoint("BOTTOMLEFT", 14, 10)
  input:SetPoint("BOTTOMRIGHT", -82, 10)
  input:SetMaxLetters(500)
  input:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    self:SetText("")
    AA.Assistant.Ask(text)
  end)
  input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  UI.input = input

  local send = makeButton(chat, "Send", 64, function()
    local text = input:GetText()
    input:SetText("")
    AA.Assistant.Ask(text)
  end)
  send:SetPoint("BOTTOMRIGHT", -10, 11)

  -- Resize grip
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetFrameLevel(frame:GetFrameLevel() + 40)   -- above the frame's ornaments
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing(); savePosition()
    if AA.Shell.Relayout then AA.Shell.Relayout(true) end   -- final layout at the new size
  end)

  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "AzerothAssistantFrame") end

  -- Border and everything that has to clear it: the title bar sits just inside the top band,
  -- the title and close button clear the corners, the grip sits above the bottom band left
  -- of the corner, and the menu and pages (UI/Shell.lua) sit inside the bands.
  local function placeChrome(ins)
    ins = ins or { l = 1, t = 1, r = 1, b = 1, curl = 0 }
    frame.aaInsets = ins
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", ins.l, -ins.t)
    bar:SetPoint("TOPRIGHT", -ins.r, -ins.t)
    title:ClearAllPoints(); title:SetPoint("LEFT", 8 + ins.curl, 0)
    mode:ClearAllPoints()
    mode:SetPoint("LEFT", title, "RIGHT", 8, 0)
    mode:SetPoint("RIGHT", bar, "RIGHT", -30 - ins.curl, 0)
    close:ClearAllPoints(); close:SetPoint("RIGHT", -ins.curl, 0)
    grip:ClearAllPoints(); grip:SetPoint("BOTTOMRIGHT", -(ins.r + ins.curl + 2), ins.b + 2)
    AA.Shell.ApplyLayout()
    if AA.Shell.Relayout then AA.Shell.Relayout() end
  end
  addFramed({ f = frame, scale = UI.FRAME_SCALE, onInsets = placeChrome })

  UI.ApplySettings()
  UI.RefreshPending()
  for _, line in ipairs(AA.db.history) do msg:AddMessage(line) end
  AA.Shell.Show(AA.Shell.StartPage())

  if not S().noticeShown then
    S().noticeShown = true
    AA:System("Welcome! I answer from your game client (bags, gear, quest log, items) and Questie's database if it's installed.")
    AA:System("Shift-click items or quests into the box below and ask. Type \"help\" for examples.")
    AA:System("For anything else, I can ask the Azeroth Companion desktop app for you, or click Ask AI to copy/paste with any AI chat.")
  end
end

local function ensure()
  if not frame then create() end
  return frame
end

function UI.RefreshPending()
  if UI.checkButton then
    if AA.Companion and AA.Companion.Pending() > 0 then UI.checkButton:Show() else UI.checkButton:Hide() end
  end
  if AA.Minimap and AA.Minimap.RefreshPending then AA.Minimap.RefreshPending() end
end

function UI.ApplySettings()
  if not frame then return end
  local scale = tonumber(S().windowScale) or 1
  frame:SetScale(math.max(0.6, math.min(1.4, scale)))
  local alpha = (tonumber(S().windowAlpha) or 92) / 100
  UI.bg:SetColorTexture(0.05, 0.05, 0.07, math.max(0.4, math.min(1, alpha)))
  local size = S().fontSize or 13
  local font, _, flags = ChatFontNormal:GetFont()
  if font then
    UI.messages:SetFont(font, size, flags or "")
    UI.input:SetFont(font, size, flags or "")
  end
  if UI.settings then
    for _, cb in ipairs(UI.settings.checks) do cb:Refresh() end
    UI.settings.note:SetText(S().buildNote or "")
    UI.settings.fontLabel:SetText("Font size: " .. size)
  end
end

function UI.AddLine(line)
  if frame then UI.messages:AddMessage(line) end
end

function UI.Clear()
  if frame then UI.messages:Clear() end
end

-- Back to the default spot (also when it was dragged somewhere awkward).
function UI.CenterWindow()
  local f = ensure()
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  savePosition()
  f:Show()
end

function UI.Show()
  ensure():Show()
end

function UI.Hide()
  if frame then frame:Hide() end
end

-- Opens the window on a page ("overview", "graphics", "assistant", ...).
function UI.ShowPage(id)
  ensure():Show()
  AA.Shell.Show(id)
end

function UI.ShowAssistant()
  UI.ShowPage("assistant")
end

function UI.ShowSettings()
  UI.ShowAssistant()
  UI.ApplySettings()
  UI.settings:Show()
end

-- Kept for older links and /aa extras: the graphics tweaks now live on their own page.
function UI.ShowExtras()
  UI.ShowPage("graphics")
end

function UI.Toggle()
  local f = ensure()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()
    AA.Shell.Refresh()
    if AA.Shell.Current() == "assistant" then UI.input:SetFocus() end
  end
end

-- Confirmation before erasing everything.
local pendingResetAt
function UI.ConfirmReset()
  if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
    StaticPopupDialogs.AZEROTHASSISTANT_RESET = StaticPopupDialogs.AZEROTHASSISTANT_RESET or {
      text = "Erase all Azeroth Familiar saved data (conversation, settings and saved recipe lists)?",
      button1 = YES or "Yes",
      button2 = NO or "No",
      OnAccept = function() AA:ResetAllData() end,
      timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("AZEROTHASSISTANT_RESET")
    return
  end
  local now = GetTime()
  if pendingResetAt and now - pendingResetAt < 10 then
    pendingResetAt = nil
    AA:ResetAllData()
  else
    pendingResetAt = now
    AA:Print("Run /fam reset again within 10 seconds to erase all saved data.")
  end
end

-- The assistant chat is one page of the window. Its frame is filled in when the window is built.
AA.Shell.Register({
  id = "assistant", title = "Assistant", order = 90,
  icon = "Interface\\Icons\\INV_Misc_QuestionMark",
  subtitle = "Ask about items, quests and your bags. Offline answers come from your game client.",
  onShow = function() if UI.input then UI.input:SetFocus() end end,
})

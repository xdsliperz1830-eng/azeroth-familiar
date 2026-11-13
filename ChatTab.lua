-- Azeroth Familiar - ChatTab.lua
-- An "Assistant" tab in the normal chat window. It shows only the assistant's conversation
-- (no player chat). When the tab is selected and you open the chat box, it starts with "/aa "
-- so what you type goes to the assistant, never to public chat. All chat-frame changes go
-- through Blizzard's own chat-window functions; nothing is sent to other players.

local ADDON, AA = ...
local T = {}
AA.ChatTab = T

T.NAME = "Assistant"
T.MAX_BUFFER = 80
local buffer = {}
local hookEditBoxes -- defined further down; declared here so T.Ensure can use it

local function S() return AA.db and AA.db.settings or {} end

-- Finds our tab by name. Returns the frame and whether it's currently shown/docked.
function T.Find()
  if type(GetChatWindowInfo) ~= "function" then return nil end
  for i = 1, (tonumber(NUM_CHAT_WINDOWS) or 10) do
    local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
    if ok and name == T.NAME then
      local frame = _G["ChatFrame" .. i]
      return frame, (shown or docked) and true or false
    end
  end
  return nil
end

function T.Ready()
  return T.frame ~= nil and S().chatTab
end

-- Is the Assistant tab the one the player is looking at?
function T.IsActive()
  return T.frame ~= nil and (SELECTED_CHAT_FRAME == T.frame or SELECTED_DOCK_FRAME == T.frame)
end

local function flush()
  if not T.frame then return end
  for _, line in ipairs(buffer) do T.frame:AddMessage(line) end
  wipe(buffer)
end

-- Every new assistant line is mirrored here (called from AA:AddLine).
function T.AddLine(line)
  if not S().chatTab then return end
  if T.frame then
    T.frame:AddMessage(line)
  else
    buffer[#buffer + 1] = line
    if #buffer > T.MAX_BUFFER then table.remove(buffer, 1) end
  end
end

local function welcome()
  if not T.frame then return end
  local c = AA.C
  T.frame:AddMessage(c.aa .. "Azeroth Familiar|r - this tab is just for me.")
  T.frame:AddMessage(c.src .. "Type your question in the box at the bottom of this tab and press Enter. It only goes to me, never to public chat. Shift-click items or quests into it too.|r")
end

-- Creates the tab once (if it doesn't exist yet), out of combat.
function T.Ensure(force)
  if not S().chatTab then return nil end
  local frame, visible = T.Find()
  if frame then
    -- Our tab already exists (from an earlier session): use it. If it was closed and the
    -- player asked for it (/aa tab), dock and show it again.
    if not visible and force then
      if type(FCF_DockFrame) == "function" then pcall(FCF_DockFrame, frame) end
      pcall(frame.Show, frame)
    end
    T.frame = frame
    flush()
    T.CreateInput()
    return frame
  end
  if AA.db.chatTabCreated and not force then return nil end -- you closed it; /aa tab brings it back
  if InCombatLockdown and InCombatLockdown() then return nil end
  if type(FCF_OpenNewWindow) ~= "function" then
    T.error = "this client has no FCF_OpenNewWindow"
    return nil
  end
  local ok, created = pcall(FCF_OpenNewWindow, T.NAME, true)
  frame = (ok and type(created) == "table" and created) or T.Find()
  if not frame then
    T.error = ok and "no free chat window (WoW allows 10)" or tostring(created)
    return nil
  end
  if type(ChatFrame_RemoveAllMessageGroups) == "function" then pcall(ChatFrame_RemoveAllMessageGroups, frame) end
  if type(ChatFrame_RemoveAllChannels) == "function" then pcall(ChatFrame_RemoveAllChannels, frame) end
  AA.db.chatTabCreated = true
  T.frame = frame
  welcome()
  flush()
  T.CreateInput()
  hookEditBoxes() -- the new tab has its own edit box
  return frame
end

-- Prefill "/fam " when a chat box opens while the Assistant tab is selected.
-- Attached to the chat edit boxes themselves (HookScript), so it works however the client
-- opens them; also hooks the activate functions by name where they exist.
local function isOurs(editBox)
  return T.frame ~= nil and (T.IsActive() or (type(editBox) == "table" and editBox.chatFrame == T.frame))
end

local function prefill(editBox)
  if not (S().chatTab and S().chatTabPrefill and T.frame) then return end
  if type(editBox) ~= "table" or type(editBox.GetText) ~= "function" then return end
  -- Check on the next frame, after the client has finished setting the box up.
  C_Timer.After(0, function()
    if editBox:IsShown() and isOurs(editBox) and (editBox:GetText() or "") == "" then
      editBox:SetText("/fam ")
      if editBox.SetCursorPosition then editBox:SetCursorPosition(5) end
    end
  end)
end

local hookedBoxes = {}
function hookEditBoxes()
  for i = 1, (tonumber(NUM_CHAT_WINDOWS) or 10) do
    local cf = _G["ChatFrame" .. i]
    local eb = _G["ChatFrame" .. i .. "EditBox"] or (type(cf) == "table" and cf.editBox)
    if type(eb) == "table" and type(eb.HookScript) == "function" and not hookedBoxes[eb] then
      hookedBoxes[eb] = true
      eb:HookScript("OnShow", prefill)
      eb:HookScript("OnEditFocusGained", prefill)
    end
  end
end

local function installHooks()
  T.hooked = {}
  hookEditBoxes()
  local n = 0
  for _ in pairs(hookedBoxes) do n = n + 1 end
  if n > 0 then T.hooked[#T.hooked + 1] = n .. " chat edit boxes" end
  if type(ChatEdit_ActivateChat) == "function" then
    hooksecurefunc("ChatEdit_ActivateChat", prefill)
    T.hooked[#T.hooked + 1] = "ChatEdit_ActivateChat"
  end
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.ActivateChat) == "function" then
    hooksecurefunc(ChatFrameUtil, "ActivateChat", prefill)
    T.hooked[#T.hooked + 1] = "ChatFrameUtil.ActivateChat"
  end
end

-- Our own input box inside the Assistant tab: always goes to the assistant, never to chat.
function T.CreateInput()
  if T.input or not T.frame then return end
  local holder = CreateFrame("Frame", nil, T.frame)
  -- Just below the chat lines (where the normal chat box appears), so no message is covered.
  holder:SetPoint("TOPLEFT", T.frame, "BOTTOMLEFT", -5, -4)
  holder:SetPoint("TOPRIGHT", T.frame, "BOTTOMRIGHT", 5, -4)
  holder:SetHeight(24)
  holder:SetFrameLevel(T.frame:GetFrameLevel() + 10)
  local bg = holder:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.04, 0.03, 0.92)
  local line = holder:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1)
  line:SetColorTexture(0.85, 0.65, 0.2, 0.8)

  local eb = CreateFrame("EditBox", nil, holder)
  eb:SetPoint("TOPLEFT", 6, -2)
  eb:SetPoint("BOTTOMRIGHT", -6, 2)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetMaxLetters(500)
  local hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 2, 0)
  hint:SetText("Ask Azeroth Familiar... (click here, type, press Enter)")
  local function refreshHint()
    if (eb:GetText() or "") == "" and not eb:HasFocus() then hint:Show() else hint:Hide() end
  end
  eb:SetScript("OnEditFocusGained", refreshHint)
  eb:SetScript("OnEditFocusLost", refreshHint)
  eb:SetScript("OnTextChanged", refreshHint)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    self:SetText("")
    if AA.Trim(text) ~= "" then AA.Assistant.Ask(text) end
  end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
  T.input, T.inputHolder = eb, holder
  refreshHint()
  -- Only visible while the Assistant tab is the one shown.
  T.frame:HookScript("OnShow", function() holder:Show() end)
  T.frame:HookScript("OnHide", function() holder:Hide() end)
  if T.frame:IsShown() then holder:Show() else holder:Hide() end
end

T.InstallHooks = installHooks
AA:On("PLAYER_LOGIN", function()
  installHooks()
end)

local tried = false
AA:On("PLAYER_ENTERING_WORLD", function()
  if tried then return end
  tried = true
  -- Chat windows finish setting up shortly after entering the world.
  C_Timer.After(2, function()
    local ok, err = pcall(T.Ensure, false)
    if not ok then T.error = tostring(err) end
  end)
end)

-- Brought back on demand (/aa tab).
function T.Recreate()
  AA.db.chatTabCreated = false
  local f = T.Ensure(true)
  if f then
    AA:Print("The Assistant chat tab is ready.")
    if type(FCF_SelectDockFrame) == "function" then pcall(FCF_SelectDockFrame, f) end
  else
    AA:Print(AA.C.warn .. "Couldn't create the Assistant chat tab: " .. tostring(T.error or "try again out of combat") .. "|r")
  end
end

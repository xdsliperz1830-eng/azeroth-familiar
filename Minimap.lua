-- Azeroth Familiar - Minimap.lua
-- A plain (non-secure) minimap button: left-click opens the window, right-click opens
-- Settings, drag to move it around the minimap edge. No libraries required.
-- Also registers with the AddOn compartment menu when the client has one (TOC directive).

local ADDON, AA = ...
local M = {}
AA.Minimap = M

M.ICON = "Interface\\AddOns\\AzerothAssistant\\Media\\Logo"

local atan2 = math.atan2 or atan2

local function radius()
  local w = Minimap and Minimap:GetWidth() or 140
  return w / 2 + 5
end

local function place(btn, angleDeg)
  local a = math.rad(angleDeg or 220)
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius(), math.sin(a) * radius())
end

local function onDragUpdate(self)
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not (mx and px and scale and atan2) then return end
  local angle = math.deg(atan2(py / scale - my, px / scale - mx)) % 360
  AA.db.settings.minimap.angle = angle
  place(self, angle)
end

function M.Create()
  if M.button or not Minimap then return end
  local b = CreateFrame("Button", "AzerothAssistantMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", 1.5, -0.5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(M.ICON)
  icon:SetSize(18, 18)
  -- Centre of the tracking-border ring, measured in game.
  icon:SetPoint("CENTER", 1.5, -0.5)
  -- Crop inside the logo's gold frame, shifted so the letter (drawn slightly high) is centred.
  icon:SetTexCoord(0.11, 0.87, 0.09, 0.85)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  badge:SetPoint("TOPRIGHT", 2, 2)
  badge:SetText("|cff3fd13f!|r")
  badge:Hide()
  M.badge = badge

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      AA.UI.ShowPage("interface")
    elseif IsShiftKeyDown() and AA.Companion and AA.Companion.Pending() > 0 then
      AA.Companion.Reload()
    else
      AA.UI.Toggle()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", onDragUpdate) -- runs only while dragging
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Azeroth Familiar")
    GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
    GameTooltip:AddLine("Right-click: interface settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
    local n = AA.Companion and AA.Companion.Pending() or 0
    if n > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(n .. " question(s) waiting for the companion", 0.25, 0.82, 0.25)
      GameTooltip:AddLine("Shift+click: check for the answer (reloads UI)", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  M.button = b
  place(b, AA.db.settings.minimap.angle)
end

function M.RefreshPending()
  if M.badge then
    if AA.Companion and AA.Companion.Pending() > 0 then M.badge:Show() else M.badge:Hide() end
  end
end

function M.Refresh()
  local hide = AA.db.settings.minimap.hide
  if hide then
    if M.button then M.button:Hide() end
  else
    M.Create()
    if M.button then
      place(M.button, AA.db.settings.minimap.angle)
      M.button:Show()
      M.RefreshPending()
    end
  end
end

function M.Toggle()
  AA.db.settings.minimap.hide = not AA.db.settings.minimap.hide
  M.Refresh()
  AA:Print(AA.db.settings.minimap.hide and "Minimap button hidden. /fam minimap shows it again." or "Minimap button shown.")
end

AA:On("PLAYER_LOGIN", function()
  local ok, err = pcall(M.Refresh)
  if not ok then AA.minimapError = tostring(err) end
end)

-- AddOn compartment (the addon menu next to the minimap on modern clients).
-- Referenced by the TOC; ignored by clients that have no compartment.
function AzerothAssistant_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then
    AA.UI.ShowPage("interface")
  else
    AA.UI.Toggle()
  end
end

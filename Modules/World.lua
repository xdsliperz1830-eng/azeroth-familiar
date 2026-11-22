-- Azeroth Familiar - Modules/World.lua
-- World page: where you are, and a list of places you saved yourself.
-- Only your own position is read. Saved places are stored account-wide in SavedVariables.
-- "Pin" uses the game's own map pin (C_Map.SetUserWaypoint) when this client has it;
-- otherwise the button is greyed out. No map data is bundled or invented.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local Wd = {}
AA.World = Wd
local I = "Interface\\Icons\\"
local MAX = 40
local v, rows = {}, {}

local function list()
  AA.db.locations = type(AA.db.locations) == "table" and AA.db.locations or {}
  return AA.db.locations
end

function Wd.CanPin()
  return AA.Api("C_Map", "SetUserWaypoint") and type(UiMapPoint) == "table"
    and type(UiMapPoint.CreateFromCoordinates) == "function" and true or false
end

-- Saves where you're standing. Returns ok, message.
function Wd.SaveHere(name)
  local mapID, x, y, mapName = St.Coords()
  if not (mapID and x) then
    return false, "The game gives no map position here (inside a dungeon, for example)."
  end
  local locs = list()
  if #locs >= MAX then return false, "You already have " .. MAX .. " saved places. Remove one first." end
  local zone, sub = St.Zone()
  name = AA.Trim(name or "")
  if name == "" then name = sub or zone or mapName or "Saved place" end
  name = AA.PlainText(name):sub(1, 40)
  locs[#locs + 1] = { name = name, mapID = mapID, x = x, y = y, zone = zone or mapName or "?" }
  return true, string.format("Saved \"%s\" (%s %.1f, %.1f).", name, zone or mapName or "?", x, y)
end

function Wd.Remove(i)
  local locs = list()
  if locs[i] then table.remove(locs, i) end
end

function Wd.Text(loc)
  return string.format("%s: %s %.1f, %.1f", loc.name, loc.zone or "?", loc.x, loc.y)
end

-- Puts the game's map pin on a saved place. Returns ok, message.
function Wd.Pin(loc)
  if not Wd.CanPin() then return false, "This client has no map pin for addons to set." end
  local can = AA.Api("C_Map", "CanSetUserWaypointOnMap")
  if can then
    local ok, allowed = pcall(can, loc.mapID)
    if ok and not allowed then return false, "The game doesn't allow a pin on that map." end
  end
  local ok, point = pcall(UiMapPoint.CreateFromCoordinates, loc.mapID, loc.x / 100, loc.y / 100)
  if not (ok and point) then return false, "Couldn't create the map pin." end
  local okSet = pcall(C_Map.SetUserWaypoint, point)
  if not okSet then return false, "The game refused the map pin." end
  local track = AA.Api("C_SuperTrack", "SetSuperTrackedUserWaypoint")
  if track then pcall(track, true) end
  return true, "Map pin set on " .. loc.name .. "."
end

function Wd.ClearPin()
  local clear = AA.Api("C_Map", "ClearUserWaypoint")
  if not clear then return false, "This client has no map pin for addons to clear." end
  pcall(clear)
  return true, "Map pin cleared."
end

local function row(p, i)
  local r = rows[i]
  if r then return r end
  -- The row spans the page width (anchored in refresh); the buttons sit at its right end
  -- and the name and coordinates use everything to their left.
  r = { frame = CreateFrame("Frame", nil, p) }
  r.frame:SetHeight(24)
  r.del = W.Button(r.frame, "Remove", 66, function()
    Wd.Remove(i)
    AA.Shell.Refresh()
  end)
  r.del:SetPoint("RIGHT", 0, 0)
  r.copy = W.Button(r.frame, "Copy", 50, function()
    local loc = list()[i]
    if loc then AA.UI.ShowCopy("Saved place", "Press Ctrl+C to copy.", Wd.Text(loc)) end
  end, "Copy", "Opens a box with the zone and coordinates to copy.")
  r.copy:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
  r.pin = W.Button(r.frame, "Pin", 44, function()
    local loc = list()[i]
    if loc then local ok, msg = Wd.Pin(loc); AA.Shell.Flash(msg, ok) end
  end, "Pin on the map", "Sets the game's map pin on this place.")
  r.pin:SetPoint("RIGHT", r.copy, "LEFT", -4, 0)
  r.text = W.Text(r.frame, "", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 4, 0)
  r.text:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  rows[i] = r
  return r
end

local page, listTop

local function build(L, p)
  page = p
  L:Header("Where you are")
  v.zone = L:KV("Zone")
  v.coords = L:KV("Coordinates")
  L:Note("Coordinates are the game's own map position for the zone map, 0-100 across and down.", 1)
  L:Buttons({
    { "Copy coordinates", 130, function()
        local zone = St.Zone()
        local xy = St.CoordText()
        if not xy then AA.Shell.Flash("The game gives no map position here.", false) return end
        AA.UI.ShowCopy("Your position", "Press Ctrl+C to copy.", (zone or "") .. " " .. xy)
      end, "Copy coordinates", "Opens a box with your zone and coordinates to copy. (Addons can't write to the clipboard here.)" },
    { "Clear map pin", 110, function() local ok, msg = Wd.ClearPin(); AA.Shell.Flash(msg, ok) end },
  })

  L:Header("Saved places")
  local y = L:Row(28)
  local box = W.Input(p, 40)
  box:SetPoint("TOPLEFT", 16, y)
  box:SetWidth(220)
  local save = W.Button(p, "Save this spot", 120, function()
    local ok, msg = Wd.SaveHere(box:GetText())
    if ok then box:SetText("") end
    AA.Shell.Flash(msg, ok)
    AA.Shell.Refresh()
  end, "Save this spot", "Saves where you're standing. Type a name first, or leave it empty to use the area name.")
  save:SetPoint("LEFT", box, "RIGHT", 8, 0)
  box:SetScript("OnEnterPressed", function(self) save:Click() end)
  v.count = L:Note("", 1)
  listTop = L:Row(0)
end

local function refresh()
  local zone, sub = St.Zone()
  v.zone:SetText((sub and (sub .. ", ") or "") .. (zone or "Unknown"))
  v.coords:SetText(St.CoordText() or W.GREY .. "not available here|r")
  local locs = list()
  v.count:SetText(#locs == 0 and (W.GREY .. "No saved places yet. Stand somewhere useful and click Save this spot.|r")
    or (#locs .. " of " .. MAX .. " saved. Also: /fam pin <name> saves where you stand."))
  local canPin = Wd.CanPin()
  for i = 1, math.max(#locs, #rows) do
    local loc = locs[i]
    if loc then
      local r = row(page, i)
      r.frame:ClearAllPoints()
      r.frame:SetPoint("TOPLEFT", 10, listTop - (i - 1) * 26)
      r.frame:SetPoint("RIGHT", page, "RIGHT", -12, 0)
      r.text:SetText(W.GOLD .. loc.name .. "|r  " .. string.format("%s %.1f, %.1f", loc.zone or "?", loc.x, loc.y))
      if canPin then r.pin:Enable() else r.pin:Disable() end
      r.frame:Show()
    elseif rows[i] then
      rows[i].frame:Hide()
    end
  end
  page:SetHeight(-listTop + #locs * 26 + 20)
end

AA.Shell.Register({
  id = "world", title = "World", order = 60, icon = I .. "INV_Misc_Map_01",
  subtitle = "Your position and the places you've saved.",
  build = build, refresh = refresh, interval = 1,
})

-- Azeroth Familiar - Modules/Performance.lua
-- Performance page and the optional small on-screen FPS / latency readout.
-- Reads once a second while visible; the addon-memory scan runs only when you click it.

local ADDON, AA = ...
local W, St = AA.W, AA.Stats
local P = {}
AA.Performance = P
local I = "Interface\\Icons\\"

local v = {}

-- Small movable readout -------------------------------------------------------
local mini
local function miniText()
  local fps = St.SampleFPS()
  local _, world = St.Latency()
  local s = fps and string.format("%d fps", fps + 0.5) or ""
  if AA.db.settings.perfLatency and world then s = s .. string.format("  %d ms", world) end
  return s
end

function P.RefreshMini()
  local want = AA.db.settings.perfDisplay
  if not want then
    if mini then mini:Hide() end
    return
  end
  if not mini then
    mini = CreateFrame("Frame", "AzerothAssistantPerfFrame", UIParent)
    mini:SetSize(120, 20)
    mini:SetMovable(true)
    mini:EnableMouse(true)
    mini:SetClampedToScreen(true)
    mini:RegisterForDrag("LeftButton")
    W.Bg(mini, 0, 0, 0, 0.45)
    local fs = W.Text(mini, "", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    local pos = AA.db.perfFrame
    if type(pos) == "table" and pos.point then
      mini:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
      mini:SetPoint("TOP", UIParent, "TOP", 0, -4)
    end
    mini:SetScript("OnDragStart", mini.StartMoving)
    mini:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local point, _, relPoint, x, y = self:GetPoint(1)
      AA.db.perfFrame = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    local acc = 1
    mini:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + (tonumber(elapsed) or 0)
      if acc >= 1 then acc = 0; fs:SetText(miniText()) end
    end)
    W.Tip(mini, "Azeroth Familiar", "Frame rate and world latency. Drag to move. Turn off on the Performance page.")
  end
  mini:Show()
end

AA:On("PLAYER_LOGIN", function() pcall(P.RefreshMini) end)

-- Addon memory (on request only: the game call is not free) -------------------
function P.MemoryReport()
  local update = AA.Api("UpdateAddOnMemoryUsage")
  local usage = AA.Api("GetAddOnMemoryUsage")
  local num = AA.Api("C_AddOns", "GetNumAddOns")
  local info = AA.Api("C_AddOns", "GetAddOnInfo")
  if not (update and usage) then return nil, "This client doesn't report addon memory." end
  pcall(update)
  local okM, mine = pcall(usage, ADDON)
  local lines = { string.format("Azeroth Familiar: %.0f KB", (okM and AA.Num(mine)) or 0) }
  if num and info then
    local okN, n = pcall(num)
    local all = {}
    for i = 1, (okN and AA.Num(n)) or 0 do
      local okI, name = pcall(info, i)
      local okU, kb = pcall(usage, i)
      kb = okU and AA.Num(kb) or 0
      if okI and AA.Str(name) and kb > 0 then all[#all + 1] = { name = name, kb = kb } end
    end
    table.sort(all, function(a, b) return a.kb > b.kb end)
    for i = 1, math.min(5, #all) do
      lines[#lines + 1] = string.format("%d. %s: %.1f MB", i, all[i].name, all[i].kb / 1024)
    end
  end
  return lines
end

-- Plain-language hints from the current numbers.
function P.Advice(fps, world)
  local out = {}
  if fps and fps < 25 then
    out[#out + 1] = AA.C.warn .. "Frame rate is low.|r Try the Low or Balanced graphics preset, or lower Shadows and View distance."
  elseif fps and fps < 45 then
    out[#out + 1] = "Frame rate is on the low side. Shadows and View distance cost the most."
  end
  if world and world > 250 then
    out[#out + 1] = AA.C.warn .. "World latency is high.|r That's the connection or the server, not graphics settings."
  end
  if #out == 0 then out[1] = AA.C.good .. "Nothing to flag right now.|r" end
  return table.concat(out, "\n")
end

local function build(L, p)
  L:Header("Right now")
  v.fps = L:KV("Frame rate")
  v.avg = L:KV("Average")
  v.world = L:KV("World latency")
  v.home = L:KV("Home latency")
  v.session = L:KV("Session length")
  L:Header("Advice")
  v.advice = L:Note("", 3)
  L:Buttons({
    { "Low preset", 96, function() local ok, m = AA.Tweaks.ApplyPreset("low"); AA.Shell.Flash(m, ok) end,
      "Low Performance preset", "Applies the Low graphics preset. Undo on the Graphics page." },
    { "Balanced preset", 120, function() local ok, m = AA.Tweaks.ApplyPreset("balanced"); AA.Shell.Flash(m, ok) end,
      "Balanced preset", "Applies the Balanced graphics preset. Undo on the Graphics page." },
    { "Graphics page", 110, function() AA.Shell.Show("graphics") end },
  })
  L:Header("On-screen readout")
  L:Check("Show frame rate on screen",
    function() return AA.db.settings.perfDisplay end,
    function(x) AA.db.settings.perfDisplay = x; P.RefreshMini() end,
    "On-screen readout", "A small movable line with your frame rate. Updates once a second.")
  L:Check("Include world latency",
    function() return AA.db.settings.perfLatency end,
    function(x) AA.db.settings.perfLatency = x end)
  L:Header("Addon memory")
  v.memory = L:Note(W.GREY .. "Click Measure to see how much memory your addons use.|r", 6)
  L:Buttons({
    { "Measure", 84, function()
        local lines, err = P.MemoryReport()
        v.memory:SetText(lines and table.concat(lines, "\n") or (AA.C.warn .. err .. "|r"))
      end, "Measure addon memory", "Asks the game for each addon's memory use. Done only when you click, because the measurement itself takes a moment." },
  })
end

local function refresh()
  local fps = St.SampleFPS()
  local home, world = St.Latency()
  local avg, n = St.AverageFPS()
  v.fps:SetText(fps and string.format("%d fps", fps + 0.5) or "n/a")
  v.avg:SetText(avg and string.format("%d fps over the last %d seconds on screen", avg + 0.5, n) or W.GREY .. "collecting...|r")
  v.world:SetText(world and (world .. " ms") or "n/a")
  v.home:SetText(home and (home .. " ms") or "n/a")
  v.session:SetText(St.Duration(St.SessionSummary().length))
  v.advice:SetText(P.Advice(fps, world))
end

AA.Shell.Register({
  id = "performance", title = "Performance", order = 30, icon = I .. "INV_Misc_PocketWatch_01",
  subtitle = "Frame rate, latency and addon memory.",
  build = build, refresh = refresh, interval = 1,
})

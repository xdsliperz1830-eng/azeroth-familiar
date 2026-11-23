-- Azeroth Familiar - Core.lua
-- Namespace, saved data, safe API access, events, slash commands, diagnostics.
-- Nothing in this addon performs protected actions, sends chat, or runs code from text.

local ADDON, AA = ...
AzerothAssistant = AA -- global handle for /dump debugging only

AA.VERSION = "0.9.5"
AA.NAME = "Azeroth Familiar"
AA.MAX_HISTORY_LINES = 400
AA.MAX_IMPORT_CHARS = 4000
AA.MAX_IMPORT_LINES = 80

-- Colors ---------------------------------------------------------------------
AA.C = {
  you    = "|cffffd100",
  aa     = "|cff4fc3f7",
  src    = "|cff9d9d9d",
  warn   = "|cffff7f50",
  good   = "|cff3fd13f",
  bad    = "|cffff4040",
  import = "|cffc586ff",
  head   = "|cffffffff",
}

-- Defaults -------------------------------------------------------------------
local DEFAULTS = {
  dbVersion = 1,
  settings = {
    fontSize = 13,
    allowContext = false, -- master permission for character data in AI packets
    ctxEquipment = true,
    ctxStats = true,
    ctxProfessions = true,
    ctxQuests = true,
    buildNote = "Enhancement shaman, leveling, melee focus",
    preference = "melee", -- "melee" | "survival"
    noticeShown = false,
    minimap = { hide = false, angle = 220 },
    autoCompanion = true,   -- send questions I can't answer offline to the desktop companion
    companionToChat = true, -- also print companion answers in the normal chat window
    chatTab = true,         -- "Assistant" tab in the chat window
    chatTabPrefill = true,  -- start the chat box with "/fam " while that tab is selected
    autoCheck = false,      -- reload by itself to pick up answers (off: answers pop up in the companion instead)
    -- Toolkit (v0.7.0)
    startPage = "overview", -- "overview" | "assistant" | "last"
    lastPage = "overview",
    compactNav = false,     -- icons-only navigation
    windowScale = 1,
    windowAlpha = 92,       -- background opacity, percent
    dash = {},              -- [cardId] = false hides an Overview card
    remind = { durability = true, bags = true, cheapest = true, vendor = true, levelup = true },
    perfDisplay = false,    -- small on-screen FPS readout
    perfLatency = true,     -- include world latency in it
    lockWindow = false,     -- true: the window can't be dragged
    border = "faction",     -- window border: "faction" (Horde red / Alliance blue), "gold" or "plain"
    contentScale = 1,       -- "Content size": pages and menu, 0.8 to 1.5 (window size is separate)
    -- Crates page (v0.9.0, formerly the Crate Scout addon)
    crates = { countOwned = false, tooltip = true },
  },
  locations = {},           -- saved places (World page), account-wide
  tweaks = { saved = {} },  -- game settings changed by the addon, with the values they had before
  history = {},
  frame = {},
  diag = nil,
}

local CHAR_DEFAULTS = {
  recipes = {}, -- [professionName] = { observed = time(), list = { ... } }
}

local function mergeDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      mergeDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- Helpers --------------------------------------------------------------------
function AA.Trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns a function from the API, or nil if it doesn't exist on this client.
-- AA.Api("GetProfessions") or AA.Api("C_Item", "GetItemInfo")
function AA.Api(ns, fn)
  if fn == nil then
    local f = _G[ns]
    return type(f) == "function" and f or nil
  end
  local t = _G[ns]
  if type(t) ~= "table" then return nil end
  local f = t[fn]
  return type(f) == "function" and f or nil
end

-- pcall wrapper that tolerates a missing function. Returns ok, ...
function AA.Try(fn, ...)
  if type(fn) ~= "function" then return false, "missing API" end
  return pcall(fn, ...)
end

-- Midnight-style secret values cannot be compared or used in arithmetic.
function AA.IsSecret(v)
  local f = _G.issecretvalue
  if type(f) ~= "function" then return false end
  local ok, res = pcall(f, v)
  return ok and res and true or false
end

-- Returns v only if it is a plain, readable number.
function AA.Num(v)
  if v == nil or AA.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end

function AA.Str(v)
  if v == nil or AA.IsSecret(v) or type(v) ~= "string" then return nil end
  return v
end

-- Plain text: removes color codes, textures and hyperlink wrappers, keeps link text.
function AA.PlainText(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|H.-|h(.-)|h", "%1")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|cn[^:]*:", "")
  s = s:gsub("|r", "")
  s = s:gsub("|T.-|t", "")
  s = s:gsub("|A.-|a", "")
  s = s:gsub("|", "/") -- anything left over must not act as an escape code
  return s
end

-- Event dispatch -------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function AA:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then
      AA.missingEvents = AA.missingEvents or {}
      AA.missingEvents[event] = true
    end
  end
  table.insert(handlers[event], fn)
end

-- Runs the handlers for an event. The game calls this through the frame below.
function AA:Fire(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then
      local eh = geterrorhandler and geterrorhandler()
      if eh then eh("AzerothAssistant " .. event .. ": " .. tostring(err)) end
    end
  end
end
eventFrame:SetScript("OnEvent", function(_, event, ...) AA:Fire(event, ...) end)

-- Output ---------------------------------------------------------------------
function AA:Print(msg)
  local cf = DEFAULT_CHAT_FRAME
  if cf and cf.AddMessage then
    cf:AddMessage(AA.C.aa .. "Azeroth Familiar:|r " .. tostring(msg))
  end
end

local function pushHistory(line)
  if not AzerothAssistantDB then return end
  local h = AzerothAssistantDB.history
  h[#h + 1] = line
  local extra = #h - AA.MAX_HISTORY_LINES
  if extra > 0 then
    for _ = 1, extra do table.remove(h, 1) end
  end
end

-- Adds one already-formatted line to the conversation.
function AA:AddLine(line)
  pushHistory(line)
  if AA.ChatTab and AA.ChatTab.AddLine then AA.ChatTab.AddLine(line) end
  if AA.UI and AA.UI.AddLine then AA.UI.AddLine(line) end
end

function AA:UserSays(text)
  AA:AddLine(AA.C.you .. "You:|r " .. text)
end

-- src is a short plain-language label telling the user where the answer came from.
function AA:Reply(src, lines)
  AA:AddLine(AA.C.aa .. "Azeroth Familiar|r " .. AA.C.src .. "(" .. src .. ")|r")
  if type(lines) == "string" then lines = { lines } end
  for i = 1, #lines do
    AA:AddLine("   " .. lines[i])
  end
end

function AA:System(text)
  AA:AddLine(AA.C.src .. text .. "|r")
end

function AA:ClearHistory()
  if AzerothAssistantDB then wipe(AzerothAssistantDB.history) end
  if AA.UI and AA.UI.Clear then AA.UI.Clear() end
end

function AA:ResetAllData()
  AzerothAssistantDB = nil
  AzerothAssistantCharDB = nil
  AA:InitDB()
  if AA.UI and AA.UI.Clear then AA.UI.Clear() end
  if AA.UI and AA.UI.ApplySettings then AA.UI.ApplySettings() end
  if AA.Shell then pcall(AA.Shell.ApplyLayout); pcall(AA.Shell.Refresh) end
  if AA.Performance then pcall(AA.Performance.RefreshMini) end
  if AA.Minimap then pcall(AA.Minimap.Refresh) end
  AA:Print("All saved data was cleared.")
end

-- Init -----------------------------------------------------------------------
function AA:InitDB()
  if type(AzerothAssistantDB) ~= "table" then AzerothAssistantDB = {} end
  mergeDefaults(AzerothAssistantDB, DEFAULTS)
  if type(AzerothAssistantCharDB) ~= "table" then AzerothAssistantCharDB = {} end
  mergeDefaults(AzerothAssistantCharDB, CHAR_DEFAULTS)
  AA.db = AzerothAssistantDB
  AA.charDB = AzerothAssistantCharDB
  -- One-time settings migrations
  local rev = tonumber(AzerothAssistantDB.settingsRev) or 1
  if rev < 2 then
    AzerothAssistantDB.settings.autoCheck = false -- v0.6.3: no automatic fetch reloads by default
    AzerothAssistantDB.settingsRev = 2
  end
end

local function detectClient()
  local version, build, bdate, iface = GetBuildInfo()
  iface = tonumber(iface)
  AA.client = {
    version = version,
    build = build,
    date = bdate,
    interface = iface,
    -- Forever reports 16xxx. Classic Era (11xxx) would pass a naive "starts with 1" test.
    isForever = (iface ~= nil and iface >= 16000 and iface < 17000) and true or false,
  }
end

AA:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  AA:InitDB()
end)

AA:On("PLAYER_LOGIN", function()
  if not AA.db then AA:InitDB() end
  detectClient()
  if AA.Links and AA.Links.InstallHooks then AA.Links.InstallHooks() end
  AA:CheckSlashConflicts()
  if not AA.client.isForever then
    AA:Print(AA.C.warn .. "This client reports interface " .. tostring(AA.client.interface) ..
      ". Azeroth Familiar was written for WoW Forever (16xxx); some features may not work.|r")
  end
end)

-- Slash commands -------------------------------------------------------------
-- /fam, /familiar and /azerothfamiliar match the addon's name (Azeroth Familiar); /aa and /azerothassistant keep working.
SLASH_AZEROTHASSISTANT1 = "/familiar"
SLASH_AZEROTHASSISTANT2 = "/fam"
SLASH_AZEROTHASSISTANT3 = "/aa"
SLASH_AZEROTHASSISTANT4 = "/azerothassistant"
SLASH_AZEROTHASSISTANT5 = "/azerothfamiliar"

function AA:CheckSlashConflicts()
  local owners, taken = {}, {}
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "string" and k:find("^SLASH_")
      and not k:find("^SLASH_AZEROTHASSISTANT") then
      local cmd = v:lower()
      if cmd == "/aa" or cmd == "/fam" then
        owners[#owners + 1] = k .. " (" .. cmd .. ")"
        taken[cmd] = true
      end
    end
  end
  AA.slashConflicts = owners
  if #owners > 0 then
    AA:Print(AA.C.warn .. "Another addon also uses " .. table.concat(owners, ", ") ..
      ". If that command opens something else, use /familiar.|r")
  end
end

local HELP = {
  "/fam  - open or close the window (/aa and /familiar work too)",
  "/fam overview, graphics, perf, character, bags, crates, world, gameplay, interface, assistant  - open that page",
  "/fam <question>  - ask the assistant, e.g. /fam search medium leather",
  "/fam crates  - Waylaid Crate planner; /fam crates verify | cancel | inspect <itemID>",
  "/fam pin <name>  - save where you're standing (World page)",
  "/fam fps  - show or hide the on-screen frame rate",
  "/fam diag  - check which game features this client has (saved for troubleshooting)",
  "/fam minimap  - show or hide the minimap button",
  "/fam center  - move the window back to the middle of the screen",
  "/fam tab  - create (or bring back) the Assistant chat tab",
  "/fam check  - reload to pick up answers from the desktop companion",
  "/fam clear  - clear the conversation",
  "/fam reset  - erase all Azeroth Familiar saved data",
  "/fam help  - this list",
}

-- One-word page shortcuts for /aa.
local PAGES = {
  overview = "overview", home = "overview", graphics = "graphics", extras = "graphics",
  perf = "performance", performance = "performance", character = "character", char = "character",
  bags = "inventory", inventory = "inventory", world = "world", map = "world",
  crates = "crates", crate = "crates",
  gameplay = "gameplay", interface = "interface", options = "interface", config = "interface",
  assistant = "assistant", ask = "assistant",
}

function AA:Slash(msg)
  msg = AA.Trim(msg or "")
  local cmd = msg:lower()
  if cmd == "" or cmd == "toggle" then
    if AA.UI then AA.UI.Toggle() end
  elseif cmd == "show" then
    if AA.UI then AA.UI.Show() end
  elseif cmd == "hide" then
    if AA.UI then AA.UI.Hide() end
  elseif cmd == "help" then
    for _, l in ipairs(HELP) do AA:Print(l) end
  elseif cmd == "diag" then
    AA:RunDiagnostics(true)
  elseif cmd == "check" then
    if AA.Companion then AA.Companion.Reload() end
  elseif cmd == "tab" then
    if AA.ChatTab then AA.ChatTab.Recreate() end
  elseif PAGES[cmd] then
    if AA.UI then AA.UI.ShowPage(PAGES[cmd]) end
  elseif cmd:find("^crates? ") and AA.Crates and AA.Crates.UI then
    AA.Crates.UI.Slash(msg:match("^%S+%s+(.*)$"))
  elseif cmd == "fps" then
    AA.db.settings.perfDisplay = not AA.db.settings.perfDisplay
    if AA.Performance then AA.Performance.RefreshMini() end
    AA:Print(AA.db.settings.perfDisplay and "Frame rate readout shown. Drag it to move it." or "Frame rate readout hidden.")
  elseif cmd == "pin" or cmd:find("^pin ") then
    local ok, text = AA.World.SaveHere(msg:sub(5))
    AA:Print((ok and "" or AA.C.warn) .. text .. (ok and "" or "|r"))
    if AA.Shell then pcall(AA.Shell.Refresh) end
  elseif cmd == "center" or cmd == "centre" then
    if AA.UI and AA.UI.CenterWindow then AA.UI.CenterWindow() end
    AA:Print("Window moved to the middle of the screen. Drag the title bar or any empty part of it to move it.")
  elseif cmd == "minimap" then
    if AA.Minimap then AA.Minimap.Toggle() end
  elseif cmd == "bagcheck" then
    if AA.BagHint then AA.BagHint.Update(); AA.BagHint.Report() end
  elseif cmd == "clear" then
    AA:ClearHistory()
  elseif cmd == "reset" then
    if AA.UI and AA.UI.ConfirmReset then AA.UI.ConfirmReset() else AA:ResetAllData() end
  else
    -- Typed in the Assistant chat tab: answer there, don't pop the window open.
    local fromTab = AA.ChatTab and AA.ChatTab.IsActive() and AA.ChatTab.Ready()
    if AA.UI and not fromTab then AA.UI.ShowAssistant() end
    if AA.Assistant then AA.Assistant.Ask(msg) end
  end
end

SlashCmdList.AZEROTHASSISTANT = function(msg) AA:Slash(msg) end

-- Diagnostics ----------------------------------------------------------------
-- Records what this exact client exposes so behavior can be verified, not assumed.
local API_CHECKS = {
  { "C_Item", "GetItemInfo" }, { "C_Item", "GetItemInfoInstant" }, { "C_Item", "GetItemStats" },
  { "C_Item", "RequestLoadItemDataByID" }, { "C_Item", "GetItemNameByID" },
  { "C_Container", "GetContainerNumSlots" }, { "C_Container", "GetContainerItemInfo" },
  { "C_QuestLog", "GetNumQuestLogEntries" }, { "C_QuestLog", "GetInfo" },
  { "C_QuestLog", "GetQuestObjectives" }, { "C_QuestLog", "GetLogIndexForQuestID" },
  { "C_QuestLog", "GetTitleForQuestID" }, { "C_QuestLog", "IsComplete" },
  { "C_TooltipInfo", "GetHyperlink" },
  { "C_TradeSkillUI", "GetAllRecipeIDs" }, { "C_TradeSkillUI", "GetRecipeInfo" },
  { "C_TradeSkillUI", "GetRecipeSchematic" }, { "C_TradeSkillUI", "GetRecipeOutputItemData" },
  { "C_TradeSkillUI", "GetBaseProfessionInfo" },
  { "C_AddOns", "IsAddOnLoaded" }, { "ChatFrameUtil", "InsertLink" },
  { "C_Traits", "GetConfigInfo" }, { "C_SpecializationInfo", "GetSpecializationInfo" },
  { "ChatEdit_InsertLink" }, { "SetItemRef" }, { "GetQuestLogQuestText" }, { "GetQuestLink" },
  { "GetProfessions" }, { "GetProfessionInfo" }, { "GetInventoryItemLink" },
  { "UnitStat" }, { "UnitAttackPower" }, { "UnitAttackSpeed" }, { "UnitArmor" },
  { "GetCritChance" }, { "GetHitModifier" }, { "issecretvalue" }, { "hooksecurefunc" },
  { "C_Map", "GetAreaInfo" }, { "GetCursorPosition" }, { "UnitFactionGroup" }, { "GetRealZoneText" }, { "ReloadUI" },
  -- Toolkit pages (v0.7.0)
  { "C_CVar", "GetCVar" }, { "C_CVar", "SetCVar" }, { "C_CVar", "GetCVarDefault" },
  { "GetMoney" }, { "GetFramerate" }, { "GetNetStats" }, { "GetInventoryItemDurability" },
  { "UnitXP" }, { "UnitXPMax" }, { "GetXPExhaustion" }, { "UnitHealth" }, { "UnitHealthMax" }, { "UnitPower" },
  { "UnitName" }, { "UnitExists" }, { "UnitClassification" }, { "UnitCreatureType" }, { "GetSubZoneText" },
  { "C_Container", "GetContainerNumFreeSlots" },
  { "C_Map", "GetBestMapForUnit" }, { "C_Map", "GetPlayerMapPosition" }, { "C_Map", "GetMapInfo" },
  { "C_Map", "SetUserWaypoint" }, { "C_Map", "ClearUserWaypoint" }, { "C_Map", "CanSetUserWaypointOnMap" },
  { "C_SuperTrack", "SetSuperTrackedUserWaypoint" },
  { "UpdateAddOnMemoryUsage" }, { "GetAddOnMemoryUsage" }, { "C_AddOns", "GetNumAddOns" }, { "C_AddOns", "GetAddOnInfo" },
  { "CanMerchantRepair" }, { "GetRepairAllCost" }, { "C_Timer", "After" },
}

local function keysOf(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for k, v in pairs(t) do out[#out + 1] = tostring(k) .. "=" .. type(v) end
  table.sort(out)
  return out
end

function AA:RunDiagnostics(verbose)
  if not AA.client then detectClient() end
  local d = {
    time = date("%Y-%m-%d %H:%M"),
    addonVersion = AA.VERSION,
    gameVersion = AA.client.version,
    build = AA.client.build,
    interface = AA.client.interface,
    isForever = AA.client.isForever,
    projectID = WOW_PROJECT_ID,
    inCombat = InCombatLockdown and InCombatLockdown() or false,
    present = {}, missing = {}, samples = {},
    slashConflicts = AA.slashConflicts,
    missingEvents = AA.missingEvents,
    linkHooks = AA.Links and AA.Links.hooked or {},
    itemMixin = (type(Item) == "table" and type(Item.CreateFromItemLink) == "function") or false,
    questieLoaded = AA.Questie and AA.Questie.IsLoaded() or false,
    questieLoaderGlobal = type(_G.QuestieLoader) == "table",
    minimapError = AA.minimapError,
    companionPending = AA.Companion and AA.Companion.Pending() or 0,
    companionDetected = AA.Companion and AA.Companion.Detected() or false,
    autoCheckBlocked = AA.db.autoCheckBlocked or false,
    chatLinkHook = AA.Companion and AA.Companion.chatLinkHook or nil,
    chatTab = AA.ChatTab and (AA.ChatTab.frame and AA.ChatTab.frame:GetName() or ("none: " .. tostring(AA.ChatTab.error))) or nil,
    chatTabHooks = AA.ChatTab and AA.ChatTab.hooked or nil,
  }
  if AA.Crates and AA.Crates.Inventory then
    local okC, n, t = pcall(AA.Crates.Inventory.Coverage, AA.Crates.Inventory)
    local okS, scan, why = pcall(AA.Crates.Scan.Capabilities, AA.Crates.Scan)
    d.crates = { verified = okC and n or nil, recipes = okC and t or nil, scanReady = okS and scan or false, scanReason = okS and why or nil,
      tooltipHook = AA.Crates.Tooltip.installed or false, locale = GetLocale and GetLocale() or nil, reasons = {}, rendered = {} }
    for id, crate in pairs(AA.Crates.Catalog.entries) do
      if not AA.Crates.verified[id] then
        d.crates.reasons[id] = crate.validation or "not checked yet"
        if AA.Crates.renderedTooltip and AA.Crates.renderedTooltip[id] then d.crates.rendered[id] = AA.Crates.renderedTooltip[id] end
      end
    end
  end
  if AA.Questie then
    local db, why = AA.Questie.DB()
    d.questieDB = db and ("contract " .. AA.Questie.CONTRACT .. " OK" .. (db.contractVersion and (", provider contract " .. tostring(db.contractVersion)) or "")) or why
    if db then
      -- 2589 = Linen Cloth, a long-standing Classic item; checks that reads really work.
      d.questieSampleRead = tostring(AA.Questie.Get("Item", 2589, "name"))
    end
  end
  for _, c in ipairs(API_CHECKS) do
    local label = c[2] and (c[1] .. "." .. c[2]) or c[1]
    if AA.Api(c[1], c[2]) then d.present[#d.present + 1] = label else d.missing[#d.missing + 1] = label end
  end
  -- Shape samples (no names, no chat, no account data)
  local ok, info = AA.Try(AA.Api("C_QuestLog", "GetInfo"), 1)
  if ok then d.samples.questLogInfoKeys = keysOf(info) end
  local ok2, bagInfo
  local getInfo = AA.Api("C_Container", "GetContainerItemInfo")
  local numSlots = AA.Api("C_Container", "GetContainerNumSlots")
  if getInfo and numSlots then
    local okN, n = pcall(numSlots, 0)
    for slot = 1, (okN and AA.Num(n) or 0) do
      ok2, bagInfo = pcall(getInfo, 0, slot)
      if ok2 and bagInfo then d.samples.bagItemInfoKeys = keysOf(bagInfo); break end
    end
  end
  local okP, p1, p2, p3, p4, p5, p6 = AA.Try(AA.Api("GetProfessions"))
  if okP then d.samples.professionIndexes = { tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5), tostring(p6) } end
  local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
  if link then
    local okS, stats = AA.Try(AA.Api("C_Item", "GetItemStats"), link)
    if okS then d.samples.mainHandStatKeys = keysOf(stats) end
    local okT, tip = AA.Try(AA.Api("C_TooltipInfo", "GetHyperlink"), link)
    if okT and type(tip) == "table" and type(tip.lines) == "table" and tip.lines[1] then
      d.samples.tooltipLineKeys = keysOf(tip.lines[1])
    end
  end
  if AA.Tweaks then
    local okP, have, lack = pcall(AA.Tweaks.Probe)
    if okP then d.cvarsFound, d.cvarsMissing = have, lack end
  end
  d.pageErrors = AA.pageErrors
  d.missingEvents = AA.missingEvents
  AA.db.diag = d

  if verbose then
    AA:Reply("Diagnostics - this client", {
      string.format("Game %s build %s, interface %s (%s).", tostring(d.gameVersion), tostring(d.build),
        tostring(d.interface), d.isForever and "WoW Forever range" or AA.C.warn .. "not the Forever range|r"),
      string.format("%d of %d checked APIs are present.", #d.present, #d.present + #d.missing),
      #d.missing > 0 and (AA.C.warn .. "Missing: " .. table.concat(d.missing, ", ") .. "|r") or (AA.C.good .. "No checked APIs are missing.|r"),
      "Link insertion hooks: " .. (#d.linkHooks > 0 and table.concat(d.linkHooks, ", ") or AA.C.warn .. "none installed|r"),
      "Questie: " .. (d.questieLoaded and "loaded" or "not loaded") .. "; database: " .. tostring(d.questieDB) ..
        (d.questieSampleRead and (" (test read: " .. d.questieSampleRead .. ")") or ""),
      d.cvarsFound and (#d.cvarsFound .. " game settings found" .. (#d.cvarsMissing > 0 and ("; " .. AA.C.warn .. "not in this client: " .. table.concat(d.cvarsMissing, ", ") .. "|r") or "; none missing.")) or "Game settings: not checked.",
      d.pageErrors and (AA.C.warn .. "A page hit an error (details saved).|r") or "Pages: no errors so far.",
      d.minimapError and (AA.C.warn .. "Minimap button error: " .. d.minimapError .. "|r") or "Minimap button: OK",
      "Saved to SavedVariables after /reload or logout (WTF\\Account\\<account>\\SavedVariables\\AzerothAssistant.lua).",
    })
    if AA.UI then AA.UI.ShowAssistant() end
  end
  return d
end

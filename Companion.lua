-- Azeroth Familiar - Companion.lua
-- Bridge to the "Azeroth Companion" desktop app. There is no live connection: the game
-- only writes files on /reload or logout, and only reads addon files when it loads them.
--
--   OUT (game -> app): questions are queued in SavedVariables (AzerothAssistantDB.companion.outbox).
--        Clicking "Send" calls ReloadUI(), which makes the game write that file to disk.
--   IN  (app -> game): the app writes CompanionInbox.lua (in this addon's folder, listed in the TOC).
--        The next /reload loads it as data; this module validates every field before display.
--
-- No API keys ever touch the addon. Answers are shown as plain text, never executed.

local ADDON, AA = ...
local CP = {}
AA.Companion = CP

CP.MAX_OUTBOX = 5
CP.MAX_SEEN = 60
CP.MAX_ANSWERS = 10
CP.MAX_SOURCES = 6

local function db()
  local d = AA.db
  d.companion = d.companion or {}
  local c = d.companion
  c.outbox = c.outbox or {}
  c.seen = c.seen or {}
  return c
end

CP.MAX_CHAT_LINES = 14

function CP.Pending()
  return #db().outbox
end

-- True once the desktop app has written its answer file at least once.
function CP.Detected()
  return db().detected ~= nil
end

function CP.AutoEnabled()
  return AA.db.settings.autoCompanion and CP.Detected()
end

-- Queue a question and reload right away (call from Enter/click/slash, i.e. a key press or click).
function CP.SendNow(question, links)
  local entry, why = CP.Queue(question, links)
  if not entry then
    AA:Reply("Companion", AA.C.warn .. why .. "|r")
    return false
  end
  db().autoTries = 0
  local ok, whyNot = CP.CanReload()
  if not ok then
    AA:Reply("Companion", { "Queued for the companion. " .. whyNot, "Type /fam check when you can." })
    return true
  end
  ReloadUI()
  return true
end

-- Prints to the normal chat window (local display only; nothing is sent to other players).
function CP.ToChat(lines)
  if not AA.db.settings.companionToChat then return end
  if AA.db.settings.chatTab and AA.db.chatTabCreated then return end -- mirrored in the Assistant tab
  local cf = DEFAULT_CHAT_FRAME
  if not (cf and cf.AddMessage) then return end
  for i, l in ipairs(lines) do
    if i > CP.MAX_CHAT_LINES then
      cf:AddMessage(AA.C.src .. "   ...the rest is in the Azeroth Familiar window: " .. CP.OpenLink() .. "|r")
      break
    end
    cf:AddMessage(l)
  end
end

-- One-click "send my last question to the companion" link (works even before detection).
function CP.SendLink()
  return "|cffc586ff|Haddon:AzerothAssistant:sendlast|h[Ask Mrgl]|h|r"
end

function CP.OpenLink()
  return "|cff4fc3f7|Haddon:AzerothAssistant:open|h[Open Azeroth Familiar]|h|r"
end

local function newId()
  return string.format("%d-%04d", time(), math.random(0, 9999))
end

-- Queues a question for the companion. Returns the entry, or nil + reason.
function CP.Queue(question, links)
  question = AA.Trim(question or "")
  if question == "" then return nil, "Type a question first." end
  local c = db()
  if #c.outbox >= CP.MAX_OUTBOX then
    return nil, "There are already " .. CP.MAX_OUTBOX .. " questions waiting for the companion. Wait for answers first."
  end
  local entry = {
    id = newId(),
    question = (AA.PlainText(question):gsub("[\r\n]+", " ")):sub(1, 500),
    prompt = AA.Export.BuildPacket(question, links),
    created = time(),
  }
  c.outbox[#c.outbox + 1] = entry
  return entry
end

function CP.CanReload()
  if InCombatLockdown and InCombatLockdown() then return false, "You're in combat; send it after combat." end
  if type(ReloadUI) ~= "function" then return false, "This client doesn't allow addons to reload the UI. Type /reload." end
  return true
end

-- Sends (or checks for answers) by reloading the UI. Must come from a click or slash command.
function CP.Reload()
  local ok, why = CP.CanReload()
  if not ok then
    AA:Reply("Companion", AA.C.warn .. why .. "|r")
    return false
  end
  ReloadUI()
  return true
end

-- Inbox validation ----------------------------------------------------------------
local function str(v, max)
  if type(v) ~= "string" then return nil end
  if max and #v > max then v = v:sub(1, max) end
  return v
end

local function safeURL(u)
  u = str(u, 300)
  if not u or u:find("|", 1, true) then return nil end
  if not u:match("^https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+$") then return nil end
  return u
end

function CP.SourceLink(title, url)
  url = safeURL(url)
  if not url then return nil end
  title = AA.PlainText(str(title, 80) or url):gsub("[%[%]]", "")
  return "|cff66bbff|Haddon:AzerothAssistant:url:" .. url .. "|h[" .. title .. "]|h|r"
end

function CP.URLFromLinkData(data)
  local u = type(data) == "string" and data:match("^addon:AzerothAssistant:url:(.+)$")
  return u and safeURL(u) or nil
end

local function isSeen(id)
  for _, s in ipairs(db().seen) do if s == id then return true end end
  return false
end

local function markSeen(id)
  local seen = db().seen
  seen[#seen + 1] = id
  while #seen > CP.MAX_SEEN do table.remove(seen, 1) end
  local out = db().outbox
  for i = #out, 1, -1 do
    if out[i].id == id then table.remove(out, i) end
  end
end

-- Reads AzerothAssistant_CompanionInbox (set by CompanionInbox.lua at load time).
function CP.ProcessInbox()
  local inbox = rawget(_G, "AzerothAssistant_CompanionInbox")
  AzerothAssistant_CompanionInbox = nil -- one-shot: drop the global after reading
  if type(inbox) ~= "table" then return 0 end
  if inbox.version ~= 1 or type(inbox.answers) ~= "table" then
    AA:Reply("Companion", AA.C.warn .. "The companion's answer file has an unknown format; update the addon or the companion.|r")
    return 0
  end
  local firstTime = not CP.Detected()
  db().detected = tonumber(inbox.written) or time()
  if firstTime then
    AA:Reply("Companion", {
      AA.C.good .. "Azeroth Companion detected.|r Questions I can't answer offline now go to it automatically.",
      AA.C.src .. "Turn this off in Settings (\"Ask the companion automatically\").|r",
    })
  end
  local shown = 0
  for i = 1, math.min(#inbox.answers, CP.MAX_ANSWERS) do
    local a = inbox.answers[i]
    local id = type(a) == "table" and str(a.id, 40)
    if id and id:match("^[%w%-]+$") and not isSeen(id) then
      local question = (AA.PlainText(str(a.question, 300) or ""):gsub("[\r\n]+", " "))
      local lines
      if a.status == "error" then
        lines = { AA.C.warn .. "The companion couldn't answer: " .. AA.PlainText(str(a.error, 300) or "unknown error") .. "|r" }
      else
        local validated, info = AA.Export.ValidateImport(str(a.answer, AA.MAX_IMPORT_CHARS * 2) or "")
        lines = {}
        if validated then
          for _, l in ipairs(validated) do lines[#lines + 1] = AA.C.import .. l .. "|r" end
          if info == true then lines[#lines + 1] = AA.C.warn .. "(Answer was cut short to fit.)|r" end
        else
          lines[1] = AA.C.warn .. "The companion sent an empty answer.|r"
        end
        if type(a.sources) == "table" then
          local links = {}
          for s = 1, math.min(#a.sources, CP.MAX_SOURCES) do
            local src = a.sources[s]
            local l = type(src) == "table" and CP.SourceLink(src.title, src.url)
            if l then links[#links + 1] = l end
          end
          if #links > 0 then lines[#lines + 1] = "Sources: " .. table.concat(links, "  ") end
        end
      end
      if question ~= "" then AA:UserSays(AA.C.src .. "(asked the companion)|r " .. question) end
      local model = str(a.model, 40)
      AA:Reply("AI answer via Azeroth Companion" .. (model and (", " .. AA.PlainText(model)) or "") ..
        " - from the web, not verified by the addon", lines)
      local chat = { AA.C.aa .. "Azeroth Familiar|r " .. AA.C.src .. "(AI answer)|r " .. AA.C.you .. question .. "|r" }
      for _, l in ipairs(lines) do chat[#chat + 1] = "   " .. l end
      CP.ToChat(chat)
      markSeen(id)
      db().autoTries = 0
      shown = shown + 1
    end
  end
  return shown
end

-- After login: show new answers, then remind about anything still waiting.
AA:On("PLAYER_LOGIN", function()
  local shown = CP.ProcessInbox()
  local pending = CP.Pending()
  if shown > 0 then
    -- With the Assistant chat tab, answers show there; otherwise open the window.
    local useTab = AA.db.settings.chatTab and AA.db.chatTabCreated
    if AA.UI and not useTab then AA.UI.ShowAssistant() end
  end
  if pending > 0 then
    local q = db().outbox[#db().outbox].question or ""
    AA:Reply("Companion", {
      "Mrgl is answering: \"" .. q .. "\"" .. (pending > 1 and (" (+" .. (pending - 1) .. " more)") or ""),
      "The answer pops up in the Azeroth Companion window over your game in about 15-30 seconds.",
      "It also appears here after your next reload. Want it here now? " .. CP.CheckLink() .. " (reloads your UI).",
      AA.C.src .. "Make sure Azeroth Companion is running on your PC. " .. CP.CancelLink() .. "|r",
    })
    CP.ToChat({ AA.C.aa .. "Azeroth Familiar|r Mrgl is answering \"" .. q .. "\". The answer pops up in the companion window; " .. CP.CheckLink() .. " shows it here." })
    CP.ScheduleAutoCheck()
  end
  if AA.UI and AA.UI.RefreshPending then AA.UI.RefreshPending() end
end)

function CP.CheckLink()
  return "|cff3fd13f|Haddon:AzerothAssistant:check|h[Show answer here]|h|r"
end

-- Auto-check -------------------------------------------------------------------------
-- The game only reads the companion's answer file on a reload, so after a question is sent
-- we reload by ourselves after a short wait (never in combat). If the client ever blocks
-- an addon-initiated reload, auto-check turns itself off and the [Check for answer] link remains.
CP.AUTO_FIRST, CP.AUTO_RETRY, CP.AUTO_MAX = 25, 20, 3

function CP.StopLink()
  return "|cffff7f50|Haddon:AzerothAssistant:stopauto|h[Don't auto-check]|h|r"
end

function CP.ScheduleAutoCheck()
  if not AA.db.settings.autoCheck or AA.db.autoCheckBlocked or CP.Pending() == 0 then return end
  local tries = db().autoTries or 0
  if tries >= CP.AUTO_MAX then
    AA:Reply("Companion", "Mrgl is taking a while. Click " .. CP.CheckLink() .. " when the companion says the answer is ready.")
    return
  end
  local delay = tries == 0 and CP.AUTO_FIRST or CP.AUTO_RETRY
  if CP.autoTimer then CP.autoTimer:Cancel() end
  if type(C_Timer.NewTimer) == "function" then
    CP.autoTimer = C_Timer.NewTimer(delay, CP.AutoCheckNow)
  else
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    C_Timer.After(delay, function() if not t.cancelled then CP.AutoCheckNow() end end)
    CP.autoTimer = t
  end
  AA:Reply("Companion", "I'll check for Mrgl's answer automatically in " .. delay .. " seconds (quick UI reload). " ..
    CP.CheckLink() .. " now, or " .. CP.StopLink() .. ".")
end

function CP.StopAuto()
  if CP.autoTimer then CP.autoTimer:Cancel() end
  CP.autoTimer = nil
  AA:Reply("Companion", "OK, I won't check automatically this time. Click " .. CP.CheckLink() .. " when it's ready.")
end

local waitingForCombat = false
function CP.AutoCheckNow()
  CP.autoTimer = nil
  if CP.Pending() == 0 or AA.db.autoCheckBlocked then return end
  if InCombatLockdown and InCombatLockdown() then
    waitingForCombat = true -- try again a few seconds after combat ends
    return
  end
  db().autoTries = (db().autoTries or 0) + 1
  ReloadUI()
end

AA:On("PLAYER_REGEN_ENABLED", function()
  if waitingForCombat then
    waitingForCombat = false
    C_Timer.After(3, CP.AutoCheckNow)
  end
end)

-- If the client refuses an addon-initiated reload, stop trying and say so once.
local function onBlocked(_, addon, func)
  if addon == ADDON and type(func) == "string" and func:find("ReloadUI", 1, true) then
    AA.db.autoCheckBlocked = true
    AA:Reply("Companion", AA.C.warn .. "The game doesn't allow automatic reloads, so auto-check is off. Click " ..
      CP.CheckLink() .. " instead.|r")
  end
end
AA:On("ADDON_ACTION_BLOCKED", onBlocked)
AA:On("ADDON_ACTION_FORBIDDEN", onBlocked)

function CP.CancelLink()
  return "|cffff7f50|Haddon:AzerothAssistant:cancel|h[Cancel waiting questions]|h|r"
end

function CP.CancelAll()
  if CP.autoTimer then CP.autoTimer:Cancel(); CP.autoTimer = nil end
  local n = CP.Pending()
  wipe(db().outbox)
  AA:Reply("Companion", n .. " waiting question(s) cancelled.")
  if AA.UI and AA.UI.RefreshPending then AA.UI.RefreshPending() end
end

-- Links printed in the normal chat window: Retail-style clients fire the EventRegistry
-- "SetItemRef" event for |Haddon:...| links. Falls back to a post-hook on SetItemRef.
local function onChatLink(link)
  if type(link) == "string" and link:find("^addon:AzerothAssistant:") and AA.UI and AA.UI.HandleAddonLink then
    AA.UI.HandleAddonLink(link)
  end
end
if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
  pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) onChatLink(link) end, CP)
  CP.chatLinkHook = "EventRegistry"
elseif type(SetItemRef) == "function" then
  hooksecurefunc("SetItemRef", function(link) onChatLink(link) end)
  CP.chatLinkHook = "SetItemRef"
end

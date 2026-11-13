-- Azeroth Familiar - Export.lua
-- Copy/paste bridge to an external AI assistant.
--   OUT: a compact plain-text "context packet" the player reviews, then copies (Ctrl+C).
--   IN:  a pasted answer, validated, size-limited and shown as plain text.
-- No networking, no files, no API keys. Imported text is never executed.

local ADDON, AA = ...
local E = {}
AA.Export = E

E.MAX_PACKET_CHARS = 3500

local function plain(s) return AA.PlainText(s or "") end

local function linkRef(l)
  local name = l.name and plain(l.name) or "?"
  local url = AA.Wowhead.URL(l.type, l.id)
  return string.format("%s:%s [%s]%s", l.type, tostring(l.id), name, url and (" " .. url) or "")
end

-- Character context section. Returns lines (plain text) and a status note.
function E.ContextLines(forPreview)
  local s = AA.db.settings
  local lines = {}
  if not s.allowContext and not forPreview then
    return lines, "Character context: not included (permission is off in Settings)."
  end
  local ctx, err = AA.Context.Gather({
    equipment = s.ctxEquipment, stats = s.ctxStats, professions = s.ctxProfessions, quests = s.ctxQuests,
  })
  if not ctx then return lines, err end
  local b = ctx.basic
  lines[#lines + 1] = string.format("Character: level %s %s %s", tostring(b.level or "?"), plain(b.race or ""), plain(b.class or ""))
  if ctx.buildNote and ctx.buildNote ~= "" then lines[#lines + 1] = "Build/goal (player's note): " .. plain(ctx.buildNote) end
  if ctx.equipment then
    local parts = {}
    for _, e in ipairs(ctx.equipment) do
      local id = e.link:match("item:(%d+)")
      parts[#parts + 1] = e.slotName .. "=" .. plain(e.name or "?") .. (id and (" (item:" .. id .. ")") or "")
    end
    lines[#lines + 1] = "Equipped: " .. (#parts > 0 and table.concat(parts, "; ") or "nothing")
  end
  if ctx.stats then
    local parts = {}
    for k, v in pairs(ctx.stats) do parts[#parts + 1] = k .. " " .. tostring(v) end
    table.sort(parts)
    lines[#lines + 1] = "Stats (out of combat): " .. table.concat(parts, ", ")
  end
  if ctx.professions then
    local parts = {}
    for _, p in ipairs(ctx.professions) do
      parts[#parts + 1] = plain(p.name) .. " " .. tostring(p.rank or "?") .. "/" .. tostring(p.max or "?")
    end
    lines[#lines + 1] = "Professions: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
  end
  if ctx.quests then
    local parts = {}
    for i, q in ipairs(ctx.quests) do
      if i > 12 then parts[#parts + 1] = "+" .. (#ctx.quests - 12) .. " more" break end
      local done, total = 0, #q.objectives
      for _, o in ipairs(q.objectives) do if o.finished then done = done + 1 end end
      parts[#parts + 1] = string.format("%s (quest:%d, %s)", plain(q.title), q.questID,
        q.complete and "complete" or (done .. "/" .. total))
    end
    lines[#lines + 1] = "Quest log: " .. (#parts > 0 and table.concat(parts, "; ") or "empty")
  end
  lines[#lines + 1] = "Observed: " .. ctx.observed
  return lines, s.allowContext and "Character context: included." or "Character context: preview only (permission is off, so it would NOT be exported)."
end

-- Detail for quests linked in the question (objective progress), always allowed
-- because the player linked them explicitly.
local function linkedQuestLines(links)
  local out = {}
  for _, l in ipairs(AA.Links.OfType(links, "quest")) do
    local q = AA.Context.FindQuest(l.id)
    if q then
      local objs = {}
      for _, o in ipairs(q.objectives) do objs[#objs + 1] = (o.finished and "[x] " or "[ ] ") .. plain(o.text) end
      out[#out + 1] = string.format("Linked quest %d '%s' in log%s%s. Objectives: %s", q.questID, plain(q.title),
        q.level and (", level " .. q.level) or "", q.zone and (", log zone " .. plain(q.zone)) or "",
        #objs > 0 and table.concat(objs, " | ") or "none listed")
    end
  end
  return out
end

-- Short, natural-language question for an AI assistant. Character details are added only
-- when the player has ticked "Include my character". Links in the question are replaced by
-- their names, and each item/quest gets its Wowhead Forever URL.
function E.BuildPacket(question, extraLinks)
  local c = AA.client or {}
  local links = AA.Links.Extract(question or "")
  if #links == 0 and extraLinks then links = extraLinks end
  local s = AA.db.settings
  local lines = {}
  local who = ""
  local ctx
  if s.allowContext then
    ctx = AA.Context.Gather({ equipment = s.ctxEquipment, stats = s.ctxStats, professions = s.ctxProfessions, quests = s.ctxQuests })
    if ctx then
      local b = ctx.basic
      who = string.format(" I'm a level %s %s %s", tostring(b.level or "?"), plain(b.race or ""), plain(b.class or ""))
      if ctx.buildNote and ctx.buildNote ~= "" then who = who .. " (" .. plain(ctx.buildNote) .. ")" end
      who = who .. "."
    end
  end
  lines[#lines + 1] = string.format("World of Warcraft: Forever (version %s, Classic-era content).%s",
    tostring(c.version or "1.60.1"), who)
  lines[#lines + 1] = "Question: " .. plain(question)
  for _, l in ipairs(links) do
    local url = AA.Wowhead.URL(l.type, l.id)
    if l.type == "item" or l.type == "quest" then
      lines[#lines + 1] = string.format("%s: %s%s", l.type == "item" and "Item" or "Quest",
        plain(l.name or (l.type .. " " .. tostring(l.id))), url and (" " .. url) or "")
    end
  end
  for _, l in ipairs(linkedQuestLines(links)) do lines[#lines + 1] = l end
  if ctx then
    local ctxLines = E.ContextLines(false)
    for _, l in ipairs(ctxLines) do -- the opener already has level/race/class and the build note
      if not (l:find("^Character:") or l:find("^Build/goal") or l:find("^Observed:")) then lines[#lines + 1] = l end
    end
  end
  lines[#lines + 1] = "Please answer for WoW Forever specifically (wowhead.com/forever is a good source), briefly, in plain text under 1000 characters. Say if you're unsure."
  local text = table.concat(lines, "\n")
  if #text > E.MAX_PACKET_CHARS then
    text = text:sub(1, E.MAX_PACKET_CHARS - 20) .. "\n[trimmed]"
  end
  return text
end

-- Import -----------------------------------------------------------------------
-- Returns lines ready to display, or nil + reason.
function E.ValidateImport(text)
  if type(text) ~= "string" then return nil, "Nothing to import." end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  text = AA.Trim(text)
  if text == "" then return nil, "Nothing to import." end
  local truncated = false
  if #text > AA.MAX_IMPORT_CHARS then
    text = text:sub(1, AA.MAX_IMPORT_CHARS)
    truncated = true
  end
  -- Drop control characters and neutralize every escape sequence: the answer is
  -- displayed as literal text, so it can't create links, textures or colors.
  text = text:gsub("[%z\1-\8\11-\31\127]", "")
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = AA.Trim(line)
    if line ~= "" then
      if #out >= AA.MAX_IMPORT_LINES then truncated = true break end
      if #line > 400 then line = line:sub(1, 400) .. "..." end
      out[#out + 1] = (line:gsub("|", "||"))
    end
  end
  if #out == 0 then return nil, "Nothing to import." end
  return out, truncated
end

function E.Import(text)
  local lines, info = E.ValidateImport(text)
  if not lines then
    AA:Reply("Import", AA.C.warn .. info .. "|r")
    return false
  end
  local shown = {}
  for i, l in ipairs(lines) do shown[i] = AA.C.import .. l .. "|r" end
  if info == true then shown[#shown + 1] = AA.C.warn .. "(The pasted answer was longer than the limit and was cut short.)|r" end
  AA:Reply("External answer - pasted by you, not verified by the addon", shown)
  return true
end

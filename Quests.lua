-- Azeroth Familiar - Quests.lua
-- Explains quests using only quest-log text from the client. Never invents locations,
-- coordinates, prerequisites or drop rates.

local ADDON, AA = ...
local Q = {}
AA.Quests = Q

local function objectiveLine(o)
  local mark = o.finished and (AA.C.good .. "[done]|r ") or "[ ] "
  local text = AA.PlainText(o.text)
  if text == "" and o.need then text = string.format("%s/%s", tostring(o.have or 0), tostring(o.need)) end
  return mark .. text
end

function Q.Describe(q, wantDescription)
  local lines = {}
  local head = AA.C.head .. q.title .. "|r"
  if q.level then head = head .. " (level " .. q.level .. ")" end
  if q.complete then head = head .. " " .. AA.C.good .. "- ready to turn in|r" end
  lines[#lines + 1] = head
  if q.zone then lines[#lines + 1] = "Quest log category: " .. q.zone .. AA.C.src .. " (the log's zone header, not a map location)|r" end
  if #q.objectives == 0 then
    lines[#lines + 1] = "No tracked objectives in the log (often a talk-to or delivery quest)."
  else
    for _, o in ipairs(q.objectives) do lines[#lines + 1] = objectiveLine(o) end
  end
  if wantDescription then
    local desc, objText = AA.Context.QuestText(q)
    if objText and objText ~= "" then lines[#lines + 1] = "Log summary: " .. AA.PlainText(objText) end
    if desc and desc ~= "" then
      local d = AA.PlainText(desc)
      if #d > 400 then d = d:sub(1, 400) .. "..." end
      lines[#lines + 1] = AA.C.src .. "Description: " .. d .. "|r"
    end
  end
  return lines
end

function Q.LocationLines(questID, title)
  local lines = {}
  local qLines, found = {}, false
  if AA.Questie and AA.Questie.Available() then qLines, found = AA.Questie.QuestLines(questID) end
  if found then
    for _, l in ipairs(qLines) do lines[#lines + 1] = l end
  else
    lines[#lines + 1] = AA.C.warn .. "Coordinates and NPC locations aren't available:|r the game client doesn't expose a quest database to addons" ..
      ((AA.Questie and AA.Questie.Available()) and ", and Questie's database has no entry for this quest." or ", and Questie's database isn't available.")
  end
  local hint = AA.Questie and AA.Questie.LocationHint()
  if hint then lines[#lines + 1] = hint end
  lines[#lines + 1] = "Look it up: " .. AA.Wowhead.Link("quest", questID, title or ("quest " .. questID)) ..
    "  or build an AI question with " .. Q.AskLink()
  return lines
end

function Q.AskLink()
  return "|cffc586ff|Haddon:AzerothAssistant:ask|h[Ask AI]|h|r"
end

-- Answer for one linked quest.
function Q.Answer(link, wantLocation)
  local q = AA.Context.FindQuest(link.id)
  local lines
  local src
  if q then
    src = "Offline - your quest log, live"
    lines = Q.Describe(q, true)
  else
    src = "Offline - quest link only"
    local okT, title = AA.Try(AA.Api("C_QuestLog", "GetTitleForQuestID"), link.id)
    title = (okT and AA.Str(title)) or link.name or ("Quest " .. link.id)
    lines = { AA.C.head .. title .. "|r", "This quest isn't in your quest log, so the client gives me only its name and ID (" .. link.id .. ")." }
  end
  if wantLocation or not q then
    for _, l in ipairs(Q.LocationLines(link.id, q and q.title or link.name)) do lines[#lines + 1] = l end
  else
    lines[#lines + 1] = AA.Wowhead.Link("quest", link.id, q.title)
  end
  return src, lines
end

-- Quest log overview, optionally filtered by a search term.
function Q.Overview(term)
  local list = (term and term ~= "") and AA.Search.FindQuests(term) or AA.Context.QuestLog()
  if #list == 0 then
    return "Offline - your quest log, live", { term and term ~= "" and ("No quest in your log matches \"" .. term .. "\".") or "Your quest log is empty." }
  end
  local lines = {}
  for i, q in ipairs(list) do
    if i > 15 then lines[#lines + 1] = "...and " .. (#list - 15) .. " more." break end
    local done, total = 0, #q.objectives
    for _, o in ipairs(q.objectives) do if o.finished then done = done + 1 end end
    local status = q.complete and (AA.C.good .. "ready to turn in|r") or (total > 0 and (done .. "/" .. total .. " objectives") or "in progress")
    local okL, ql = AA.Try(AA.Api("GetQuestLink"), q.questID)
    local name = (okL and AA.Str(ql)) or q.title
    lines[#lines + 1] = (q.level and ("[" .. q.level .. "] ") or "") .. name .. " - " .. status .. (q.zone and (AA.C.src .. " (" .. q.zone .. ")|r") or "")
  end
  return "Offline - your quest log, live", lines
end

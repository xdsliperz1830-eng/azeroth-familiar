-- Azeroth Familiar - Integrations/Wowhead.lua
-- Builds Wowhead Forever URLs. The addon cannot open websites or fetch data from
-- Wowhead; it only shows a URL the player can copy into a browser.
-- Verified URL shape (from wowhead.com search results):  https://www.wowhead.com/forever/item=<id>
-- Assumed by Wowhead convention (not yet verified for Forever): quest=, npc=, spell=, search?q=

local ADDON, AA = ...
local W = {}
AA.Wowhead = W

W.BASE = "https://www.wowhead.com/forever/"

local VALID_TYPES = { item = true, quest = true, npc = true, spell = true }

local function urlencode(s)
  s = tostring(s or "")
  s = s:gsub("[^%w%-_%.~ ]", function(c) return string.format("%%%02X", string.byte(c)) end)
  return (s:gsub(" ", "+"))
end

function W.URL(kind, id)
  id = tonumber(id)
  if not VALID_TYPES[kind] or not id then return nil end
  return W.BASE .. kind .. "=" .. math.floor(id)
end

function W.SearchURL(term)
  term = AA.Trim(AA.PlainText(term or ""))
  if term == "" then return nil end
  return W.BASE .. "search?q=" .. urlencode(term:sub(1, 80))
end

-- A clickable line inside the assistant window. Clicking opens a copy box with the URL.
-- Data format: addon:AzerothAssistant:wh:<kind>:<id>   or   addon:AzerothAssistant:whs:<term>
function W.Link(kind, id, label)
  if not W.URL(kind, id) then return "" end
  label = AA.PlainText(label or (kind .. " " .. tostring(id)))
  return "|cff66bbff|Haddon:AzerothAssistant:wh:" .. kind .. ":" .. math.floor(tonumber(id)) ..
    "|h[Wowhead: " .. label .. "]|h|r"
end

function W.SearchLink(term)
  term = AA.Trim(AA.PlainText(term or "")):gsub(":", " ")
  if term == "" then return "" end
  term = term:sub(1, 60)
  return "|cff66bbff|Haddon:AzerothAssistant:whs:" .. term .. "|h[Wowhead search: " .. term .. "]|h|r"
end

-- Returns the URL for a clicked addon link, or nil if it isn't one of ours.
function W.FromLinkData(data)
  if type(data) ~= "string" then return nil end
  local kind, id = data:match("^addon:AzerothAssistant:wh:(%a+):(%d+)$")
  if kind then return W.URL(kind, id) end
  local term = data:match("^addon:AzerothAssistant:whs:(.+)$")
  if term then return W.SearchURL(term) end
  return nil
end

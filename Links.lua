-- Azeroth Familiar - Links.lua
-- Parses item/quest/spell hyperlinks from text and lets shift-click insert links into
-- the assistant's input box. Uses post-hooks only (hooksecurefunc): normal linking into
-- chat keeps working exactly as before, and no global handler is replaced.

local ADDON, AA = ...
local L = {}
AA.Links = L
L.hooked = {}

-- Extracts every |H...|h[...]|h hyperlink. Does not assume a fixed field count after the ID,
-- and accepts both classic |cffRRGGBB and newer |cn...: color prefixes (they are ignored).
function L.Extract(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for data, display in text:gmatch("|H(.-)|h(.-)|h") do
    local ltype, rest = data:match("^([^:]+):?(.*)$")
    if ltype then
      local id = tonumber((rest or ""):match("^(%-?%d+)"))
      local name = display:gsub("^%[", ""):gsub("%]$", "")
      out[#out + 1] = {
        type = ltype,
        id = id,
        data = data,
        name = name,
        link = "|H" .. data .. "|h" .. display .. "|h",
      }
    end
  end
  -- Also accept typed plain references like "item:2319" or "quest:123"
  local stripped = text:gsub("|H.-|h.-|h", " ")
  for ltype, id in stripped:gmatch("%f[%w](%a+):(%d+)") do
    ltype = ltype:lower()
    if ltype == "item" or ltype == "quest" or ltype == "spell" then
      out[#out + 1] = { type = ltype, id = tonumber(id), data = ltype .. ":" .. id, name = nil, link = ltype .. ":" .. id, typed = true }
    end
  end
  return out
end

function L.OfType(links, ltype)
  local out = {}
  for _, l in ipairs(links) do
    if l.type == ltype and l.id then out[#out + 1] = l end
  end
  return out
end

-- Removes hyperlinks from a question so keyword matching only sees the player's words.
function L.StripLinks(text)
  if type(text) ~= "string" then return "" end
  local s = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
  s = s:gsub("|H.-|h.-|h", " ")
  return s
end

-- Shift-click insertion -------------------------------------------------------
local lastText, lastTime

local function focusedInput()
  local boxes = { AA.UI and AA.UI.input or false, AA.ChatTab and AA.ChatTab.input or false }
  for i = 1, #boxes do
    local box = boxes[i]
    if box and box:IsVisible() and box:HasFocus() then return box end
  end
  return nil
end

local function onInsertLink(text)
  local box = focusedInput()
  if not box then return end
  if type(text) ~= "string" or not text:find("|H", 1, true) then return end
  local now = GetTime()
  -- Some clients route one insert through two functions; insert only once.
  if lastText == text and lastTime == now then return end
  lastText, lastTime = text, now
  box:Insert(text)
end

function L.InstallHooks()
  if L.installed then return end
  L.installed = true
  if type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
    L.hooked[#L.hooked + 1] = "ChatEdit_InsertLink"
  end
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
    hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
    L.hooked[#L.hooked + 1] = "ChatFrameUtil.InsertLink"
  end
end

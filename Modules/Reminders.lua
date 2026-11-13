-- Azeroth Familiar - Modules/Reminders.lua
-- Optional one-line reminders in your chat window. Each is event-driven, prints once
-- when the condition starts, and can be switched off on the Interface page.
-- Reminders only tell you things: nothing is sold, repaired or bought for you.
-- No low-health/low-mana reminder: those numbers are hidden from addons in combat here.

local ADDON, AA = ...
local R = {}
AA.Reminders = R

R.DURABILITY_PCT = 25
R.BAG_SLOTS = 3

local warned = {}
local function on(key) return AA.db and AA.db.settings.remind[key] end

function R.CheckDurability()
  if not on("durability") then return end
  local pct, list = AA.Stats.Durability()
  local worst = list[1]
  if worst and worst.pct < R.DURABILITY_PCT then
    if not warned.durability then
      warned.durability = true
      AA:Print(AA.C.warn .. string.format("Low durability: %s is at %d%%. Overall %d%%.|r",
        worst.link or "an item", worst.pct, pct or 0))
    end
  else
    warned.durability = nil
  end
end

function R.CheckBags()
  if not on("bags") then return end
  local free = AA.Stats.Bags()
  if not free then return end
  if free <= R.BAG_SLOTS then
    if not warned.bags then
      warned.bags = true
      AA:Print(AA.C.warn .. "Bags nearly full: " .. free .. " free slot" .. (free == 1 and "" or "s") .. " left.|r")
    end
  else
    warned.bags = nil
  end
end

function R.AtMerchant()
  if not on("vendor") then return end
  local parts = {}
  local junk, value = AA.Stats.Junk()
  if #junk > 0 then
    parts[#parts + 1] = #junk .. " grey item" .. (#junk == 1 and "" or "s") .. " to sell (" .. AA.Stats.MoneyText(value) .. ")"
  end
  local okC, can = AA.Try(AA.Api("CanMerchantRepair"))
  if okC and can then
    local okR, cost = AA.Try(AA.Api("GetRepairAllCost"))
    cost = okR and AA.Num(cost) or 0
    if cost > 0 then parts[#parts + 1] = "repairs here cost " .. AA.Stats.MoneyText(cost) end
  end
  if #parts > 0 then AA:Print("At this vendor: " .. table.concat(parts, "; ") .. ".") end
end

function R.LevelUp(level)
  if not on("levelup") then return end
  local s = AA.Stats.SessionSummary()
  local line = "Level " .. tostring(level or "up") .. "! This session: " .. AA.Stats.Duration(s.length)
  if s.xpPerHour then line = line .. string.format(", %d XP per hour", s.xpPerHour) end
  AA:Print(AA.C.good .. line .. ".|r")
end

AA:On("UPDATE_INVENTORY_DURABILITY", function() R.CheckDurability() end)
AA:On("BAG_UPDATE_DELAYED", function() R.CheckBags() end)
AA:On("MERCHANT_SHOW", function() R.AtMerchant() end)
AA:On("PLAYER_LEVEL_UP", function(_, level) R.LevelUp(level) end)
AA:On("PLAYER_ENTERING_WORLD", function()
  if C_Timer and C_Timer.After then
    C_Timer.After(6, function() pcall(R.CheckDurability); pcall(R.CheckBags) end)
  end
end)

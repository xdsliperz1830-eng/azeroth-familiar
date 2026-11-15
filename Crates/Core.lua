-- Azeroth Familiar - Crates/Core.lua (ported from Crate Scout 0.2.0)
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.engine = "Crate Scout 0.2.0"
C.mode = "My Crates"
C.owned, C.live, C.verified, C.unsupported = {}, {}, {}, {}
C.countOwned = false
C.revision = 0
-- Shared palette. Green is reserved for ready / confirmed-cheapest states.
C.Color = {
    gold="|cffffd100", green="|cff4cff4c", amber="|cffffb84d", orange="|cffff8a3d",
    red="|cffff5a5a", grey="|cff9d9d9d", white="|cffffffff", muted="|cffc8c2b4",
}
function C.Now() return GetServerTime() end
function C.Money(n)
    if not n then return "--" end
    n = math.floor(n)
    local g, s, c = math.floor(n / 10000), math.floor(n / 100) % 100, n % 100
    if g > 0 then return g .. "g " .. s .. "s " .. c .. "c" end
    if s > 0 then return s .. "s " .. c .. "c" end
    return c .. "c"
end
-- Same amounts as C.Money with coin-colored unit letters (no textures, so
-- right-justified columns stay aligned).
function C.Coins(n)
    if not n then return "--" end
    local tint = {g="|cffffd700g|r", s="|cffc7c7cfs|r", c="|cffeda55fc|r"}
    return (C.Money(n):gsub("(%d+)([gsc])", function(d, u) return d .. tint[u] end))
end
function C.Age(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return seconds .. "s ago" end
    return math.floor(seconds / 60) .. "m " .. string.format("%02d", seconds % 60) .. "s ago"
end
-- Data changed (scan, inventory, validation, settings): bump the revision and
-- notify views. Views decide whether anything visible changed.
function C.Changed()
    C.revision = C.revision + 1
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
    if C.Tooltip then C.Tooltip:Refresh() end
end
function C.Status(text)
    C.message = text
    C.Changed()
end
function C.ItemName(id, fallback)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or fallback or ("Item " .. id)
end
function C.ItemIcon(id)
    local icon
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    if not icon then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if instant then local ok, _, _, _, _, tex = pcall(instant, id); if ok then icon = tex end end
    end
    return icon
end
C.CRATE_ICON = "Interface\\Icons\\INV_Crate_03"

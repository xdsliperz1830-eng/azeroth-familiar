-- Azeroth Familiar - Crates/Bags.lua (ported from Crate Scout 0.2.0)
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.Inventory = {}
local I=C.Inventory
function I:Read()
    local owned,unknown={},{}
    for bag=0,(NUM_BAG_SLOTS or 4) do
        for slot=1,C_Container.GetContainerNumSlots(bag) do
            local info=C_Container.GetContainerItemInfo(bag,slot)
            if info and info.itemID then
                local id=info.itemID
                owned[id]=(owned[id] or 0)+(info.stackCount or 1)
                local name=C.ItemName(id,info.hyperlink or "")
                if not C.Catalog.entries[id] and name:find("Waylaid Crate",1,true) then unknown[id]=name end
            end
        end
    end
    C.owned,C.unsupported=owned,unknown
end
local function clean(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1"):gsub("%s+"," "))
end
-- Historical source data alone never certifies a recipe for a newer client.
-- Read the client's own rendered tooltip and verify EVERY alternative and count.
function I:ValidateCatalog()
    if not self.tip then self.tip=CreateFrame("GameTooltip","AzerothFamiliarCrateTooltip",UIParent,"GameTooltipTemplate") end
    local tip=self.tip
    for id,crate in pairs(C.Catalog.entries) do
        local ok, valid, reason=pcall(function()
            local infoFn=(C_Item and C_Item.GetItemInfo) or GetItemInfo
            local name,_,_,_,required=infoFn(id)
            if not name then
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                return false,"Waiting for client item data"
            end
            if GetLocale()~="enUS" and GetLocale()~="enGB" then return false,"Tooltip verifier currently requires English client" end
            tip:SetOwner(UIParent,"ANCHOR_NONE"); tip:ClearLines(); tip:SetItemByID(id)
            local lines={}
            for j=1,tip:NumLines() do
                local fs=_G["AzerothFamiliarCrateTooltipTextLeft"..j]
                lines[#lines+1]=fs and fs:GetText() or ""
            end
            tip:Hide()
            local text=clean(table.concat(lines," "))
            if not text:find("Fill the crate with any bundle",1,true) then return false,"Fill tooltip missing or changed" end
            if required~=crate.level then return false,"Level requirement changed" end
            local start=text:find("Fill the crate with any bundle",1,true)
            local tail=text:sub(start)
            local count=0
            for _ in tail:gmatch("%-%s*%d+%s") do count=count+1 end
            if count~=#crate.bundles then return false,"Bundle count changed or tooltip not loaded" end
            for _,b in ipairs(crate.bundles) do
                local material=infoFn(b.itemID)
                if not material then
                    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(b.itemID) end
                    return false,"Waiting for material names"
                end
                if material~=b.name then return false,"Material ID/name mismatch" end
                local wanted="- "..b.quantity.." "..material
                local pos=tail:find(wanted,1,true)
                if not pos then return false,"Bundle tooltip mismatch" end
                local after=tail:sub(pos+#wanted,pos+#wanted)
                if after~="" and after~=" " then return false,"Bundle name mismatch" end
            end
            return true,"Client tooltip verified"
        end)
        C.verified[id]=ok and valid or false
        crate.validation=ok and reason or "Tooltip verification failed"
    end
end
function I:Coverage()
    local n,total=0,0
    for id in pairs(C.Catalog.entries) do total=total+1; if C.verified[id] then n=n+1 end end
    return n,total
end

-- Azeroth Familiar - Crates/Model.lua (ported from Crate Scout 0.2.0)
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.Model={}
local M=C.Model
function M:Rows()
    local rows={}
    local owned=(C.mode=="My Crates" or (C.mode=="All Crates" and C.countOwned)) and C.owned or {}
    for id,crate in pairs(C.Catalog.entries) do
        if C.mode~="My Crates" or (C.owned[id] or 0)>0 then
            local row={crate=crate,id=id,count=C.owned[id] or 0,locked=UnitLevel("player")<crate.level}
            if not C.verified[id] then row.status="Unsupported #"..id..": "..(crate.validation or "Tooltip unverified")
            else
                row.rec=self:Recommend(crate,owned)
                row.best,row.alternatives,row.priced=row.rec.best,row.rec.alternatives,row.rec.priced
                row.cost=row.best.cost
                row.status=row.best.status
                if row.priced>0 and row.priced<#crate.bundles and row.cost~=0 then row.status="Cheapest of priced bundles · "..row.status end
                if C.mode=="Buy & Fill" then
                    row.cratePrice=C.Providers:Quote(id,1)
                    row.fillCost=row.cost
                    row.cost=row.cost and row.cratePrice.cost and row.cost+row.cratePrice.cost or nil
                    row.status=row.status.." / crate: "..row.cratePrice.status
                    if row.cratePrice.kind=="estimate" then row.status=row.status.." (crate stack cash unknown)" end
                end
            end
            rows[#rows+1]=row
        end
    end
    if C.mode=="My Crates" then
        for id,name in pairs(C.unsupported) do rows[#rows+1]={id=id,crate={name=name,id=id},status="Unsupported recipe · item ID "..id,count=C.owned[id] or 0} end
    end
    table.sort(rows,function(a,b)
        if a.cost~=b.cost then return (a.cost or math.huge)<(b.cost or math.huge) end
        return a.id<b.id
    end)
    return rows
end
-- Classifies Cost.Compare output so the tooltip and the window highlight by
-- identical rules. It never prices anything itself.
--   ready       a valid bundle is fully owned (0c)
--   live        cheapest is a live buyout from a complete, fresh AH snapshot
--   estimate    cheapest relies on a cached provider estimate (never "confirmed")
--   unpriced    no alternative could be priced
--   unsupported recipe not verified against the client tooltip
function M:Recommend(crate,owned)
    local rec={crate=crate,id=crate and crate.id,winners={},winnerList={},total=crate and crate.bundles and #crate.bundles or 0,priced=0}
    if not crate or not crate.bundles or not C.verified[crate.id] then
        rec.state="unsupported"; rec.reason=crate and crate.validation or "Tooltip unverified"; return rec
    end
    local best,alts,priced=C.Cost.Compare(crate,owned or {},function(item,n) return C.Providers:Quote(item,n) end)
    rec.best,rec.alternatives,rec.priced=best,alts,priced
    if priced==0 then rec.state="unpriced"; return rec end
    local estimate=false
    for _,r in ipairs(alts) do
        if r.cost==best.cost then
            rec.winners[r.bundle.itemID]=r; rec.winnerList[#rec.winnerList+1]=r
            if r.kind~="live" and r.kind~="owned" then estimate=true end
        end
        if r.cost and r.kind=="estimate" then rec.mixed=true end
    end
    rec.tie=#rec.winnerList>1
    if best.cost==0 then rec.state="ready"; rec.partial=false
    else
        rec.state=estimate and "estimate" or "live"
        rec.partial=priced<rec.total
    end
    return rec
end
function M:SearchIDs()
    local ids={}
    for id,crate in pairs(C.Catalog.entries) do
        if C.verified[id] and (C.mode~="My Crates" or (C.owned[id] or 0)>0) then
            for _,b in ipairs(crate.bundles) do ids[#ids+1]=b.itemID end
            if C.mode=="Buy & Fill" then ids[#ids+1]=id end
        end
    end
    return ids
end
function M:SearchItem(id)
    C.Scan:Cancel("Preparing item search")
    if not C.Scan.open then C.Status("Open the AH to search for item "..id); return end
    local api=Auctionator and Auctionator.API and Auctionator.API.v1
    local name=C.ItemName(id)
    if api and type(api.MultiSearchExact)=="function" and not name:match("^Item %d+$") then
        local ok=pcall(api.MultiSearchExact,"Azeroth Familiar",{name})
        if ok then C.Status("Auctionator search opened: "..name.." · verify item ID "..id); return end
    end
    -- Without Auctionator, prepare the exact item's native result cache and
    -- give a copyable name in the UI; do not call undocumented frame methods.
    if C.UI and C.UI.searchBox then C.UI.searchBox:SetText(name); C.UI.searchBox:HighlightText(); C.UI.searchBox:SetFocus() end
    C.Status("Copy the prepared item name into the AH search: "..name.." (#"..id..")")
end

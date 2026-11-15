-- Azeroth Familiar - Crates/Scan.lua (ported from Crate Scout 0.2.0)
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.Scan={open=false,serial=0}
local S=C.Scan
local required={"SendSearchQuery","MakeItemKey","GetItemKeyInfo","HasSearchResults","IsThrottledMessageSystemReady","GetNumItemSearchResults","GetItemSearchResultInfo","HasFullItemSearchResults","RequestMoreItemSearchResults","GetNumCommoditySearchResults","GetCommoditySearchResultInfo","HasFullCommoditySearchResults","RequestMoreCommoditySearchResults"}
function S:Capabilities()
    local _,build,_,interface=GetBuildInfo()
    if interface~=16001 or tostring(build)~="70938" then return false,"AH adapter requires reviewed build 70938 / interface 16001" end
    for _,key in ipairs(required) do
        if not C_AuctionHouse or type(C_AuctionHouse[key])~="function" then return false,"Missing AH API: "..key end
    end
    return true
end
function S:Cancel(reason)
    self.serial=self.serial+1
    if self.pending then
        for index=self.pending.index,#self.pending.ids do
            local id=self.pending.ids[index]
            C.live[id]={complete=false,rows={},time=C.Now(),reason=reason or "Cancelled"}
        end
    end
    self.pending=nil
    C.Status(reason or "Scan cancelled. Completed items remain available.")
end
function S:Start(ids)
    if self.pending then C.Status("Scan already running; Cancel first."); return end
    local ok,reason=self:Capabilities()
    if not ok then C.Status(reason); return end
    if not self.open then C.Status("Open the Auction House, then click Scan Auction House."); return end
    local unique,queue={},{}
    for _,id in ipairs(ids or C.Model:SearchIDs()) do
        if not unique[id] then unique[id]=true; queue[#queue+1]=id end
    end
    table.sort(queue)
    if #queue==0 then C.Status("No verified crates to scan. Click Verify on the Crates page after item data loads."); return end
    self.serial=self.serial+1
    self.pending={ids=queue,index=1,token=self.serial,phase="query",deadline=GetTime()+30}
    for _,id in ipairs(queue) do C.live[id]={complete=false,rows={},time=C.Now(),reason="Queued"} end
    self:Schedule()
    C.Status("Scan queued: "..#queue.." items. Keep other AH searches idle; Cancel stops safely.")
end
function S:Schedule()
    local pending=self.pending
    if not pending or pending.timer then return end
    pending.timer=true
    local token=self.serial
    C_Timer.After(0.8,function()
        pending.timer=nil
        if self.pending and token==self.serial then
            local ok,err=pcall(self.Tick,self)
            if not ok then self:Cancel("Scan stopped safely: "..tostring(err)) end
        end
    end)
end
function S:Advance()
    local p=self.pending
    p.index=p.index+1
    if p.index>#p.ids then
        self.pending=nil
        C.Status("Scan complete. Rows are independent comparisons; confirm listings before buying.")
    else
        p.phase="query"; p.deadline=GetTime()+30; p.partial=nil; p.key=nil
        self:Schedule()
    end
end
function S:Tick()
    local p=self.pending
    if not p or not self.open then return end
    if GetTime()>p.deadline then self:Cancel("Incomplete scan: request timed out. Retry when AH is idle."); return end
    if p.phase=="waiting" or not C_AuctionHouse.IsThrottledMessageSystemReady() then self:Schedule(); return end
    local id=p.ids[p.index]
    if p.phase=="query" and not C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(id)) then
        C.Status("Waiting for AH item metadata: "..id); self:Schedule(); return
    end
    C.Status("Scanning "..p.index.."/"..#p.ids..": "..C.ItemName(id).." (keep other AH searches idle)")
    self.issuing=true
    local ok,err=pcall(function()
        if p.phase=="query" then
            p.key=C_AuctionHouse.MakeItemKey(id)
            p.phase="waiting"
            C_AuctionHouse.SendSearchQuery(p.key,{},true)
        else
            p.phase="waiting"
            if p.partial then C_AuctionHouse.RequestMoreCommoditySearchResults(id)
            else C_AuctionHouse.RequestMoreItemSearchResults(p.key) end
        end
    end)
    self.issuing=false
    if not ok then self:Cancel("AH request failed: "..tostring(err)); return end
    -- A synchronous event may have advanced or finished the request.
    if self.pending==p and p.phase=="waiting" then self:Schedule() end
end
function S:Read(partial)
    local p=self.pending
    local id=p.ids[p.index]
    if not C_AuctionHouse.HasSearchResults(p.key) then p.phase="query"; return end
    local full
    if partial then full=C_AuctionHouse.HasFullCommoditySearchResults(id)
    else full=C_AuctionHouse.HasFullItemSearchResults(p.key) end
    if not full then p.partial=partial; p.phase="more"; return end
    local count=partial and C_AuctionHouse.GetNumCommoditySearchResults(id) or C_AuctionHouse.GetNumItemSearchResults(p.key)
    if not count or count>20000 then self:Cancel("Incomplete scan: unexpected result count"); return end
    local rows,seen={},{}
    for i=1,count do
        local r
        if partial then r=C_AuctionHouse.GetCommoditySearchResultInfo(id,i)
        else r=C_AuctionHouse.GetItemSearchResultInfo(p.key,i) end
        if not r or type(r.quantity)~="number" or r.quantity<1 or r.quantity~=math.floor(r.quantity) or
            (partial and (type(r.unitPrice)~="number" or r.unitPrice<=0)) or (not partial and not r.auctionID) then
            self:Cancel("Incomplete listing data; retry scan"); return
        end
        if (partial and r.itemID~=id) or (not partial and (not r.itemKey or r.itemKey.itemID~=id)) then
            self:Cancel("Search results changed; scan discarded"); return
        end
        if partial then
            -- Read the final cumulative result list only once; a tier is not
            -- appended again on each pagination event. Exclude account tiers.
            local quantity=math.max(0,r.quantity-(r.numOwnerItems or 0))
            if not r.containsAccountItem and quantity>0 then
                rows[#rows+1]={auctionID="tier:"..i,quantity=quantity,unitPrice=r.unitPrice}
            end
        elseif r.auctionID and not seen[r.auctionID] then
            seen[r.auctionID]=true
            if not r.containsOwnerItem and not r.containsAccountItem then
                rows[#rows+1]={auctionID=r.auctionID,quantity=r.quantity,buyout=r.buyoutAmount}
            end
        end
    end
    C.live[id]={complete=true,rows=rows,partial=partial,time=C.Now()}
    self:Advance()
end
function S:Event(event,arg)
    if event=="AUCTION_HOUSE_SHOW" then self.open=true; C.Status("AH open. Scan on request; purchases stay manual."); return end
    if event=="AUCTION_HOUSE_CLOSED" or event=="AUCTION_HOUSE_DISABLED" then
        self.open=false; self:Cancel("AH closed. Reopen and rescan for live plans."); return
    end
    local p=self.pending
    if not p or p.phase~="waiting" then return end
    local id=p.ids[p.index]
    if event=="COMMODITY_SEARCH_RESULTS_UPDATED" and arg==id then
        self:Read(true)
    elseif event=="ITEM_SEARCH_RESULTS_UPDATED" and type(arg)=="table" and arg.itemID==id and
        (arg.itemLevel or 0)==(p.key.itemLevel or 0) and (arg.itemSuffix or 0)==(p.key.itemSuffix or 0) then
        self:Read(false)
    end
end
function S:InstallHooks()
    if self.hooked or not C_AuctionHouse or not hooksecurefunc then return end
    self.hooked=true
    for _,method in ipairs({"SendSearchQuery","SendSellSearchQuery","RequestMoreItemSearchResults","RequestMoreCommoditySearchResults"}) do
        if type(C_AuctionHouse[method])=="function" then
            hooksecurefunc(C_AuctionHouse,method,function()
                if self.pending and not self.issuing then self:Cancel("Another AH search interrupted this scan. Retry with other searches idle.") end
            end)
        end
    end
end

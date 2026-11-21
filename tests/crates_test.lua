-- Azeroth Familiar - tests/crates_test.lua
-- Fixture tests for the Crates feature (ported from Crate Scout 0.2.0). Loads Familiar's
-- real Core, widgets, page shell and Crates modules against mocked client APIs.
-- Run: python tests/run.py [path/to/lua51.dll]   (no purchases are mocked or implemented)
local passed=0
local function eq(a,b,msg) assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local function test(name,fn) fn(); passed=passed+1; print("PASS "..name) end
local now=1000
GetServerTime=function() return now end
GetTime=function() return now end
GetBuildInfo=function() return "1.60.1","70938","",16001 end
GetLocale=function() return "enUS" end
UnitLevel=function() return 15 end
date=os.date
print=print
local frames={}
local noop=function() end
local function widget()
    -- Unlisted frame methods are harmless no-ops; getters used by the addon are explicit.
    local w=setmetatable({scripts={},shown=true},{__index=function(_,k) if type(k)=="string" and k:match("^%u") then return noop end end})
    function w:GetPoint() return rawget(self,"point") or "CENTER",nil,rawget(self,"rel") or "CENTER",rawget(self,"x") or 0,rawget(self,"y") or 0 end
    function w:SetPoint(point,a,b,c,d) if type(a)=="number" or a==nil then self.point,self.rel,self.x,self.y=point,point,a or 0,b or 0 elseif type(b)=="string" then self.point,self.rel,self.x,self.y=point,b,c or 0,d or 0 end end
    function w:GetScript(event) return self.scripts[event] end
    function w:GetCenter() return 500,400 end
    function w:GetEffectiveScale() return 1 end
    function w:SetTexture(t) self.texture=t end
    function w:SetTextColor(r,g,b) self.color={r,g,b} end
    function w:SetEnabled(v) self.enabled=v end
    function w:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
    function w:SetText(text) self.text=text end
    function w:GetText() return self.text end
    function w:SetScript(event,fn) self.scripts[event]=fn end
    function w:HookScript(event,fn) self.scripts[event]=fn end
    function w:Show() self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function w:Hide() self.shown=false end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown end
    function w:SetChecked(value) self.checked=value end
    function w:GetChecked() return self.checked end
    function w:SetSize(a,b) self.w,self.h=a,b end
    function w:GetWidth() return rawget(self,"w") or 560 end
    function w:GetHeight() return rawget(self,"h") or 400 end
    function w:CreateFontString() return widget() end
    function w:CreateTexture() return widget() end
    function w:RegisterEvent(ev) self.events=self.events or {}; self.events[ev]=true end
    return w
end
local altered=false
local C
CreateFrame=function(kind,name)
    local w=widget(); frames[#frames+1]=w
    if name then _G[name]=w end
    function w:SetItemByID(id)
        local crate=C.Catalog.entries[id]
        local parts={"Use: Fill the crate with any bundle from the following list:"}
        for _,b in ipairs(crate.bundles) do parts[#parts+1]="- "..(b.quantity+(altered and 1 or 0)).." "..b.name end
        _G.AzerothFamiliarCrateTooltipTextLeft1={GetText=function() return table.concat(parts,"\n") end}
    end
    function w:NumLines() return 1 end
    return w
end
UIParent=widget(); UISpecialFrames={}; GameTooltip=widget(); SlashCmdList={}; ChatFontNormal={}
C_Item={}
-- Familiar namespace, loaded as the client would (TOC order for the files involved)
local AA={}
local function loadFam(path,ns) assert(loadfile(path))("AzerothAssistant",ns or AA) end
loadFam("Core.lua"); loadFam("UI/Widgets.lua"); loadFam("UI/Shell.lua")
local CRATE_FILES={"Crates/Core.lua","Crates/Catalog.lua","Crates/Cost.lua","Crates/Bags.lua","Crates/Providers.lua","Crates/Scan.lua","Crates/Model.lua","Crates/Tooltip.lua"}
for _,f in ipairs(CRATE_FILES) do loadFam(f) end
loadFam("Modules/Crates.lua")
local eventFrame=frames[1] -- Core.lua's event frame
local function fire(event,...) eventFrame.scripts.OnEvent(eventFrame,event,...) end
fire("ADDON_LOADED","AzerothAssistant")
C=AA.Crates
eq(type(C),"table","AA.Crates namespace")
local cost=C.Cost
local function stack(id,n,p) return {auctionID=id,quantity=n,buyout=p} end

test("20 at 40s loses to two 5 at 11s",function()
    local p=cost.Plan(10,{stack(1,20,4000),stack(2,5,1100),stack(3,5,1100)},false)
    eq(p.cost,2200); eq(#p.buys,2); eq(p.leftover,0)
end)
test("larger stack really cheaper",function()
    local p=cost.Plan(10,{stack(1,20,1800),stack(2,5,1100),stack(3,5,1100)},false)
    eq(p.cost,1800); eq(p.leftover,10); eq(#p.buys,1)
end)
test("deduplicate listings and ignore bid-only",function()
    eq(cost.Plan(10,{stack(1,5,10),stack(1,5,10),stack(2,5,0)},false),nil)
end)
test("partial tiers, ownership and insufficient supply",function()
    local rows={{auctionID=1,quantity=8,unitPrice=7},{auctionID=2,quantity=20,unitPrice=9}}
    local p=cost.Plan(10,rows,true); eq(p.cost,74); eq(p.buys[2].quantity,2); eq(p.leftover,0)
    eq(cost.Plan(29,rows,true),nil)
    rows[1].own=true; eq(cost.Plan(21,rows,true),nil)
end)
test("knapsack agrees with exhaustive subsets",function()
    math.randomseed(77)
    for case=1,200 do
        local rows={}; local n=math.random(1,20)
        for i=1,8 do rows[i]=stack(i,math.random(1,20),math.random(1,500)) end
        local minimum=math.huge
        for mask=0,255 do
            local q,p=0,0
            for i=1,8 do if math.floor(mask/2^(i-1))%2==1 then q=q+rows[i].quantity; p=p+rows[i].buyout end end
            if q>=n then minimum=math.min(minimum,p) end
        end
        local p=cost.Plan(n,rows,false)
        eq(p and p.cost or math.huge,minimum)
        if p then local ids,sum={},0; for _,b in ipairs(p.buys) do assert(not ids[b.auctionID]); ids[b.auctionID]=true; sum=sum+b.cost end; eq(sum,p.cost) end
    end
end)
local herbs=C.Catalog.entries[248686]
test("catalog 30 recipes / 96 materials and five herb alternatives",function()
    local count,mats=0,{}
    for id,r in pairs(C.Catalog.entries) do
        eq(id,r.id); assert(r.level); count=count+1
        for _,b in ipairs(r.bundles) do assert(b.itemID and b.quantity>0); mats[b.itemID]=true end
    end
    eq(count,30); local n=0; for _ in pairs(mats) do n=n+1 end; eq(n,96)
    eq(#herbs.bundles,5)
    for _,b in ipairs(herbs.bundles) do eq(b.quantity,10) end
end)
test("each herb separately can fill; mixed herbs cannot",function()
    for _,b in ipairs(herbs.bundles) do
        local best=cost.Compare(herbs,{[b.itemID]=10},function() return {status="No price"} end)
        eq(best.cost,0); eq(best.bundle.itemID,b.itemID)
    end
    local mixed={}; for _,b in ipairs(herbs.bundles) do mixed[b.itemID]=2 end
    local best=cost.Compare(herbs,mixed,function(_,n) return {cost=n*10,status="Estimate"} end)
    eq(best.missing,8); eq(best.cost,80)
end)
test("unequal bundle amounts and partial bag ownership",function()
    local crate=C.Catalog.entries[248702]
    eq(crate.bundles[1].quantity,2); eq(crate.bundles[2].quantity,20)
    local best=cost.Compare(crate,{[4231]=1},function(id,n) return {cost=(id==4231 and 100 or 10)*n} end)
    eq(best.bundle.itemID,4231); eq(best.missing,1); eq(best.cost,100)
end)
test("provider absent, late loaded, stale, missing age, errors",function()
    eq(C.Providers:Quote(3820,10).cost,nil)
    Auctionator={API={v1={GetAuctionPriceByItemID=function(caller,id) eq(caller,"Azeroth Familiar"); return 42 end,
        GetAuctionAgeByItemID=function() return 3 end}}}
    local p=C.Providers:Quote(3820,10); eq(p.cost,420); eq(p.kind,"estimate"); eq(p.stale,true); assert(p.status:find("3d",1,true))
    Auctionator.API.v1.GetAuctionAgeByItemID=function() return nil end
    eq(C.Providers:Quote(3820,10).stale,true)
    Auctionator.API.v1.GetAuctionPriceByItemID=function() error("not ready") end
    eq(C.Providers:Quote(3820,10).cost,nil); Auctionator=nil
end)
test("live no supply never falls back to estimate; expired/incomplete explicit",function()
    C.Scan.open=true
    C.live[3820]={complete=true,time=now,rows={stack(1,5,100)}}
    eq(C.Providers:Quote(3820,10).cost,nil)
    C.live[3820].rows={stack(1,20,100)}
    eq(C.Providers:Quote(3820,10).cost,100)
    now=now+121; eq(C.Providers:Quote(3820,10).cost,nil)
    C.live[3820].complete=false; assert(C.Providers:Quote(3820,10).status:find("Incomplete",1,true))
    C.live={}
end)
test("buy-and-fill pays for full crate stack and flags level",function()
    C.verified[248686]=true; C.mode="Buy & Fill"; C.Scan.open=true
    C.live[248686]={complete=true,time=now,rows={stack(12,5,900)}}
    C.live[3820]={complete=true,time=now,rows={stack(13,10,2200)}}
    local found
    for _,r in ipairs(C.Model:Rows()) do if r.id==248686 then found=r end end
    eq(found.cost,3100); eq(found.cratePrice.plan.leftover,4); eq(found.fillCost,2200)
    assert(found.status:find("Cheapest of priced bundles",1,true)); eq(found.locked,false)
    C.live={}; C.mode="My Crates"
end)
test("bag reader sums carried slots, reports unknown crates",function()
    C_Item={GetItemNameByID=function(id) return id==999 and "Waylaid Crate: Unknown" or nil end}
    C_Container={GetContainerNumSlots=function(bag) return bag==0 and 3 or 0 end,
        GetContainerItemInfo=function(bag,slot) return ({ {itemID=3820,stackCount=2},{itemID=3820,stackCount=3},{itemID=999,stackCount=1} })[slot] end}
    C.Inventory:Read(); eq(C.owned[3820],5); assert(C.unsupported[999]); C.owned={}
end)
-- Deterministic timer/event harness. No purchases are mocked or implemented.
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn} end}
local function tick()
    table.sort(timers,function(a,b) return a.at<b.at end)
    local t=table.remove(timers,1); if t then now=t.at; t.fn() end
end
local requests,full,ready=0,false,true
local fixtures={stack(101,5,1100),stack(102,5,1100)}
C_AuctionHouse={MakeItemKey=function(id) return {itemID=id,itemLevel=0,itemSuffix=0} end,
    GetItemKeyInfo=function() return {isCommodity=false} end,
    HasSearchResults=function() return true end,
    IsThrottledMessageSystemReady=function() return ready end,
    SendSearchQuery=function() requests=requests+1 end,
    GetNumItemSearchResults=function() return #fixtures end,
    GetItemSearchResultInfo=function(key,i) local r=fixtures[i]; return {itemKey=key,auctionID=r.auctionID,quantity=r.quantity,buyoutAmount=r.buyout} end,
    HasFullItemSearchResults=function() return full end,
    RequestMoreItemSearchResults=function() requests=requests+1 end,
    GetNumCommoditySearchResults=function() return 1 end,
    GetCommoditySearchResultInfo=function(id) return {itemID=id,quantity=10,unitPrice=22,numOwnerItems=0} end,
    HasFullCommoditySearchResults=function() return full end,
    RequestMoreCommoditySearchResults=function() requests=requests+1 end}
test("scan dedup, throttle, pagination, matching ID, full snapshot",function()
    timers={}; C.Scan.open=true; C.Scan:Start({3820,3820}); eq(#C.Scan.pending.ids,1)
    ready=false; tick(); eq(requests,0); ready=true; tick(); eq(requests,1)
    C.Scan:Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=123}); assert(C.Scan.pending)
    C.Scan:Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=3820}); eq(C.Scan.pending.phase,"more")
    tick(); eq(requests,2); full=true
    C.Scan:Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=3820}); eq(C.Scan.pending,nil)
    eq(#C.live[3820].rows,2); eq(C.Providers:Quote(3820,10).cost,2200)
end)
test("cancel and late events leave scan restartable",function()
    timers={}; C.Scan:Start({3820,2453}); tick(); C.Scan:Cancel()
    C.Scan:Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=3820}); tick(); eq(C.Scan.pending,nil)
    eq(C.live[3820].complete,false); C.Scan:Start({3820}); assert(C.Scan.pending); C.Scan:Cancel()
end)
test("AH close invalidates live plans and can reopen",function()
    timers={}; C.Scan.open=true; C.Scan:Start({3820}); tick()
    C.Scan:Event("AUCTION_HOUSE_CLOSED"); eq(C.Scan.open,false); eq(C.Scan.pending,nil)
    C.Scan:Start({3820}); eq(C.Scan.pending,nil)
    C.Scan:Event("AUCTION_HOUSE_SHOW"); C.Scan:Start({3820}); tick(); tick()
    C.Scan:Event("COMMODITY_SEARCH_RESULTS_UPDATED",3820)
    eq(C.Scan.pending,nil); eq(C.Providers:Quote(3820,10).cost,220); eq(C.live[3820].partial,true)
end)
test("timeout and wrong build fail closed",function()
    timers={}; C.Scan:Start({3820}); tick(); now=now+40; C.Scan:Tick(); eq(C.Scan.pending,nil)
    local old=GetBuildInfo; GetBuildInfo=function() return "1.60.2","99999","",16002 end
    C.Scan:Start({3820}); eq(C.Scan.pending,nil); GetBuildInfo=old
end)
test("reload has no stale live plans or pending requests",function()
    local fresh={}; for _,f in ipairs(CRATE_FILES) do loadFam(f,fresh) end
    local F=fresh.Crates; eq(next(F.live),nil); eq(F.Scan.pending,nil); eq(F.Scan.open,false)
end)
local names={}; for _,r in pairs(C.Catalog.entries) do names[r.id]=r.name; for _,b in ipairs(r.bundles) do names[b.itemID]=b.name end end
C_Item.GetItemInfo=function(id) return names[id],nil,nil,nil,C.Catalog.entries[id] and C.Catalog.entries[id].level end
test("current tooltip validation accepts all fixtures and rejects changed quantities",function()
    C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),30)
    altered=true; C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),0)
    altered=false; C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),30)
end)
test("non-English tooltips fail closed",function()
    GetLocale=function() return "esES" end; C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),0)
    GetLocale=function() return "enUS" end; C.Inventory:ValidateCatalog()
end)
test("missing item cache is unsupported and requests data",function()
    local old=C_Item.GetItemInfo; local requests=0
    C_Item.GetItemInfo=function() return nil end
    C_Item.RequestLoadItemDataByID=function() requests=requests+1 end
    C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),0); eq(requests,30)
    C_Item.GetItemInfo=old; C.Inventory:ValidateCatalog()
end)
-- ---------------------------------------------------------------------------
-- 0.2.0 regression checks: shared recommendation, tooltip highlight, window,
-- minimap. All fixtures; no live client.
-- ---------------------------------------------------------------------------
local CUR=248685 -- Apprentice Curiosities: 20 Strange Dust / 4 GME / 6 SGS / 2 LGS
local DUST,GME,SGS,LGS=10940,10939,10978,11084
local GREEN,AMBER=C.Tooltip.HIGHLIGHT.confirmed,C.Tooltip.HIGHLIGHT.estimate
local function units(price,n) return {complete=true,time=now,partial=true,rows={{auctionID="tier:1",quantity=n or 200,unitPrice=price}}} end
local function scan(prices) C.live={}; for id,snap in pairs(prices) do C.live[id]=snap end end
local function rec(owned) return C.Model:Recommend(C.Catalog.entries[CUR],owned or {}) end
local function strip(s) return (s:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end
local function count(s,needle) local n,i=0,1; while true do local a,b=s:find(needle,i,true); if not a then return n end; n=n+1; i=b+1 end end
local function standardScan()
    -- GME 4 x 3s28c = 13s 12c. Dust is cheaper per unit (40c) but sold only as a
    -- 40-stack (16s): total cost, not unit price, decides.
    scan({[GME]=units(328),[DUST]={complete=true,time=now,rows={stack(501,40,1600)}},[SGS]=units(300),[LGS]=units(900)})
end
test("1 cheapest bundle changes after a new scan (total incl. whole stacks)",function()
    C.verified[CUR]=true; C.Scan.open=true; C.Scan.pending=nil; standardScan()
    local r=rec(); eq(r.state,"live"); eq(r.best.bundle.itemID,GME); eq(r.best.cost,1312); eq(r.tie,false); eq(r.partial,false)
    C.live[DUST]={complete=true,time=now,rows={stack(502,20,1000)}}
    r=rec(); eq(r.best.bundle.itemID,DUST); eq(r.best.cost,1000)
end)
test("2 owned materials change the winning bundle",function()
    standardScan()
    local r=rec({[SGS]=5}); eq(r.best.bundle.itemID,SGS); eq(r.best.missing,1); eq(r.best.cost,300); eq(r.state,"live")
end)
test("3 fully owned valid bundle is Ready to fill at 0c",function()
    C.live={}
    local r=rec({[LGS]=2}); eq(r.state,"ready"); eq(r.best.cost,0); eq(r.best.bundle.itemID,LGS)
    C.owned={[LGS]=2}
    local c=C.Tooltip:Content(C.Catalog.entries[CUR])
    eq(strip(c.lines[3]),"Ready to fill · 0c"); eq(c.color,GREEN); eq(c.targets[1].itemID,LGS)
    C.owned={}
end)
test("4 mixed materials never fill a crate",function()
    C.live={}
    local r=rec({[DUST]=19,[GME]=3,[SGS]=5,[LGS]=1})
    assert(r.state~="ready")
    for _,a in ipairs(r.alternatives) do assert(a.missing>0) end
    C.owned={[DUST]=19,[GME]=3,[SGS]=5,[LGS]=1}
    local c=C.Tooltip:Content(C.Catalog.entries[CUR]); eq(c.targets[1],nil); C.owned={}
end)
test("5 tied alternatives are all highlighted and labelled",function()
    scan({[GME]=units(450),[DUST]=units(90),[SGS]=units(300),[LGS]=units(900)}) -- all 1800
    local r=rec(); eq(r.tie,true); eq(#r.winnerList,4)
    scan({[GME]=units(500),[DUST]=units(90),[SGS]=units(300),[LGS]=units(1000)}) -- dust 1800, SGS 1800
    r=rec(); eq(r.tie,true); eq(#r.winnerList,2); assert(r.winners[DUST] and r.winners[SGS])
    local c=C.Tooltip:Content(C.Catalog.entries[CUR])
    assert(strip(c.lines[2]):find("Tied best: 2 tied bundles",1,true),c.lines[2]); eq(#c.targets,2)
    assert(strip(c.lines[4]):find("Tie",1,true))
end)
test("6 missing prices and incomplete scans: cheapest of priced only",function()
    scan({[GME]=units(328),[SGS]=units(300)})
    local r=rec(); eq(r.priced,2); eq(r.partial,true); eq(r.best.bundle.itemID,GME)
    local c=C.Tooltip:Content(C.Catalog.entries[CUR]); assert(strip(c.lines[4]):find("Cheapest of priced bundles",1,true))
    C.live[GME]={complete=false,rows={},time=now,reason="Cancelled"}
    r=rec(); eq(r.best.bundle.itemID,SGS); eq(r.winners[GME],nil) -- incomplete never wins
    scan({[GME]={complete=false,rows={},time=now,reason="Queued"}})
    r=rec(); eq(r.state,"unpriced"); c=C.Tooltip:Content(C.Catalog.entries[CUR]); eq(c.color,nil); eq(#c.targets,0)
end)
test("7 stale snapshots lose green; cached-only estimates are a distinct state",function()
    standardScan(); now=now+121
    local r=rec(); eq(r.state,"unpriced") -- expired live data is not replaced by estimates
    C.live={}
    Auctionator={API={v1={GetAuctionPriceByItemID=function(_,id) return ({[GME]=300,[DUST]=100,[SGS]=400,[LGS]=900})[id] end,
        GetAuctionAgeByItemID=function() return 2 end}}}
    r=rec(); eq(r.state,"estimate"); eq(r.best.bundle.itemID,GME)
    local c=C.Tooltip:Content(C.Catalog.entries[CUR]); eq(c.color,AMBER); assert(c.color~=GREEN)
    assert(strip(c.lines[2]):find("^Estimate: 4 Greater Magic Essence")); assert(strip(c.lines[4]):find("stale",1,true))
    -- a live winner beats estimates but is labelled as compared against them
    C.Scan.open=true; C.live[SGS]=units(100) -- 600 live
    r=rec(); eq(r.state,"live"); eq(r.best.bundle.itemID,SGS); eq(r.mixed,true)
    -- AH closes: live result invalidated at once
    C.Scan:Event("AUCTION_HOUSE_CLOSED"); r=rec(); assert(r.state~="live"); eq(r.winners[SGS],nil)
    Auctionator=nil; C.live={}; C.Scan:Event("AUCTION_HOUSE_SHOW")
end)
-- Fake GameTooltip mimicking FontString reuse: ClearLines keeps old FontStrings
-- and their text (as the client does) until the next AddLine reuses them.
local function fakeTip(name)
    local tip={lines=0,scripts={},shown=true,name=name,showCalls=0}
    function tip:GetName() return self.name end
    function tip:NumLines() return self.lines end
    function tip:HookScript(ev,fn) self.scripts[ev]=self.scripts[ev] or {}; table.insert(self.scripts[ev],fn) end
    function tip:Fire(ev) for _,fn in ipairs(self.scripts[ev] or {}) do fn(self) end end
    function tip:AddLine(text)
        self.lines=self.lines+1
        local key=self.name.."TextLeft"..self.lines
        local fs=_G[key] or {SetText=function(f,t) f.text=t; f.writes=(f.writes or 0)+1 end,GetText=function(f) return f.text end}
        _G[key]=fs; fs.text=text
    end
    function tip:ClearLines() self.lines=0; self.link=nil; self:Fire("OnTooltipCleared") end
    function tip:GetItem() if self.link then return "x",self.link end end
    function tip:IsShown() return self.shown end
    function tip:Show() self.shown=true; self.showCalls=self.showCalls+1 end
    function tip:Hide() self.shown=false; self:Fire("OnHide") end
    function tip:Line(i) return _G[self.name.."TextLeft"..i].text end
    function tip:Fill(id,lines) self:ClearLines(); self.link="|cffffffff|Hitem:"..id.."::::::::10:::::|h[x]|h|r"; for _,l in ipairs(lines) do self:AddLine(l) end; self:Fire("OnTooltipSetItem") end
    return tip
end
local USE="Use: Fill the crate with any bundle from the following list:"
local SHARED={"Waylaid Crate: Apprentice Curiosities","Requires Level 10",USE.."\n- 20 Strange Dust\n- 4 Greater Magic Essence\n- 6 Small Glimmering Shard\n- 2 Large Glimmering Shard","Sell Price: 1c"}
local SPLIT={"Waylaid Crate: Apprentice Curiosities",USE,"- 20 Strange Dust","- 4 Greater Magic Essence","- 6 Small Glimmering Shard","- 2 Large Glimmering Shard","Auctionator: 4 Greater Magic Essence"}
local tip=fakeTip("CSFakeTooltip")
local function install()
    C.Tooltip.installed=false; C.Tooltip.tips={}; C.Tooltip.state={}
    local oldGT,oldRef=GameTooltip,ItemRefTooltip
    GameTooltip,ItemRefTooltip=tip,nil; TooltipDataProcessor=nil
    tip.scripts={}
    C.Tooltip:Install(); GameTooltip,ItemRefTooltip=oldGT,oldRef
end
test("9 alternatives sharing one FontString: only the winning substring is colored",function()
    install(); C.Scan.open=true; standardScan()
    tip:Fill(CUR,SHARED)
    local list=tip:Line(3)
    assert(list:find(GREEN.."- 4 Greater Magic Essence|r",1,true),list)
    eq(count(list,"|c"),1); eq(strip(list),SHARED[3]) -- newlines, quantities, other bundles intact
    eq(tip:Line(1),SHARED[1]); eq(tip:Line(2),SHARED[2]); eq(tip:Line(4),SHARED[4])
    eq(tip:NumLines(),#SHARED+4); eq(strip(tip:Line(6)),"Best bundle: 4 Greater Magic Essence")
    eq(strip(tip:Line(7)),"Buy 4 · 13s 12c"); eq(strip(tip:Line(8)),"AH snapshot · 0s ago")
    -- decoys: a larger quantity and a longer name with the same prefix never match
    local out,n=C.Tooltip.Colorize(USE.."\n- 14 Greater Magic Essence\n- 4 Greater Magic Essence Pouch\n- 4 Greater Magic Essence",1,{{quantity=4,name="Greater Magic Essence"}},GREEN)
    eq(n,1); local want="\n"..GREEN.."- 4 Greater Magic Essence|r"; eq(out:sub(-#want),want); assert(out:find("\n- 14 Greater",1,true))
    -- text before the accepted-bundle header is never searched
    out,n=C.Tooltip.Colorize("- 4 Greater Magic Essence\n"..USE,#"- 4 Greater Magic Essence\n"+1,{{quantity=4,name="Greater Magic Essence"}},GREEN); eq(n,0)
    -- an outer color code is re-applied after the highlight
    out=C.Tooltip.Colorize("|cffffffff"..USE.."\n- 4 Greater Magic Essence\n- 6 Small Glimmering Shard|r",1,{{quantity=4,name="Greater Magic Essence"}},GREEN)
    assert(out:find(GREEN.."- 4 Greater Magic Essence|r|cffffffff\n- 6",1,true),out)
    -- one line per bundle: section-scoped, other addons' lines untouched
    tip:Fill(CUR,SPLIT)
    eq(tip:Line(4),GREEN.."- 4 Greater Magic Essence|r"); eq(tip:Line(3),"- 20 Strange Dust"); eq(tip:Line(7),SPLIT[7])
end)
test("8 switching item tooltips leaves no stale colors or duplicate lines",function()
    install(); C.Scan.open=true; standardScan()
    tip:Fill(CUR,SHARED); assert(tip:Line(3):find(GREEN,1,true))
    tip:Fire("OnTooltipSetItem"); eq(tip:NumLines(),#SHARED+4) -- repeated post-call: no duplicates
    tip:Fill(2589,{"Linen Cloth","Sell Price: 1c"}); eq(tip:NumLines(),2); eq(tip:Line(1),"Linen Cloth"); eq(next(C.Tooltip.state),nil)
    local herbs={"Waylaid Crate: Journeyman Herbs",USE.."\n- 10 Stranglekelp\n- 10 Bruiseweed\n- 10 Wild Steelbloom\n- 10 Grave Moss\n- 10 Kingsblood"}
    C.verified[248686]=true; C.live[2453]=units(50)
    tip:Fill(248686,herbs); eq(tip:NumLines(),6)
    assert(tip:Line(2):find(GREEN.."- 10 Bruiseweed|r",1,true)); eq(count(tip:Line(2),"|c"),1)
    tip:Fill(CUR,SHARED); eq(tip:NumLines(),#SHARED+4); eq(count(tip:Line(3),"|c"),1)
    tip:Hide(); eq(tip:Line(3),SHARED[3]); tip.shown=true -- hidden, not cleared: client text restored
end)
test("tooltip updates in place on scan, inventory, freshness and AH close",function()
    install(); C.Scan.open=true; standardScan(); C.owned={}
    tip:Fill(CUR,SHARED); local writes=_G.CSFakeTooltipTextLeft6.writes or 0
    C.Changed(); eq(_G.CSFakeTooltipTextLeft6.writes or 0,writes) -- unchanged: no rewrite, no flicker
    C.live[DUST]={complete=true,time=now,rows={stack(502,20,1000)}}; C.Changed()
    assert(tip:Line(3):find(GREEN.."- 20 Strange Dust|r",1,true)); assert(not tip:Line(3):find(GREEN.."- 4 Greater",1,true))
    eq(strip(tip:Line(6)),"Best bundle: 20 Strange Dust"); eq(tip:NumLines(),#SHARED+4)
    C.owned={[LGS]=2}; C.Changed(); eq(strip(tip:Line(7)),"Ready to fill · 0c"); assert(tip:Line(3):find(GREEN.."- 2 Large Glimmering Shard|r",1,true))
    C.owned={}; now=now+5; C.Tooltip:Refresh(); assert(strip(tip:Line(8)):find("5s ago",1,true))
    now=now+200; C.Tooltip:Refresh(); eq(count(tip:Line(3),"|c"),0) -- expired: green removed
    standardScan(); C.Changed(); assert(tip:Line(3):find(GREEN,1,true))
    C.Scan:Event("AUCTION_HOUSE_CLOSED"); eq(count(tip:Line(3),"|c"),0); eq(strip(tip:Line(6)),"Best bundle: not priced yet")
    C.Scan:Event("AUCTION_HOUSE_SHOW")
end)
test("unknown and unverified crates stay unsupported in the tooltip",function()
    install(); standardScan()
    C.verified[CUR]=false; tip:Fill(CUR,SHARED)
    eq(count(tip:Line(3),"|c"),0); assert(strip(tip:Line(6)):find("Unsupported",1,true))
    tip:Fill(999,{"Waylaid Crate: Unknown",USE.."\n- 4 Greater Magic Essence"}); eq(tip:NumLines(),2); eq(count(tip:Line(2),"|c"),0)
    C.verified[CUR]=true
end)
test("verification tooltips are never altered by the highlight hook",function()
    install(); standardScan()
    C.Tooltip:Apply(AzerothFamiliarCrateTooltip) -- not a hooked tooltip: ignored
    C.Inventory:ValidateCatalog(); eq(C.Inventory:Coverage(),30)
end)
-- ---------------------------------------------------------------------------
-- Integration with Azeroth Familiar: page, events, slash, settings, diagnostics.
-- ---------------------------------------------------------------------------
local P=C.UI
local host=widget()
local function openPage()
    if not P.frame then AA.Shell.defs.crates.makeFrame(host) end
    P.frame:Show(); P:Refresh()
end
local function find(fn) for i=1,P.index do local w=P.widgets[i]; if fn(w) then return w end end end
test("Crates page is registered and builds inside the Familiar shell",function()
    local def=AA.Shell.defs.crates
    assert(def and def.makeFrame and def.refresh); eq(def.title,"Crates"); eq(def.interval,5)
    assert(type(def.icon)=="function" and def.icon())
    openPage(); assert(P.searchBox and P.scanButton and P.cancelButton and P.verifyButton)
end)
test("page: three views, best badge, expanded plans, Buy & Fill breakdown, empty state",function()
    install(); C.Scan.open=true; standardScan(); C.owned={[CUR]=1}; C.unsupported={}; C.mode="My Crates"; P.expanded={[CUR]=true}
    openPage()
    local parent=find(function(w) return w.crate.text and w.crate.text:find("Apprentice Curiosities",1,true) end)
    assert(parent); eq(parent.badge.text,"BEST"); assert(parent.fields.bundle.text:find("4 Greater Magic Essence",1,true))
    eq(strip(parent.fields.cost.text),"13s 12c")
    assert(find(function(w) return w.badge.text=="BEST" and w~=parent end))
    assert(find(function(w) return w.crate.text and w.crate.text:find("own 0/20",1,true) end))
    assert(find(function(w) return w.fields.bundle.text and w.fields.bundle.text:find("Buy stack of 40",1,true) end))
    C.mode="All Crates"; P:Refresh(); assert(P.index>=30) -- every recipe stays visible
    C.mode="Buy & Fill"; C.live[CUR]={complete=true,time=now,rows={stack(77,3,900)}}; P:Refresh()
    assert(find(function(w) return w.crate.text and w.crate.text:find("Empty crate",1,true) end))
    assert(find(function(w) return w.crate.text and w.crate.text:find("Materials",1,true) end))
    local e=find(function(w) return w.fields.bundle.text and w.fields.bundle.text:find("Extra crates",1,true) end); eq(e.fields.need.text,"2")
    local t=find(function(w) return w.crate.text and w.crate.text:find("Total cash for this crate",1,true) end); eq(strip(t.fields.cost.text),"22s 12c")
    C.mode="My Crates"; C.owned={}; P:Refresh(); assert(P.empty.text:find("No Waylaid Crates",1,true))
    C.live={}
end)
test("page: scan controls, AH closed explanation, cancel, no automatic scans",function()
    openPage(); eq(C.Scan.pending,nil) -- opening the page never scans
    fire("AUCTION_HOUSE_CLOSED"); eq(C.Scan.open,false); eq(P.scanButton.enabled,false); assert(P.ahNote.text:find("closed",1,true))
    eq(C.Scan.pending,nil)
    fire("AUCTION_HOUSE_SHOW"); eq(C.Scan.open,true); eq(P.scanButton.enabled,true); eq(C.Scan.pending,nil)
    C.owned={[CUR]=1}; P.scanButton:Click(); assert(C.Scan.pending); eq(P.cancelButton.enabled,true); assert(P.progress.shown)
    P.cancelButton:Click(); eq(C.Scan.pending,nil); eq(P.cancelButton.enabled,false); C.owned={}
end)
test("events: Familiar dispatches AH results and bag refreshes to the crate engine",function()
    timers={}; C.Scan.open=true; C.Scan:Start({3820}); tick(); tick()
    fire("COMMODITY_SEARCH_RESULTS_UPDATED",3820); eq(C.Scan.pending,nil); eq(C.live[3820].complete,true)
    local reads=0; local old=C.Inventory.Read; C.Inventory.Read=function(self) reads=reads+1; return old(self) end
    fire("BAG_UPDATE_DELAYED"); fire("BAG_UPDATE_DELAYED"); tick(); eq(reads,1) -- coalesced
    C.Inventory.Read=old; C.live={}
end)
test("slash: /fam crates and subcommands, /cratescout alias",function()
    local shown; AA.UI={ShowPage=function(id) shown=id end}
    SlashCmdList.AZEROTHASSISTANT("crates"); eq(shown,"crates")
    shown=nil; SlashCmdList.AZEROTHASSISTANT("crate"); eq(shown,"crates")
    C.Scan:Start({3820}); SlashCmdList.AZEROTHASSISTANT("crates cancel"); eq(C.Scan.pending,nil)
    local printed; local oldPrint=AA.Print; AA.Print=function(_,m) printed=m end
    SlashCmdList.AZEROTHASSISTANT("crates verify"); assert(printed and printed:find("30/30",1,true)); AA.Print=oldPrint
    shown=nil; SlashCmdList.AZEROTHASSISTANTCRATES(""); eq(shown,"crates")
    SlashCmdList.AZEROTHASSISTANTCRATES("inspect 123456"); assert(C.unsupported[123456])
    C.unsupported={}
end)
test("settings: defaults merged, countOwned and tooltip switch persist",function()
    eq(AzerothAssistantDB.settings.crates.countOwned,false); eq(AzerothAssistantDB.settings.crates.tooltip,true)
    C.mode="All Crates"; openPage(); P.own:SetChecked(true); P.own.scripts.OnClick(P.own)
    eq(AzerothAssistantDB.settings.crates.countOwned,true); eq(C.countOwned,true)
    -- existing settings survive a merge
    AzerothAssistantDB.settings.crates={countOwned=true}; AA:InitDB(); eq(AA.db.settings.crates.countOwned,true); eq(AA.db.settings.crates.tooltip,true)
    -- tooltip switch off: no lines, no colors, existing highlight restored
    install(); C.Scan.open=true; standardScan(); C.owned={}
    tip:Fill(CUR,SHARED); assert(tip:Line(3):find(GREEN,1,true))
    C.Tooltip:SetEnabled(false); eq(AA.db.settings.crates.tooltip,false); eq(tip:Line(3),SHARED[3])
    tip:Fill(CUR,SHARED); eq(tip:NumLines(),#SHARED)
    C.Tooltip:SetEnabled(true); tip:Fill(CUR,SHARED); eq(tip:NumLines(),#SHARED+4)
    C.countOwned=false; AA.db.settings.crates.countOwned=false; C.mode="My Crates"; C.live={}
end)
test("diagnostics report crate coverage and scan readiness",function()
    AA.client=nil
    local ok,err=pcall(AA.RunDiagnostics,AA,false)
    assert(ok,tostring(err)); assert(AA.db.diag and AA.db.diag.crates,"diag.crates missing")
    eq(AA.db.diag.crates.recipes,30); eq(AA.db.diag.crates.verified,30); eq(AA.db.diag.crates.tooltipHook,true)
end)
test("one tooltip summary header names Azeroth Familiar",function()
    standardScan(); C.Scan.open=true
    local c=C.Tooltip:Content(C.Catalog.entries[CUR]); eq(strip(c.lines[1]),"Azeroth Familiar · Crates")
    C.live={}
end)

test("page layout: columns never overlap or overflow, at small, default and large widths",function()
    for _,width in ipairs({480,566,700,1000}) do
        local c=C.UI.Columns(width); local prev=0
        for _,k in ipairs({"crate","level","bundle","need","cost","status"}) do
            assert(c[k].x>=prev,"overlap at "..k.." width "..width); assert(c[k].w>0); prev=c[k].x+c[k].w+1
        end
        assert(c.status.x+c.status.w<=width,"overflow at width "..width)
        assert(c.bundle.w>=100 and c.crate.w>=70)
    end
    local small,big=C.UI.Columns(566),C.UI.Columns(1000)
    assert(big.bundle.w>small.bundle.w and big.crate.w>small.crate.w) -- extra width goes to the names
    eq(big.status.w,small.status.w) -- numbers keep their columns
end)
test("window moving: default unlocked, /fam center recenters",function()
    eq(AA.db.settings.lockWindow,false)
    local centered=0; AA.UI={ShowPage=function() end,CenterWindow=function() centered=centered+1 end}
    SlashCmdList.AZEROTHASSISTANT("center"); eq(centered,1)
    SlashCmdList.AZEROTHASSISTANT("centre"); eq(centered,2)
end)
print("Passed "..passed.." Crates test groups (includes 200 exhaustive optimizer comparisons)")

-- Azeroth Familiar - Crates/Providers.lua (ported from Crate Scout 0.2.0)
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.Providers={adapters={},staleDays=1,liveSeconds=120}
local P=C.Providers
function P:Register(adapter) self.adapters[#self.adapters+1]=adapter end
P:Register({name="Auctionator", Get=function(_,id)
    local api=Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or type(api.GetAuctionPriceByItemID)~="function" then return end
    local ok,price=pcall(api.GetAuctionPriceByItemID,"Azeroth Familiar",id)
    if not ok or type(price)~="number" or price<=0 then return end
    local age
    if type(api.GetAuctionAgeByItemID)=="function" then
        local success,value=pcall(api.GetAuctionAgeByItemID,"Azeroth Familiar",id)
        if success and type(value)=="number" and value>=0 then age=value end
    end
    return {unit=math.floor(price),days=age}
end})
function P:Quote(id,quantity)
    local snapshot=C.live[id]
    if snapshot then
        local age=math.max(0,C.Now()-snapshot.time)
        if not snapshot.complete then return {kind="unavailable",status="Incomplete scan: "..(snapshot.reason or "pending")} end
        if age>self.liveSeconds or not C.Scan.open then
            return {kind="unavailable",status="Expired AH snapshot ("..age.."s); rescan"}
        end
        local plan,reason=C.Cost.Plan(quantity,snapshot.rows,snapshot.partial)
        if not plan then return {kind="unavailable",status=reason.." · AH "..age.."s"} end
        return {cost=plan.cost,kind="live",plan=plan,status="AH snapshot · "..age.."s",age=age}
    end
    for _,adapter in ipairs(self.adapters) do
        local ok,p=pcall(adapter.Get,adapter,id)
        if ok and p then
            local age=p.days and (p.days.."d") or "age unknown"
            local stale=p.days==nil or p.days>=self.staleDays
            return {cost=p.unit*quantity,kind="estimate",status="Estimate · "..adapter.name.." · "..age..(stale and " · stale" or ""),stale=stale}
        end
    end
    return {kind="unavailable",status="No price (Auctionator optional)"}
end

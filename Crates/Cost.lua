-- Azeroth Familiar - Crates/Cost.lua (ported from Crate Scout 0.2.0)
-- Pure Lua 5.1. All monetary input/output is integer copper.
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
local Cost = {}
C.Cost = Cost
local function integer(v) return type(v)=="number" and v>=0 and v==math.floor(v) and v<9007199254740991 end
function Cost.Plan(needed, listings, partial)
    assert(integer(needed), "invalid quantity")
    if needed==0 then return {cost=0,quantity=0,leftover=0,buys={}} end
    local rows, seen = {}, {}
    for i,r in ipairs(listings or {}) do
        local key = r.auctionID or i
        local price = partial and r.unitPrice or r.buyout
        if not seen[key] and integer(r.quantity) and r.quantity>0 and integer(price) and price>0 and not r.own then
            seen[key]=true; rows[#rows+1]={row=r,index=i,price=price}
        end
    end
    if partial then
        table.sort(rows,function(a,b) return a.price<b.price end)
        local cost, remaining, buys=0,needed,{}
        for _,r in ipairs(rows) do
            local n=math.min(remaining,r.row.quantity)
            if n>0 then buys[#buys+1]={auctionID=r.row.auctionID,quantity=n,cost=n*r.price,unitPrice=r.price}; cost=cost+n*r.price; remaining=remaining-n end
            if remaining==0 then return {cost=cost,quantity=needed,leftover=0,buys=buys} end
        end
        return nil,"Insufficient AH supply"
    end
    -- 0/1 capped knapsack. Immutable parent nodes avoid reusing a listing during
    -- reconstruction. Descending quantities ensure each auction is used once.
    local dp={[0]={cost=0,quantity=0}}
    for _,r in ipairs(rows) do
        for q=needed-1,0,-1 do
            local prev=dp[q]
            if prev then
                local dest=math.min(needed,q+r.row.quantity)
                local cost=prev.cost+r.price
                local quantity=prev.quantity+r.row.quantity
                if not dp[dest] or cost<dp[dest].cost or (cost==dp[dest].cost and quantity<dp[dest].quantity) then
                    dp[dest]={cost=cost,quantity=quantity,parent=prev,listing=r}
                end
            end
        end
    end
    local best=dp[needed]
    if not best then return nil,"Insufficient AH supply" end
    local result={cost=best.cost,quantity=best.quantity,leftover=best.quantity-needed,buys={}}
    while best.listing do
        local r=best.listing
        result.buys[#result.buys+1]={auctionID=r.row.auctionID,quantity=r.row.quantity,cost=r.price}
        best=best.parent
    end
    return result
end
function Cost.Bundle(bundle, owned, quote)
    local have=math.min(bundle.quantity, owned[bundle.itemID] or 0)
    local missing=bundle.quantity-have
    local r={bundle=bundle,owned=have,missing=missing}
    if missing==0 then r.cost=0; r.status="Ready to fill"; r.kind="owned"; return r end
    local p=quote(bundle.itemID,missing)
    for k,v in pairs(p) do r[k]=v end
    return r
end
function Cost.Compare(crate,owned,quote)
    local results,priced={},0
    for _,bundle in ipairs(crate.bundles) do
        local r=Cost.Bundle(bundle,owned,quote); results[#results+1]=r
        if r.cost then priced=priced+1 end
    end
    table.sort(results,function(a,b)
        if a.cost~=b.cost then return (a.cost or math.huge)<(b.cost or math.huge) end
        return a.bundle.itemID<b.bundle.itemID
    end)
    return results[1],results,priced
end

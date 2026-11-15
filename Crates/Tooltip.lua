-- Azeroth Familiar - Crates/Tooltip.lua (ported from Crate Scout 0.2.0)
-- Crate tooltip: compact recommendation lines plus in-place highlighting of the
-- winning bundle inside the client's own "Fill the crate with any bundle" list.
-- All decisions come from C.Model:Recommend (which uses C.Cost); no cost logic here.
local _, AA = ...
AA.Crates = AA.Crates or {}
local C = AA.Crates
C.Tooltip = {state = {}, tips = {}}
local T = C.Tooltip
local G = C.Color
T.HEADER = "Fill the crate with any bundle"
T.HIGHLIGHT = {confirmed = "|cff4cff4c", estimate = "|cffffb84d"}
T.LINES = 4 -- fixed shape so later updates rewrite our own lines in place

local function escape(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end
local function stripCodes(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Removes trailing whitespace and color codes, to test "starts a line".
local function trimTail(s)
    while true do
        local n = #s
        s = s:gsub("[ \t]+$", ""):gsub("|c%x%x%x%x%x%x%x%x$", ""):gsub("|r$", "")
        if #s == n then return s end
    end
end

-- Color code in effect at the end of `s` (nil = the FontString's own color).
-- Escaped pipes ("||") are skipped.
function T.ActiveColor(s)
    local stack, pos = {}, 1
    while true do
        local at = s:find("|", pos, true)
        if not at then break end
        local nextc = s:sub(at + 1, at + 1)
        if nextc == "|" then pos = at + 2
        elseif nextc == "c" and s:sub(at, at + 9):match("^|c%x%x%x%x%x%x%x%x$") then
            stack[#stack + 1] = s:sub(at, at + 9); pos = at + 10
        elseif nextc == "r" then stack[#stack] = nil; pos = at + 2
        else pos = at + 1 end
    end
    return stack[#stack]
end

-- Pure: color each target's "- <qty> <name>" line inside `text`, searching only
-- from `from`. A match must start a line and end at a line end, so a quantity
-- or name embedded in another line/name never matches. Returns text, matches.
function T.Colorize(text, from, targets, color)
    local hits = {}
    for _, t in ipairs(targets or {}) do
        local pattern = "%-[ \t]*" .. t.quantity .. "[ \t]+" .. escape(t.name)
        local init = from or 1
        while true do
            local s, e = text:find(pattern, init)
            if not s then break end
            local before = trimTail(text:sub(1, s - 1))
            local after = text:sub(e + 1)
            local starts = before == "" or before:sub(-1) == "\n" or before:sub(-2) == "|n"
            local ends = after:match("^[ \t]*$") or after:match("^[ \t]*[\r\n|]")
            if starts and ends then hits[#hits + 1] = {s = s, e = e}; break end
            init = e + 1
        end
    end
    table.sort(hits, function(a, b) return a.s > b.s end)
    for _, h in ipairs(hits) do
        local outer = T.ActiveColor(text:sub(1, h.s - 1))
        text = text:sub(1, h.s - 1) .. color .. text:sub(h.s, h.e) .. "|r" .. (outer or "") .. text:sub(h.e + 1)
    end
    return text, #hits
end

local function lineFS(tip, i)
    local name = tip.GetName and tip:GetName()
    return name and _G[name .. "TextLeft" .. i]
end

-- The accepted-bundle section: the FontString holding the header (searched
-- after the header) plus directly following "- N Name" lines. Stops at the first
-- other line, so price lines from other addons are never touched.
function T:Section(tip, limit)
    local list = {}
    for i = 1, limit do
        local fs = lineFS(tip, i)
        local text = fs and fs:GetText()
        if type(text) ~= "string" then
            if list[1] then break end
        elseif not list[1] then
            local _, e = text:find(self.HEADER, 1, true)
            if e then list[1] = {fs = fs, from = e + 1} end
        elseif stripCodes(text):match("^%s*%-%s*%d+%s") then
            list[#list + 1] = {fs = fs, from = 1}
        else
            break
        end
    end
    return list
end

local function shorten(s, n)
    s = tostring(s or "")
    if #s > n then return s:sub(1, n - 3) .. "..." end
    return s
end
local function bundleName(r) return C.ItemName(r.bundle.itemID, r.bundle.name) end

local function buyText(r, tie, estimate)
    local cost = (estimate and "~" or "") .. C.Coins(r.cost)
    if tie then return "Each tied bundle · " .. cost .. (estimate and " est." or "") end
    local s = (r.owned > 0) and ("Own " .. r.owned .. " · buy " .. r.missing) or ("Buy " .. r.missing)
    if r.plan and r.plan.leftover and r.plan.leftover > 0 then s = s .. " (+" .. r.plan.leftover .. " extra)" end
    return s .. " · " .. cost .. (estimate and " est." or "")
end

-- Builds the fixed-shape lines and highlight targets for a crate.
function T:Content(crate)
    local rec = C.Model:Recommend(crate, C.owned)
    local out = {rec = rec, lines = {}, targets = {}}
    local L = out.lines
    L[1] = G.gold .. "Azeroth Familiar · Crates|r"
    if rec.state == "unsupported" then
        L[2] = G.orange .. "Unsupported / unverified #" .. crate.id .. "|r"
        L[3] = G.grey .. shorten(rec.reason, 44) .. "|r"
        L[4] = G.grey .. "Not compared · /fam crates verify|r"
    elseif rec.state == "unpriced" then
        L[2] = "Best bundle: " .. G.grey .. "not priced yet|r"
        L[3] = G.grey .. (C.Scan.open and "Scan the AH on the Crates page (/fam crates)" or "Open the AH, then scan (/fam crates)") .. "|r"
        L[4] = G.grey .. shorten(rec.best and rec.best.status, 44) .. "|r"
    else
        local w = rec.winnerList[1]
        local estimate = rec.state == "estimate"
        local color = estimate and G.amber or G.green
        out.color = estimate and self.HIGHLIGHT.estimate or self.HIGHLIGHT.confirmed
        for _, r in ipairs(rec.winnerList) do
            out.targets[#out.targets + 1] = {itemID = r.bundle.itemID, quantity = r.bundle.quantity, name = bundleName(r)}
        end
        local what = rec.tie and (#rec.winnerList .. " tied bundles") or (w.bundle.quantity .. " " .. bundleName(w))
        local partial = (rec.partial and "Cheapest of priced bundles · " or "") .. (rec.tie and "Tie · " or "")
        if rec.state == "ready" then
            L[2] = color .. "Ready to fill: " .. what .. "|r"
            L[3] = color .. "Ready to fill · 0c|r"
            L[4] = G.grey .. (rec.tie and "Tie · any highlighted bundle fills it" or ("Owned " .. w.owned .. "/" .. w.bundle.quantity .. " in bags")) .. "|r"
        elseif estimate then
            L[2] = (rec.tie and "Tied estimate: " or "Estimate: ") .. color .. what .. "|r"
            L[3] = buyText(w, rec.tie, true)
            L[4] = G.grey .. partial .. shorten(w.status, 40) .. "|r"
        else
            L[2] = (rec.tie and "Tied best: " or "Best bundle: ") .. color .. what .. "|r"
            L[3] = buyText(w, rec.tie, false)
            L[4] = G.grey .. partial .. ((rec.mixed and not rec.partial and not rec.tie) and "vs estimates · " or "") .. "AH snapshot · " .. C.Age(w.age) .. "|r"
        end
    end
    local ids = {}
    for _, t in ipairs(out.targets) do ids[#ids + 1] = t.itemID end
    out.sig = table.concat(L, "\1") .. "\2" .. (out.color or "") .. table.concat(ids, ",")
    return out
end

local function itemID(tip)
    if not tip.GetItem then return end
    local _, link = tip:GetItem()
    return link and tonumber(link:match("item:(%d+)"))
end

-- True while every FontString we wrote still shows exactly what we wrote.
function T:Intact(st)
    for _, l in ipairs(st.lines) do if not l.fs or l.fs:GetText() ~= l.text then return false end end
    for _, f in ipairs(st.fs) do if f.fs:GetText() ~= f.set then return false end end
    return true
end

function T:Paint(st, content)
    for _, f in ipairs(st.fs) do
        local text = f.base
        if content.color and #content.targets > 0 then text = T.Colorize(f.base, f.from, content.targets, content.color) end
        if f.fs:GetText() ~= text then f.fs:SetText(text) end
        f.set = f.fs:GetText()
    end
end

-- Restores the client's text if our colors are still in place (a hidden but
-- not cleared tooltip); a cleared tooltip was already reset by the client.
function T:Release(tip)
    local st = self.state[tip]
    if not st then return end
    self.state[tip] = nil
    for _, f in ipairs(st.fs) do
        if f.set ~= f.base and f.fs:GetText() == f.set then f.fs:SetText(f.base) end
    end
end

-- Interface page switch ("Crates: highlight the cheapest bundle in crate tooltips").
function T:Enabled()
    local s = AA.db and AA.db.settings and AA.db.settings.crates
    return not (s and s.tooltip == false)
end
function T:SetEnabled(on)
    if AA.db and AA.db.settings.crates then AA.db.settings.crates.tooltip = on and true or false end
    if not on then for tip in pairs(self.state) do self:Release(tip) end end
end

function T:Apply(tip)
    if not self.tips[tip] or (tip.IsForbidden and tip:IsForbidden()) then return end
    if not self:Enabled() then if self.state[tip] then self:Release(tip) end; return end
    local id = itemID(tip)
    local crate = id and C.Catalog.entries[id]
    local st = self.state[tip]
    if st and (st.id ~= id or not self:Intact(st)) then self:Release(tip); st = nil end
    if not crate then return end
    if st then return self:Update(tip, st) end -- repeated post-call: no duplicate lines
    st = {tip = tip, id = id, fs = {}, lines = {}}
    for _, sec in ipairs(self:Section(tip, tip:NumLines())) do
        local text = sec.fs:GetText()
        st.fs[#st.fs + 1] = {fs = sec.fs, base = text, set = text, from = sec.from}
    end
    local content = self:Content(crate)
    for i = 1, self.LINES do
        tip:AddLine(content.lines[i], 1, 1, 1)
        local fs = lineFS(tip, tip:NumLines())
        st.lines[i] = {fs = fs, text = fs and fs:GetText()}
    end
    self:Paint(st, content)
    st.sig = content.sig
    self.state[tip] = st
    self:Watch()
end

function T:Update(tip, st)
    local crate = C.Catalog.entries[st.id]
    if not crate or itemID(tip) ~= st.id or not self:Intact(st) then self.state[tip] = nil; return end
    local content = self:Content(crate)
    if content.sig == st.sig then return end
    local grew = false
    for i, l in ipairs(st.lines) do
        local text = content.lines[i] or ""
        if text ~= l.text then
            if #text > #(l.text or "") then grew = true end
            l.fs:SetText(text); l.text = l.fs:GetText()
        end
    end
    self:Paint(st, content)
    st.sig = content.sig
    -- Re-measure only when text widened. Show() on a shown tooltip resizes it
    -- without firing OnShow or a refill, so it cannot recurse or flicker.
    if grew and tip:IsShown() then tip:Show() end
end

-- Inventory, scan, validation or freshness changed.
function T:Refresh()
    for tip, st in pairs(self.state) do
        local ok = pcall(self.Update, self, tip, st)
        if not ok then self.state[tip] = nil end
    end
end

-- One-second ticker that runs only while a crate tooltip is shown (snapshot age
-- and 120 s expiry). Nothing else is reparsed.
function T:Watch()
    if not CreateFrame then return end
    if not self.ticker then
        self.ticker = CreateFrame("Frame")
        self.ticker.elapsed = 0
        self.ticker:SetScript("OnUpdate", function(f, dt)
            f.elapsed = f.elapsed + (dt or 0)
            if f.elapsed < 1 then return end
            f.elapsed = 0
            if next(self.state) == nil then f:Hide(); return end
            self:Refresh()
        end)
    end
    self.ticker:Show()
end

function T:Install()
    if self.installed then return end
    self.installed = true
    for _, tip in ipairs({GameTooltip, ItemRefTooltip}) do if tip then self.tips[tip] = true end end
    local function post(tip) if self.tips[tip] then pcall(self.Apply, self, tip) end end
    local viaProcessor = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        viaProcessor = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, post)
    end
    for tip in pairs(self.tips) do
        if not viaProcessor then pcall(tip.HookScript, tip, "OnTooltipSetItem", post) end
        pcall(tip.HookScript, tip, "OnTooltipCleared", function(t) self:Release(t) end)
        pcall(tip.HookScript, tip, "OnHide", function(t) self:Release(t) end)
    end
end

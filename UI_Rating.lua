-- MOO rating prompt: shown after you leave a dungeon or raid (never inside one).
-- 1-5 stars and positive tags per groupmate. Everything is optional; Skip rates nobody.

local _, ns = ...

local ROWS = 5
local ROW_H = 78
local frame

local function starTexCoord(tex, filled)
    tex:SetTexture("Interface\\COMMON\\ReputationStar")
    if filled then tex:SetTexCoord(0, 0.5, 0, 0.5) else tex:SetTexCoord(0.5, 1, 0, 0.5) end
end

local function makeRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(560, ROW_H - 2)
    r:SetPoint("TOPLEFT", 14, -56 - (i - 1) * ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.02)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", 6, -6)
    r.name:SetWidth(240)
    r.name:SetJustifyH("LEFT")

    r.stars = {}
    for s = 1, 5 do
        local b = CreateFrame("Button", nil, r)
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", 260 + (s - 1) * 22, -2)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        starTexCoord(b.tex, false)
        b:SetScript("OnClick", function()
            local sel = frame.sel[r.member]
            sel.stars = (sel.stars == s) and 0 or s
            frame:RefreshRows()
        end)
        r.stars[s] = b
    end
    r.hint = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.hint:SetPoint("LEFT", r.stars[5], "RIGHT", 8, 0)

    r.tags = {}
    for t = 1, 7 do
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(78, 18)
        b:SetPoint("TOPLEFT", 6 + (t - 1) * 79, -28)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetScript("OnClick", function(self)
            local sel = frame.sel[r.member]
            local bit = self.tagBit
            if ns.TagMaskHas(sel.tags, bit) then sel.tags = sel.tags - 2 ^ (bit - 1)
            else sel.tags = sel.tags + 2 ^ (bit - 1) end
            frame:RefreshRows()
        end)
        r.tags[t] = b
    end

    -- Private tips: sent only to this player, never shown publicly or with your name
    r.suggLabel = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.suggLabel:SetPoint("BOTTOMLEFT", 6, 7)
    r.suggLabel:SetText("Private tip:")
    r.suggs = {}
    for t = 1, 5 do
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(96, 18)
        b:SetPoint("BOTTOMLEFT", 66 + (t - 1) * 98, 3)
        b:SetNormalFontObject("GameFontHighlightSmall")
        b:SetScript("OnClick", function(self)
            local sel = frame.sel[r.member]
            local bit = self.suggBit
            if ns.TagMaskHas(sel.sugg, bit) then sel.sugg = sel.sugg - 2 ^ (bit - 1)
            else sel.sugg = sel.sugg + 2 ^ (bit - 1) end
            frame:RefreshRows()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Private tip", 1, 0.82, 0)
            GameTooltip:AddLine("Only this player sees it, with a how-to guide. Your name is never shown, and tips only appear once 2 different players have sent some.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        r.suggs[t] = b
    end
    return r
end

local function makeFrame()
    local ok, f = pcall(CreateFrame, "Frame", "MOORatingFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOORatingFrame2", UIParent) end
    f:SetSize(590, 56 + ROWS * ROW_H + 50)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -6)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 16, -32)
    f.sub:SetText("Stars and compliments count toward ratings. Private tips go only to that player.")

    f.rows = {}
    for i = 1, ROWS do f.rows[i] = makeRow(f, i) end
    f.offset = 0

    f.prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.prev:SetSize(60, 22); f.prev:SetText("<"); f.prev:SetPoint("BOTTOMLEFT", 14, 12)
    f.prev:SetScript("OnClick", function() f.offset = math.max(0, f.offset - ROWS); f:RefreshRows() end)
    f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.next:SetSize(60, 22); f.next:SetText(">"); f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.next:SetScript("OnClick", function()
        if f.offset + ROWS < #f.members then f.offset = f.offset + ROWS; f:RefreshRows() end
    end)
    f.page = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.page:SetPoint("LEFT", f.next, "RIGHT", 8, 0)

    f.submit = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.submit:SetSize(110, 22); f.submit:SetText("Submit")
    f.submit:SetPoint("BOTTOMRIGHT", -14, 12)
    f.submit:SetScript("OnClick", function() f:Submit() end)
    f.skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.skip:SetSize(80, 22); f.skip:SetText("Skip")
    f.skip:SetPoint("RIGHT", f.submit, "LEFT", -4, 0)
    f.skip:SetScript("OnClick", function() f:Done() end)

    function f:RefreshRows()
        for i, r in ipairs(self.rows) do
            local m = self.members[self.offset + i]
            if not m then r:Hide() else
                r:Show()
                r.member = m.name
                local sel = self.sel[m.name]
                local roleText = m.role and ("  " .. ns.RoleText(m.role)) or ""
                r.name:SetText(ns.ClassColor(m.class, ns.ShortName(m.name)) .. roleText)
                for s, b in ipairs(r.stars) do
                    starTexCoord(b.tex, s <= sel.stars)
                    b:SetEnabled(m.aol)
                    b:SetAlpha(m.aol and 1 or 0.3)
                end
                r.hint:SetText(m.aol and "" or "no MOO (or not opted in)")
                local tags = m.aol and ns.TagsForRole(m.role or "ANY") or {}
                local suggs = m.aol and ns.SuggestionsForRole(m.role or "ANY") or {}
                r.suggLabel:SetShown(#suggs > 0)
                for t, b in ipairs(r.suggs) do
                    local sug = suggs[t]
                    if sug then
                        b.suggBit = sug.bit
                        local on = ns.TagMaskHas(sel.sugg, sug.bit)
                        b:SetText(on and ("|cffff9966" .. sug.label .. "|r") or sug.label)
                        b:Show()
                    else
                        b:Hide()
                    end
                end
                for t, b in ipairs(r.tags) do
                    local tag = tags[t]
                    if tag then
                        b.tagBit = tag.bit
                        local on = ns.TagMaskHas(sel.tags, tag.bit)
                        b:SetText(on and ("|cff33ff33" .. tag.label .. "|r") or tag.label)
                        b:Show()
                    else
                        b:Hide()
                    end
                end
            end
        end
        local pages = math.max(1, math.ceil(#self.members / ROWS))
        self.page:SetText("Page " .. (math.floor(self.offset / ROWS) + 1) .. " / " .. pages)
        self.prev:SetShown(pages > 1); self.next:SetShown(pages > 1); self.page:SetShown(pages > 1)
    end

    function f:Submit()
        local n, tips = 0, 0
        for name, sel in pairs(self.sel) do
            if sel.stars and sel.stars > 0 then
                ns.SubmitRating(self.pending.id, name, sel.stars, sel.tags)
                n = n + 1
            end
            if sel.sugg and sel.sugg > 0 then
                ns.SendSuggestions(self.pending.id, name, sel.sugg)
                tips = tips + 1
            end
        end
        if n == 0 and tips == 0 then
            ns.Print("Nothing selected, nothing sent.")
        else
            ns.Print("Thanks! " .. n .. " rating(s) and " .. tips .. " private tip(s) sent.")
        end
        self:Done()
    end

    function f:Done()
        local list = MOO_CharDB.pending or {}
        for i = #list, 1, -1 do
            if list[i].id == self.pending.id then table.remove(list, i) end
        end
        self:Hide()
        ns.Fire("STATE_CHANGED")
    end

    ns.Themed(f)
    f:Hide()
    frame = f
end

function ns.ShowRatingPrompt(pending)
    if not ns.IsOptedIn() then ns.Print("Opt in to rate players (/moo optin).") return end
    pending = pending or (MOO_CharDB.pending and MOO_CharDB.pending[1])
    if not pending then ns.Print("No recent runs to rate.") return end
    if ns.InRestrictedInstance() then
        ns.Print("You can rate once you are out of the instance.")
        return
    end
    if not frame then makeFrame() end
    frame.pending = pending
    frame.members, frame.sel = {}, {}
    for name, m in pairs(pending.members) do
        table.insert(frame.members, { name = name, class = m.class, aol = m.aol, role = m.role })
        frame.sel[name] = { stars = 0, tags = 0, sugg = 0 }
    end
    local order = { TANK = 1, HEAL = 2, DPS = 3 }
    table.sort(frame.members, function(a, b)
        if a.aol ~= b.aol then return a.aol end
        local ra, rb = order[a.role] or 4, order[b.role] or 4
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    frame.offset = 0
    frame.title:SetText("Rate your " .. (ns.INSTANCE_BY_KEY[pending.inst] and ns.InstanceName(pending.inst) or (pending.name or "group")) .. " group")
    frame:Show()
    frame:RefreshRows()
end

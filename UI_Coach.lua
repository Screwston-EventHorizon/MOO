-- MOO Feedback tab and how-to guide window.

local _, ns = ...

------------------------------------------------------------------------
-- Guide window
------------------------------------------------------------------------
local guideFrame

local function makeGuideFrame()
    local UI = ns.UI
    local ok, f = pcall(CreateFrame, "Frame", "MOOGuideFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOOGuideFrame2", UIParent) end
    f:SetSize(470, 420)
    f:SetPoint("CENTER", 260, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    f.title = UI.Text(f, "GameFontNormal", "CENTER")
    f.title:SetPoint("TOP", 0, -6)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -34)
    sf:SetPoint("BOTTOMRIGHT", -32, 34)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(410, 10)
    sf:SetScrollChild(child)
    f.body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT")
    f.body:SetWidth(410)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetWordWrap(true)
    f.body:SetSpacing(3)
    f.child = child

    f.note = UI.Text(f, "GameFontDisableSmall")
    f.note:SetPoint("BOTTOMLEFT", 14, 12)
    f.note:SetText("Tips are general. Forever changes some classes, so check your own spellbook.")
    ns.Themed(f)
    f:Hide()
    guideFrame = f
end

function ns.ShowGuide(key)
    local g = ns.GUIDES[key]
    if not g then return end
    if not guideFrame then makeGuideFrame() end
    guideFrame.title:SetText(g.title)
    guideFrame.body:SetText(table.concat(g.body, "\n\n"))
    guideFrame.child:SetHeight(guideFrame.body:GetStringHeight() + 10)
    guideFrame:Show()
end

------------------------------------------------------------------------
-- Feedback tab
------------------------------------------------------------------------
local KIND_LABEL = {
    tip  = "|cffffd100Tip|r",
    inst = "|cff88ccffInstance|r",
    sugg = "|cffff9966Suggestion|r",
    good = "|cff33ff33Nice|r",
}

local function FeedbackPage(parent)
    local UI = ns.UI
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local s = UI.Section(p, "Feedback for your role")
    s:SetPoint("TOPLEFT", 4, -4)
    p.role = UI.Dropdown(p, 170, function()
        local out = {}
        for _, r in ipairs(ns.ROLES) do table.insert(out, { value = r, label = "Feedback as: " .. ns.ROLE_LABEL[r] }) end
        return out
    end, function() p:Refresh() end)
    p.role:SetPoint("TOPRIGHT", -4, -2)

    p.status = UI.Text(p, "GameFontHighlight")
    p.status:SetPoint("TOPLEFT", 8, -34)
    p.status:SetPoint("RIGHT", -8, 0)
    p.status:SetWordWrap(true)
    p.strengths = UI.Text(p, "GameFontHighlightSmall")
    p.strengths:SetPoint("TOPLEFT", p.status, "BOTTOMLEFT", 0, -6)
    p.strengths:SetPoint("RIGHT", -8, 0)
    p.strengths:SetWordWrap(true)

    p.list = UI.List(p, 30, 8,
        function(r)
            r.kind = UI.Text(r, "GameFontHighlightSmall")
            r.kind:SetPoint("LEFT", 4, 0)
            r.kind:SetWidth(70)
            r.text = UI.Text(r, "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 78, 0)
            r.text:SetPoint("RIGHT", -90, 0)
            r.text:SetWordWrap(true)
            r.how = UI.Button(r, "How to", 80, 20)
            r.how:SetPoint("RIGHT", -4, 0)
        end,
        function(r, item)
            r.kind:SetText(KIND_LABEL[item.kind] or "")
            r.text:SetText(item.text)
            r.how:SetShown(item.guide ~= nil)
            r.how:SetScript("OnClick", function() ns.ShowGuide(item.guide) end)
        end)
    p.list:SetPoint("TOPLEFT", 4, -92)
    p.list:SetPoint("RIGHT", -4, 0)

    p.suggestNote = UI.Text(p, "GameFontDisableSmall")
    p.suggestNote:SetPoint("TOPLEFT", 8, -340)
    p.suggestNote:SetPoint("RIGHT", -8, 0)
    p.suggestNote:SetWordWrap(true)

    -- All guides
    local g = UI.Section(p, "Guides")
    g:SetPoint("TOPLEFT", 4, -362)
    p.guide = UI.Dropdown(p, 220, function()
        local out = {}
        for key, guide in pairs(ns.GUIDES) do table.insert(out, { value = key, label = guide.title }) end
        table.sort(out, function(a, b) return a.label < b.label end)
        return out
    end)
    p.guide:SetPoint("TOPLEFT", 4, -380)
    local open = UI.Button(p, "Read", 70, 22, function() ns.ShowGuide(p.guide.value) end)
    open:SetPoint("LEFT", p.guide, "RIGHT", 8, 0)

    p.toggle = UI.Button(p, "", 210, 22, function() ns.SetSuggestionsOn(MOO_CharDB.suggestionsOff) end)
    p.toggle:SetPoint("TOPRIGHT", -4, -380)

    local how = UI.Text(p, "GameFontDisableSmall")
    how:SetPoint("BOTTOMLEFT", 6, 4)
    how:SetPoint("RIGHT", -6, 0)
    how:SetWordWrap(true)
    how:SetText("Feedback comes only from groupmates' ratings, tags and private suggestions. MOO can't see " ..
        "combat data, so it never judges your numbers. Suggestions are only visible to you and never say who sent them.")

    function p:Refresh()
        if not self.role.value or self.firstShow == nil then
            self.role:SetValue(MOO_CharDB.role)
            self.firstShow = true
        end
        self.guide:Refresh()
        local fb = ns.CoachFeedback(self.role.value or MOO_CharDB.role)
        self.status:SetText(fb.status or "")
        self.strengths:SetText(fb.strengths and ("|cff33ff33" .. fb.strengths .. "|r") or "")
        self.list:SetData(fb.items, "")
        self.suggestNote:SetText(fb.suggestNote or "")
        self.toggle:SetText(MOO_CharDB.suggestionsOff and "Private suggestions: Off" or "Private suggestions: On")
    end
    return p
end

ns.EXTRA_TABS = ns.EXTRA_TABS or {}
table.insert(ns.EXTRA_TABS, { key = "coach", label = "Coach", build = FeedbackPage })

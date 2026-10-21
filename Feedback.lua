-- MOO Feedback: players send feedback to MOO's author from inside the game.
--
-- * Written on the Feedback tab (up to 800 characters) with a category.
-- * Sent as Blizzard *logged* addon whispers (it's player-written text, so it can be
--   reported like chat), split into parts and resent until the author's MOO confirms
--   each part arrived (up to 7 days, like ratings).
-- * The author's MOO saves it in MOO_DB.feedbackInbox, which WoW writes to
--   WTF/Account/<ACCOUNT>/SavedVariables/MOO.lua on logout or /reload.
-- * The sender's character name comes with it, so the author can follow up.

local _, ns = ...

-- Where feedback goes: the author's character, as you'd type it in /tell.
-- On launch servers, update this (and the owner list in Recruit.lua) to the live character.
ns.FEEDBACK_TO = "Screwston Eventhorizon"

local MAX_CHARS = 800
local CHUNK = 190
local MAX_PER_HOUR, MAX_PER_DAY = 3, 10
local INBOX_MAX = 500

ns.FEEDBACK_CATEGORIES = {
    { value = "BUG",       label = "Bug" },
    { value = "IDEA",      label = "Idea or request" },
    { value = "CONFUSING", label = "Something was confusing" },
    { value = "PRAISE",    label = "Something I liked" },
}
local CAT_LABEL = {}
for _, c in ipairs(ns.FEEDBACK_CATEGORIES) do CAT_LABEL[c.value] = c.label end

function ns.IsAuthor()
    return ns.IsRecruitOwner and ns.IsRecruitOwner() or false
end

-- Keep the words, drop anything that could break MOO's message format or inject
-- chat codes (| and ^), and control characters.
local function cleanText(text, max)
    text = tostring(text or ""):gsub("[|%^]", " "):gsub("%c", " "):gsub("%s+", " ")
    text = strtrim(text)
    if #text > max then text = text:sub(1, max) end
    return text
end

-- Split into parts without cutting a multi-byte (accented) character in half.
local function split(text)
    local parts, i = {}, 1
    while i <= #text do
        local j = math.min(#text, i + CHUNK - 1)
        while j < #text and j > i do
            local b = text:byte(j + 1)
            if b < 0x80 or b >= 0xC0 then break end
            j = j - 1
        end
        table.insert(parts, text:sub(i, j))
        i = j + 1
    end
    return parts
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local function sentLog()
    MOO_CharDB.feedbackSent = MOO_CharDB.feedbackSent or {}
    return MOO_CharDB.feedbackSent
end

local function recentCount(seconds)
    local n, now = 0, ns.Now()
    for _, e in ipairs(sentLog()) do if now - e.ts < seconds then n = n + 1 end end
    return n
end

function ns.FeedbackStatusLine()
    local _, build = GetBuildInfo()
    return string.format("MOO %s, game %s, role %s, theme %s, sound %s",
        ns.VERSION, tostring((GetBuildInfo())) .. " (" .. tostring(build) .. ")",
        MOO_CharDB and MOO_CharDB.role or "?", (MOO_DB and MOO_DB.theme) or "classic",
        (MOO_DB and MOO_DB.sound == false) and "off" or "on")
end

-- Returns true, or false and a reason to show the player.
function ns.SendFeedback(category, text, includeStatus)
    if not CAT_LABEL[category] then return false, "Pick a category." end
    text = cleanText(text, MAX_CHARS)
    if #text < 5 then return false, "Write a little more first." end
    if recentCount(3600) >= MAX_PER_HOUR then return false, "You've sent 3 this hour. Try again a bit later." end
    if recentCount(86400) >= MAX_PER_DAY then return false, "You've sent 10 today. Thanks! Try again tomorrow." end
    if includeStatus then text = text .. "  [" .. ns.FeedbackStatusLine() .. "]" end
    local fid = ns.Hash(ns.Me() .. text .. ns.Now()):sub(1, 8)
    local parts = split(text)
    for i, part in ipairs(parts) do
        ns.Deliver("FB", ns.FEEDBACK_TO, { fid, tostring(i), tostring(#parts), category, part })
    end
    table.insert(sentLog(), 1, { fid = fid, ts = ns.Now(), category = category, preview = text:sub(1, 60) })
    while #sentLog() > 50 do table.remove(sentLog()) end
    ns.Fire("FEEDBACK_UPDATED")
    return true
end

-- Still waiting = some part of it is still in the outbox.
function ns.FeedbackDelivered(fid)
    for _, e in pairs(MOO_CharDB.outbox or {}) do
        if e.kind == "FB" and e.fields and e.fields[1] == fid then return false end
    end
    return true
end

------------------------------------------------------------------------
-- Receiving (the author's MOO only)
------------------------------------------------------------------------
local partial = {}          -- [sender .. fid] = { parts = {}, got = 0, total = n, category = }
local perSenderToday = {}

local function inbox()
    MOO_DB.feedbackInbox = MOO_DB.feedbackInbox or {}
    return MOO_DB.feedbackInbox
end

ns.Handle("FB", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    ns.Ack(sender, f[2])                       -- stop their retries either way
    if not ns.IsAuthor() then return end
    local fid = f[3]
    local part, total = ns.Clamp(f[4], 1, 10, nil), ns.Clamp(f[5], 1, 10, nil)
    local category, text = f[6], f[7]
    if type(fid) ~= "string" or #fid > 12 or not part or not total or part > total then return end
    if not CAT_LABEL[category] or type(text) ~= "string" then return end
    local day = date("%Y%m%d")
    local key = sender .. "|" .. fid
    local p = partial[key]
    if not p then
        local s = perSenderToday[sender]
        if not s or s.day ~= day then s = { day = day, n = 0 }; perSenderToday[sender] = s end
        if s.n >= 20 then return end            -- one player can't flood the inbox
        s.n = s.n + 1
        p = { parts = {}, got = 0, total = total, category = category, ts = ns.Now() }
        partial[key] = p
    end
    if not p.parts[part] then
        p.parts[part] = cleanText(text, CHUNK + 10)
        p.got = p.got + 1
    end
    if p.got >= p.total then
        partial[key] = nil
        table.insert(inbox(), 1, {
            from = sender, ts = p.ts, category = p.category,
            text = table.concat(p.parts, ""), read = false,
        })
        while #inbox() > INBOX_MAX do table.remove(inbox()) end
        ns.Print("New feedback from " .. ns.ShortName(sender) .. " (" .. CAT_LABEL[p.category] .. "). See the Feedback tab.")
        ns.Alert(SOUNDKIT and SOUNDKIT.TELL_MESSAGE, 3081)
        ns.Fire("FEEDBACK_UPDATED")
    end
end)

function ns.FeedbackExportText()
    local lines = { "MOO feedback inbox, exported " .. date("%Y-%m-%d %H:%M"), "" }
    for _, e in ipairs(inbox()) do
        table.insert(lines, string.format("[%s] %s - %s", date("%Y-%m-%d %H:%M", math.floor(e.ts)), e.from, CAT_LABEL[e.category] or e.category))
        table.insert(lines, e.text)
        table.insert(lines, "")
    end
    if #inbox() == 0 then table.insert(lines, "(empty)") end
    return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- The Feedback tab
------------------------------------------------------------------------
local function FeedbackSendPage(parent)
    local UI = ns.UI
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Author view: inbox
    local inboxBox = CreateFrame("Frame", nil, p)
    inboxBox:SetAllPoints()
    local ih = UI.Section(inboxBox, "Feedback inbox")
    ih:SetPoint("TOPLEFT", 4, -4)
    inboxBox.count = UI.Text(inboxBox, "GameFontHighlightSmall")
    inboxBox.count:SetPoint("LEFT", ih, "RIGHT", 12, 0)
    local copyAll = UI.Button(inboxBox, "Copy all", 90, 22, function()
        for _, e in ipairs(inbox()) do e.read = true end
        ns.ShowCopyBox("MOO feedback", ns.FeedbackExportText())
        ns.Fire("FEEDBACK_UPDATED")
    end)
    copyAll:SetPoint("TOPRIGHT", -4, -2)
    local clear = UI.Button(inboxBox, "Delete read", 100, 22, function()
        local keep = {}
        for _, e in ipairs(inbox()) do if not e.read then table.insert(keep, e) end end
        MOO_DB.feedbackInbox = keep
        ns.Fire("FEEDBACK_UPDATED")
    end)
    clear:SetPoint("RIGHT", copyAll, "LEFT", -6, 0)
    local X = { 0, 110, 230, 380 }
    local hdr = CreateFrame("Frame", nil, inboxBox)
    hdr:SetPoint("TOPLEFT", 4, -30); hdr:SetPoint("RIGHT", -4, 0); hdr:SetHeight(14)
    UI.Header(hdr, { { "When", X[1] }, { "From", X[2] }, { "Type", X[3] }, { "Feedback", X[4] } })
    inboxBox.list = UI.List(inboxBox, 24, 13,
        function(r)
            r.c = {}
            for i = 1, 4 do r.c[i] = UI.Text(r); r.c[i]:SetPoint("LEFT", X[i] + 2, 0) end
            r.c[4]:SetPoint("RIGHT", -4, 0)
            r:SetScript("OnClick", function(self)
                if not self.item then return end
                self.item.read = true
                ns.ShowCopyBox("Feedback from " .. self.item.from, self.item.text)
                ns.Fire("FEEDBACK_UPDATED")
            end)
        end,
        function(r, e)
            local style = e.read and "|cffaaaaaa" or "|cffffffff"
            r.c[1]:SetText(style .. date("%m-%d %H:%M", math.floor(e.ts)) .. "|r")
            r.c[2]:SetText(style .. ns.ShortName(e.from) .. "|r")
            r.c[3]:SetText(style .. (CAT_LABEL[e.category] or e.category) .. "|r")
            r.c[4]:SetText(style .. e.text .. "|r")
        end)
    inboxBox.list:SetPoint("TOPLEFT", 4, -46)
    inboxBox.list:SetPoint("RIGHT", -4, 0)
    local where = UI.Text(inboxBox, "GameFontDisableSmall")
    where:SetPoint("BOTTOMLEFT", 6, 4); where:SetPoint("RIGHT", -6, 0); where:SetWordWrap(true)
    where:SetText("Click a row to read and copy it. Saved on your computer in WTF/Account/<your account>/SavedVariables/MOO.lua " ..
        "(written when you log out or /reload).")

    -- Player view: write and send
    local sendBox = CreateFrame("Frame", nil, p)
    sendBox:SetAllPoints()
    local sh = UI.Section(sendBox, "Send feedback to MOO's author")
    sh:SetPoint("TOPLEFT", 4, -4)
    local intro = UI.Text(sendBox, "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 6, -24); intro:SetPoint("RIGHT", -6, 0); intro:SetWordWrap(true)
    intro:SetText("Found a bug, have an idea, or something felt confusing? Tell us here. Your character name is sent " ..
        "with it so we can follow up. If the author is offline, it's delivered when they're next online.")
    sendBox.cat = UI.Dropdown(sendBox, 220, function() return ns.FEEDBACK_CATEGORIES end)
    sendBox.cat:SetPoint("TOPLEFT", 4, -56)

    local sf = CreateFrame("ScrollFrame", nil, sendBox, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -92)
    sf:SetPoint("RIGHT", -32, 0)
    sf:SetHeight(150)
    local bg = sendBox:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", sf, -4, 4); bg:SetPoint("BOTTOMRIGHT", sf, 24, -4)
    bg:SetColorTexture(0, 0, 0, 0.5)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(640)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(MAX_CHARS)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    sf:SetScrollChild(eb)
    sf:EnableMouse(true)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    sendBox.eb = eb
    sendBox.chars = UI.Text(sendBox, "GameFontDisableSmall", "RIGHT")
    sendBox.chars:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 24, -8)
    eb:SetScript("OnTextChanged", function(self)
        sendBox.chars:SetText(#(self:GetText() or "") .. " / " .. MAX_CHARS)
    end)

    sendBox.status = true
    local check = CreateFrame("CheckButton", nil, sendBox, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", -4, -4)
    check:SetChecked(true)
    check:SetScript("OnClick", function(self) sendBox.status = self:GetChecked() and true or false end)
    local cl = UI.Text(sendBox, "GameFontHighlightSmall")
    cl:SetPoint("LEFT", check, "RIGHT", 2, 0)
    cl:SetText("Include MOO's version and my settings (helps with bugs)")

    sendBox.result = UI.Text(sendBox, "GameFontHighlight")
    sendBox.result:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -10)
    local send = UI.Button(sendBox, "Send", 110, 24, function()
        local ok, why = ns.SendFeedback(sendBox.cat.value, eb:GetText(), sendBox.status)
        if ok then
            eb:SetText("")
            eb:ClearFocus()
            sendBox.result:SetText("|cff33ff33Sent, thank you!|r")
        else
            sendBox.result:SetText("|cffff6666" .. why .. "|r")
        end
    end)
    send:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 24, -28)

    local sentH = UI.Section(sendBox, "Your recent feedback")
    sentH:SetPoint("TOPLEFT", 4, -320)
    sendBox.sent = UI.List(sendBox, 20, 4,
        function(r)
            r.a = UI.Text(r); r.a:SetPoint("LEFT", 4, 0)
            r.b = UI.Text(r); r.b:SetPoint("LEFT", 110, 0); r.b:SetPoint("RIGHT", -120, 0)
            r.s = UI.Text(r, nil, "RIGHT"); r.s:SetPoint("RIGHT", -4, 0)
        end,
        function(r, e)
            r.a:SetText("|cffaaaaaa" .. date("%m-%d %H:%M", math.floor(e.ts)) .. "|r")
            r.b:SetText(e.preview)
            r.s:SetText(ns.FeedbackDelivered(e.fid) and "|cff33ff33delivered|r" or "|cffffd100waiting to deliver|r")
        end)
    sendBox.sent:SetPoint("TOPLEFT", 4, -340)
    sendBox.sent:SetPoint("RIGHT", -4, 0)

    function p:Refresh()
        local author = ns.IsAuthor()
        inboxBox:SetShown(author)
        sendBox:SetShown(not author)
        if author then
            local unread = 0
            for _, e in ipairs(inbox()) do if not e.read then unread = unread + 1 end end
            inboxBox.count:SetText(#inbox() .. " total, " .. unread .. " unread")
            inboxBox.list:SetData(inbox(), "No feedback yet.")
        else
            sendBox.cat:Refresh()
            sendBox.chars:SetText(#(eb:GetText() or "") .. " / " .. MAX_CHARS)
            sendBox.sent:SetData(sentLog(), "Nothing sent yet.")
        end
    end
    return p
end

ns.EXTRA_TABS = ns.EXTRA_TABS or {}
table.insert(ns.EXTRA_TABS, { key = "feedback", label = "Feedback", build = FeedbackSendPage })
ns.Listen("FEEDBACK_UPDATED", function() if ns.RefreshUI then ns.RefreshUI() end end)

-- MOO Recruit: answer "I want to test MOO" whispers with one click.
--
-- Turn it on with /moo recruit on after posting your tester call. While it's on, a
-- whisper that looks like a request ("want in", "tester", "moo", "interested"...)
-- shows a small window: Send download info / Not now. The reply only goes out when
-- you click: MOO never whispers anyone by itself. Everyone you replied to is kept in
-- a list you can copy (/moo recruit list).

local _, ns = ...

-- Only these characters can use recruiting. A name with no realm matches that name on
-- any realm; add "-Realm" to pin it to one realm. Capitals and spaces don't matter,
-- so both the first name and "First Surname" forms are listed.
-- Everyone else gets "not available".
local OWNERS = {
    "Screwston",
    "Screwston Eventhorizon",
}

local function norm(n) return (n or ""):lower():gsub("%s", "") end

local ownerSet = {}
for _, n in ipairs(OWNERS) do ownerSet[norm(n)] = true end

function ns.IsRecruitOwner()
    local me = ns.Me()
    if not me then return false end
    local short = me:match("^(.-)%-[^%-]+$") or me
    return ownerSet[norm(me)] == true or ownerSet[norm(short)] == true
end

local KEYWORDS = {
    "%f[%a]moo%f[%A]", "tester", "testing", "%f[%a]test%f[%A]", "try it", "try moo",
    "want in", "i'm in", "im in", "count me in", "sign me up", "interested",
    "download", "the addon", "your addon",
}
local REPEAT_SECONDS = 600
local DEFAULT_MESSAGE = "Thanks for helping test MOO! Download: {link} - put the MOO folder in Interface/AddOns, " ..
    "/reload, then type /mooo. Install BugSack too, and send bugs with /moo bug."

local queue, lastSeen = {}, {}
local popup

local function cfg()
    MOO_DB.recruit = MOO_DB.recruit or { on = false, link = nil, message = nil, people = {} }
    return MOO_DB.recruit
end

local function looksLikeRequest(text)
    text = text:lower()
    for _, k in ipairs(KEYWORDS) do
        if text:find(k) then return true end
    end
    return false
end

local function replyText()
    local c = cfg()
    local msg = (c.message or DEFAULT_MESSAGE):gsub("{link}", c.link or "")
    if #msg > 255 then msg = msg:sub(1, 255) end
    return msg
end

------------------------------------------------------------------------
-- Popup (MOO's own window, not a game popup, so it also works with the gamepad UI)
------------------------------------------------------------------------
local function showNext()
    if not popup or popup:IsShown() then return end
    local item = table.remove(queue, 1)
    if not item then return end
    popup.item = item
    local c = cfg()
    local sent = c.people[item.name] and c.people[item.name].sent
    popup.title:SetText(ns.ShortName(item.name) .. (sent and " asked again" or " wants to test MOO"))
    popup.quote:SetText("\"" .. item.text .. "\"")
    popup.send:SetText(sent and "Send again" or "Send download info")
    popup:Show()
    ns.Alert(SOUNDKIT and SOUNDKIT.TELL_MESSAGE, 3081)
end

local function makePopup()
    local UI = ns.UI
    local ok, f = pcall(CreateFrame, "Frame", "MOORecruitPopup", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOORecruitPopup2", UIParent) end
    f:SetSize(380, 130)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.title = UI.Text(f, "GameFontNormal", "CENTER")
    f.title:SetPoint("TOP", 0, -6)
    f.quote = UI.Text(f, "GameFontHighlight", "CENTER")
    f.quote:SetPoint("TOP", 0, -36)
    f.quote:SetWidth(340)
    f.quote:SetWordWrap(true)

    f.send = UI.Button(f, "Send download info", 150, 24, function()
        ns.SendRecruitReply(f.item.name)
        f:Hide()
    end)
    f.send:SetPoint("BOTTOMLEFT", 14, 12)
    local later = UI.Button(f, "Not now", 80, 24, function() f:Hide() end)
    later:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
    local stop = UI.Button(f, "Stop asking", 100, 24, function()
        ns.SetRecruiting(false)
        wipe(queue)
        f:Hide()
    end)
    stop:SetPoint("LEFT", later, "RIGHT", 6, 0)

    f:SetScript("OnHide", function() C_Timer.After(0.3, showNext) end)
    ns.Themed(f)
    f:Hide()
    popup = f
end

------------------------------------------------------------------------
-- Sending (only ever from a click or a command you typed)
------------------------------------------------------------------------
function ns.SendRecruitReply(name)
    if not ns.IsRecruitOwner() then return end
    local c = cfg()
    if not c.link or c.link == "" then
        ns.Print("Set your download link first: /moo recruit link <link>")
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(replyText(), "WHISPER", nil, ns.SendTarget(name))
    c.people[name] = c.people[name] or {}
    c.people[name].sent = ns.Now()
    ns.Print("Sent MOO download info to " .. ns.ShortName(name) .. ".")
end

function ns.SetRecruiting(on)
    cfg().on = on and true or false
    if on then
        ns.Print("Recruiting on: tester requests in whispers will pop up so you can reply with one click." ..
            (cfg().link and "" or " Set your download link with /moo recruit link <link>."))
    else
        ns.Print("Recruiting off.")
    end
end

------------------------------------------------------------------------
-- Watching whispers
------------------------------------------------------------------------
ns.On("CHAT_MSG_WHISPER", function(text, sender)
    if not MOO_DB or not ns.IsRecruitOwner() or not cfg().on then return end
    if ns.IsSecret(text) or ns.IsSecret(sender) or not text or not sender then return end
    if not looksLikeRequest(text) then return end
    local name = ns.FullName(sender)
    if lastSeen[name] and GetTime() - lastSeen[name] < REPEAT_SECONDS then return end
    lastSeen[name] = GetTime()
    local c = cfg()
    c.people[name] = c.people[name] or {}
    c.people[name].asked = ns.Now()
    table.insert(queue, { name = name, text = ns.Clean(text, 120) })
    if not popup then makePopup() end
    showNext()
end)

------------------------------------------------------------------------
-- /moo recruit ...
------------------------------------------------------------------------
function ns.RecruitCommand(rest)
    if not ns.IsRecruitOwner() then
        ns.Print("Recruiting is not available on " .. (ns.Me() or "this character") .. ".")
        return
    end
    local sub, arg = strsplit(" ", strtrim(rest or ""), 2)
    sub = (sub or ""):lower()
    local c = cfg()
    if sub == "on" then
        ns.SetRecruiting(true)
    elseif sub == "off" then
        ns.SetRecruiting(false)
    elseif sub == "link" then
        c.link = arg and strtrim(arg) or nil
        ns.Print(c.link and ("Download link set. Reply preview: " .. replyText()) or "Link cleared.")
    elseif sub == "message" then
        if arg and strtrim(arg) ~= "" then
            c.message = strtrim(arg)
            ns.Print("Reply message set. Use {link} where the link should go. Preview: " .. replyText())
        else
            c.message = nil
            ns.Print("Reply message reset to the default. Preview: " .. replyText())
        end
    elseif sub == "send" and arg then
        ns.SendRecruitReply(ns.FullName(strtrim(arg)))
    elseif sub == "list" then
        local lines = { "MOO testers you replied to:" }
        local names = {}
        for name, p in pairs(c.people) do table.insert(names, { name = name, p = p }) end
        table.sort(names, function(a, b) return (a.p.asked or 0) > (b.p.asked or 0) end)
        for _, e in ipairs(names) do
            table.insert(lines, e.name .. "  asked " .. (e.p.asked and date("%m-%d %H:%M", e.p.asked) or "-") ..
                "  sent " .. (e.p.sent and date("%m-%d %H:%M", e.p.sent) or "not yet"))
        end
        if #names == 0 then table.insert(lines, "(nobody yet)") end
        ns.ShowCopyBox("MOO testers", table.concat(lines, "\n"))
    else
        ns.Print("Recruiting is " .. (c.on and "on" or "off") .. ". Link: " .. (c.link or "not set"))
        ns.Print("/moo recruit on | off | link <link> | message <text with {link}> | send Name | list")
    end
end

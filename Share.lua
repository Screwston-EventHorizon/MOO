-- MOO Share: "Tell my guild" posts one short line about MOO to your own guild chat.
--
-- * Only from a click on "Post to guild chat" in the preview window (or /moo share,
--   which opens the same window). MOO never posts anything by itself.
-- * Once per character every SHARE_COOLDOWN seconds, so no guild hears it too often.

local _, ns = ...

local SHARE_MESSAGE = "Try MOO (Muster Of Olympus), a free group finder for all Olympus guilds. " ..
    "Find dungeon, raid, PvP and quest groups in one window. CurseForge: curseforge.com/wow/addons/moo-muster-of-olympus"
local SHARE_COOLDOWN = 3 * 3600

local popup

local function lastShared() return (MOO_CharDB and MOO_CharDB.lastShare) or 0 end

local function waitLeft()
    return math.max(0, lastShared() + SHARE_COOLDOWN - ns.Now())
end

local function waitText(sec)
    local h, m = math.floor(sec / 3600), math.ceil((sec % 3600) / 60)
    if m == 60 then h, m = h + 1, 0 end
    if h > 0 and m > 0 then return h .. "h " .. m .. "m" end
    if h > 0 then return h .. "h" end
    return math.max(1, m) .. "m"
end

-- Why you can't post right now, or nil if you can.
local function blocker()
    if not IsInGuild() then return "You're not in a guild." end
    if ns.InRestrictedInstance and ns.InRestrictedInstance() then
        return "Post it after you leave the instance."
    end
    local left = waitLeft()
    if left > 0 then return "You told your guild recently. You can post again in " .. waitText(left) .. "." end
end

local function post()
    local why = blocker()
    if why then ns.Print(why) return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, SHARE_MESSAGE, "GUILD")
    if not ok then
        ns.RecordError("share", err)
        ns.Print("Couldn't post to guild chat. Try again in a moment.")
        return false
    end
    MOO_CharDB.lastShare = ns.Now()
    ns.Print("Thanks for telling your guild about MOO!")
    return true
end

local function refresh()
    if not popup or not popup:IsShown() then return end
    local why = blocker()
    popup.post:SetEnabled(why == nil)
    if why then
        popup.hint:SetText("|cffffaa00" .. why .. "|r")
    else
        popup.hint:SetText("Posts this once to your guild chat, as you. You can do it once every " ..
            math.floor(SHARE_COOLDOWN / 3600) .. " hours.")
    end
end

local function makePopup()
    local UI = ns.UI
    local ok, f = pcall(CreateFrame, "Frame", "MOOSharePopup", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOOSharePopup2", UIParent) end
    f:SetSize(420, 170)
    f:SetPoint("TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, f:GetName())

    f.title = UI.Text(f, "GameFontNormal", "CENTER")
    f.title:SetPoint("TOP", 0, -6)
    f.title:SetText("Tell my guild about MOO")

    f.quote = UI.Text(f, "GameFontHighlight", "LEFT")
    f.quote:SetPoint("TOPLEFT", 18, -38)
    f.quote:SetPoint("RIGHT", -18, 0)
    f.quote:SetWordWrap(true)
    f.quote:SetText("\"" .. SHARE_MESSAGE .. "\"")

    f.hint = UI.Text(f, "GameFontDisableSmall", "LEFT")
    f.hint:SetPoint("BOTTOMLEFT", 18, 44)
    f.hint:SetPoint("RIGHT", -18, 0)
    f.hint:SetWordWrap(true)

    f.post = UI.Button(f, "Post to guild chat", 150, 24, function()
        if post() then f:Hide() else refresh() end
    end)
    f.post:SetPoint("BOTTOMRIGHT", -100, 12)
    local cancel = UI.Button(f, "Cancel", 80, 24, function() f:Hide() end)
    cancel:SetPoint("LEFT", f.post, "RIGHT", 6, 0)

    f:SetScript("OnShow", refresh)
    ns.Themed(f)
    f:Hide()
    popup = f
end

-- Open the preview (header button, empty-list prompt, /moo share).
function ns.ShowShare()
    if not popup then makePopup() end
    popup:Show()
    refresh()
end

ns.Listen("STATE_CHANGED", refresh)

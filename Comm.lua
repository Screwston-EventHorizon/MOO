-- MOO Comm: every message MOO sends goes through here.
--
-- * Only Blizzard addon messages (C_ChatInfo.SendAddonMessage). No external server.
-- * One message every 1.2 s at most, below Blizzard's addon message limits.
-- * Nothing is sent from inside a dungeon, raid or battleground: the queue waits
--   until you are out (Forever, like Midnight, restricts addon messages there).
-- * "NET" messages go to your guild, and (once an officer has set a key) to a sealed
--   hidden channel shared by MOO users in every Olympus guild using the same key.

local _, ns = ...

local SEP = "^"
local queue = {}
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 200
local channelName, channelPass

------------------------------------------------------------------------
-- Hidden channel
------------------------------------------------------------------------
-- The channel exists only once an Olympus officer has set a key (see Guild.lua).
-- Without one, MOO talks to your own guild only.
local function deriveChannel()
    local key = MOO_DB and MOO_DB.channelKey
    if key and key ~= "" then
        channelName = "MOOnet" .. ns.Hash("chan:" .. key):sub(1, 6)
        channelPass = ns.Hash("pass:" .. key) .. ns.Hash("pw2:" .. key .. ":moo")
    elseif not ns.REQUIRE_KEY then
        channelName, channelPass = "MOOnet", nil      -- the open default channel
    else
        channelName, channelPass = nil, nil
    end
end

local function hideChannelFromChat()
    if not channelName then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, cf, channelName)
            elseif ChatFrameUtil and ChatFrameUtil.RemoveChannel then
                pcall(ChatFrameUtil.RemoveChannel, cf, channelName)
            end
        end
    end
end

local function channelIndex()
    if not channelName then return 0 end
    local id = GetChannelName(channelName)
    return id or 0
end

local function leaveChannel()
    if channelName and channelIndex() > 0 then LeaveChannelByName(channelName) end
end

function ns.JoinChannel()
    if not ns.InOlympus() then return end
    if not ns.CROSS_GUILD then
        channelName = nil
        if (GetChannelName("MOOnet") or 0) > 0 then LeaveChannelByName("MOOnet") end
        return
    end
    deriveChannel()
    -- sealed with a key: make sure we're not still sitting in the open channel
    if channelName ~= "MOOnet" and (GetChannelName("MOOnet") or 0) > 0 then LeaveChannelByName("MOOnet") end
    if not channelName then return end
    if channelIndex() == 0 then
        if JoinTemporaryChannel then
            JoinTemporaryChannel(channelName, channelPass)
        else
            JoinChannelByName(channelName, channelPass)
        end
    end
    C_Timer.After(2, hideChannelFromChat)
end

function ns.RejoinChannel()
    leaveChannel()
    C_Timer.After(1, ns.JoinChannel)
end

function ns.ChannelStatus()
    if not ns.CROSS_GUILD then return "off (your guild only)" end
    if not channelName then return "off (no officer key yet: your guild only)" end
    local kind = (MOO_DB and MOO_DB.channelKey) and "sealed" or "open"
    return kind .. (channelIndex() > 0 and ", joined" or ", not joined yet")
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local function inRestrictedInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena")
end
ns.InRestrictedInstance = inRestrictedInstance

-- Messages that can carry text a player typed (listing, availability and application
-- notes, and the names of instances MOO added) go through Blizzard's *logged* addon
-- message API, so the server keeps them and players can report abuse under the Code
-- of Conduct, as Blizzard asks of addons that send user-generated content.
local LOGGED_KINDS = { L = true, W = true, J = true, FB = true }

-- Whisper targets MOO used in the last few seconds, so the game's
-- "No player named ... is currently playing" for them can be hidden.
local recentTargets = {}

local function rawSend(dist, msg, target)
    if dist == "WHISPER" then
        target = ns.SendTarget(target)
        if target then recentTargets[target:lower()] = GetTime() end
    end
    if dist == "CHANNEL" then
        local idx = channelIndex()
        if idx == 0 then return end
        target = tostring(idx)
    end
    local kind = msg:match("^([^%^]+)")
    if LOGGED_KINDS[kind] and C_ChatInfo.SendAddonMessageLogged then
        C_ChatInfo.SendAddonMessageLogged(ns.PREFIX, msg, dist, target)
    else
        C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, dist, target)
    end
end

-- dist: "NET" | "GUILD" | "GROUP" | "WHISPER"
function ns.Send(dist, fields, target, front)
    local parts = {}
    for i = 1, #fields do parts[i] = tostring(fields[i] == nil and "" or fields[i]) end
    local msg = table.concat(parts, SEP)
    if #msg > 250 then msg = msg:sub(1, 250) end
    if #queue >= MAX_QUEUE then table.remove(queue, 1) end
    local item = { dist = dist, msg = msg, target = target }
    if front then table.insert(queue, 1, item) else table.insert(queue, item) end
end

local function pump()
    if #queue == 0 or inRestrictedInstance() then return end
    local item = table.remove(queue, 1)
    if item.dist == "NET" then
        if IsInGuild() then rawSend("GUILD", item.msg) end
        -- the channel copy is a separate send, so it takes the next slot
        if channelName and channelIndex() > 0 then
            table.insert(queue, 1, { dist = "CHANNEL", msg = item.msg })
        end
    elseif item.dist == "GROUP" then
        if IsInRaid() then rawSend("RAID", item.msg)
        elseif IsInGroup() then rawSend("PARTY", item.msg) end
    else
        rawSend(item.dist, item.msg, item.target)
    end
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local handlers = {}
function ns.Handle(kind, fn) handlers[kind] = fn end

local seen, seenCount = {}, 0
local function duplicate(sender, msg)
    local k = sender .. "\1" .. msg
    local now = GetTime()
    if seen[k] and now - seen[k] < 15 then return true end
    seen[k] = now
    seenCount = seenCount + 1
    if seenCount > 500 then
        for key, t in pairs(seen) do if now - t > 15 then seen[key] = nil end end
        seenCount = 0
    end
    return false
end

-- Flood guard: a player sending more than FLOOD_MAX messages a minute is ignored
-- for FLOOD_MUTE seconds. Honest clients send a handful per minute at most.
local FLOOD_WINDOW, FLOOD_MAX, FLOOD_MUTE = 60, 40, 600
local flood = {}
local function flooding(sender)
    local now = GetTime()
    local f = flood[sender]
    if not f or now - f.start > FLOOD_WINDOW then
        if f and f.muted and now < f.muted then return true end
        f = { start = now, count = 0 }
        flood[sender] = f
    end
    if f.muted and now < f.muted then return true end
    f.count = f.count + 1
    if f.count > FLOOD_MAX then
        f.muted = now + FLOOD_MUTE
        return true
    end
    return false
end

function ns.IsMuted(sender)
    local f = flood[sender]
    return f and f.muted and GetTime() < f.muted
end

local function onAddonMessage(prefix, msg, dist, sender, logged)
    if prefix ~= ns.PREFIX or not sender then return end
    if ns.IsSecret(msg) or ns.IsSecret(sender) then return end
    ns.lastSenders = ns.lastSenders or {}
    if #ns.lastSenders < 5 and not tContains(ns.lastSenders, sender) then table.insert(ns.lastSenders, sender) end
    sender = ns.FullName(sender)
    -- my own login probe coming back: remember exactly how the server writes my name
    if ns.myProbe and msg == "ME^" .. ns.myProbe then
        ns.myAliases[sender:lower()] = true
        ns.myStamped = sender
        return
    end
    if ns.IsMe(sender) then
        -- my own message came back from the server: it really went out (see ns.MyAvailableStatus)
        local kind = msg:match("^([^%^]+)")
        if kind then ns.Fire("OWN_ECHO", kind) end
        if not ns.selfTest then return end
    end
    ns.Fire("SEEN", sender)
    if not ns.InOlympus() then return end
    if #msg > 255 then return end
    -- the same NET message arrives twice for guildmates (guild + channel)
    if (dist == "GUILD" or dist == "CHANNEL") and duplicate(sender, msg) then return end
    if flooding(sender) then return end
    -- the channel only counts while sealed with an officer key
    if dist == "CHANNEL" and not (ns.CrossGuildOn and ns.CrossGuildOn()) then return end
    -- players the game showed us in a non-Olympus guild are ignored (except in our group)
    if dist ~= "PARTY" and dist ~= "RAID" and ns.GuildStatus and ns.GuildStatus(sender) == "other" then return end
    local fields = { strsplit(SEP, msg) }
    -- text-carrying kinds are only accepted when they came through the logged API
    if LOGGED_KINDS[fields[1]] and not logged and C_ChatInfo.SendAddonMessageLogged then return end
    local fn = handlers[fields[1]]
    if fn then fn(sender, fields, dist) end
end

ns.On("CHAT_MSG_ADDON", function(prefix, msg, dist, sender)
    onAddonMessage(prefix, msg, dist, sender, false)
end)
ns.On("CHAT_MSG_ADDON_LOGGED", function(prefix, msg, dist, sender)
    onAddonMessage(prefix, msg, dist, sender, true)
end)

ns.On("PLAYER_LOGIN", function()
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    C_Timer.NewTicker(SEND_INTERVAL, pump)
end)

ns.Listen("READY", function()
    ns.JoinChannel()
end)

ns.Listen("READY", function()
    -- one guild message to myself, to learn how the server stamps my name
    if IsInGuild() then
        ns.myProbe = ns.Hash(tostring(GetTime()) .. tostring(math.random()))
        ns.Send("GUILD", { "ME", ns.myProbe }, nil, true)
    end
end)

ns.On("CHANNEL_UI_UPDATE", function()
    if channelName then hideChannelFromChat() end
end)

------------------------------------------------------------------------
-- Hide "player not found" for MOO's own background whispers
------------------------------------------------------------------------
local notFoundPattern
local function systemFilter(_, _, msg, ...)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return false end
    if not notFoundPattern then
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
        notFoundPattern = "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    end
    local who = msg:match(notFoundPattern)
    if who then
        local t = recentTargets[who:lower()]
        if t and GetTime() - t < 10 then return true end
    end
    return false
end

ns.Listen("READY", function()
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
    elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
    end
end)

------------------------------------------------------------------------
-- Outbox: whispers that must arrive (ratings, private tips).
-- Each carries an id; the receiver's MOO answers "AK" with it. Until then MOO resends
-- every 10 minutes, or right away when it hears from that player, for up to 7 days.
------------------------------------------------------------------------
local RESEND_SECONDS, KEEP_SECONDS, MAX_TRIES = 600, 7 * 86400, 60

local function outbox()
    MOO_CharDB.outbox = MOO_CharDB.outbox or {}
    return MOO_CharDB.outbox
end

local function trySend(id, e)
    if inRestrictedInstance() then return end
    e.last = ns.Now()
    e.tries = (e.tries or 0) + 1
    local fields = { e.kind, id }
    for _, v in ipairs(e.fields) do table.insert(fields, v) end
    ns.Send("WHISPER", fields, e.to)
end

function ns.Deliver(kind, to, fields)
    to = ns.FullName(to) or to             -- one spelling, so the receiver's "AK" matches
    local id = ns.Hash(kind .. "|" .. to .. "|" .. table.concat(fields, "|") .. "|" .. ns.Now()):sub(1, 8)
    local e = { kind = kind, to = to, fields = fields, created = ns.Now(), last = 0, tries = 0 }
    outbox()[id] = e
    trySend(id, e)
end

function ns.Ack(to, id)
    if type(id) == "string" and #id <= 12 then ns.Send("WHISPER", { "AK", id }, to) end
end

ns.Handle("AK", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local e = outbox()[f[2]]
    if e and ns.LooseSame and ns.LooseSame(e.to, sender) then outbox()[f[2]] = nil end
end)

local function retry(onlyFor)
    local now, sent = ns.Now(), 0
    for id, e in pairs(outbox()) do
        if now - e.created > KEEP_SECONDS or e.tries >= MAX_TRIES then
            outbox()[id] = nil
        elseif onlyFor then
            if ns.LooseSame(e.to, onlyFor) and now - e.last >= 15 then trySend(id, e) end
        elseif now - e.last >= RESEND_SECONDS and sent < 5 then
            trySend(id, e); sent = sent + 1
        end
    end
end

-- Heard from someone: they're online, so deliver anything waiting for them.
ns.Listen("SEEN", function(name) retry(name) end)
ns.Listen("READY", function() C_Timer.NewTicker(60, function() retry(nil) end) end)

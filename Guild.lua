-- MOO Guild: who is an officer, which guild other players are in, and the channel key.
--
-- Olympus-only, in layers:
--   1. Your own guild must be an Olympus guild (Core.lua), or MOO stays off.
--   2. Cross-guild features (the hidden channel) need a key set by an Olympus officer.
--      Until then MOO works inside your own guild only, where every sender is a guildmate.
--   3. When the game shows MOO another player's guild (they're in your group, your target,
--      under your mouse or on a nameplate), MOO remembers it. Players seen in a non-Olympus
--      guild are marked and their messages ignored; players MOO hasn't seen yet are marked
--      "unverified".
--
-- The key: an officer (the guild master or the rank right below) types /moo key <secret>.
-- It goes to guildmates over guild addon messages (never the channel), and each MOO
-- accepts it only from someone its own guild roster shows as an officer. Members who log
-- in later ask, and an online officer's MOO answers. Officers of different Olympus guilds
-- agree on the same secret (e.g. in the officers' Discord) so all guilds share one channel.

local _, ns = ...

local OFFICER_MAX_RANK = 1      -- rank index 0 = guild master, 1 = the rank right below
local GUILD_CACHE_SECONDS = 6 * 3600

ns.guildmates = {}              -- [name] = rankIndex
ns.guildCache = {}              -- [name] = { guild = "Name" or false, ts = GetTime() }

------------------------------------------------------------------------
-- Guild roster
------------------------------------------------------------------------
local function requestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

local function readRoster()
    if not IsInGuild() then ns.guildmates = {} return end
    local mates = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and not ns.IsSecret(name) then mates[ns.FullName(name)] = rankIndex end
    end
    if n > 0 then ns.guildmates = mates end
end

ns.On("GUILD_ROSTER_UPDATE", readRoster)
ns.On("PLAYER_GUILD_UPDATE", function() requestRoster() end)

function ns.IsGuildmate(name) return ns.guildmates[name] ~= nil end

function ns.IsOfficer(name)
    local r = ns.guildmates[name]
    return r ~= nil and r <= OFFICER_MAX_RANK
end

function ns.AmOfficer()
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex ~= nil and rankIndex <= OFFICER_MAX_RANK
end

------------------------------------------------------------------------
-- Other players' guilds, as the game shows them
------------------------------------------------------------------------
local function remember(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name = ns.UnitFullName(unit)
    if not name then return end
    local guild = GetGuildInfo(unit)
    if ns.IsSecret(guild) then return end
    if guild and guild ~= "" then
        ns.guildCache[name] = { guild = guild, ts = GetTime() }
    elseif UnitIsConnected(unit) and UnitIsVisible(unit) then
        -- loaded and visible but no guild shown: treat as guildless
        ns.guildCache[name] = { guild = false, ts = GetTime() }
    end
end

ns.On("PLAYER_TARGET_CHANGED", function() remember("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() remember("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(unit) remember(unit) end)
ns.On("GROUP_ROSTER_UPDATE", function()
    C_Timer.After(2, function()
        for _, u in ipairs(ns.GroupUnits()) do remember(u) end
    end)
end)

-- "mine" | "olympus" | "other" | "unknown"
function ns.GuildStatus(name)
    if not name then return "unknown" end
    if name == ns.Me() or ns.IsGuildmate(name) then return "mine" end
    local c = ns.guildCache[name]
    if not c or GetTime() - c.ts > GUILD_CACHE_SECONDS then return "unknown" end
    if c.guild and ns.IsOlympusGuildName(c.guild) then return "olympus" end
    return "other"
end

function ns.GuildOf(name)
    if ns.IsGuildmate(name) then return GetGuildInfo("player") end
    local c = ns.guildCache[name]
    return c and c.guild or nil
end

-- Small marker after a name; empty when the player is confirmed Olympus.
function ns.GuildMark(name)
    local s = ns.GuildStatus(name)
    if s == "other" then return " |cffff4444(not Olympus)|r" end
    if s == "unknown" then return " |cff888888(unverified)|r" end
    return ""
end

function ns.GuildTooltipLine(name)
    local s = ns.GuildStatus(name)
    if s == "mine" then return "Your guild", 0.4, 1, 0.4 end
    if s == "olympus" then return "Guild: " .. ns.GuildOf(name) .. " (Olympus)", 0.4, 1, 0.4 end
    if s == "other" then
        local g = ns.GuildOf(name)
        return (g and ("Guild: " .. g) or "No guild") .. " - not an Olympus guild", 1, 0.3, 0.3
    end
    return "Guild not seen yet. MOO checks it when they're in your group, targeted or nearby.", 0.6, 0.6, 0.6
end

------------------------------------------------------------------------
-- The channel key
------------------------------------------------------------------------
local function cleanKey(k)
    return strtrim((k or ""):gsub("[%^|%c]", ""))
end

local function applyKey(key, ts, by)
    key = cleanKey(key)
    MOO_DB.channelKey = (key ~= "") and key or nil
    MOO_DB.channelKeyTs = ts
    MOO_DB.channelKeyBy = by
    ns.RejoinChannel()
    ns.Fire("STATE_CHANGED")
end

local function broadcastKey()
    ns.Send("GUILD", { "K", MOO_DB.channelKey or "", MOO_DB.channelKeyTs or 0 })
end

-- /moo key <secret>  (officers: sets it for the guild; "/moo key clear" removes it)
function ns.SetChannelKey(secret)
    if not ns.CROSS_GUILD then
        ns.Print("Cross-guild features are switched off in this build.")
        return
    end
    secret = cleanKey(secret)
    if secret == "" then
        ns.Print("Use /moo key <secret> (officers), or /moo key clear. " ..
            "Share the same secret with officers of the other Olympus guilds.")
        return
    end
    local clear = secret:lower() == "clear"
    if not ns.AmOfficer() then
        ns.Print("Only your guild master or officers (the rank right below) can set MOO's key. " ..
            "It reaches you automatically once they do.")
        return
    end
    applyKey(clear and "" or secret, ns.Now(), ns.Me())
    broadcastKey()
    ns.Print(clear and (ns.REQUIRE_KEY and "Key cleared for your guild. MOO now works inside your guild only."
            or "Key cleared for your guild. MOO is back on the open cross-guild channel.")
        or "Key set and sent to your guildmates. Cross-guild features are on for everyone in Olympus guilds that use the same secret.")
end

ns.Handle("K", function(sender, f, dist)
    if not ns.CROSS_GUILD then return end
    if dist ~= "GUILD" or not ns.IsOfficer(sender) then return end
    ns.Fire("KEY_HEARD")
    local ts = ns.Clamp(f[3], 0, ns.Now() + 120, 0)
    if ts <= (MOO_DB.channelKeyTs or 0) then return end   -- only newer keys replace older ones
    local had = MOO_DB.channelKey
    applyKey(f[2], ts, sender)
    if MOO_DB.channelKey and not had then
        ns.Print("Your officers sealed MOO's cross-guild channel with a key.")
    elseif not MOO_DB.channelKey then
        ns.Print(ns.REQUIRE_KEY and "Your officers turned off cross-guild features. MOO works inside your guild only."
            or "Your officers removed the key. MOO is back on the open cross-guild channel.")
    end
end)

-- Late login: ask officers for the key. One officer answers (random short delay, and an
-- officer who sees another answer first stays quiet).
local answering, lastAnswer = false, 0
ns.Handle("KR", function(sender, f, dist)
    if not ns.CROSS_GUILD or dist ~= "GUILD" or not ns.AmOfficer() or not MOO_DB.channelKeyTs then return end
    if answering or GetTime() - lastAnswer < 60 then return end
    answering = true
    C_Timer.After(1 + math.random() * 4, function()
        answering = false
        if GetTime() - lastAnswer < 60 then return end
        lastAnswer = GetTime()
        broadcastKey()
    end)
end)

-- Seeing any officer's K counts as an answer for other officers' throttles.
ns.Listen("KEY_HEARD", function() lastAnswer = GetTime() end)

ns.Listen("READY", function()
    requestRoster()
    C_Timer.NewTicker(120, requestRoster)
    C_Timer.After(20, function()
        if not ns.CROSS_GUILD or not ns.InOlympus() then return end
        if ns.AmOfficer() and MOO_DB.channelKeyTs then
            broadcastKey()                    -- keeps everyone online on the newest key
        else
            ns.Send("GUILD", { "KR" })
        end
    end)
end)

function ns.CrossGuildOn()
    if not ns.CROSS_GUILD or not MOO_DB then return false end
    return MOO_DB.channelKey ~= nil or not ns.REQUIRE_KEY
end

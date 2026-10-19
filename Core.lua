-- Muster Of Olympus (MOO)
-- Core: namespace, saved variables, event dispatch, Olympus guild check, slash commands.
-- Fan project. Not affiliated with Blizzard Entertainment, Asmongold or the Olympus leadership.

local ADDON, ns = ...
_G.MOO = ns

ns.VERSION = "0.11.0-alpha"
ns.PREFIX  = "MOO1"

-- Cross-guild: MOO users in every Olympus guild share one hidden channel.
-- REQUIRE_KEY = false (alpha): the channel works right away, no officer setup.
-- Officers can still seal it with /moo key <secret>; set REQUIRE_KEY = true to make
-- MOO stay inside each guild until an officer does.
ns.CROSS_GUILD = true
ns.REQUIRE_KEY = false

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
function ns.Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff8888ffMOO|r: " .. msg)
end

function ns.Now()
    return GetServerTime and GetServerTime() or time()
end

-- Midnight / Forever "secret values": never compute on them.
function ns.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Call an API safely; returns default on error or secret value.
function ns.Safe(default, fn, ...)
    if type(fn) ~= "function" then return default end
    local ok, a = pcall(fn, ...)
    if not ok or a == nil or ns.IsSecret(a) then return default end
    return a
end

-- Full "Name-Realm" so names from rosters and addon messages match.
-- One form for every player name: "Name-Realm", with your own realm always spelled
-- the same way (the server's capitalization can differ from GetNormalizedRealmName).
-- The name is kept whole, surname included.
local function myRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = (GetRealmName and GetRealmName() or ""):gsub("[%s%-]", "") end
    return r
end
ns.MyRealm = myRealm

function ns.FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local n, r = name:match("^(.-)%-([^%-]+)$")
    if not n then n, r = name, realm end
    n = strtrim(n)
    if n == "" then return nil end
    local mine = myRealm()
    if not r or r == "" then
        r = mine
    else
        r = r:gsub("%s", "")
        if mine ~= "" and r:lower() == mine:lower() then r = mine end
    end
    return n .. "-" .. r
end

-- The name to whisper or invite, written the way a player would type it:
-- same-realm players without a realm ("Screwston Eventhorizon"), others with it.
function ns.SendTarget(full)
    if type(full) ~= "string" then return full end
    local n, r = full:match("^(.-)%-([^%-]+)$")
    if n and r:lower() == myRealm():lower() then return n end
    return full
end

-- Names the server has actually stamped on my own messages (learned at login, see Comm.lua).
ns.myAliases = {}

function ns.IsMe(name)
    if type(name) ~= "string" then return false end
    local me = ns.Me()
    if me and name:lower() == me:lower() then return true end
    return ns.myAliases[name:lower()] == true
end

function ns.UnitFullName(unit)
    local name, realm = UnitName(unit)
    if not name or ns.IsSecret(name) then return nil end
    return ns.FullName(name, realm)
end

function ns.Me()
    if not ns.me then ns.me = ns.UnitFullName("player") end
    return ns.me
end

function ns.ShortName(full)
    return full and (Ambiguate and Ambiguate(full, "short") or full:match("^[^-]+")) or "?"
end

-- Strip characters used by the wire format and chat escapes.
function ns.Clean(text, maxBytes)
    text = tostring(text or ""):gsub("[%^,|\n\r\t]", " "):gsub("%s+", " ")
    text = strtrim(text)
    if maxBytes and #text > maxBytes then text = text:sub(1, maxBytes) end
    return text
end

-- Deterministic short hash (djb2, base36). Same result on every client.
function ns.Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    local chars, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    repeat
        local r = h % 36
        out = chars:sub(r + 1, r + 1) .. out
        h = math.floor(h / 36)
    until h == 0
    return out
end

------------------------------------------------------------------------
-- Validators for anything that arrives from another player.
-- Rule: text from the network is never shown unless it passed one of these,
-- so nobody can inject color codes, textures or fake links into MOO's UI.
------------------------------------------------------------------------
local VALID_ROLES = { TANK = true, HEAL = true, DPS = true }
local VALID_CATS = { DUNGEON = true, RAID = true, BG = true, WPVP = true }

function ns.ValidRole(r) return VALID_ROLES[r] and r or nil end
function ns.ValidCat(c) return VALID_CATS[c] and c or nil end
function ns.ValidClass(c)
    if type(c) ~= "string" or not RAID_CLASS_COLORS then return nil end
    return RAID_CLASS_COLORS[c] and c or nil
end

-- A character name as the game writes it: "Name-Realm", no escape codes,
-- no spaces or separators, sane length. UTF-8 letters (accented names) are fine.
function ns.SafeName(n)
    if type(n) ~= "string" or #n < 2 or #n > 64 then return nil end
    -- Forever names can have a surname, so single spaces between words are allowed
    if n:find("[%c\t\r\n|%^,:;=\\]") or n:find("  ") or n:find("^ ") or n:find(" $") then return nil end
    return n
end

-- A number within bounds, or the default. Rejects nan and infinity.
function ns.Clamp(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return default end
    return math.max(lo, math.min(hi, math.floor(v)))
end

-- Alert sounds respect the player's setting (/moo sound on|off).
function ns.Alert(sound, fallback)
    if MOO_DB and MOO_DB.sound == false then return end
    PlaySound(sound or fallback)
end

function ns.SetSound(on)
    MOO_DB.sound = on and true or false
    ns.Print(on and "Alert sounds on." or "Alert sounds off. Chat messages still tell you about new applicants.")
    ns.Fire("STATE_CHANGED")
end

function ns.ClassColor(classFile, text)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
    return text
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

-- Recent MOO errors, for /moo bug (kept in memory only, last 20)
ns.errors = {}
function ns.RecordError(where, err)
    table.insert(ns.errors, 1, { t = date("%H:%M:%S"), where = where, msg = tostring(err):sub(1, 300) })
    while #ns.errors > 20 do table.remove(ns.errors) end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.RecordError(event, err); geterrorhandler()(err) end
    end
end)

-- Simple message bus between modules.
local callbacks = {}
function ns.Listen(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end
function ns.Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ns.RecordError(name, err); geterrorhandler()(err) end
    end
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
local DB_DEFAULTS = {
    version  = 1,
    realms   = {},      -- [realmGroup] = { attest = {}, ratings = {}, given = {} }
    channelKey = nil,   -- optional shared secret to seal the hidden channel
    learned  = {},      -- [mapID] = { key, name } instances matched by name
    seenInstances = {}, -- [mapID] = { name, type, last } every instance visited
    minimap  = { angle = 200, hide = false },
    theme    = "classic",   -- or "dark"
    sound    = true,        -- alert sounds (new applicant, recruit request)
}

local CHAR_DEFAULTS = {
    optedIn  = false,
    role     = "DPS",   -- "TANK" | "HEAL" | "DPS"
}

local function applyDefaults(t, d)
    for k, v in pairs(d) do
        if t[k] == nil then
            t[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
    return t
end

function ns.RealmData()
    local key = GetNormalizedRealmName and GetNormalizedRealmName() or "default"
    local r = MOO_DB.realms[key]
    if not r then
        r = { attest = {}, ratings = {}, given = {} }
        MOO_DB.realms[key] = r
    end
    return r
end

------------------------------------------------------------------------
-- Olympus guild check (MOO's own, so it works even if Olympus is absent)
------------------------------------------------------------------------
local REJECT = { "anti", "hater", "against" }

function ns.IsOlympusGuildName(guild)
    if not guild or guild == "" then return false end
    local n = guild:lower():gsub("[^%a]", "")
    for _, bad in ipairs(REJECT) do
        if n:find(bad, 1, true) then return false end
    end
    -- olymp*, olimp*, olmp* cover OLYMPVS, Olympos, Olympuz, Olimpo, Olmps...
    local s, e = n:find("ol[yi]?mp")
    if not s then return false end
    local rest = n:sub(e + 1)
    -- Olympia / Olympic are other things; Olympian is an approved Olympus guild.
    if rest:find("^ian") then return true end
    if rest:find("^ia") or rest:find("^ic") then return false end
    return true
end

-- With Olympus's Board (Olympus.lua), MOO lets Olympus say who is a member.
function ns.WithOlympus()
    return ns.Olympus ~= nil and ns.Olympus.Integrated()
end

function ns.InOlympus()
    if ns.WithOlympus() then return ns.Olympus.IsMember() end
    if not IsInGuild() then return false end
    local guild = GetGuildInfo("player")
    return ns.IsOlympusGuildName(guild)
end

-- Is the Olympus addon loaded? Checks the folder name "Olympus", then any loaded
-- addon whose folder or title starts with "Olympus".
function ns.OlympusAddonLoaded()
    local A = C_AddOns
    local isLoaded = (A and A.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Olympus") then return true end
    local num = (A and A.GetNumAddOns and A.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
    local info = (A and A.GetAddOnInfo) or GetAddOnInfo
    for i = 1, num do
        local name, title = info(i)
        local n = (name or ""):lower()
        local t = (title or ""):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if (n:find("^olympus") or t:find("^olympus")) and isLoaded(i) then return true end
    end
    return false
end

-- Find the function behind a slash command (e.g. "/oly"), whichever addon registered it.
-- The game's hash_SlashCmdList is only filled after you've typed a command, so look
-- through SlashCmdList and the SLASH_<KEY><n> globals directly.
local function findSlashCommand(command)
    command = command:lower()
    for key, fn in pairs(SlashCmdList) do
        local i = 1
        while true do
            local alias = _G["SLASH_" .. key .. i]
            if not alias then break end
            if type(alias) == "string" and alias:lower() == command then return fn end
            i = i + 1
        end
    end
end

-- command: what follows /oly ("" opens the window, "privacy" its privacy page). Olympus registers
-- its own key, SlashCmdList.OLYMPUS; the alias search is the fallback for anything else.
function ns.OpenOlympus(command)
    command = type(command) == "string" and command or ""
    local list = type(SlashCmdList) == "table" and SlashCmdList or nil
    local fn = list and type(list.OLYMPUS) == "function" and list.OLYMPUS
        or findSlashCommand("/oly") or findSlashCommand("/olympus")
    if fn then
        local ok, err = pcall(fn, command)
        if not ok then
            ns.RecordError("open Olympus", err)
            ns.Print("Olympus couldn't open from here. Use its minimap button.")
        end
    elseif ns.OlympusAddonLoaded() then
        -- (Olympus registers no slash command at a gamepad-UI login.)
        ns.Print("Couldn't open Olympus from here. Use its minimap button" .. (command ~= "" and (", then /oly " .. command) or "") .. ".")
    else
        ns.Print("The Olympus addon is not loaded.")
    end
end

------------------------------------------------------------------------
-- Opt-in
------------------------------------------------------------------------
function ns.IsOptedIn()
    return MOO_CharDB and MOO_CharDB.optedIn
end

function ns.SetOptIn(on)
    MOO_CharDB.optedIn = on and true or false
    if on then
        ns.Print("You are opted in. You can list and join groups and be rated.")
    else
        ns.Print("You are opted out. Your listings were removed and you won't be rated from now on.")
        ns.Fire("OPTED_OUT")
    end
    ns.Fire("STATE_CHANGED")
end

function ns.RequireReady(action)
    if not ns.InOlympus() then
        ns.Print("MOO only works inside an Olympus guild.")
        return false
    end
    if not ns.IsOptedIn() then
        ns.Print("Opt in first (MOO window, or /moo optin) to " .. (action or "do that") .. ".")
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    MOO_DB = applyDefaults(MOO_DB or {}, DB_DEFAULTS)
    MOO_CharDB = applyDefaults(MOO_CharDB or {}, CHAR_DEFAULTS)
    ns.Fire("DB_READY")
end)

ns.On("PLAYER_LOGIN", function()
    ns.me = nil
    C_Timer.After(5, function()
        ns.Fire("READY")
        if ns.InOlympus() then
            local extra = ns.OlympusAddonLoaded() and (ns.Olympus and ns.Olympus.LoginNote() or "")
                or " (tip: install the Olympus addon too)"
            ns.Print("v" .. ns.VERSION .. " loaded. Type /mooo to open (plain /moo still moos)." .. extra)
            local _, _, rankIndex = GetGuildInfo("player")
            if ns.CROSS_GUILD and ns.REQUIRE_KEY and not MOO_DB.channelKey and rankIndex and rankIndex <= 1 then
                ns.Print("|cffffaa00Officer tip: cross-guild features are off until you set a key: /moo key <secret>. " ..
                    "Agree on the secret with the other Olympus officers.|r")
            end
        end
    end)
end)

------------------------------------------------------------------------
-- Slash commands
--
-- /moo is shared with the game's own /moo emote, on purpose:
--   /moo              -> moo (at your target, if you have one), like always
--   /moo Name         -> moo at that player, like always
--   /moo <command>    -> MOO addon command (open, rc, rate, who, help...)
-- Anything that isn't a MOO command moos. Forgot a command? You moo at someone.
-- /mooo (three o's) opens the window directly.
------------------------------------------------------------------------
local COMMANDS = {}

COMMANDS.open = function() ns.ToggleMain() end
COMMANDS.optin = function() ns.SetOptIn(true) end
COMMANDS.optout = function() ns.SetOptIn(false) end
COMMANDS.role = function(rest)
    local r = (rest or ""):upper()
    if r == "HEALER" then r = "HEAL" end
    if r == "TANK" or r == "HEAL" or r == "DPS" then
        MOO_CharDB.role = r
        ns.Print("Your default role is now " .. r .. ".")
        ns.Fire("STATE_CHANGED")
    else
        ns.Print("Use /moo role tank | heal | dps")
    end
end
COMMANDS.rc = function() ns.StartReadyCheck() end
COMMANDS.ready = COMMANDS.rc
COMMANDS.rate = function() ns.ShowRatingPrompt() end
COMMANDS.who = function(rest)
    if rest and rest ~= "" then ns.ShowProfile(ns.FullName(rest))
    else ns.Print("Use /moo who Name") end
end
COMMANDS.key = function(rest) ns.SetChannelKey(rest) end
COMMANDS.instance = function(rest) ns.InstanceCommand(rest) end
COMMANDS.instances = function(rest)
    if rest and rest:lower() == "export" then
        ns.ShowCopyBox("MOO instance IDs", ns.InstanceExportText())
    else
        ns.ListInstances()
    end
end
COMMANDS.status = function() ns.PrintStatus() end
-- Self-test: see and apply to your own listing, so one person can check that MOO's
-- messages really go out and come back. Session only: /reload turns it off.
COMMANDS.selftest = function(rest)
    local v = (rest or ""):lower()
    if v == "on" then
        ns.selfTest = true
        ns.Print("Self-test ON: your own listings show up and you can apply to them. " ..
            "List a group, wait a few seconds, then apply to it from the same tab. /moo selftest off or /reload ends it.")
    elseif v == "off" then
        ns.selfTest = false
        for leader in pairs(ns.listings or {}) do
            if ns.IsMe(leader) then ns.listings[leader] = nil end
        end
        ns.Print("Self-test off.")
    else
        ns.Print("Self-test is " .. (ns.selfTest and "on" or "off") .. ". Use /moo selftest on | off")
    end
    ns.Fire("LISTINGS_UPDATED")
end
COMMANDS.names = function()
    local n, r = UnitName("player")
    ns.Print("UnitName: [" .. tostring(n) .. "] realm: [" .. tostring(r) .. "]")
    ns.Print("GetRealmName: [" .. tostring(GetRealmName and GetRealmName()) .. "]  normalized: [" ..
        tostring(GetNormalizedRealmName and GetNormalizedRealmName()) .. "]")
    ns.Print("MOO thinks you are: [" .. tostring(ns.Me()) .. "]  and whispers you as: [" .. tostring(ns.SendTarget(ns.Me())) .. "]")
    ns.Print("The server stamps your messages as: [" .. tostring(ns.myStamped or "not learned yet") .. "]")
    ns.Print("Senders seen on MOO messages: " .. (ns.lastSenders and #ns.lastSenders > 0 and
        ("[" .. table.concat(ns.lastSenders, "] [") .. "]") or "none yet (list a group, then try again)"))
end
COMMANDS.sound = function(rest)
    local v = (rest or ""):lower()
    if v == "on" then ns.SetSound(true)
    elseif v == "off" then ns.SetSound(false)
    else ns.SetSound(MOO_DB.sound == false) end   -- no word: toggle
end
COMMANDS.theme = function(rest) ns.SetTheme((rest or ""):lower()) end
COMMANDS.coach = function() ns.ToggleMain(7) end
COMMANDS.feedback = function() ns.ToggleMain(8) end
COMMANDS.recruit = function(rest) ns.RecruitCommand(rest) end
COMMANDS.bug = function() ns.ShowCopyBox("MOO bug report: copy and paste this into your report", ns.BugReport()) end
COMMANDS.minimap = function() ns.SetMinimapButtonShown(MOO_DB.minimap.hide) end
COMMANDS.guide = function(rest)
    local want = (rest or ""):lower()
    for key, g in pairs(ns.GUIDES) do
        if want ~= "" and (key:find(want, 1, true) or g.title:lower():find(want, 1, true)) then
            ns.ShowGuide(key) return
        end
    end
    local names = {}
    for key in pairs(ns.GUIDES) do table.insert(names, key) end
    table.sort(names)
    ns.Print("Guides: " .. table.concat(names, ", ") .. "  (e.g. /moo guide marking)")
end
COMMANDS.suggestions = function(rest)
    local v = (rest or ""):lower()
    if v == "on" then ns.SetSuggestionsOn(true)
    elseif v == "off" then ns.SetSuggestionsOn(false)
    else ns.Print("Use /moo suggestions on | off") end
end
COMMANDS.help = function()
    ns.Print("/mooo or /moo open: open the window. Plain /moo (or /moo Name) still moos.")
    ns.Print("/moo optin | optout | role tank|heal|dps | rc | rate | who Name | coach | feedback | guide <topic> | suggestions on|off | minimap")
    ns.Print("/moo key <secret> | instance [link KEY | forget | keys] | instances [export] | status | bug | theme dark|classic | sound on|off | names | selftest on|off")
    if ns.IsRecruitOwner and ns.IsRecruitOwner() then
        ns.Print("/moo recruit on | off | link <link> | message <text> | send Name | list  (answer tester whispers)")
    end
end

local function moo(target)
    if target == "" then target = nil end
    DoEmote("MOO", target)
end

local function runCommand(input, openIfEmpty)
    input = strtrim(input or "")
    local cmd, rest = strsplit(" ", input, 2)
    local fn = COMMANDS[(cmd or ""):lower()]
    if fn then
        fn(rest and strtrim(rest) or nil)
    elseif openIfEmpty and input == "" then
        ns.ToggleMain()
    elseif openIfEmpty then
        COMMANDS.help()
    else
        moo(input)
    end
end

-- Keys differ from Blizzard's emote tokens so nothing of theirs is overwritten.
SLASH_MOOADDON1 = "/moo"
SlashCmdList["MOOADDON"] = function(input) runCommand(input, false) end

SLASH_MOOWINDOW1 = "/mooo"
SlashCmdList["MOOWINDOW"] = function(input) runCommand(input, true) end

function ns.PrintStatus()
    ns.Print("Version " .. ns.VERSION)
    ns.Print("Olympus guild: " .. (ns.InOlympus() and "yes" or "no") ..
        "  |  Olympus addon: " .. (ns.OlympusAddonLoaded() and "loaded" or "not loaded"))
    ns.Print("Opted in: " .. (ns.IsOptedIn() and "yes" or "no") .. "  |  Role: " .. MOO_CharDB.role)
    if ns.Olympus then ns.Print("Olympus link: " .. ns.Olympus.StatusText()) end
    ns.Print("Network channel: " .. (ns.ChannelStatus and ns.ChannelStatus() or "?"))
    if not ns.CROSS_GUILD then
        ns.Print("Cross-guild features are switched off in this build.")
    elseif not MOO_DB.channelKey and ns.REQUIRE_KEY then
        ns.Print("|cffffaa00Cross-guild features are off: MOO only works inside your guild until an officer " ..
            "sets a key with /moo key <secret> (use the same secret as the other Olympus guilds' officers).|r")
    elseif not MOO_DB.channelKey then
        ns.Print("Cross-guild channel: open (no key). Officers can optionally seal it with /moo key <secret>.")
    else
        ns.Print("Key set by " .. (MOO_DB.channelKeyBy and ns.ShortName(MOO_DB.channelKeyBy) or "you") ..
            (MOO_DB.channelKeyTs and (" on " .. date("%Y-%m-%d %H:%M", MOO_DB.channelKeyTs)) or "") .. ".")
    end
    ns.Print("Officer: " .. (ns.AmOfficer and ns.AmOfficer() and "yes" or "no"))
end

------------------------------------------------------------------------
-- Instance commands: MOO remembers every ID it sees (MOO_DB, account-wide)
------------------------------------------------------------------------
local HOW_TEXT = {
    known = "already remembered",
    name  = "matched by name and |cff33ff33remembered|r",
    added = "not in MOO's list, so it was |cff33ff33added and remembered|r",
}

function ns.InstanceCommand(rest)
    local sub, arg = strsplit(" ", strtrim(rest or ""), 2)
    sub = (sub or ""):lower()
    local name, kind, _, diffName, maxPlayers, _, _, mapID = GetInstanceInfo()
    if not kind or kind == "none" or not mapID then
        ns.Print("You are not in an instance. Enter one, then type /moo instance.")
        return
    end
    ns.LogInstance(mapID, name, kind)

    if sub == "link" then
        local key = arg and arg:upper()
        if key and ns.LinkInstance(mapID, key, name) then
            ns.Print("Remembered: ID " .. mapID .. " is " .. ns.InstanceName(key) .. " [" .. key .. "].")
        else
            ns.Print("Unknown key. Keys are in the list from /moo instance keys (e.g. DALA, THANES, BARROW).")
        end
        return
    elseif sub == "forget" then
        ns.ForgetInstance(mapID)
        ns.Print("Forgot what MOO remembered about ID " .. mapID .. ". Type /moo instance to match it again.")
        return
    elseif sub == "keys" then
        local cat = kind == "raid" and "RAID" or (kind == "pvp" and "BG" or "DUNGEON")
        local keys = {}
        for _, i in ipairs(ns.INSTANCES_BY_CAT[cat] or {}) do
            if not i.custom then table.insert(keys, i.key .. " = " .. i.name) end
        end
        ns.Print("Keys: " .. table.concat(keys, ", "))
        return
    end

    local inst, how = ns.ResolveInstance(mapID, name, kind)
    ns.Print(string.format("%s  |  %s, %s (%s players)  |  ID |cffffff00%s|r",
        name or "?", kind, diffName or "", tostring(maxPlayers), tostring(mapID)))
    if inst then
        ns.Print("MOO: " .. inst.name .. " [" .. inst.key .. "], " .. (HOW_TEXT[how] or "remembered") .. ".")
        if how == "name" or how == "added" then
            ns.Print("Wrong match? /moo instance link KEY (see /moo instance keys), or /moo instance forget.")
        end
    else
        ns.Print("MOO: not a group instance (" .. kind .. "), only logged.")
    end
end

function ns.ListInstances()
    local list = {}
    for id, e in pairs(MOO_DB.seenInstances or {}) do
        local inst = ns.MatchInstance(id, e.name)
        local status
        if not inst then status = "  |cff888888logged only|r"
        elseif inst.custom then status = " -> |cffffaa00added by MOO|r [" .. inst.key .. "]"
        else status = " -> " .. inst.key end
        table.insert(list, { id = id, text = string.format("%d = %s (%s)%s", id, e.name or "?", e.type or "?", status) })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    if #list == 0 then ns.Print("No instances seen yet. Enter one and try again.") return end
    for _, l in ipairs(list) do ns.Print(l.text) end
    ns.Print("Type /moo instances export for a copyable list.")
end

-- A small window with selectable text (chat can't be copied).
local copyBox
function ns.ShowCopyBox(title, text)
    if not copyBox then
        local ok, f = pcall(CreateFrame, "Frame", "MOOCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        if not ok then f = CreateFrame("Frame", "MOOCopyFrame2", UIParent) end
        f:SetSize(560, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, f:GetName())
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -6)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -32)
        sf:SetPoint("BOTTOMRIGHT", -32, 40)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(500)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("BOTTOM", 0, 14)
        hint:SetText("Ctrl+A to select all, Ctrl+C to copy.")
        ns.Themed(f)
        copyBox = f
    end
    copyBox.title:SetText(title)
    copyBox.eb:SetText(text)
    copyBox:Show()
    copyBox.eb:SetFocus()
    copyBox.eb:HighlightText()
end

------------------------------------------------------------------------
-- /moo bug: one block of text for bug reports. Never includes the channel key,
-- other players' names, or your ratings.
------------------------------------------------------------------------
function ns.BugReport()
    local L = {}
    local function add(...) table.insert(L, strjoin("", tostringall(...))) end
    add("What happened:  ")
    add("What you expected:  ")
    add("Steps to repeat:  ")
    add("")
    add("--- MOO ", ns.VERSION, " ---")
    local version, build, _, toc = GetBuildInfo()
    add("Game: ", version, " (", build, "), interface ", toc, ", locale ", GetLocale and GetLocale() or "?")
    add("Date: ", date("%Y-%m-%d %H:%M"))
    add("Olympus guild: ", ns.InOlympus() and "yes" or "no", "   Officer: ", (ns.AmOfficer and ns.AmOfficer()) and "yes" or "no")
    add("Olympus addon: ", ns.OlympusAddonLoaded() and "loaded" or "not loaded")
    if ns.Olympus then
        add("Olympus link: ", ns.Olympus.StatusText())
        if ns.WithOlympus() then add("Board listings seen: ", ns.Olympus.ListingCount()) end
    end
    add("Opted in: ", ns.IsOptedIn() and "yes" or "no", "   Role: ", MOO_CharDB and MOO_CharDB.role or "?",
        "   Private tips: ", (MOO_CharDB and MOO_CharDB.suggestionsOff) and "off" or "on")
    add("Cross-guild: ", ns.ChannelStatus and ns.ChannelStatus() or "?")
    add("In group: ", IsInRaid() and "raid" or (IsInGroup() and "party" or "no"),
        "   In instance: ", select(2, IsInInstance()) or "?")
    add("Listings seen: ", ns.listings and #(ns.SortedListings("DUNGEON")) + #(ns.SortedListings("RAID")) +
        #(ns.SortedListings("BG")) + #(ns.SortedListings("WPVP")) or 0,
        "   Available players: ", ns.available and #(ns.SortedAvailable()) or 0,
        "   My listing: ", ns.myListing and ns.myListing.inst or "none",
        "   Applicants: ", ns.applicants and #(ns.SortedApplicants()) or 0)
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    add("Ratings about me: ", count(MOO_CharDB and MOO_CharDB.aboutMe), "   Ratings I gave: ", count(MOO_CharDB and MOO_CharDB.given),
        "   Waiting to deliver: ", count(MOO_CharDB and MOO_CharDB.outbox), "   Pending rating windows: ",
        MOO_CharDB and MOO_CharDB.pending and #MOO_CharDB.pending or 0)
    if MOO_CharDB and MOO_CharDB.activeRun then
        add("Active run: ", MOO_CharDB.activeRun.inst, " (map ", MOO_CharDB.activeRun.mapID, ")")
    end
    local unmatched = {}
    for id, e in pairs(MOO_DB.seenInstances or {}) do
        local inst = ns.MatchInstance(id, e.name)
        if not inst or inst.custom then table.insert(unmatched, id .. "=" .. (e.name or "?")) end
    end
    table.sort(unmatched)
    add("Unmatched instances: ", #unmatched > 0 and table.concat(unmatched, "; ") or "none")
    add("BugSack/BugGrabber: ", (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BugGrabber")) and "loaded" or "not loaded")
    add("")
    if #ns.errors == 0 then
        add("Recent MOO errors: none caught this session")
    else
        add("Recent MOO errors (newest first):")
        for _, e in ipairs(ns.errors) do add(e.t, " [", e.where, "] ", e.msg) end
    end
    return table.concat(L, "\n")
end

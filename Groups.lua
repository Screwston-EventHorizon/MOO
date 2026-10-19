-- MOO Groups: list a group, mark yourself available, apply, invite.
--
-- * Listings and "available" flags go to Olympus MOO users on your realm (guild + hidden
--   channel), repeated every 90 s while up, and drop off 4 minutes after the last repeat.
-- * Applying is a whisper (addon message) to the leader only, with your gear and stats.
-- * Every invite comes from the leader clicking Invite. MOO never invites, accepts,
--   queues or joins anything by itself.
-- * With Olympus's Board (Olympus.lua), the listings, flags and applications are Olympus's:
--   nothing here goes out, and Invite and Decline go through Olympus.

local _, ns = ...

local REFRESH = 90
local EXPIRE = 240

ns.listings = {}       -- [leader] = listing
ns.available = {}      -- [name] = { cat, inst, role, lvl, class, note, ts }
ns.applicants = {}     -- [name] = { id, role, lvl, class, ilvl, note, ts, state }
ns.myApplications = {} -- [leader] = { id, role, state, ts }
ns.myListing = nil
ns.myAvailable = nil

local function myClass() return select(2, UnitClass("player")) end

-- Custom instances (key C<mapID>) travel with their name so other clients can show them.
local function customName(key)
    local e = ns.INSTANCE_BY_KEY[key]
    return (e and e.custom) and ns.Clean(e.name, 40) or ""
end

-- Custom instances from other players are display-only (see ns.LearnRemoteInstance).
local function learnCustom(key, name)
    ns.LearnRemoteInstance(key, name)
end
local function myLevel() return UnitLevel("player") end

------------------------------------------------------------------------
-- Listing a group
------------------------------------------------------------------------
-- Who is in my group right now, as "Name-Realm:ROLE:CLASS" entries.
local function myMembers()
    local out = {}
    if IsInGroup() and ns.GroupRoster then
        for _, m in ipairs(ns.GroupRoster()) do
            table.insert(out, m.name .. ":" .. (m.role or "?") .. ":" .. (m.class or ""))
        end
    else
        table.insert(out, ns.Me() .. ":" .. MOO_CharDB.role .. ":" .. (myClass() or ""))
    end
    return out
end

local function sendListing()
    local l = ns.myListing
    if not l or ns.WithOlympus() then return end
    ns.Send("NET", { "L", l.id, l.cat, l.inst, l.t, l.h, l.d, l.min, myLevel(), myClass(), l.note, customName(l.inst) })
    -- the group's members follow in one or more "LM" messages, so everyone can see their ratings
    local chunk, size, seq = {}, 0, 0
    local function flush()
        if #chunk == 0 then return end
        seq = seq + 1
        ns.Send("NET", { "LM", l.id, seq, table.concat(chunk, ",") })
        chunk, size = {}, 0
    end
    for _, e in ipairs(myMembers()) do
        if size + #e + 1 > 190 then flush() end
        table.insert(chunk, e)
        size = size + #e + 1
    end
    flush()
end

-- Re-announce the listing a few seconds after the group changes (members joined/left).
-- At most once every 30 s, so a raid filling up doesn't flood the channel.
local resendPending, lastResend = false, 0
local function resendSoon()
    if resendPending or not ns.myListing then return end
    resendPending = true
    local wait = math.max(5, 30 - (GetTime() - lastResend))
    C_Timer.After(wait, function()
        resendPending = false
        lastResend = GetTime()
        sendListing()
    end)
end

function ns.PostListing(cat, inst, t, h, d, minLvl, note)
    if ns.WithOlympus() then ns.Olympus.OpenListingDialog(ns.Olympus.KindOfCat(cat)) return end
    if not ns.RequireReady("list a group") then return end
    if IsInGroup() and not UnitIsGroupLeader("player") then
        ns.Print("Only the group leader can list the group.")
        return
    end
    ns.myListing = {
        id = ns.Hash(ns.Me() .. ns.Now()):sub(1, 6),
        cat = cat, inst = inst,
        t = math.max(0, tonumber(t) or 0), h = math.max(0, tonumber(h) or 0), d = math.max(0, tonumber(d) or 0),
        min = math.max(1, tonumber(minLvl) or 1),
        note = ns.Clean(note, 60),
        ts = ns.Now(),
    }
    ns.applicants = {}
    sendListing()
    ns.Print("Group listed: " .. ns.InstanceName(inst) .. ".")
    ns.Fire("LISTINGS_UPDATED")
end

function ns.UpdateNeeds(t, h, d)
    local l = ns.myListing
    if not l or ns.WithOlympus() then return end
    l.t, l.h, l.d = math.max(0, t), math.max(0, h), math.max(0, d)
    sendListing()
    ns.Fire("LISTINGS_UPDATED")
end

function ns.Delist(silent)
    if not ns.myListing then return end
    ns.Send("NET", { "X", ns.myListing.id }, nil, true)
    for name, a in pairs(ns.applicants) do
        if a.state == "new" then ns.Send("WHISPER", { "JD", a.id }, name) end
    end
    ns.myListing = nil
    ns.applicants = {}
    if not silent then ns.Print("Listing removed.") end
    ns.Fire("LISTINGS_UPDATED")
end

local function validId(id)
    return type(id) == "string" and #id >= 1 and #id <= 12 and id:match("^%w+$") ~= nil
end

ns.Handle("L", function(sender, f)
    if ns.WithOlympus() then return end
    local id, cat, inst = f[2], ns.ValidCat(f[3]), f[4]
    if not validId(id) or not cat or not validId(inst) then return end
    learnCustom(inst, f[12])
    if not ns.IsKnownInstanceKey(inst) then return end
    local known = ns.INSTANCE_BY_KEY[inst]
    if known and known.cat ~= cat then return end
    ns.listings[sender] = {
        id = id, leader = sender, cat = cat, inst = inst,
        t = ns.Clamp(f[5], 0, 40, 0), h = ns.Clamp(f[6], 0, 40, 0), d = ns.Clamp(f[7], 0, 40, 0),
        min = ns.Clamp(f[8], 1, 60, 1), lvl = ns.Clamp(f[9], 0, 60, 0), class = ns.ValidClass(f[10]),
        note = ns.Clean(f[11], 60), ts = GetTime(),
    }
    ns.Fire("LISTINGS_UPDATED")
end)

ns.listingMembers = {}   -- [leader] = { id=, list = { {name, role, class}, ... } }

local MAX_MEMBERS = 40

ns.Handle("LM", function(sender, f)
    if ns.WithOlympus() then return end
    local id, seq, list = f[2], ns.Clamp(f[3], 1, 20, nil), f[4]
    if not validId(id) or not seq or not list then return end
    local l = ns.listings[sender]
    if not l or l.id ~= id then return end          -- only for a listing we know
    local lm = ns.listingMembers[sender]
    if not lm or lm.id ~= id or seq == 1 then
        lm = { id = id, list = {}, seen = {} }
        ns.listingMembers[sender] = lm
    end
    for entry in list:gmatch("[^,]+") do
        if #lm.list >= MAX_MEMBERS then break end
        local name, role, class = strsplit(":", entry)
        name = ns.SafeName(name) and ns.FullName(name)
        if name and not lm.seen[name] then
            lm.seen[name] = true
            table.insert(lm.list, { name = name, role = ns.ValidRole(role), class = ns.ValidClass(class) })
        end
    end
    ns.Fire("LISTINGS_UPDATED")
end)

-- Members of a listing (falls back to just the leader for older versions).
function ns.ListingMembers(l)
    if ns.myListing and l == ns.myListing then
        local out = {}
        for _, e in ipairs(myMembers()) do
            local name, role, class = strsplit(":", e)
            table.insert(out, { name = name, role = ns.ROLE_LABEL[role] and role or nil, class = class })
        end
        return out
    end
    local lm = ns.listingMembers[l.leader]
    if lm and lm.id == l.id and #lm.list > 0 then return lm.list end
    return { { name = l.leader, class = l.class } }
end

ns.Handle("X", function(sender, f)
    local l = ns.listings[sender]
    if l and l.id == f[2] then
        ns.listings[sender] = nil
        ns.listingMembers[sender] = nil
        if ns.myApplications[sender] then ns.myApplications[sender].state = "closed" end
        ns.Fire("LISTINGS_UPDATED")
    end
end)

------------------------------------------------------------------------
-- Marking yourself available (shows on the Players tab, leaders can invite you)
------------------------------------------------------------------------
local MAX_AVAIL_INSTANCES = 12
local LIST_SEP = ","   -- inside one field: keys or roles

-- Names of custom instances (C<mapID>) among the keys, as "C123=Name;C456=Name".
local function customNames(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local n = customName(k):gsub("[;=]", " ")
        if n ~= "" then table.insert(parts, k .. "=" .. n) end
    end
    local out = table.concat(parts, ";")
    return #out > 60 and out:sub(1, 60) or out
end

local function sendAvailable()
    local a = ns.myAvailable
    if not a or ns.WithOlympus() then return end
    ns.Send("NET", { "W", a.cat, table.concat(a.insts, LIST_SEP), table.concat(a.roles, LIST_SEP),
        myLevel(), myClass(), a.note, customNames(a.insts) })
end

-- insts: list of instance keys ({"ANY"} = anything in the category); roles: list of roles
function ns.SetAvailable(cat, insts, roles, note)
    if ns.WithOlympus() then ns.Print("Raise your flag on Olympus's Board: that's where leaders look.") return end
    if not ns.RequireReady("mark yourself available") then return end
    local keys = {}
    for _, k in ipairs(insts or {}) do
        if k == "ANY" then keys = { "ANY" } break end
        if ns.INSTANCE_BY_KEY[k] and #keys < MAX_AVAIL_INSTANCES then table.insert(keys, k) end
    end
    if #keys == 0 then keys = { "ANY" } end
    local rl = {}
    for _, r in ipairs(ns.ROLES) do
        for _, want in ipairs(roles or {}) do if want == r then table.insert(rl, r) end end
    end
    if #rl == 0 then rl = { MOO_CharDB.role } end
    ns.myAvailable = { cat = cat, insts = keys, roles = rl, note = ns.Clean(note, 60) }
    ns.myAvailableReminded = nil
    sendAvailable()
    ns.Print("You are listed as available for " .. ns.AvailableWhereText(cat, keys) ..
        " as " .. ns.RolesText(rl) .. ".")
    ns.Fire("LISTINGS_UPDATED")
end

function ns.ClearAvailable(silent)
    if not ns.myAvailable then return end
    ns.myAvailable = nil
    ns.Send("NET", { "WX" }, nil, true)
    if not silent then ns.Print("You are no longer listed as available.") end
    ns.Fire("LISTINGS_UPDATED")
end

ns.Handle("W", function(sender, f)
    if ns.WithOlympus() then return end
    local cat = ns.ValidCat(f[2])
    if not cat then return end
    for entry in (f[8] or ""):gmatch("[^;]+") do
        local key, name = entry:match("^(C%d+)=(.+)$")
        if key then learnCustom(key, name) end
    end
    local insts = {}
    for k in (f[3] or ""):gmatch("[^,]+") do
        if k == "ANY" or ns.IsKnownInstanceKey(k) then table.insert(insts, k) end
        if #insts >= MAX_AVAIL_INSTANCES then break end
    end
    if #insts == 0 then insts = { "ANY" } end
    local roles = {}
    local seenRole = {}
    for r in (f[4] or ""):gmatch("[^,]+") do
        if ns.ValidRole(r) and not seenRole[r] then seenRole[r] = true; table.insert(roles, r) end
    end
    if #roles == 0 then roles = { "DPS" } end
    ns.available[sender] = {
        cat = cat, insts = insts, roles = roles,
        lvl = ns.Clamp(f[5], 0, 60, 0), class = ns.ValidClass(f[6]), note = ns.Clean(f[7], 60), ts = GetTime(),
    }
    ns.Fire("LISTINGS_UPDATED")
end)

function ns.RolesText(roles)
    local parts = {}
    for _, r in ipairs(roles or {}) do table.insert(parts, ns.RoleText(r)) end
    return table.concat(parts, "/")
end

-- "Any dungeon", "Blackrock Depths", or "Blackrock Depths, Stratholme +2"
function ns.AvailableWhereText(cat, insts)
    if not insts or #insts == 0 or insts[1] == "ANY" then
        local label = cat
        for _, c in ipairs(ns.CATEGORIES) do if c.key == cat then label = c.label end end
        return "any " .. label:lower():gsub("s$", "")
    end
    if #insts <= 2 then
        local names = {}
        for _, k in ipairs(insts) do table.insert(names, ns.InstanceName(k)) end
        return table.concat(names, ", ")
    end
    return ns.InstanceName(insts[1]) .. ", " .. ns.InstanceName(insts[2]) .. " +" .. (#insts - 2)
end

-- Does an available player fit a listing (same category, wants that instance or
-- anything, and plays a role the group still needs)?
function ns.AvailableMatches(a, l)
    if not l or a.cat ~= l.cat then return false end
    local instOk = false
    for _, k in ipairs(a.insts) do if k == "ANY" or k == l.inst then instOk = true end end
    if not instOk then return false end
    if (l.t or 0) + (l.h or 0) + (l.d or 0) == 0 then return true end
    local need = { TANK = (l.t or 0) > 0, HEAL = (l.h or 0) > 0, DPS = (l.d or 0) > 0 }
    for _, r in ipairs(a.roles) do if need[r] then return true end end
    return false
end

ns.Handle("WX", function(sender)
    if ns.available[sender] then
        ns.available[sender] = nil
        ns.Fire("LISTINGS_UPDATED")
    end
end)

------------------------------------------------------------------------
-- Applying
------------------------------------------------------------------------
function ns.Apply(leader, role, note)
    if ns.WithOlympus() then return end   -- applications are Olympus's (its card's Apply)
    if not ns.RequireReady("apply") then return end
    local l = ns.listings[leader]
    if not l then ns.Print("That listing is gone.") return end
    if InCombatLockdown() then ns.Print("Wait until you are out of combat.") return end
    role = role or MOO_CharDB.role
    ns.Send("WHISPER", { "J", l.id, role, myLevel(), myClass(), ns.AverageItemLevel(), ns.Clean(note, 60) }, leader)
    ns.SendGearTo(leader, l.id)
    ns.SendRatingSummaryTo(leader, l.id)
    ns.myApplications[leader] = { id = l.id, role = role, state = "sent", ts = ns.Now() }
    ns.Print("Applied to " .. ns.ShortName(leader) .. "'s " .. ns.InstanceName(l.inst) .. " group as " .. ns.ROLE_LABEL[role] .. ".")
    ns.Fire("LISTINGS_UPDATED")
end

function ns.CancelApplication(leader)
    local a = ns.myApplications[leader]
    if not a then return end
    ns.Send("WHISPER", { "JC", a.id }, leader)
    ns.myApplications[leader] = nil
    ns.Fire("LISTINGS_UPDATED")
end

local lastApplyAlert = {}

ns.Handle("J", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local l = ns.myListing
    if not l or f[2] ~= l.id then return end
    local role = ns.ValidRole(f[3]) or "DPS"
    local class = ns.ValidClass(f[5])
    local prev = ns.applicants[sender]
    ns.applicants[sender] = {
        id = l.id, role = role,
        lvl = ns.Clamp(f[4], 0, 60, 0), class = class, ilvl = ns.Clamp(f[6], 0, 1000, 0),
        note = ns.Clean(f[7], 60), ts = ns.Now(),
        state = (prev and prev.state ~= "new") and prev.state or "new",   -- re-applying can't undo a decline
    }
    ns.gearAllowed[sender] = GetTime()
    -- one sound and chat line per applicant per 30 s, so re-sending can't spam you
    if not lastApplyAlert[sender] or GetTime() - lastApplyAlert[sender] > 30 then
        lastApplyAlert[sender] = GetTime()
        ns.Alert(SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE, 880)
        ns.Print(ns.ClassColor(class, ns.ShortName(sender)) .. " wants to join as " .. ns.RoleText(role) ..
            ". Type /mooo, My Group.")
    end
    ns.Fire("APPLICANTS_UPDATED")
end)

ns.Handle("JC", function(sender, f)
    local a = ns.applicants[sender]
    if a and not a.olympus and a.id == f[2] then
        ns.applicants[sender] = nil
        ns.Fire("APPLICANTS_UPDATED")
    end
end)

ns.Handle("JD", function(sender, f)
    local a = ns.myApplications[sender]
    if a and a.id == f[2] and a.state == "sent" then
        a.state = "declined"
        ns.Print(ns.ShortName(sender) .. " declined your application. Thanks for applying!")
        ns.Fire("LISTINGS_UPDATED")
    end
end)

ns.Handle("JI", function(sender, f)
    local a = ns.myApplications[sender]
    if a and a.id == f[2] then
        a.state = "invited"
        ns.Print(ns.ShortName(sender) .. " invited you. Accept the invite in the game's window.")
        ns.Fire("LISTINGS_UPDATED")
    end
end)

------------------------------------------------------------------------
-- Leader actions (all from button clicks)
------------------------------------------------------------------------
function ns.InviteName(name)
    local target = ns.SendTarget(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(target)
    elseif InviteUnit then
        InviteUnit(target)
    end
end

function ns.InviteApplicant(name)
    if ns.WithOlympus() then return ns.Olympus.InviteApplicant(name) end
    local a = ns.applicants[name]
    ns.InviteName(name)
    if a then
        a.state = "invited"
        ns.Send("WHISPER", { "JI", a.id }, name)
        ns.Fire("APPLICANTS_UPDATED")
    end
end

function ns.DeclineApplicant(name)
    if ns.WithOlympus() then return ns.Olympus.DeclineApplicant(name) end
    local a = ns.applicants[name]
    if not a then return end
    a.state = "declined"
    ns.Send("WHISPER", { "JD", a.id }, name)
    ns.Fire("APPLICANTS_UPDATED")
end

------------------------------------------------------------------------
-- Upkeep
------------------------------------------------------------------------
local function tick()
    local now = GetTime()
    local changed = false
    for k, l in pairs(ns.listings) do
        if now - l.ts > EXPIRE then ns.listings[k] = nil; ns.listingMembers[k] = nil; changed = true end
    end
    for k, a in pairs(ns.available) do
        if now - a.ts > EXPIRE then ns.available[k] = nil; changed = true end
    end
    if changed then ns.Fire("LISTINGS_UPDATED") end
end

local function refresh()
    if not ns.InOlympus() or not ns.IsOptedIn() then return end
    sendListing()
    sendAvailable()
end

-- Mark applicants who joined; drop "available" once you're in a group for it.
ns.On("GROUP_ROSTER_UPDATE", function()
    local changed = false
    for _, u in ipairs(ns.GroupUnits()) do
        local n = ns.UnitFullName(u)
        local a = n and ns.applicants[n]
        if a and a.state ~= "joined" then a.state = "joined"; changed = true end
    end
    if changed then ns.Fire("APPLICANTS_UPDATED") end
    local av = ns.myAvailable
    if av and IsInGroup() and #av.roles > 1 and not ns.myAvailableReminded then
        ns.myAvailableReminded = true
        ns.Print("You joined a group while listed as " .. ns.RolesText(av.roles) ..
            ". Pick the role you'll play for this run with /moo role tank|heal|dps (it's the role you'll be rated in). " ..
            "You're still listed as available; \"Remove me\" on the Players tab takes you off.")
    end
    if ns.myListing and IsInGroup() and not UnitIsGroupLeader("player") then
        ns.Delist()
    else
        resendSoon()
    end
end)

ns.Listen("OPTED_OUT", function()
    ns.Delist(true)
    ns.ClearAvailable(true)
    for leader in pairs(ns.myApplications) do ns.CancelApplication(leader) end
end)

ns.On("PLAYER_LOGOUT", function()
    -- nothing to send on logout (the game may drop it); listings simply expire.
end)

ns.Listen("READY", function()
    C_Timer.NewTicker(30, tick)
    C_Timer.NewTicker(REFRESH, refresh)
end)

-- Helpers for the UI
function ns.SortedListings(cat)
    local out = {}
    for _, l in pairs(ns.listings) do
        if l.cat == cat then table.insert(out, l) end
    end
    table.sort(out, function(a, b) return a.ts > b.ts end)
    return out
end

function ns.SortedAvailable(filterCat)
    local out = {}
    for name, a in pairs(ns.available) do
        local keep
        if filterCat == "MATCH" then keep = ns.AvailableMatches(a, ns.myListing)
        else keep = not filterCat or a.cat == filterCat end
        if keep then
            local row = CopyTable(a); row.name = name
            table.insert(out, row)
        end
    end
    table.sort(out, function(a, b) return a.ts > b.ts end)
    return out
end

function ns.SortedApplicants()
    local out = {}
    for name, a in pairs(ns.applicants) do
        local row = CopyTable(a); row.name = name
        table.insert(out, row)
    end
    local order = { new = 1, invited = 2, joined = 3, declined = 4 }
    table.sort(out, function(a, b)
        if order[a.state] ~= order[b.state] then return (order[a.state] or 9) < (order[b.state] or 9) end
        return a.ts < b.ts
    end)
    return out
end

function ns.NeedsText(l)
    local parts = {}
    if l.t > 0 then table.insert(parts, "|c" .. ns.ROLE_COLOR.TANK .. l.t .. " Tank|r") end
    if l.h > 0 then table.insert(parts, "|c" .. ns.ROLE_COLOR.HEAL .. l.h .. " Healer|r") end
    if l.d > 0 then table.insert(parts, "|c" .. ns.ROLE_COLOR.DPS .. l.d .. " DPS|r") end
    return #parts > 0 and table.concat(parts, " ") or "|cff888888full|r"
end

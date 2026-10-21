-- MOO Olympus: MOO on top of the Olympus addon's Board, when the player wants it.
--
-- With an Olympus build that offers its group API ("groups", "groups.manage" and
-- "ui.board-groups") and the player's Yes on Olympus's privacy page, MOO works as the
-- heavier layer of Olympus's Board ("with Olympus"):
--   * Membership comes from Olympus (GetProfile().member), not from MOO's guild-name check.
--   * MOO sends no listings and no "available" flags of its own and stays off MOOnet:
--     every group and every player looking is on Olympus's Board, so everyone with
--     Olympus sees them. MOO's Dungeons, Raids, PvP and Players tabs show that data, and
--     "List a group" and "Apply" open Olympus's own dialog and card (the player clicks there).
--   * MOO's My Group panel takes the Board's "Your group" area (Olympus keeps a switch
--     to show its own). Invite, Decline and Delist go through Olympus, and so does
--     inviting a player looking.
--   * Gear, stats and rating summaries still travel on MOO's own whispers: the leader's MOO
--     asks an applicant Olympus reports, and the applicant's MOO answers only a leader
--     whose listing Olympus says it applied to.
--   * Ratings, the coach, the ready check and feedback work as always.
-- Without such an Olympus, before the player answers, or after a No, MOO works on its own
-- exactly as before.
--
-- Everything Olympus returns is data: names, words and numbers are checked field by field
-- before MOO shows or uses them, and every call is guarded.

local ADDON, ns = ...

local Oly = {}
ns.Olympus = Oly

local NEEDED = { "groups", "groups.manage", "ui.board-groups" }
local KINDS = { dungeon = true, raid = true, pvp = true, quest = true }
local CAT_KIND = { DUNGEON = "dungeon", RAID = "raid", BG = "pvp", WPVP = "pvp", QUEST = "quest" }
local KIND_LABEL = { dungeon = "dungeon", raid = "raid", pvp = "PvP", quest = "quest" }
local ROLE_IN = { tank = "TANK", healer = "HEAL", damage = "DPS" }
local ROLE_OUT = { TANK = "tank", HEAL = "healer", DPS = "damage" }
-- Olympus writes classes as the chats' two-letter codes.
local CLASS_FILE = { WA = "WARRIOR", PA = "PALADIN", HU = "HUNTER", RO = "ROGUE", PR = "PRIEST",
    SH = "SHAMAN", MA = "MAGE", WL = "WARLOCK", DR = "DRUID", DK = "DEATHKNIGHT" }
local LOOKING_KINDS = { dungeon = true, raid = true, pvp = true }
local PANEL_HEIGHT = 480       -- MOO's My Group page, in the Board's panel frame
local APPLIED = { waiting = "waiting", invited = "invited", declined = "declined" }
local APPLICANT_STATE = { waiting = "new", invited = "invited" }

local MAX_ROWS = 300           -- listings or players looking kept from one read
local MAX_APPLICANTS = 40
local LOOKING_EVERY = 10       -- seconds between reads of the players looking, when no event tells MOO
local GEAR_WAIT = 60           -- how long a leader's gear request waits for Olympus to report the application
local MAX_WAITING = 10         -- gear requests waiting at once, so asks without an application cannot pile up

local handle                   -- MOO's handle from OlympusAPI.Register
local why = "absent"           -- why MOO has no handle: "absent", "old", "features", "error" or Register's reason
local status = "none"          -- the player's answer: "pending", "granted" or "refused"
local eventsOk = false         -- Olympus took MOO's callbacks for GROUPS_CHANGED and MY_GROUP_CHANGED
local lookingEvent = false     -- and for LOOKING_CHANGED
local integrated = false
local member                   -- GetProfile().member, while with Olympus
local groups = {}              -- GetGroups(), checked, in the Board's order
local looking, lookingAt = {}, nil
local mine                     -- GetMyGroup(), checked
local asked = {}               -- [applicant .. "|" .. token] = true: one gear request per application
local waiting = {}             -- [leader] = { token =, t = }: gear requests waiting for Olympus's report
local panel = { registered = false, built = {} }

------------------------------------------------------------------------
-- Guarded access: OlympusAPI and the handle are another addon's tables
------------------------------------------------------------------------
local function Field(t, k)
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

local function Has(feature)
    if type(OlympusAPI) ~= "table" then return false end
    local has = Field(OlympusAPI, "Has")
    if type(has) ~= "function" then return false end
    local ok, yes = pcall(has, feature)
    return ok and yes == true
end

-- handle:method(...), never raising; returns its first two results, or nil and a reason.
local function Call(method, ...)
    if not handle then return nil, "unavailable" end
    local fn = Field(handle, method)
    if type(fn) ~= "function" then return nil, "unavailable" end
    local ok, a, b = pcall(fn, handle, ...)
    if not ok then
        ns.RecordError("Olympus " .. method, a)
        return nil, "error"
    end
    return a, b
end

local function Guard(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.RecordError("Olympus " .. where, err) end
end

------------------------------------------------------------------------
-- What Olympus returns, checked field by field
------------------------------------------------------------------------
-- Cut to max bytes without splitting an accented letter.
local function Cut(s, max)
    if #s <= max then return s end
    local j = max
    while j > 0 do
        local b = s:byte(j + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        j = j - 1
    end
    return s:sub(1, j)
end

-- Words to show: no escape codes, no control characters, no wire separators.
local function Words(v, max)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[|%^%c]", " "):gsub("%s+", " ")
    v = strtrim(v)
    if v == "" then return nil end
    return Cut(v, max)
end

local function Name(v)
    if type(v) ~= "string" or not ns.SafeName(v) then return nil end
    return ns.FullName(v)
end

local function Id(v)
    if type(v) ~= "string" or #v < 1 or #v > 128 or v:find("[%c|]") then return nil end
    return v
end

local function Class(v)
    return type(v) == "string" and ns.ValidClass(CLASS_FILE[v] or v) or nil
end

local function Place(v)
    if type(v) ~= "string" or #v > 24 or not v:match("^[%w_]+$") then return nil end
    return v
end

-- A PvP place MOO knows as a battleground keeps its ratings; any other is World PvP (none).
local function CatOf(kind, place)
    if kind == "pvp" then
        local inst = place and ns.INSTANCE_BY_KEY[place]
        return (inst and inst.cat == "BG") and "BG" or "WPVP"
    end
    return (kind == "dungeon" and "DUNGEON") or (kind == "raid" and "RAID") or (kind == "quest" and "QUEST") or nil
end

local function Listing(g)
    if type(g) ~= "table" then return nil end
    local id, kind, leader = Id(g.id), KINDS[g.kind] and g.kind, Name(g.leader)
    if not id or not kind or not leader then return nil end
    local need = type(g.need) == "table" and g.need or {}
    local anyNumber = type(need.anyNumber) == "table" and need.anyNumber or {}
    local row = {
        olympus = true, id = id, kind = kind, leader = leader,
        place = Place(g.place), placeName = Words(g.placeName, 40), questTitle = Words(g.questTitle, 40),
        zone = Words(g.zone, 30), -- (a quest's zone, when the Board gives one)
        guild = Words(g.guild, 48), class = Class(g.class),
        lvl = ns.Clamp(g.level, 0, 60, 0), min = ns.Clamp(g.minLevel, 1, 60, 1), size = ns.Clamp(g.size, 0, 40, 0),
        t = ns.Clamp(need.tank, 0, 40, 0), h = ns.Clamp(need.healer, 0, 40, 0), d = ns.Clamp(need.damage, 0, 40, 0),
        any = need.any == true,
        anyNumber = { TANK = anyNumber.tank == true, HEAL = anyNumber.healer == true, DPS = anyNumber.damage == true },
        note = Words(g.note, 80) or "",
        own = g.own == true,
        applied = APPLIED[g.applied],
        members = {},
    }
    row.cat = CatOf(kind, row.place)
    local counted = 0
    if type(g.members) == "table" then
        for i = 1, math.min(#g.members, 40) do
            local m = g.members[i]
            local count = type(m) == "table" and ns.Clamp(m.count, 0, 40, 0) or 0
            if count > 0 then
                table.insert(row.members, { class = Class(m.class), role = ROLE_IN[m.role], count = count })
                counted = counted + count
            end
        end
    end
    if row.size == 0 then row.size = math.max(1, counted) end
    return row
end

local function Looking(r)
    if type(r) ~= "table" then return nil end
    local name, kind = Name(r.name), LOOKING_KINDS[r.kind] and r.kind
    if not name or not kind then return nil end
    local roles = {}
    local rs = type(r.roles) == "table" and r.roles or {}
    for _, role in ipairs({ "tank", "healer", "damage" }) do
        if rs[role] == true then table.insert(roles, ROLE_IN[role]) end
    end
    local insts = {}
    if type(r.places) == "table" then
        for i = 1, math.min(#r.places, 12) do
            local p = Place(r.places[i])
            if p then table.insert(insts, p) end
        end
    end
    if #insts == 0 then insts = { "ANY" } end
    return {
        olympus = true, name = name, kind = kind, guild = Words(r.guild, 48), class = Class(r.class),
        lvl = ns.Clamp(r.level, 0, 60, 0), roles = roles, insts = insts, fits = r.fits == true and r.own ~= true, note = "",
        own = r.own == true, -- the player's own flag on the Board
    }
end

local function MyGroup(m)
    if type(m) ~= "table" then return nil end
    local out = { listing = Listing(m.listing), applicants = {}, members = {} }
    if type(m.applicants) == "table" then
        for i = 1, math.min(#m.applicants, MAX_APPLICANTS) do
            local a = m.applicants[i]
            local olyName = type(a) == "table" and type(a.name) == "string" and ns.SafeName(a.name) and a.name
            local state = olyName and APPLICANT_STATE[a.state]
            local role = olyName and ROLE_IN[a.role]
            if olyName and state and role then
                table.insert(out.applicants, {
                    name = ns.FullName(olyName), olyName = olyName, role = role, olyRole = a.role,
                    lvl = ns.Clamp(a.level, 0, 60, 0), class = Class(a.class),
                    note = Words(a.note, 80) or "", state = state,
                })
            end
        end
    end
    if type(m.members) == "table" then
        for i = 1, math.min(#m.members, 40) do
            local x = m.members[i]
            local name = type(x) == "table" and Name(x.name)
            if name then
                table.insert(out.members, { name = name, class = Class(x.class), lvl = ns.Clamp(x.level, 0, 60, 0), role = ROLE_IN[x.role] })
            end
        end
    end
    return out
end

-- Group members only: the realm part of a unit's name can read differently than the server's
-- (WoW: Forever's unit functions give "First-Surname" for "First Surname-Realm"). Display only.
local function Forms(n)
    n = n:lower()
    return n, (n:match("^(.-)%-[^%-]+$") or n), (n:gsub("%-", " ", 1))
end

local function SameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local a1, a2, a3 = Forms(a)
    local b1, b2, b3 = Forms(b)
    return a1 == b1 or a2 == b2 or a3 == b2 or a2 == b3
end

local function InMyGroup(name)
    for _, m in ipairs(mine and mine.members or {}) do
        if SameName(m.name, name) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Taking Olympus's data
------------------------------------------------------------------------
-- A short id for one of my listings, the same after a /reload: the applicant's MOO echoes it
-- on its gear and rating whispers, so they count only for that application.
function Oly.Token(listingId)
    return ns.Hash("olympus|" .. tostring(listingId) .. "|" .. (ns.Me() or "")):sub(1, 8)
end

local function ValidToken(t)
    return type(t) == "string" and #t >= 1 and #t <= 12 and t:match("^%w+$") ~= nil
end

local function TakeProfile(p)
    if type(p) ~= "table" then return end
    local was = member
    member = p.member == true
    if was ~= member then ns.Fire("STATE_CHANGED") end
end

local function AppliedTo(leader)
    for _, g in ipairs(groups) do
        if g.leader == leader and (g.applied == "waiting" or g.applied == "invited") then return true end
    end
    return false
end

-- Requests that waited for Olympus to report the application (or for combat to end).
local answerQueued
local function AnswerWaiting()
    local left = false
    for leader, w in pairs(waiting) do
        if GetTime() - w.t > GEAR_WAIT or not integrated then
            waiting[leader] = nil
        elseif AppliedTo(leader) and not InCombatLockdown() then
            waiting[leader] = nil
            ns.AnswerGearRequest(leader, w.token, true)
        else
            left = true
        end
    end
    if left and not answerQueued then
        answerQueued = true
        C_Timer.After(5, function() answerQueued = false; Guard("gear", AnswerWaiting) end)
    end
end

local function TakeGroups(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, math.min(#list, MAX_ROWS) do
            local row = Listing(list[i])
            if row then table.insert(out, row) end
        end
    end
    groups = out
    AnswerWaiting()
end

local function TakeLooking(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, math.min(#list, MAX_ROWS) do
            local r = Looking(list[i])
            if r then table.insert(out, r) end
        end
    end
    looking = out
end

-- The leader's MOO asks each new applicant's MOO for gear, stats and rating summary.
local function AskGear(name, token)
    local key = name .. "|" .. token
    if asked[key] then return end
    asked[key] = true
    ns.gearAllowed[name] = GetTime()
    ns.Send("WHISPER", { "GR", token }, name)
end

local function TakeMine(m)
    mine = MyGroup(m)
    local listing = mine and mine.listing
    local token = listing and Oly.Token(listing.id)
    local fresh = {}
    if token then
        for _, a in ipairs(mine.applicants) do
            local prev = ns.applicants[a.name]
            local gear = ns.gearSeen[a.name]
            fresh[a.name] = {
                olympus = true, id = token, olyName = a.olyName, role = a.role, olyRole = a.olyRole,
                lvl = a.lvl, class = a.class, ilvl = gear and gear.ilvl or 0, note = a.note,
                state = InMyGroup(a.name) and "joined" or a.state,
                ts = prev and prev.ts or ns.Now(),
            }
            AskGear(a.name, token)
        end
    end
    ns.applicants = fresh
end

local retryQueued
local function ReadAll()
    if not integrated then return end
    local busy = false
    local p, r1 = Call("GetProfile")
    if type(p) == "table" then TakeProfile(p) elseif r1 == "busy" then busy = true end
    local g, r2 = Call("GetGroups")
    if type(g) == "table" then TakeGroups(g) elseif r2 == "busy" then busy = true else TakeGroups(nil) end
    local m, r3 = Call("GetMyGroup")
    if type(m) == "table" then TakeMine(m) elseif r3 == "busy" then busy = true else TakeMine(nil) end
    local l, r4 = Call("GetLooking")
    lookingAt = GetTime()
    if type(l) == "table" then TakeLooking(l) elseif r4 == "busy" then busy = true else TakeLooking(nil) end
    if busy and not retryQueued then
        retryQueued = true
        C_Timer.After(5, function()
            retryQueued = false
            Guard("read", ReadAll)
            ns.Fire("LISTINGS_UPDATED"); ns.Fire("APPLICANTS_UPDATED")
        end)
    end
end

------------------------------------------------------------------------
-- With Olympus or on its own
------------------------------------------------------------------------
function Oly.Integrated() return integrated end
-- MOO's line on Olympus's privacy page still waits for the player's answer (the link would work).
function Oly.AwaitingAnswer() return not integrated and handle ~= nil and eventsOk and status == "pending" end
function Oly.IsMember() return member == true end

local RefreshBuilt

-- Registered while with Olympus; taken off after a No, so the Board's own comes back.
local function RegisterPanel()
    if panel.registered then return end
    local ok, reason = Call("RegisterGroupPanel", {
        label = "Muster Of Olympus (MOO)",
        build = function(frame) Guard("panel", panel.Build, frame) end,
        refresh = function(frame) Guard("panel", RefreshBuilt, frame) end,
    })
    panel.registered = ok == true or reason == "registered"
    panel.why = (not panel.registered) and (reason or "failed") or nil
end

local function UnregisterPanel()
    if not panel.registered then return end
    local ok, reason = Call("UnregisterGroupPanel")
    if ok == true or reason == "unregistered" then panel.registered = false end
end

local function Enter()
    -- What MOO had up on its own network comes down first (MOO's own "gone" messages).
    local had = ns.myListing ~= nil or ns.myAvailable ~= nil or next(ns.myApplications or {}) ~= nil
    ns.Delist(true)
    ns.ClearAvailable(true)
    for leader in pairs(ns.myApplications or {}) do ns.CancelApplication(leader) end
    integrated = true
    ns.applicants = {}
    ReadAll()
    RegisterPanel()
    -- MOOnet carries only listings and flags: leave it once those last messages went out.
    C_Timer.After(5, function() if integrated then ns.JoinChannel() end end)
    if had then
        ns.Print("MOO now uses Olympus's Board for groups. What you had up in MOO's own finder was taken down: list or apply again from the Board.")
    end
end

local function Leave()
    integrated = false
    member, mine = nil, nil
    groups, looking, lookingAt, waiting = {}, {}, nil, {}
    ns.applicants = {}
    UnregisterPanel()
    ns.JoinChannel()
end

function Oly.Evaluate()
    if handle then
        local s = Call("Status")
        if s == "pending" or s == "granted" or s == "refused" then status = s end
    end
    local want = handle ~= nil and eventsOk and status == "granted"
    if want ~= integrated then
        if want then Enter() else Leave() end
        ns.Fire("STATE_CHANGED"); ns.Fire("LISTINGS_UPDATED"); ns.Fire("APPLICANTS_UPDATED")
        Oly.RefreshPanel()
    end
end

local function Listen(event, fn)
    return Call("On", event, function(_, data) Guard(event, fn, data) end) == true
end

local function Setup()
    if type(OlympusAPI) ~= "table" then why = "absent" return end
    local version = Field(OlympusAPI, "VERSION")
    if type(version) ~= "number" or version < 1 then why = "old" return end
    for _, f in ipairs(NEEDED) do
        if not Has(f) then why = "features" return end
    end
    local register = Field(OlympusAPI, "Register")
    if type(register) ~= "function" then why = "features" return end
    local ok, h, reason = pcall(register, ADDON)
    if not ok then why = "error" ns.RecordError("Olympus Register", h) return end
    if type(h) ~= "table" then why = reason or "refused" return end
    handle = h
    Listen("PERMISSION_CHANGED", function(s)
        if s == "granted" or s == "refused" then status = s end
        Oly.Evaluate()
    end)
    Listen("PROFILE_CHANGED", function(p) if integrated then TakeProfile(p) end end)
    local a = Listen("GROUPS_CHANGED", function(list)
        if not integrated then return end
        TakeGroups(list)
        ns.Fire("LISTINGS_UPDATED")
    end)
    local b = Listen("MY_GROUP_CHANGED", function(m)
        if not integrated then return end
        TakeMine(m)
        ns.Fire("APPLICANTS_UPDATED")
    end)
    lookingEvent = Listen("LOOKING_CHANGED", function(list)
        if not integrated then return end
        TakeLooking(list)
        lookingAt = GetTime()
        ns.Fire("LISTINGS_UPDATED")
    end)
    eventsOk = a and b
end
Setup()

-- Before MOO's network starts (Comm.lua joins MOOnet on READY, after this). An Olympus that
-- wasn't ready when MOO loaded gets one more try here.
ns.Listen("READY", function()
    if not handle and (why == "absent" or why == "features" or why == "consent") then Setup() end
    Oly.Evaluate()
end)

ns.Listen("GEAR_UPDATED", function(name)
    local a = integrated and name and ns.applicants[name]
    local g = a and ns.gearSeen[name]
    if g and g.ilvl then a.ilvl = g.ilvl end
end)

------------------------------------------------------------------------
-- Gear requests from a leader (Gear.lua hands them here while with Olympus)
------------------------------------------------------------------------
local lastFreshRead = 0
function Oly.GearAsked(leader, token)
    if not integrated or not ValidToken(token) then return end
    if AppliedTo(leader) and not InCombatLockdown() then
        ns.AnswerGearRequest(leader, token, true)
        return
    end
    -- Olympus may not have told MOO about this application yet: wait for it, a minute at most.
    if not waiting[leader] then
        local n = 0
        for _ in pairs(waiting) do n = n + 1 end
        if n >= MAX_WAITING then return end
    end
    waiting[leader] = { token = token, t = GetTime() }
    if GetTime() - lastFreshRead >= 5 then
        lastFreshRead = GetTime()
        local list = Call("GetGroups")
        if type(list) == "table" then TakeGroups(list) return end
    end
    AnswerWaiting()
end

------------------------------------------------------------------------
-- The Board's panel: MOO's My Group page in Olympus's "Your group" area
------------------------------------------------------------------------
local function ShowBuilt(b)
    b.page:SetShown(integrated)
    b.notice:SetShown(not integrated)
    if integrated and b.page.Refresh then b.page:Refresh() end
end

function panel.Build(frame)
    if panel.built[frame] then return ShowBuilt(panel.built[frame]) end
    frame:SetHeight(PANEL_HEIGHT)
    local b = { page = ns.UI.MyGroupPage(frame), notice = ns.UI.Text(frame, "GameFontHighlight") }
    b.notice:SetPoint("TOPLEFT", 8, -8)
    b.notice:SetPoint("RIGHT", -8, 0)
    b.notice:SetWordWrap(true)
    b.notice:SetText("MOO works on its own right now (answer MOO's line on Olympus's privacy page, /oly privacy). " ..
        "Pick \"Olympus's own\" above to see your group here.")
    panel.built[frame] = b
    ShowBuilt(b)
end

RefreshBuilt = function(frame)
    local b = panel.built[frame]
    if b then ShowBuilt(b) else panel.Build(frame) end
end

local refreshQueued
function Oly.RefreshPanel()
    if not panel.registered or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function()
        refreshQueued = false
        Call("RefreshGroupPanel")
    end)
end

------------------------------------------------------------------------
-- For MOO's tabs
------------------------------------------------------------------------
function Oly.KindOfCat(cat) return CAT_KIND[cat] end

-- The Board's listings for these MOO categories, in the Board's order.
function Oly.Listings(cats)
    local want, out = {}, {}
    for _, c in ipairs(cats or {}) do want[c] = true end
    for _, g in ipairs(groups) do
        if g.cat and want[g.cat] then table.insert(out, g) end
    end
    return out
end

function Oly.ListingCount()
    local n = 0
    for _, g in ipairs(groups) do if g.cat then n = n + 1 end end
    return n
end

-- The Board's players looking. filter: nil/"ALL", "MATCH" (fits my listing) or a MOO category.
function Oly.Looking(filter)
    if not integrated then return {} end
    -- LOOKING_CHANGED keeps them current; without it, a read now and then
    if not lookingEvent and (not lookingAt or GetTime() - lookingAt >= LOOKING_EVERY) then
        lookingAt = GetTime()
        local rows, reason = Call("GetLooking")
        if type(rows) == "table" then TakeLooking(rows) elseif reason ~= "busy" then TakeLooking(nil) end
    end
    local kind = filter and CAT_KIND[filter]
    local out, seen = {}, {}
    for _, r in ipairs(looking) do
        local keep = (filter == "MATCH" and r.fits) or (kind and r.kind == kind) or (not kind and filter ~= "MATCH")
        -- a flag that names two kinds is in both sections: once here, unless one kind is asked
        if keep and (kind or not seen[r.name]) then
            seen[r.name] = true
            table.insert(out, r)
        end
    end
    return out
end

function Oly.MyListing() return integrated and mine and mine.listing or nil end

-- A quest listing from the Board for a quest in my own log (by its title: the Board gives no quest ID).
function Oly.HaveQuest(l)
    if not (l and l.kind == "quest" and l.questTitle and ns.MyQuests) then return false end
    for _, e in ipairs(ns.MyQuests()) do
        if e.title and ns.Clean(e.title, 40) == l.questTitle then return true end
    end
    return false
end

-- The role a group member's leader set for him on the Board, as MOO writes roles.
function Oly.MemberRole(name)
    if not integrated then return nil end
    for _, m in ipairs(mine and mine.members or {}) do
        if m.role and SameName(m.name, name) then return m.role end
    end
end

local function InstName(key)
    local inst = key and ns.INSTANCE_BY_KEY[key]
    return inst and inst.name or key
end

function Oly.PlaceText(l)
    if l.kind == "quest" then return l.questTitle or "Quest" end
    return l.placeName or InstName(l.place) or ("Any " .. KIND_LABEL[l.kind])
end

-- What a listing still needs; a role that takes any number reads "1+".
function Oly.NeedsText(l)
    local parts = {}
    for _, role in ipairs(ns.ROLES) do
        local n = (role == "TANK" and l.t) or (role == "HEAL" and l.h) or l.d
        if n > 0 then
            local count = (l.anyNumber and l.anyNumber[role]) and (n .. "+") or tostring(n)
            table.insert(parts, "|c" .. ns.ROLE_COLOR[role] .. count .. " " .. ns.ROLE_LABEL[role] .. "|r")
        end
    end
    return #parts > 0 and table.concat(parts, " ") or "|cff888888full|r"
end

-- The first role a player looking plays (any, when his flag names none) that my listing still needs.
local function RoleFor(a, l)
    local plays = {}
    for _, r in ipairs(a.roles or {}) do plays[r] = true end
    local any = next(plays) == nil
    for _, role in ipairs(ns.ROLES) do
        local n = (role == "TANK" and l.t) or (role == "HEAL" and l.h) or l.d
        if n > 0 and (any or plays[role]) then return role end
    end
end

function Oly.WantsText(a)
    if a.insts[1] == "ANY" then return "any " .. KIND_LABEL[a.kind] end
    local names = {}
    for i = 1, math.min(2, #a.insts) do table.insert(names, InstName(a.insts[i])) end
    local text = table.concat(names, ", ")
    if #a.insts > 2 then text = text .. " +" .. (#a.insts - 2) end
    return text
end

------------------------------------------------------------------------
-- Actions: each one opens or runs Olympus's own, from the player's click
------------------------------------------------------------------------
local REASONS = {
    pending = "answer MOO's line on Olympus's privacy page first (/oly privacy)",
    refused = "you said No to MOO on Olympus's privacy page",
    guild = "you're not in an Olympus guild",
    busy = "Olympus is busy, try again in a few seconds",
    combat = "wait until you're out of combat",
    ["not-leader"] = "only the listing's leader can do that",
    unknown = "that listing or applicant is gone",
    role = "the listing doesn't want that role any more",
    unavailable = "this Olympus can't do that",
    invited = "already invited, waiting for them to join",
    invite = "the game refused the invite",
    kind = "Olympus doesn't know that kind of group",
    failed = "Olympus couldn't do it",
}

local function Refused(what, reason)
    ns.Print(what .. ": " .. (REASONS[reason] or "Olympus said no") .. ".")
end

function Oly.OpenListingDialog(kind)
    if not integrated then return false end
    local ok, reason = Call("OpenListingDialog", KINDS[kind] and kind or nil)
    if ok ~= true then Refused("Couldn't open Olympus's listing dialog", reason) end
    return ok == true
end

function Oly.OpenGroup(id)
    if not integrated or not Id(id) then return false end
    local ok, reason = Call("OpenGroup", id)
    if ok ~= true then Refused("Couldn't open that group on Olympus's Board", reason) end
    return ok == true
end

function Oly.OpenFlagDialog(kind)
    if not integrated then return false end
    local ok, reason = Call("OpenFlagDialog", LOOKING_KINDS[kind] and kind or nil)
    if ok ~= true then Refused("Couldn't open Olympus's flag", reason) end
    return ok == true
end

function Oly.LowerListing()
    if not integrated then return false end
    local ok, reason = Call("LowerListing")
    if ok ~= true then Refused("Couldn't take your listing down", reason) end
    return ok == true
end

-- Invite a player looking, as a role my listing still needs, the Board's "Invite as" way.
function Oly.InviteLooking(a)
    if not integrated or type(a) ~= "table" or not a.olympus then return false end
    local l = mine and mine.listing
    if not l then
        ns.Print("List a group on the Board first: Olympus invites a player looking as a role your listing needs.")
        return false
    end
    local role = RoleFor(a, l)
    if not role then
        ns.Print("Your listing doesn't need a role " .. ns.ShortName(a.name) .. " plays.")
        return false
    end
    local ok, reason = Call("InviteLooking", a.name, ROLE_OUT[role])
    if ok ~= true then Refused("Olympus couldn't invite " .. ns.ShortName(a.name), reason) end
    return ok == true
end

function Oly.InviteApplicant(name)
    local a = integrated and ns.applicants[name]
    if not a or not a.olympus then return false end
    local ok, reason = Call("InviteApplicant", a.olyName, a.olyRole)
    if ok ~= true then
        Refused("Olympus couldn't invite " .. ns.ShortName(name), reason)
        return false
    end
    a.state = "invited"
    ns.Fire("APPLICANTS_UPDATED")
    return true
end

function Oly.DeclineApplicant(name)
    local a = integrated and ns.applicants[name]
    if not a or not a.olympus then return false end
    local ok, reason = Call("DeclineApplicant", a.olyName)
    if ok ~= true then
        Refused("Olympus couldn't decline " .. ns.ShortName(name), reason)
        return false
    end
    a.state = "declined"
    ns.Fire("APPLICANTS_UPDATED")
    return true
end

------------------------------------------------------------------------
-- Status lines
------------------------------------------------------------------------
local WHY = {
    absent = "not loaded (MOO works on its own)",
    old = "too old for MOO's link (MOO works on its own)",
    features = "this version has no group API yet (MOO works on its own)",
}

function Oly.StatusText()
    if integrated then
        local text = "with Olympus's Board (listings, applications and players looking are Olympus's)"
        if panel.why then text = text .. "; My Group panel not on the Board (" .. tostring(panel.why) .. ")" end
        return text
    end
    if not handle then return WHY[why] or ("not linked (" .. tostring(why) .. "); MOO works on its own") end
    if not eventsOk then return "its group events are missing (MOO works on its own)" end
    if status == "refused" then return "you said No on Olympus's privacy page (MOO works on its own)" end
    return "waiting for your answer to MOO's line on Olympus's privacy page, /oly privacy (MOO works on its own)"
end

function Oly.LoginNote()
    if integrated then return " Groups are on Olympus's Board; MOO adds gear, ratings and the ready check." end
    if handle and eventsOk and status == "pending" then
        return " To use Olympus's Board for groups, answer MOO's line on Olympus's privacy page (/oly privacy)."
    end
    return ""
end


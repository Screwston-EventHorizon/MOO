-- MOO Ratings
--
-- Ratings live with the people they're about. No broadcasting, no shared database:
--   1. MOO notices when your group enters a dungeon or raid and remembers who was in it.
--   2. Afterwards you rate groupmates (1-5 stars + compliments). Each rating is whispered
--      straight to that player, and resent until their MOO confirms it arrived.
--   3. Your MOO keeps the ratings about you, but only from players its own record shows
--      were in that run with you. The role and instance come from your own record too.
--   4. When you apply to a group, your rating summary goes to the leader with your gear,
--      and when you join a group it's shared with the group. Nobody else ever sees it.
--   5. The leader's MOO quietly checks a few of your ratings with the players who gave them
--      (if they're online). If one doesn't match, your rating simply isn't shown.
--   6. A role's score only shows once 3 different players have rated it.
--
-- The run id is the same on every member's client: instance + group leader + UTC day.

local _, ns = ...

local MIN_RUN_SECONDS = 300            -- shorter runs aren't rated
local OUT_GRACE = 90                   -- stay out this long before the run counts as over
local KEEP_DAYS = 180
local MIN_RATERS = 3

ns.MIN_RATERS = MIN_RATERS
ns.groupInfo = {}                      -- [name] = { opt=bool, role=, ver= } from party/raid hello

------------------------------------------------------------------------
-- Group hello: who in my group has MOO, is opted in, and what role they play
------------------------------------------------------------------------
local helloPending
local function sendHello()
    helloPending = nil
    if not IsInGroup() or not ns.InOlympus() then return end
    ns.Send("GROUP", { "H", ns.VERSION, ns.IsOptedIn() and 1 or 0, MOO_CharDB.role })
end

function ns.QueueHello()
    if helloPending then return end
    helloPending = true
    C_Timer.After(3, sendHello)
end

ns.Handle("H", function(sender, f, dist)
    if dist ~= "PARTY" and dist ~= "RAID" then return end
    local isNew = not ns.groupInfo[sender]
    ns.groupInfo[sender] = { ver = ns.Clean(f[2], 12), opt = f[3] == "1", role = ns.ValidRole(f[4]) }
    if isNew then ns.QueueHello() end
    ns.Fire("GROUP_INFO")
end)

ns.Listen("STATE_CHANGED", function() ns.QueueHello() end)

------------------------------------------------------------------------
-- Roster helpers
------------------------------------------------------------------------
function ns.GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do table.insert(units, "raid" .. i) end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, GetNumSubgroupMembers() do table.insert(units, "party" .. i) end
    end
    return units
end

local function leaderName()
    for _, u in ipairs(ns.GroupUnits()) do
        if UnitIsGroupLeader(u) then return ns.UnitFullName(u) end
    end
    return "noleader"
end

local function utcDay()
    return date("!%Y%m%d", ns.Now())
end

------------------------------------------------------------------------
-- Run tracking
------------------------------------------------------------------------
local function run() return MOO_CharDB.activeRun end

local function addRoster()
    local r = run()
    if not r then return end
    for _, u in ipairs(ns.GroupUnits()) do
        local n = ns.UnitFullName(u)
        if n and n ~= ns.Me() then
            local gi = ns.groupInfo[n]
            local e = r.roster[n] or {}
            e.class = e.class or select(2, UnitClass(u))
            if gi then e.aol = gi.opt; e.role = gi.role end
            r.roster[n] = e
        end
    end
end

local function startRun(mapID, instName)
    local inst = ns.ResolveInstance(mapID, instName, "party")
    local key = inst and inst.key or ("I" .. tostring(mapID))
    local leader = leaderName()
    local day = utcDay()
    MOO_CharDB.activeRun = {
        -- the map ID (not the name) goes in the id, so every client language agrees
        id = ns.Hash(tostring(mapID) .. "|" .. leader .. "|" .. day),
        inst = key, mapID = mapID, name = instName,
        start = ns.Now(), lastIn = ns.Now(), roster = {},
    }
    addRoster()
end

local function finishRun()
    local r = run()
    MOO_CharDB.activeRun = nil
    if not r then return end
    if (r.lastIn - r.start) < MIN_RUN_SECONDS then return end
    local members = {}
    for name, e in pairs(r.roster) do
        local gi = ns.groupInfo[name]
        members[name] = {
            class = e.class,
            aol = (gi and gi.opt) or e.aol or false,
            role = (gi and gi.role) or e.role,
        }
    end
    if not next(members) then return end
    if ns.IsOptedIn() then
        MOO_CharDB.runs = MOO_CharDB.runs or {}
        local names = {}
        for n in pairs(members) do names[n] = true end
        table.insert(MOO_CharDB.runs, 1, { id = r.id, inst = r.inst, role = MOO_CharDB.role, ts = ns.Now(), roster = names })
        while #MOO_CharDB.runs > 60 do table.remove(MOO_CharDB.runs) end
    end
    local pending = { id = r.id, inst = r.inst, name = r.name, members = members, ts = ns.Now() }
    MOO_CharDB.pending = MOO_CharDB.pending or {}
    table.insert(MOO_CharDB.pending, 1, pending)
    while #MOO_CharDB.pending > 3 do table.remove(MOO_CharDB.pending) end
    if ns.IsOptedIn() then
        ns.ShowRatingPrompt(pending)
    end
end

local outSince
local function checkZone()
    if not MOO_CharDB then return end
    local instName, kind, _, _, _, _, _, mapID = GetInstanceInfo()
    if kind and kind ~= "none" and mapID then
        ns.LogInstance(mapID, instName, kind)
        local inst, how = ns.ResolveInstance(mapID, instName, kind)
        if how == "added" then
            ns.Print("New instance remembered: " .. (instName or "?") .. " (ID " .. mapID .. "). It's in the group finder now.")
        end
    end
    local r = run()
    if (kind == "party" or kind == "raid") and IsInGroup() then
        outSince = nil
        if not r or r.mapID ~= mapID then
            if r then finishRun() end
            startRun(mapID, instName)
        else
            r.lastIn = ns.Now()
            addRoster()
        end
    elseif r then
        outSince = outSince or GetTime()
        -- dead and running back, or hearthed for a moment: wait before closing the run
        if GetTime() - outSince >= OUT_GRACE and not UnitIsDeadOrGhost("player") then
            outSince = nil
            finishRun()
        end
    end
end

ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, checkZone) end)
ns.On("ZONE_CHANGED_NEW_AREA", checkZone)
ns.On("GROUP_ROSTER_UPDATE", function()
    if run() and ns.InRestrictedInstance() then addRoster() end
    ns.QueueHello()
    local present = {}
    for _, u in ipairs(ns.GroupUnits()) do
        local n = ns.UnitFullName(u)
        if n then present[n] = true end
    end
    for name in pairs(ns.groupInfo) do
        if not present[name] then ns.groupInfo[name] = nil end
    end
    ns.Fire("GROUP_INFO")
end)
ns.Listen("READY", function()
    C_Timer.NewTicker(15, checkZone)
end)

------------------------------------------------------------------------
-- Storage (per character): ratings about me, and ratings I gave
------------------------------------------------------------------------
local MAX_STORED = 3000
local TAG_LIMIT = 2 ^ 13

local function aboutMe() MOO_CharDB.aboutMe = MOO_CharDB.aboutMe or {}; return MOO_CharDB.aboutMe end
local function given() MOO_CharDB.given = MOO_CharDB.given or {}; return MOO_CharDB.given end

function ns.MyRun(runId)
    for _, r in ipairs(MOO_CharDB.runs or {}) do
        if r.id == runId then return r end
    end
    local a = MOO_CharDB.activeRun
    if a and a.id == runId then
        local names = {}
        for n in pairs(a.roster or {}) do names[n] = true end
        return { id = a.id, inst = a.inst, role = MOO_CharDB.role, roster = names }
    end
end

-- Written with %d so every copy of MOO produces exactly the same text (no "5" vs "5.0").
local function digest(runId, stars, tags)
    return ns.Hash(string.format("%s|%d|%d", runId, math.floor(stars + 0.5), math.floor(tags + 0.5)))
end

-- Names can reach MOO spelled slightly differently (surname, realm capitalization),
-- so record lookups compare the first name and realm, ignoring case.
function ns.LooseSame(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local function key(x)
        local n, r = x:match("^(.-)%-([^%-]+)$")
        n = (n or x):match("^(%S+)") or ""
        return (n .. "-" .. (r or "")):lower()
    end
    return key(a) == key(b)
end

------------------------------------------------------------------------
-- Giving a rating
------------------------------------------------------------------------
function ns.SubmitRating(runId, ratee, stars, tags)
    if not ns.IsOptedIn() then return end
    stars = math.max(1, math.min(5, math.floor(tonumber(stars) or 0)))
    tags = math.floor(tonumber(tags) or 0) % TAG_LIMIT
    given()[runId .. ">" .. ratee] = { run = runId, ratee = ratee, stars = stars, tags = tags, ts = ns.Now() }
    ns.Deliver("RT", ratee, { runId, string.format("%d", stars), string.format("%d", tags) })
end

-- A rating arrives: keep it only if the rater was in that run with me.
ns.Handle("RT", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local id, runId = f[2], f[3]
    ns.Ack(sender, id)                                   -- stop their retries either way
    if not ns.IsOptedIn() or type(runId) ~= "string" or #runId > 12 then return end
    local stars = ns.Clamp(f[4], 0, 5, 0)
    local tags = ns.Clamp(f[5], 0, TAG_LIMIT - 1, 0)
    if stars < 1 then return end
    local r = ns.MyRun(runId)
    if not r then return end
    local inRun = false
    for n in pairs(r.roster or {}) do if ns.LooseSame(n, sender) then inRun = true break end end
    if not inRun then return end
    aboutMe()[runId .. ">" .. sender] = {
        run = runId, rater = sender, stars = stars, tags = tags,
        role = r.role or "DPS", inst = r.inst or "?", ts = ns.Now(),
    }
    ns.Fire("RATINGS_UPDATED", ns.Me())
end)

------------------------------------------------------------------------
-- My profile, built from the ratings about me
------------------------------------------------------------------------
local function myProfile()
    local p = { roles = {}, inst = {}, tags = {}, total = 0, mine = true }
    local cutoff = ns.Now() - KEEP_DAYS * 86400
    for _, r in pairs(aboutMe()) do
        if r.ts >= cutoff then
            local role = r.role
            local pr = p.roles[role]
            if not pr then pr = { sum = 0, count = 0, raters = {}, nRaters = 0, tags = {} }; p.roles[role] = pr end
            pr.sum, pr.count = pr.sum + r.stars, pr.count + 1
            if not pr.raters[r.rater] then pr.raters[r.rater] = true; pr.nRaters = pr.nRaters + 1 end
            p.inst[r.inst] = p.inst[r.inst] or {}
            local pi = p.inst[r.inst][role]
            if not pi then pi = { sum = 0, count = 0, raters = {}, nRaters = 0 }; p.inst[r.inst][role] = pi end
            pi.sum, pi.count = pi.sum + r.stars, pi.count + 1
            if not pi.raters[r.rater] then pi.raters[r.rater] = true; pi.nRaters = pi.nRaters + 1 end
            for _, t in ipairs(ns.TAGS) do
                if ns.TagMaskHas(r.tags or 0, t.bit) then
                    p.tags[t.bit] = (p.tags[t.bit] or 0) + 1
                    pr.tags[t.bit] = (pr.tags[t.bit] or 0) + 1
                end
            end
            p.total = p.total + 1
        end
    end
    for _, pr in pairs(p.roles) do pr.avg = pr.sum / pr.count; pr.shown = pr.nRaters >= MIN_RATERS end
    for _, roles in pairs(p.inst) do for _, pi in pairs(roles) do pi.avg = pi.sum / pi.count end end
    return p
end

------------------------------------------------------------------------
-- Summaries other players shared with me (applicants, group members)
------------------------------------------------------------------------
ns.summaries = {}      -- [name] = { roles = { ROLE = {avg,count,nRaters,shown} }, tags = { [bit]=count } }
local hidden = {}      -- applicants whose spot-check didn't match: their rating isn't shown

-- "TANK:4.62:22:11,HEAL:..." + "bit:count,bit:count"
local function encodeSummary()
    local p = myProfile()
    local roles = {}
    for _, role in ipairs(ns.ROLES) do
        local pr = p.roles[role]
        if pr then
            if pr.shown then
                table.insert(roles, string.format("%s:%.2f:%d:%d", role, pr.avg, pr.count, pr.nRaters))
            else
                table.insert(roles, string.format("%s:0:0:%d", role, pr.nRaters))
            end
        end
    end
    local tags = {}
    for b, c in pairs(p.tags) do table.insert(tags, { b = b, c = c }) end
    table.sort(tags, function(a, b) return a.c > b.c end)
    local t = {}
    for i = 1, math.min(4, #tags) do table.insert(t, tags[i].b .. ":" .. tags[i].c) end
    return table.concat(roles, ","), table.concat(t, ",")
end

local function decodeSummary(rolesStr, tagsStr)
    local s = { roles = {}, tags = {} }
    for entry in (rolesStr or ""):gmatch("[^,]+") do
        local role, avg, count, n = strsplit(":", entry)
        role = ns.ValidRole(role)
        if role then
            local nR = ns.Clamp(n, 0, 100000, 0)
            local a = tonumber(avg)
            if a and (a ~= a or a < 0 or a > 5) then a = nil end
            s.roles[role] = { avg = a, count = ns.Clamp(count, 0, 100000, 0), nRaters = nR,
                              shown = a ~= nil and a >= 1 and nR >= MIN_RATERS }
        end
    end
    for entry in (tagsStr or ""):gmatch("[^,]+") do
        local b, c = strsplit(":", entry)
        b = ns.Clamp(b, 1, 13, nil)
        if b then s.tags[b] = ns.Clamp(c, 0, 100000, 0) end
    end
    return s
end

-- Applying: my summary plus a few ratings the leader's MOO can check with their raters.
function ns.SendRatingSummaryTo(leader, listingId)
    if not ns.IsOptedIn() then return end
    local roles, tags = encodeSummary()
    ns.Send("WHISPER", { "JR", listingId, roles, tags }, leader)
    local list = {}
    for _, r in pairs(aboutMe()) do table.insert(list, r) end
    table.sort(list, function(a, b) return a.ts > b.ts end)
    local picks = {}
    for i = 1, math.min(10, #list) do table.insert(picks, list[i]) end
    for i = 1, math.min(3, #picks) do
        local j = math.random(i, #picks)
        picks[i], picks[j] = picks[j], picks[i]
        local r = picks[i]
        ns.Send("WHISPER", { "JV", listingId, r.rater, r.run, digest(r.run, r.stars, r.tags) }, leader)
    end
end

ns.Handle("JR", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local a = ns.applicants and ns.applicants[sender]
    if not a or a.id ~= f[2] or hidden[sender] then return end
    ns.summaries[sender] = decodeSummary(f[3], f[4])
    ns.Fire("RATINGS_UPDATED", sender)
end)

-- Spot-checks, all silent: ask the rater, and drop the summary only on a clear mismatch.
local pendingChecks = {}   -- [rater:lower() .. "|" .. runId] = { applicant=, digest=, t= }

ns.Handle("JV", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local a = ns.applicants and ns.applicants[sender]
    if not a or a.id ~= f[2] then return end
    local rater, runId, dg = ns.SafeName(f[3]) and ns.FullName(f[3]), f[4], f[5]
    if not rater or type(runId) ~= "string" or #runId > 12 or type(dg) ~= "string" or #dg > 12 then return end
    if ns.IsMe(rater) then return end
    a.checks = (a.checks or 0) + 1
    if a.checks > 3 then return end
    pendingChecks[rater:lower() .. "|" .. runId] = { applicant = sender, digest = dg, t = GetTime() }
    ns.Send("WHISPER", { "VQ", runId, sender }, rater)
end)

-- Someone asks: "did you rate this player in this run?" Answer from my own record.
local answered, answerWindow = 0, 0
ns.Handle("VQ", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    if GetTime() - answerWindow > 60 then answered, answerWindow = 0, GetTime() end
    answered = answered + 1
    if answered > 20 then return end
    local runId, ratee = f[2], f[3]
    if type(runId) ~= "string" or #runId > 12 then return end
    for _, g in pairs(given()) do
        if g.run == runId and ns.LooseSame(g.ratee, ratee) then
            ns.Send("WHISPER", { "VA", runId, digest(g.run, g.stars, g.tags) }, sender)
            return
        end
    end
    -- no record (never rated, or data lost): say nothing
end)

ns.Handle("VA", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    local key = sender:lower() .. "|" .. tostring(f[2])
    local c = pendingChecks[key]
    if not c then return end
    pendingChecks[key] = nil
    if f[3] ~= c.digest then
        hidden[c.applicant] = true
        ns.summaries[c.applicant] = nil
        ns.Fire("RATINGS_UPDATED", c.applicant)
    end
end)

-- In a group: share my summary with the group (with the hello).
local shareQueued
function ns.QueueShareSummary()
    if shareQueued then return end
    shareQueued = true
    C_Timer.After(4, function()
        shareQueued = false
        if not IsInGroup() or not ns.IsOptedIn() then return end
        local roles, tags = encodeSummary()
        ns.Send("GROUP", { "RS", roles, tags })
    end)
end
ns.On("GROUP_ROSTER_UPDATE", function() if IsInGroup() then ns.QueueShareSummary() end end)

ns.Handle("RS", function(sender, f, dist)
    if dist ~= "PARTY" and dist ~= "RAID" then return end
    if hidden[sender] then return end
    local isNew = ns.summaries[sender] == nil
    ns.summaries[sender] = decodeSummary(f[2], f[3])
    if isNew then ns.QueueShareSummary() end      -- newcomer: make sure they get mine too
    ns.Fire("RATINGS_UPDATED", sender)
end)

------------------------------------------------------------------------
-- Profile API used by the UI and the Feedback tab
------------------------------------------------------------------------
function ns.GetProfile(name)
    if ns.IsMe(name) then return myProfile() end
    local s = ns.summaries[name]
    local p = { roles = {}, inst = {}, tags = {}, total = 0, shared = s ~= nil }
    if s then
        for role, r in pairs(s.roles) do
            p.roles[role] = { avg = r.avg, count = r.count, nRaters = r.nRaters, shown = r.shown, tags = {} }
            p.total = p.total + r.count
        end
        for b, c in pairs(s.tags) do p.tags[b] = c end
    end
    return p
end

function ns.TagBaseline() return nil end   -- no shared data to compare against any more

function ns.StarsText(avg)
    if not avg then return "|cff888888-|r" end
    return string.format("|cffffd100%.1f|r|TInterface\\COMMON\\ReputationStar:12:12:0:0:32:32:0:16:0:16|t", avg)
end

-- One-line summary for a role (applicants and group members only).
function ns.RatingSummary(name, role)
    if not ns.IsMe(name) and not ns.summaries[name] then return "|cff888888-|r" end
    local p = ns.GetProfile(name)
    local pr = role and p.roles[role]
    if not pr then
        for _, r in pairs(p.roles) do if not pr or r.count > pr.count then pr = r end end
    end
    if not pr then return "|cff888888new|r" end
    if not pr.shown then return "|cff888888" .. pr.nRaters .. "/" .. MIN_RATERS .. " ratings|r" end
    return ns.StarsText(pr.avg) .. " |cff888888(" .. pr.count .. ")|r"
end

function ns.TopTags(p, n)
    local list = {}
    for b, c in pairs(p.tags) do table.insert(list, { bit = b, count = c }) end
    table.sort(list, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(n or 3, #list) do
        local t = ns.TAG_BY_BIT[list[i].bit]
        if t then table.insert(out, t.label .. " x" .. list[i].count) end
    end
    return table.concat(out, ", ")
end

------------------------------------------------------------------------
-- Upkeep
------------------------------------------------------------------------
ns.Listen("OPTED_OUT", function()
    MOO_CharDB.pending = {}
end)

local function trim(tbl)
    local cutoff = ns.Now() - KEEP_DAYS * 86400
    local list = {}
    for k, v in pairs(tbl) do
        if (v.ts or 0) < cutoff then tbl[k] = nil else table.insert(list, { k = k, ts = v.ts }) end
    end
    if #list > MAX_STORED then
        table.sort(list, function(a, b) return a.ts < b.ts end)
        for i = 1, #list - MAX_STORED do tbl[list[i].k] = nil end
    end
end

ns.Listen("DB_READY", function()
    -- 0.10 stopped sharing ratings realm-wide: drop the old shared store to free space
    if (MOO_DB.version or 1) < 2 then
        MOO_DB.realms = {}
        MOO_DB.version = 2
    end
end)

ns.Listen("READY", function()
    trim(aboutMe()); trim(given())
    C_Timer.NewTicker(3600, function() trim(aboutMe()); trim(given()) end)
end)

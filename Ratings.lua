-- MOO Ratings
--
-- How a rating becomes trustworthy without a server:
--   1. MOO notices when your group enters a dungeon or raid and remembers who was in it.
--   2. When you leave (and stay out), your addon "attests" the run: run id, instance,
--      the role you played, and who you were grouped with. Only opted-in players attest.
--   3. You rate groupmates: 1-5 stars plus positive tags.
--   4. Every client accepts a rating from A about B for a run ONLY if A attested the run
--      naming B, and B attested the same run naming A. The game stamps every sender's
--      name, so nobody can attest or rate in someone else's name.
--   5. The role on a rating comes from the ratee's own attestation, not the rater.
--   6. A score shows only once 3 different players have rated that role.
--
-- The run id is the same on every member's client: instance + group leader + UTC day.
-- So the same leader running the same dungeon twice in one day counts as one run for
-- ratings, which also stops friends farming stars for each other.
--
-- Each client re-sends its own attestations and given ratings now and then, so players
-- who were offline still learn them. Nobody re-sends anyone else's.

local _, ns = ...

local MIN_RUN_SECONDS = 300            -- shorter runs aren't rated
local OUT_GRACE = 90                   -- stay out this long before the run counts as over
local KEEP_DAYS = 180
local MIN_RATERS = 3
local REBROADCAST_EVERY = 600
local REBROADCAST_BATCH = 8

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
        ns.Attest(r.id, r.inst, MOO_CharDB.role, members)
    end
    if ns.IsOptedIn() then
        MOO_CharDB.runs = MOO_CharDB.runs or {}
        local names = {}
        for n in pairs(members) do names[n] = true end
        table.insert(MOO_CharDB.runs, 1, { id = r.id, inst = r.inst, role = MOO_CharDB.role, ts = ns.Now(), roster = names })
        while #MOO_CharDB.runs > 30 do table.remove(MOO_CharDB.runs) end
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
-- Storage
------------------------------------------------------------------------
local index, indexDirty = {}, true
local baselineDirty

local MAX_NAMES_PER_RUN_STORE = 40
local function storeAttest(runId, attester, inst, role, names, ts)
    local db = ns.RealmData()
    db.attest[runId] = db.attest[runId] or {}
    local a = db.attest[runId][attester]
    if not a then
        a = { inst = inst, role = role, names = {}, ts = ts }
        db.attest[runId][attester] = a
    end
    a.role = role or a.role
    a.inst = inst or a.inst
    a.ts = math.max(a.ts or 0, ts or 0)
    a.nNames = a.nNames or 0
    for _, n in ipairs(names) do
        if not a.names[n] and a.nNames < MAX_NAMES_PER_RUN_STORE then
            a.names[n] = true
            a.nNames = a.nNames + 1
        end
    end
    indexDirty = true
end

local function storeRating(runId, rater, ratee, stars, tags, ts)
    local db = ns.RealmData()
    local key = runId .. ">" .. rater .. ">" .. ratee
    local old = db.ratings[key]
    if old and old.ts >= ts then return false end
    db.ratings[key] = { run = runId, rater = rater, ratee = ratee, stars = stars, tags = tags, ts = ts }
    indexDirty = true
    return true
end

------------------------------------------------------------------------
-- Attest and rate (local player)
------------------------------------------------------------------------
local function sendAttestChunks(runId, inst, role, nameList)
    local chunk, size = {}, 0
    local function flush()
        if #chunk > 0 then
            ns.Send("NET", { "A", runId, inst, role, table.concat(chunk, ",") })
            chunk, size = {}, 0
        end
    end
    for _, n in ipairs(nameList) do
        if size + #n + 1 > 180 then flush() end
        table.insert(chunk, n)
        size = size + #n + 1
    end
    flush()
end

function ns.Attest(runId, inst, role, members)
    local names = {}
    for n in pairs(members) do table.insert(names, n) end
    table.sort(names)
    local me = ns.Me()
    storeAttest(runId, me, inst, role, names, ns.Now())
    local db = ns.RealmData()
    db.given.attests = db.given.attests or {}
    db.given.attests[runId] = ns.Now()
    sendAttestChunks(runId, inst, role, names)
end

function ns.SubmitRating(runId, ratee, stars, tags)
    if not ns.IsOptedIn() then return end
    stars = math.max(1, math.min(5, math.floor(tonumber(stars) or 0)))
    tags = math.floor(tonumber(tags) or 0)
    local ts = ns.Now()
    if storeRating(runId, ns.Me(), ratee, stars, tags, ts) then
        local db = ns.RealmData()
        db.given.ratings = db.given.ratings or {}
        db.given.ratings[runId .. ">" .. ns.Me() .. ">" .. ratee] = ts
        ns.Send("NET", { "R", runId, ratee, stars, tags, ts })
    end
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local function plausibleTs(ts)
    local now = ns.Now()
    return ts and ts <= now + 120 and ts >= now - KEEP_DAYS * 86400
end

-- Per-sender daily budgets: far above what an honest player produces, low enough
-- that one bad actor can't bloat everyone's saved data.
local MAX_RUNS_PER_DAY = 30         -- new runs one player can attest per day
local MAX_RATINGS_PER_DAY = 200     -- new ratings one player can give per day
local MAX_NAMES_PER_RUN = 40
local TAG_LIMIT = 2 ^ 13            -- 13 tag bits exist
local budgets = {}

local function spend(sender, kind, limit)
    local day = utcDay()
    local b = budgets[sender]
    if not b or b.day ~= day then b = { day = day }; budgets[sender] = b end
    b[kind] = (b[kind] or 0) + 1
    return b[kind] <= limit
end

local function validId(id)
    return type(id) == "string" and #id >= 1 and #id <= 12 and id:match("^%w+$") ~= nil
end

ns.Handle("A", function(sender, f)
    local runId, inst, role, list = f[2], f[3], ns.ValidRole(f[4]), f[5]
    if not validId(runId) or not validId(inst) or not role or not list then return end
    local db = ns.RealmData()
    local known = db.attest[runId] and db.attest[runId][sender]
    if known and known.nNames and known.nNames >= MAX_NAMES_PER_RUN then return end
    if not known and not spend(sender, "runs", MAX_RUNS_PER_DAY) then return end
    local names = {}
    for n in list:gmatch("[^,]+") do
        local safe = ns.SafeName(n)
        if safe and safe ~= sender then table.insert(names, safe) end
        if #names >= MAX_NAMES_PER_RUN then break end
    end
    if #names == 0 then return end
    storeAttest(runId, sender, inst, role, names, ns.Now())
end)

ns.Handle("R", function(sender, f)
    local runId, ratee = f[2], ns.SafeName(f[3])
    local stars = ns.Clamp(f[4], 0, 5, 0)
    local tags = ns.Clamp(f[5], 0, TAG_LIMIT - 1, 0)
    local ts = ns.Clamp(f[6], 0, 4102444800, nil)
    if not validId(runId) or not ratee or ratee == sender or stars < 1 then return end
    if not plausibleTs(ts) then return end
    local db = ns.RealmData()
    local isNew = not db.ratings[runId .. ">" .. sender .. ">" .. ratee]
    if isNew and not spend(sender, "ratings", MAX_RATINGS_PER_DAY) then return end
    if storeRating(runId, sender, ratee, stars, tags, ts) then
        ns.Fire("RATINGS_UPDATED", ratee)
    end
end)

-- If someone opts out, stop counting new runs for them (their own client stops attesting).
ns.Listen("OPTED_OUT", function()
    MOO_CharDB.pending = {}
end)

------------------------------------------------------------------------
-- Validation and aggregation
------------------------------------------------------------------------
function ns.IsRatingValid(r)
    local runAtt = ns.RealmData().attest[r.run]
    if not runAtt then return false end
    local a, b = runAtt[r.rater], runAtt[r.ratee]
    if not a or not b then return false end
    return a.names[r.ratee] and b.names[r.rater] and true or false
end

local function rebuildIndex()
    baselineDirty = true
    index = {}
    for key, r in pairs(ns.RealmData().ratings) do
        index[r.ratee] = index[r.ratee] or {}
        table.insert(index[r.ratee], key)
    end
    indexDirty = false
end

-- Returns { roles = { TANK = {avg, count, raters, shown}, ... },
--           inst  = { [instKey] = { [role] = {avg, count} } },
--           tags  = { [bit] = count }, total = n }
function ns.GetProfile(name)
    if indexDirty then rebuildIndex() end
    local db = ns.RealmData()
    local p = { roles = {}, inst = {}, tags = {}, total = 0 }
    local cutoff = ns.Now() - KEEP_DAYS * 86400
    for _, key in ipairs(index[name] or {}) do
        local r = db.ratings[key]
        if r and r.ts >= cutoff and ns.IsRatingValid(r) then
            local att = db.attest[r.run][r.ratee]
            local role = att.role or "DPS"
            local inst = att.inst or "?"
            local pr = p.roles[role]
            if not pr then pr = { sum = 0, count = 0, raters = {}, nRaters = 0, tags = {} }; p.roles[role] = pr end
            pr.sum, pr.count = pr.sum + r.stars, pr.count + 1
            if not pr.raters[r.rater] then pr.raters[r.rater] = true; pr.nRaters = pr.nRaters + 1 end
            p.inst[inst] = p.inst[inst] or {}
            local pi = p.inst[inst][role]
            if not pi then pi = { sum = 0, count = 0, raters = {}, nRaters = 0 }; p.inst[inst][role] = pi end
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
    for _, pr in pairs(p.roles) do
        pr.avg = pr.sum / pr.count
        pr.shown = pr.nRaters >= MIN_RATERS
    end
    for _, roles in pairs(p.inst) do
        for _, pi in pairs(roles) do pi.avg = pi.sum / pi.count end
    end
    return p
end

-- How often each tag is given to players in a role, across every valid rating this
-- client knows. Used as the "typical" level when coaching.
local baseline = {}
baselineDirty = true
function ns.TagBaseline(role)
    if indexDirty then rebuildIndex(); baselineDirty = true end
    if baselineDirty then
        baseline = {}
        local db = ns.RealmData()
        for _, r in pairs(db.ratings) do
            if ns.IsRatingValid(r) then
                local att = db.attest[r.run][r.ratee]
                local ro = att.role or "DPS"
                local b = baseline[ro]
                if not b then b = { total = 0, tags = {} }; baseline[ro] = b end
                b.total = b.total + 1
                for _, t in ipairs(ns.TAGS) do
                    if ns.TagMaskHas(r.tags or 0, t.bit) then b.tags[t.bit] = (b.tags[t.bit] or 0) + 1 end
                end
            end
        end
        baselineDirty = false
    end
    return baseline[role]
end

function ns.StarsText(avg)
    if not avg then return "|cff888888-|r" end
    return string.format("|cffffd100%.1f|r|TInterface\\COMMON\\ReputationStar:12:12:0:0:32:32:0:16:0:16|t", avg)
end

-- One-line summary for a role, used on listing and applicant rows.
function ns.RatingSummary(name, role)
    local p = ns.GetProfile(name)
    local pr = role and p.roles[role]
    if not pr then
        -- fall back to their best-known role
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
-- Re-send my own records for players who were offline; prune old data
------------------------------------------------------------------------
local cursor = 0
local function rebroadcast()
    if not ns.InOlympus() or not ns.IsOptedIn() or ns.InRestrictedInstance() then return end
    local db = ns.RealmData()
    local me = ns.Me()
    local items = {}
    for runId in pairs(db.given.attests or {}) do table.insert(items, { "A", runId }) end
    for key in pairs(db.given.ratings or {}) do table.insert(items, { "R", key }) end
    if #items == 0 then return end
    table.sort(items, function(a, b) return a[1] .. a[2] < b[1] .. b[2] end)
    for i = 1, math.min(REBROADCAST_BATCH, #items) do
        cursor = (cursor % #items) + 1
        local it = items[cursor]
        if it[1] == "A" then
            local a = db.attest[it[2]] and db.attest[it[2]][me]
            if a then
                local names = {}
                for n in pairs(a.names) do table.insert(names, n) end
                table.sort(names)
                sendAttestChunks(it[2], a.inst, a.role, names)
            end
        else
            local r = db.ratings[it[2]]
            if r then ns.Send("NET", { "R", r.run, r.ratee, r.stars, r.tags, r.ts }) end
        end
    end
end

-- Keeps saved data small and drops anything that never became a real rating:
--   * ratings older than 180 days
--   * ratings still not confirmed by both players' attestations after 3 days
--   * other players' attestations for runs nobody rated, after 14 days
--   * if still over the caps, the oldest entries first
local MAX_RATINGS_STORED = 30000
local MAX_RUNS_STORED = 20000

local function trimOldest(tbl, count, max, tsOf)
    if count <= max then return end
    local list = {}
    for k, v in pairs(tbl) do table.insert(list, { k = k, ts = tsOf(v) }) end
    table.sort(list, function(a, b) return a.ts < b.ts end)
    for i = 1, count - max do tbl[list[i].k] = nil end
end

local function prune()
    local db = ns.RealmData()
    local now = ns.Now()
    local cutoff = now - KEEP_DAYS * 86400
    local me = ns.Me()
    local given = db.given.ratings or {}
    local nRatings, ratedRuns = 0, {}
    for key, r in pairs(db.ratings) do
        if r.ts < cutoff or (not given[key] and r.ts < now - 3 * 86400 and not ns.IsRatingValid(r)) then
            db.ratings[key] = nil
        else
            nRatings = nRatings + 1
            ratedRuns[r.run] = true
        end
    end
    trimOldest(db.ratings, nRatings, MAX_RATINGS_STORED, function(r) return r.ts end)
    local nRuns = 0
    for runId, byAttester in pairs(db.attest) do
        for name, a in pairs(byAttester) do
            local old = (a.ts or 0) < cutoff
            local unused = name ~= me and not ratedRuns[runId] and (a.ts or 0) < now - 14 * 86400
            if old or unused then byAttester[name] = nil end
        end
        if not next(byAttester) then db.attest[runId] = nil else nRuns = nRuns + 1 end
    end
    trimOldest(db.attest, nRuns, MAX_RUNS_STORED, function(byAttester)
        local newest = 0
        for _, a in pairs(byAttester) do newest = math.max(newest, a.ts or 0) end
        return newest
    end)
    for _, list in pairs({ db.given.attests or {}, db.given.ratings or {} }) do
        for k, ts in pairs(list) do if ts < cutoff then list[k] = nil end end
    end
    indexDirty = true
end

ns.Listen("READY", function()
    prune()
    C_Timer.NewTicker(3600, prune)
    C_Timer.After(60, rebroadcast)
    C_Timer.NewTicker(REBROADCAST_EVERY, rebroadcast)
end)

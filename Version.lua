-- MOO Version: tells players when a newer MOO is out on CurseForge.
--
-- * Only the author marks a release, after it is live on CurseForge:
--   /moo release 0.13.0-alpha. Local test builds announce nothing until then.
-- * The author's MOO announces it at login and every 15 minutes while online.
-- * Every MOO that heard it repeats it once when it logs in, so the news spreads while
--   the author is offline. A repeated notice can only claim a version close to yours
--   (same major version, at most 3 minor versions ahead), and the author's own notice
--   always wins, so nobody can make MOO nag with a made-up version.
-- * Players with an older version get one chat line per session and a note in the
--   window title. The download link is built in; a notice can't change it.

local _, ns = ...

ns.DOWNLOAD_URL = "curseforge.com/wow/addons/moo-muster-of-olympus"

local ANNOUNCE_EVERY = 15 * 60
local MAX_MINOR_JUMP = 3
local SUFFIX_RANK = { ["-alpha"] = 1, ["-beta"] = 2, [""] = 3 }

-- "0.13.0-alpha" -> { 0, 13, 0, 1 }, or nil if it isn't a version MOO uses.
local function parse(v)
    if type(v) ~= "string" or #v > 20 then return nil end
    local a, b, c, suffix = v:match("^(%d+)%.(%d+)%.(%d+)(%-?%a*)$")
    if not a or not SUFFIX_RANK[suffix] then return nil end
    return { tonumber(a), tonumber(b), tonumber(c), SUFFIX_RANK[suffix] }
end
ns.ParseVersion = parse

-- 1 if a is newer than b, -1 if older, 0 if the same (nil if either isn't valid)
function ns.CompareVersions(a, b)
    local x, y = parse(a), parse(b)
    if not x or not y then return nil end
    for i = 1, 4 do
        if x[i] ~= y[i] then return x[i] > y[i] and 1 or -1 end
    end
    return 0
end

local function known()
    return MOO_DB and MOO_DB.release
end

-- The newer released version, if mine is out of date.
function ns.UpdateAvailable()
    local r = known()
    if r and ns.CompareVersions(r.v, ns.VERSION) == 1 then return r.v end
end

local told = false
local function tellIfOld()
    local v = ns.UpdateAvailable()
    if not v or told then return end
    told = true
    ns.Print("A newer MOO (" .. v .. ") is out. Update from CurseForge: " .. ns.DOWNLOAD_URL)
    ns.Fire("STATE_CHANGED")
end

-- Is a repeated (not the author's own) notice believable next to my version?
local function plausible(v)
    local x, mine = parse(v), parse(ns.VERSION)
    if not x or not mine then return false end
    return x[1] == mine[1] and x[2] <= mine[2] + MAX_MINOR_JUMP
end

local function announce(kind)
    local r = known()
    if r and ns.InOlympus() then ns.Send("NET", { "RV", r.v, kind }) end
end

ns.Handle("RV", function(sender, f)
    local v, kind = f[2], f[3]
    if not parse(v) then return end
    local r = known()
    if kind == "a" and ns.IsAuthorName and ns.IsAuthorName(sender) then
        -- the author's word is final, even if it's lower (a release taken back)
        if not r or r.v ~= v or not r.author then
            MOO_DB.release = { v = v, author = true, ts = ns.Now() }
        end
    elseif kind == "r" or kind == "a" then
        if not plausible(v) then return end
        if r and ns.CompareVersions(v, r.v) ~= 1 then return end
        MOO_DB.release = { v = v, author = false, ts = ns.Now() }
    else
        return
    end
    tellIfOld()
end)

------------------------------------------------------------------------
-- /moo release (author only)
------------------------------------------------------------------------
function ns.ReleaseCommand(rest)
    rest = strtrim(rest or "")
    local r = known()
    if not (ns.IsRecruitOwner and ns.IsRecruitOwner()) then
        ns.Print("Your MOO is " .. ns.VERSION .. ". Newest release MOO has heard of: " .. (r and r.v or "none yet") .. ".")
        return
    end
    if rest == "" then
        ns.Print("Announcing: " .. (MOO_DB.announceRelease or "nothing") .. ". Known release: " .. (r and r.v or "none") ..
            ". Use /moo release <version> once it's live on CurseForge, or /moo release off.")
        return
    end
    if rest:lower() == "off" then
        MOO_DB.announceRelease = nil
        ns.Print("Stopped announcing releases. Players keep the last one they heard.")
        return
    end
    if not parse(rest) then
        ns.Print("That doesn't look like a MOO version. Example: /moo release 0.13.0-alpha")
        return
    end
    MOO_DB.release = { v = rest, author = true, ts = ns.Now() }
    MOO_DB.announceRelease = rest
    announce("a")
    ns.Print("Release " .. rest .. " marked. Players with an older MOO will be told to update." ..
        (ns.CompareVersions(rest, ns.VERSION) ~= 0 and (" (Your own MOO is " .. ns.VERSION .. ".)") or ""))
end

ns.Listen("READY", function()
    if ns.IsRecruitOwner and ns.IsRecruitOwner() and MOO_DB.announceRelease then
        -- the author's notice: at login and every 15 minutes
        MOO_DB.release = { v = MOO_DB.announceRelease, author = true, ts = ns.Now() }
        C_Timer.After(20, function() announce("a") end)
        C_Timer.NewTicker(ANNOUNCE_EVERY, function()
            if MOO_DB.announceRelease then announce("a") end
        end)
    else
        -- everyone else repeats what they know once, a little after login
        C_Timer.After(30 + math.random(0, 60), function() announce("r") end)
    end
    C_Timer.After(10, tellIfOld)
end)

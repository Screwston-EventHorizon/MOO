-- MOO Gear: what an applicant is wearing, and their basic stats.
--
-- * Your own addon builds the snapshot from your own character (out of combat only)
--   and sends it ONLY to a group leader you apply to, or one with an open listing
--   who asks while you are listed as available. Never broadcast.
-- * Self-reported until checked: once the player is in your group and within inspect
--   range (~28 yd), MOO inspects them once (out of combat) and marks the snapshot
--   "verified" or "changed".
-- * Nothing is scored or ranked here. It shows items and numbers; you decide.

local _, ns = ...

ns.SLOTS = {
    { id = 1,  label = "Head" },      { id = 2,  label = "Neck" },
    { id = 3,  label = "Shoulder" },  { id = 15, label = "Back" },
    { id = 5,  label = "Chest" },     { id = 9,  label = "Wrist" },
    { id = 10, label = "Hands" },     { id = 6,  label = "Waist" },
    { id = 7,  label = "Legs" },      { id = 8,  label = "Feet" },
    { id = 11, label = "Ring" },      { id = 12, label = "Ring" },
    { id = 13, label = "Trinket" },   { id = 14, label = "Trinket" },
    { id = 16, label = "Main hand" }, { id = 17, label = "Off hand" },
    { id = 18, label = "Ranged" },
}

-- Item IDs in SLOTS order, comma separated, 0 = empty.
function ns.GearSnapshot()
    local ids = {}
    for i, s in ipairs(ns.SLOTS) do
        ids[i] = ns.Safe(0, GetInventoryItemID, "player", s.id)
    end
    return table.concat(ids, ",")
end

local function itemLevel(id)
    if not id or id == 0 then return nil end
    local lvl
    if C_Item and C_Item.GetItemInfo then
        lvl = select(4, C_Item.GetItemInfo(id))
    elseif GetItemInfo then
        lvl = select(4, GetItemInfo(id))
    end
    return lvl
end

function ns.AverageItemLevel(gearString)
    if not gearString then
        local avg = ns.Safe(nil, GetAverageItemLevel)
        if avg and avg > 0 then return math.floor(avg + 0.5) end
        gearString = ns.GearSnapshot()
    end
    local sum, n = 0, 0
    for id in gearString:gmatch("[^,]+") do
        local lvl = itemLevel(tonumber(id))
        if lvl then sum, n = sum + lvl, n + 1 end
    end
    return n > 0 and math.floor(sum / n + 0.5) or 0
end

ns.STAT_LABELS = { "Str", "Agi", "Sta", "Int", "Spi", "Armor", "Health", "Mana",
                   "Melee crit %", "Spell crit %", "Spell power", "Attack power" }

function ns.StatSnapshot()
    if InCombatLockdown() then return nil end
    local s = {}
    for i = 1, 5 do
        s[i] = math.floor(ns.Safe(0, function() return select(2, UnitStat("player", i)) end))
    end
    s[6] = math.floor(ns.Safe(0, function() return select(2, UnitArmor("player")) end))
    s[7] = ns.Safe(0, UnitHealthMax, "player")
    s[8] = ns.Safe(0, UnitPowerMax, "player", 0)
    s[9] = string.format("%.1f", ns.Safe(0, GetCritChance))
    s[10] = string.format("%.1f", ns.Safe(0, GetSpellCritChance, 2))
    s[11] = ns.Safe(0, GetSpellBonusDamage, 2)
    s[12] = ns.Safe(0, function()
        local base, pos, neg = UnitAttackPower("player")
        return base + pos + neg
    end)
    for i = 1, #s do s[i] = tostring(s[i]) end
    return table.concat(s, ",")
end

-- Send my gear and stats to one player (a leader I applied to, or who asked).
function ns.SendGearTo(target, listingId)
    if InCombatLockdown() then return end
    ns.Send("WHISPER", { "JG", listingId or "0", ns.GearSnapshot() }, target)
    local stats = ns.StatSnapshot()
    if stats then ns.Send("WHISPER", { "JS", listingId or "0", stats }, target) end
end

------------------------------------------------------------------------
-- Received snapshots: ns.gearSeen[name] = { gear=, stats=, ilvl=, ts=, status= }
------------------------------------------------------------------------
ns.gearSeen = {}
-- Gear is only accepted from players who applied to my listing, players I asked,
-- and members of my group: nobody can push data at you uninvited.
ns.gearAllowed = {}      -- [name] = GetTime() when they became allowed
local ALLOW_SECONDS = 600

local function allowed(sender)
    local t = ns.gearAllowed[sender]
    if t and GetTime() - t < ALLOW_SECONDS then return true end
    for _, u in ipairs(ns.GroupUnits and ns.GroupUnits() or {}) do
        if ns.UnitFullName(u) == sender then return true end
    end
    return false
end

local function entry(name)
    local e = ns.gearSeen[name]
    if not e then e = { status = "self" }; ns.gearSeen[name] = e end
    return e
end

-- "id,id,..." with exactly one number per slot, nothing else
local function parseGear(str)
    if type(str) ~= "string" then return nil end
    local ids = {}
    for id in str:gmatch("[^,]+") do
        local n = ns.Clamp(id, 0, 9999999, nil)
        if not n then return nil end
        table.insert(ids, n)
        if #ids > #ns.SLOTS then return nil end
    end
    if #ids ~= #ns.SLOTS then return nil end
    return table.concat(ids, ",")
end

-- stats are numbers only (the two crit values may have one decimal)
local function parseStats(str)
    if type(str) ~= "string" then return nil end
    local out = {}
    for v in str:gmatch("[^,]+") do
        local n = tonumber(v)
        if not n or n ~= n or n < 0 or n > 10000000 then return nil end
        table.insert(out, (math.floor(n) == n) and tostring(n) or string.format("%.1f", n))
        if #out > #ns.STAT_LABELS then return nil end
    end
    return table.concat(out, ",")
end

ns.Handle("JG", function(sender, f)
    if not allowed(sender) then return end
    local gear = parseGear(f[3])
    if not gear then return end
    local e = entry(sender)
    e.gear = gear
    e.ilvl = ns.AverageItemLevel(gear)
    e.ts = ns.Now()
    e.status = "self"
    ns.Fire("GEAR_UPDATED", sender)
end)

ns.Handle("JS", function(sender, f)
    if not allowed(sender) then return end
    local stats = parseStats(f[3])
    if not stats then return end
    entry(sender).stats = stats
    ns.Fire("GEAR_UPDATED", sender)
end)

-- A leader with an open listing may ask for my gear while I'm listed as available.
-- Answered at most once a minute per leader.
local lastAnswer = {}
ns.Handle("GR", function(sender)
    if not ns.IsOptedIn() then return end
    if not ns.myAvailable then return end
    if not (ns.listings and ns.listings[sender]) then return end
    if lastAnswer[sender] and GetTime() - lastAnswer[sender] < 60 then return end
    lastAnswer[sender] = GetTime()
    ns.SendGearTo(sender, "0")
end)

function ns.RequestGear(name)
    ns.gearAllowed[name] = GetTime()
    ns.Send("WHISPER", { "GR" }, name)
end

------------------------------------------------------------------------
-- Verification by inspect, once they are in my group and close by
------------------------------------------------------------------------
local inspecting

local function groupUnitFor(name)
    local n = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) and ns.UnitFullName(u) == name then return u end
    end
end

local function tryVerify()
    if inspecting or InCombatLockdown() or not IsInGroup() then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    for name, e in pairs(ns.gearSeen) do
        if e.gear and e.status == "self" then
            local unit = groupUnitFor(name)
            if unit and CanInspect(unit) and CheckInteractDistance(unit, 1) then
                inspecting = { name = name, unit = unit, guid = UnitGUID(unit) }
                NotifyInspect(unit)
                C_Timer.After(5, function() inspecting = nil end)
                return
            end
        end
    end
end

ns.On("INSPECT_READY", function(guid)
    if not inspecting or guid ~= inspecting.guid then return end
    local e = ns.gearSeen[inspecting.name]
    if e and e.gear then
        local claimed, diff, i = {}, 0, 0
        for id in e.gear:gmatch("[^,]+") do i = i + 1; claimed[i] = tonumber(id) end
        for idx, s in ipairs(ns.SLOTS) do
            local real = GetInventoryItemID(inspecting.unit, s.id) or 0
            if real ~= (claimed[idx] or 0) then diff = diff + 1 end
        end
        e.status = diff == 0 and "verified" or "changed"
        e.diff = diff
        ns.Fire("GEAR_UPDATED", inspecting.name)
    end
    if ClearInspectPlayer then ClearInspectPlayer() end
    inspecting = nil
end)

ns.Listen("READY", function()
    C_Timer.NewTicker(5, tryVerify)
end)

function ns.GearStatusText(e)
    if not e or not e.gear then return "|cff888888no gear sent|r" end
    if e.status == "verified" then return "|cff33ff33verified|r" end
    if e.status == "changed" then
        return "|cffffaa00changed (" .. (e.diff or "?") .. " slots)|r"
    end
    return "|cffccccccself-reported|r"
end

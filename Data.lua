-- MOO Data: instances, categories and rating tags.
-- Forever may add new dungeons and raids: add a line to the right list and it shows everywhere.
-- mapID is the 8th return of GetInstanceInfo(); used to detect when a run starts and ends.

local _, ns = ...

ns.CATEGORIES = {
    { key = "DUNGEON", label = "Dungeons" },
    { key = "RAID",    label = "Raids" },
    { key = "BG",      label = "Battlegrounds" },
    { key = "WPVP",    label = "World PvP" },
    { key = "QUEST",   label = "Group Quests" },
}

ns.INSTANCES = {
    -- Dungeons (min = Forever's level where known; Classic map IDs where they exist)
    { key = "RFC",    cat = "DUNGEON", name = "Ragefire Chasm",          mapID = 389, min = 13 },
    { key = "THANES", cat = "DUNGEON", name = "Hall of Thanes",                       min = 13 },
    { key = "RUINS",  cat = "DUNGEON", name = "Ruins of Lordaeron",                   min = 15 },
    { key = "DM",     cat = "DUNGEON", name = "Deadmines",               mapID = 36,  min = 16 },
    { key = "WC",     cat = "DUNGEON", name = "Wailing Caverns",         mapID = 43,  min = 17 },
    { key = "SFK",    cat = "DUNGEON", name = "Shadowfang Keep",         mapID = 33,  min = 18 },
    { key = "BFD",    cat = "DUNGEON", name = "Blackfathom Deeps",       mapID = 48,  min = 22 },
    { key = "STOCK",  cat = "DUNGEON", name = "Stockade",                mapID = 34,  min = 23 },
    { key = "RFK",    cat = "DUNGEON", name = "Razorfen Kraul",          mapID = 47,  min = 24 },
    { key = "GNOME",  cat = "DUNGEON", name = "Gnomeregan",              mapID = 90,  min = 25 },
    { key = "EXCAV",  cat = "DUNGEON", name = "Excavation Site",                      min = 24 },
    { key = "DALA",   cat = "DUNGEON", name = "City of Dalaran",                      min = 28 },
    { key = "SM",     cat = "DUNGEON", name = "Scarlet Monastery",       mapID = 189, min = 30 },
    { key = "RFD",    cat = "DUNGEON", name = "Razorfen Downs",          mapID = 129, min = 34 },
    { key = "ULDA",   cat = "DUNGEON", name = "Uldaman",                 mapID = 70,  min = 35 },
    { key = "DROWN",  cat = "DUNGEON", name = "Drowned City",                         min = 35 },
    { key = "KROL",   cat = "DUNGEON", name = "Krol'dok Stronghold",                  min = 40 },
    { key = "MARA",   cat = "DUNGEON", name = "Maraudon",                mapID = 349, min = 42 },
    { key = "ZF",     cat = "DUNGEON", name = "Zul'Farrak",              mapID = 209, min = 42 },
    { key = "ST",     cat = "DUNGEON", name = "Sunken Temple",           mapID = 109, min = 45 },
    { key = "ALCAZ",  cat = "DUNGEON", name = "Alcaz Prison",                         min = 48 },
    { key = "BRD",    cat = "DUNGEON", name = "Blackrock Depths",        mapID = 230, min = 52 },
    { key = "BRS",    cat = "DUNGEON", name = "Blackrock Spire",         mapID = 229, min = 53 },
    { key = "DIRE",   cat = "DUNGEON", name = "Dire Maul",               mapID = 429, min = 54 },
    { key = "BLACKM", cat = "DUNGEON", name = "Blackmaw Hold",                        min = 55 },
    { key = "STRAT",  cat = "DUNGEON", name = "Stratholme",              mapID = 329, min = 55 },
    { key = "SCHOLO", cat = "DUNGEON", name = "Scholomance",             mapID = 289, min = 57 },
    { key = "SHAPER", cat = "DUNGEON", name = "Shaper's Terrace",                     min = 58 },
    { key = "PINT",   cat = "DUNGEON", name = "Half-Pint Tavern",                     min = 1 },
    { key = "MISTM",  cat = "DUNGEON", name = "Manor Mistmantle",                     min = 1 },
    -- Raids (Barrow Deeps, Hyjal Summit and Onyxia open on Dec 9, 2026)
    { key = "BARROW", cat = "RAID",    name = "Barrow Deeps",                         min = 60 },
    { key = "HYJAL",  cat = "RAID",    name = "Hyjal Summit",                         min = 60 },
    { key = "ONY",    cat = "RAID",    name = "Onyxia's Lair",           mapID = 249, min = 60 },
    { key = "ZG",     cat = "RAID",    name = "Zul'Gurub",               mapID = 309, min = 58 },
    { key = "AQ20",   cat = "RAID",    name = "Ruins of Ahn'Qiraj",      mapID = 509, min = 58 },
    { key = "MC",     cat = "RAID",    name = "Molten Core",             mapID = 409, min = 60 },
    { key = "BWL",    cat = "RAID",    name = "Blackwing Lair",          mapID = 469, min = 60 },
    { key = "AQ40",   cat = "RAID",    name = "Temple of Ahn'Qiraj",     mapID = 531, min = 60 },
    { key = "NAXX",   cat = "RAID",    name = "Naxxramas",               mapID = 533, min = 60 },
    -- Battlegrounds
    { key = "WSG",    cat = "BG",      name = "Warsong Gulch",           mapID = 489, min = 10 },
    { key = "AB",     cat = "BG",      name = "Arathi Basin",            mapID = 529, min = 20 },
    { key = "AV",     cat = "BG",      name = "Alterac Valley",          mapID = 30,  min = 51 },
    { key = "DARK",   cat = "BG",      name = "Darkspear Island",                     min = 10 },
    -- World PvP (no instance; the zone is in the note)
    { key = "WPVP",   cat = "WPVP",    name = "World PvP",               min = 1 },
    { key = "HILLS",  cat = "WPVP",    name = "Hillsbrad / Tarren Mill", min = 20 },
    { key = "BRM",    cat = "WPVP",    name = "Blackrock Mountain",      min = 50 },
    { key = "SILI",   cat = "WPVP",    name = "Silithus",                min = 55 },
    { key = "EPL",    cat = "WPVP",    name = "Eastern Plaguelands",     min = 55 },
    -- Catch-alls for content added before this list is updated
    { key = "OTHERD", cat = "DUNGEON", name = "Other dungeon (see note)", min = 1 },
    { key = "OTHERR", cat = "RAID",    name = "Other raid (see note)",    min = 1 },
}

ns.INSTANCE_BY_KEY, ns.INSTANCE_BY_MAP, ns.INSTANCES_BY_CAT = {}, {}, {}
for _, inst in ipairs(ns.INSTANCES) do
    ns.INSTANCE_BY_KEY[inst.key] = inst
    if inst.mapID then ns.INSTANCE_BY_MAP[inst.mapID] = inst end
    ns.INSTANCES_BY_CAT[inst.cat] = ns.INSTANCES_BY_CAT[inst.cat] or {}
    table.insert(ns.INSTANCES_BY_CAT[inst.cat], inst)
end

-- Find the MOO entry for the instance you are in, and remember it.
--   1. Map ID already known (built in, or remembered earlier)  -> that entry
--   2. Game's instance name matches an entry (English clients)  -> remember the ID for it
--   3. Nothing matches -> MOO adds the instance to its own list under the game's name,
--      so it shows in the group finder and its runs can be rated.
-- Everything remembered is kept in MOO_DB (account-wide, survives logouts and /reload).
local function norm(n)
    return (n or ""):lower():gsub("^the ", ""):gsub("[^%a]", "")
end

local KIND_TO_CAT = { party = "DUNGEON", raid = "RAID", pvp = "BG" }
local VALID_CAT = { DUNGEON = true, RAID = true, BG = true, WPVP = true }

local function addEntry(entry)
    table.insert(ns.INSTANCES, entry)
    ns.INSTANCE_BY_KEY[entry.key] = entry
    if entry.mapID then ns.INSTANCE_BY_MAP[entry.mapID] = entry end
    ns.INSTANCES_BY_CAT[entry.cat] = ns.INSTANCES_BY_CAT[entry.cat] or {}
    table.insert(ns.INSTANCES_BY_CAT[entry.cat], entry)
end

local function removeEntry(key)
    local e = ns.INSTANCE_BY_KEY[key]
    if not e then return end
    ns.INSTANCE_BY_KEY[key] = nil
    if e.mapID and ns.INSTANCE_BY_MAP[e.mapID] == e then ns.INSTANCE_BY_MAP[e.mapID] = nil end
    for _, list in ipairs({ ns.INSTANCES, ns.INSTANCES_BY_CAT[e.cat] or {} }) do
        for i = #list, 1, -1 do if list[i] == e then table.remove(list, i) end end
    end
end

-- An instance MOO didn't know. Key "C<mapID>" is the same on every client.
-- save=true keeps it in your saved variables; listings from others only add it for the session.
function ns.AddCustomInstance(mapID, name, cat, save)
    mapID = tonumber(mapID)
    if not mapID or not VALID_CAT[cat] then return nil end
    local key = "C" .. mapID
    local e = ns.INSTANCE_BY_KEY[key]
    if not e then
        e = { key = key, cat = cat, name = name or ("Instance " .. mapID), mapID = mapID, min = 1, custom = true }
        addEntry(e)
        ns.Fire("INSTANCES_CHANGED")
    end
    if save and MOO_DB then
        MOO_DB.custom = MOO_DB.custom or {}
        MOO_DB.custom[mapID] = { name = e.name, cat = e.cat }
    end
    return e
end

-- Is this one of MOO's own list entries (not one MOO added by itself)?
local function builtIn(inst)
    return inst and not inst.custom
end

function ns.MatchInstance(mapID, gameName)
    if ns.INSTANCE_BY_MAP[mapID] then return ns.INSTANCE_BY_MAP[mapID] end
    local learned = MOO_DB and MOO_DB.learned
    if learned and learned[mapID] and ns.INSTANCE_BY_KEY[learned[mapID].key] then
        return ns.INSTANCE_BY_KEY[learned[mapID].key]
    end
    local g = norm(gameName)
    if g == "" then return nil end
    for _, inst in ipairs(ns.INSTANCES) do
        if builtIn(inst) and inst.cat ~= "WPVP" and not inst.key:find("^OTHER") then
            local n = norm(inst.name)
            if g:find(n, 1, true) or n:find(g, 1, true) then
                if learned then learned[mapID] = { key = inst.key, name = gameName } end
                return inst, "name"
            end
        end
    end
    return nil
end

-- Match or add, and remember. Returns the entry and how it was found:
-- "known", "name" (just matched by name), "added" (new custom entry) or nil (arena etc).
function ns.ResolveInstance(mapID, gameName, kind)
    if not mapID then return nil end
    local known = ns.INSTANCE_BY_MAP[mapID] or (MOO_DB and MOO_DB.learned and MOO_DB.learned[mapID])
    local inst, how = ns.MatchInstance(mapID, gameName)
    if inst then return inst, (known and not how) and "known" or (how or "known") end
    local cat = KIND_TO_CAT[kind]
    if not cat then return nil end
    return ns.AddCustomInstance(mapID, gameName, cat, true), "added"
end

-- Point an instance ID at one of MOO's entries by hand (fixes a wrong or missing match).
function ns.LinkInstance(mapID, key, gameName)
    local target = ns.INSTANCE_BY_KEY[key]
    if not target or target.custom then return false end
    MOO_DB.learned[mapID] = { key = key, name = gameName }
    if MOO_DB.custom then MOO_DB.custom[mapID] = nil end
    removeEntry("C" .. mapID)
    if ns.INSTANCE_BY_MAP[mapID] and ns.INSTANCE_BY_MAP[mapID] ~= target then
        ns.INSTANCE_BY_MAP[mapID] = nil
    end
    ns.Fire("INSTANCES_CHANGED")
    return true
end

-- Forget what MOO remembered about an instance ID (built-in IDs stay).
function ns.ForgetInstance(mapID)
    if MOO_DB.learned then MOO_DB.learned[mapID] = nil end
    if MOO_DB.custom then MOO_DB.custom[mapID] = nil end
    removeEntry("C" .. mapID)
    ns.Fire("INSTANCES_CHANGED")
end

-- Log every instance visited, so its ID can be checked and added to the list.
function ns.LogInstance(mapID, gameName, kind)
    if not MOO_DB or not mapID then return end
    MOO_DB.seenInstances = MOO_DB.seenInstances or {}
    MOO_DB.seenInstances[mapID] = { name = gameName, type = kind, last = date("%Y-%m-%d") }
end

-- Lines to paste into Data.lua (or send to the author), from what this account remembered.
function ns.InstanceExportText()
    local lines = { "-- MOO instance IDs remembered on this account (" .. date("%Y-%m-%d") .. ")" }
    local ids = {}
    for id in pairs(MOO_DB.seenInstances or {}) do table.insert(ids, id) end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local seen = MOO_DB.seenInstances[id]
        local inst = ns.INSTANCE_BY_MAP[id] or ns.MatchInstance(id, seen.name)
        if inst and not inst.custom and inst.mapID == id then
            table.insert(lines, string.format("-- %d = %s (already built into MOO)", id, seen.name or "?"))
        elseif inst and not inst.custom then
            table.insert(lines, string.format('-- %d = %s  ->  set mapID = %d on the "%s" line', id, seen.name or "?", id, inst.key))
        elseif inst then
            table.insert(lines, string.format('{ key = "NEW%d", cat = "%s", name = "%s", mapID = %d, min = 1 },',
                id, inst.cat, (seen.name or inst.name):gsub('"', "'"), id))
        else
            table.insert(lines, string.format("-- %d = %s (%s), not a group instance", id, seen.name or "?", seen.type or "?"))
        end
    end
    if #ids == 0 then table.insert(lines, "-- no instances visited yet") end
    return table.concat(lines, "\n")
end

-- Put remembered instances back into the list at login.
ns.Listen("DB_READY", function()
    MOO_DB.learned = MOO_DB.learned or {}
    MOO_DB.custom = MOO_DB.custom or {}
    for mapID, c in pairs(MOO_DB.custom) do
        if not ns.INSTANCE_BY_MAP[mapID] then ns.AddCustomInstance(mapID, c.name, c.cat, false) end
    end
end)

-- Names of instances other players told us about (custom ones). Display only:
-- they never enter the dropdowns, so nobody can fill your menus with spam.
ns.remoteInstanceNames = {}
local remoteCount = 0
function ns.LearnRemoteInstance(key, name)
    if type(key) ~= "string" or not key:match("^C%d+$") or #key > 12 then return end
    if ns.INSTANCE_BY_KEY[key] or ns.remoteInstanceNames[key] then return end
    if remoteCount >= 100 then return end
    name = ns.Clean(name, 40)
    if name == "" then return end
    remoteCount = remoteCount + 1
    ns.remoteInstanceNames[key] = name
end

function ns.IsKnownInstanceKey(key)
    return ns.INSTANCE_BY_KEY[key] ~= nil or ns.remoteInstanceNames[key] ~= nil
end

function ns.InstanceName(key)
    local i = ns.INSTANCE_BY_KEY[key]
    if i then return i.name end
    if ns.remoteInstanceNames[key] then return ns.remoteInstanceNames[key] end
    if type(key) == "string" and key:match("^Q%d+$") then return "Group quest" end
    local id = type(key) == "string" and (key:match("^C(%d+)$") or key:match("^I(%d+)$"))
    return id and ("Instance " .. id) or "Unknown instance"
end

ns.ROLES = { "TANK", "HEAL", "DPS" }
ns.ROLE_LABEL = { TANK = "Tank", HEAL = "Healer", DPS = "DPS" }
ns.ROLE_COLOR = { TANK = "ff6fa8dc", HEAL = "ff6aa84f", DPS = "ffe06666" }

function ns.RoleText(role)
    local c = ns.ROLE_COLOR[role]
    if not c then return "?" end
    return "|c" .. c .. ns.ROLE_LABEL[role] .. "|r"
end

-- Rating tags: positive only, on purpose (like Uber compliments).
-- Stars carry the bad news; tags can't be used to insult anyone.
-- The bit index never changes once released, or old ratings would read wrong.
ns.TAGS = {
    { bit = 1,  role = "TANK", label = "Great pulls" },
    { bit = 2,  role = "TANK", label = "Solid threat" },
    { bit = 3,  role = "TANK", label = "Marked targets" },
    { bit = 4,  role = "HEAL", label = "Kept us alive" },
    { bit = 5,  role = "HEAL", label = "Smart mana" },
    { bit = 6,  role = "HEAL", label = "Quick dispels" },
    { bit = 7,  role = "DPS",  label = "Big damage" },
    { bit = 8,  role = "DPS",  label = "Good CC" },
    { bit = 9,  role = "DPS",  label = "Watched threat" },
    { bit = 10, role = "ANY",  label = "Friendly" },
    { bit = 11, role = "ANY",  label = "Knew the fights" },
    { bit = 12, role = "ANY",  label = "Fair on loot" },
    { bit = 13, role = "ANY",  label = "Patient teacher" },
}
ns.TAG_BY_BIT = {}
for _, t in ipairs(ns.TAGS) do ns.TAG_BY_BIT[t.bit] = t end

function ns.TagsForRole(role)
    local out = {}
    for _, t in ipairs(ns.TAGS) do
        if t.role == role or t.role == "ANY" then table.insert(out, t) end
    end
    return out
end

function ns.TagMaskHas(mask, b)
    return math.floor(mask / 2 ^ (b - 1)) % 2 == 1
end

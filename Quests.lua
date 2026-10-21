-- MOO Quests: reads your quest log for the Quests tab.
--
-- * The leader picks a quest from their own log (Group and Elite quests first) or types
--   a custom name. The listing carries the quest's ID, name and zone (see Groups.lua).
-- * Listings for quests you also have are marked and sorted to the top.
-- * Quest listings take themselves down after QUEST_LIFETIME; list again to renew.

local _, ns = ...

ns.QUEST_LIFETIME = 20 * 60

local GROUP_TAGS = { group = true, elite = true }

local cache            -- list of { id, title, zone, level, group }
local byId             -- [questID] = entry

local function str(v)
    if type(v) ~= "string" or ns.IsSecret(v) or v == "" then return nil end
    return v
end

local function num(v)
    if type(v) ~= "number" or ns.IsSecret(v) then return nil end
    return v
end

local function numEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and num(n) then return n end
    end
    if GetNumQuestLogEntries then
        local ok, n = pcall(GetNumQuestLogEntries)
        if ok and num(n) then return n end
    end
    return 0
end

-- title, isHeader, questID, level, suggestedGroup, tag for quest log line i
local function readEntry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" then
            return str(info.title), info.isHeader == true, num(info.questID), num(info.level), num(info.suggestedGroup)
        end
    end
    if GetQuestLogTitle then
        -- Classic: title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
        -- Older clients put a tag string ("Elite") where suggestedGroup is.
        local ok, title, level, third, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, i)
        if ok then
            local tag = type(third) == "string" and third or nil
            return str(title), isHeader == true or isHeader == 1, num(questID), num(level), num(third), tag
        end
    end
end

local function tagName(questID)
    if not questID or questID == 0 then return nil end
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local ok, info = pcall(C_QuestLog.GetQuestTagInfo, questID)
        if ok and type(info) == "table" and str(info.tagName) then return info.tagName end
    end
    if GetQuestTagInfo then
        local ok, _, name = pcall(GetQuestTagInfo, questID)
        if ok and str(name) then return name end
    end
end

local function scan()
    cache, byId = {}, {}
    local zone
    for i = 1, math.min(numEntries(), 200) do
        local title, isHeader, questID, level, suggested, tag = readEntry(i)
        if title then
            if isHeader then
                zone = title
            else
                tag = tag or tagName(questID)
                local e = {
                    id = questID, title = title, zone = zone, level = level,
                    group = (suggested and suggested > 1) or (tag and GROUP_TAGS[tag:lower()]) or false,
                    tag = tag,
                }
                table.insert(cache, e)
                if questID and questID > 0 then byId[questID] = e end
            end
        end
    end
end

-- Your quest log, group quests first, then by zone and title.
function ns.MyQuests()
    if not cache then scan() end
    local out = {}
    for _, e in ipairs(cache) do table.insert(out, e) end
    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group end
        if (a.zone or "") ~= (b.zone or "") then return (a.zone or "") < (b.zone or "") end
        return a.title < b.title
    end)
    return out
end

-- The quest log entry for a questID, if you have that quest.
function ns.MyQuest(questID)
    questID = tonumber(questID)
    if not questID or questID == 0 then return nil end
    if not byId then scan() end
    return byId[questID]
end

-- Your current zone, cleaned for sending.
function ns.CurrentZone()
    local z = (GetZoneText and GetZoneText()) or (GetRealZoneText and GetRealZoneText()) or ""
    if ns.IsSecret(z) then return "" end
    return ns.Clean(z, 30)
end

-- What a quest listing is for: your own log's title when you have it, else the sent name.
function ns.QuestListingName(l)
    local mine = ns.MyQuest(l.qid)
    return (mine and ns.Clean(mine.title, 40)) or l.qname or "Group quest"
end

-- Do you have the quest a listing is for? (Custom names never match.)
function ns.HaveListingQuest(l)
    return l and l.cat == "QUEST" and ns.MyQuest(l.qid) ~= nil
end

-- Quest listings: yours first, then quests you have, then newest. zone = nil for all.
function ns.SortedQuestListings(zone)
    local out = {}
    for _, l in pairs(ns.listings) do
        if l.cat == "QUEST" and (not zone or l.zone == zone) then table.insert(out, l) end
    end
    table.sort(out, function(a, b)
        local ha, hb = ns.HaveListingQuest(a), ns.HaveListingQuest(b)
        if ha ~= hb then return ha end
        return a.ts > b.ts
    end)
    return out
end

-- Quest log changes come in bursts: rescan at most once a second, and only when asked.
local pending = false
ns.On("QUEST_LOG_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(1, function()
        pending = false
        cache, byId = nil, nil
        ns.Fire("QUESTS_CHANGED")
    end)
end)

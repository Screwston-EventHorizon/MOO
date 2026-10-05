-- MOO Ready Check
--
-- Uses the game's own ready check (DoReadyCheck), started by the leader's or an
-- assistant's click. MOO adds a panel that shows each member's answer next to their
-- role, MOO rating and gear check, and a role count (e.g. 1 tank, 1 healer, 3 DPS).
-- It never answers a ready check for anyone.

local _, ns = ...

ns.readyCheck = { active = false, states = {}, started = 0 }

function ns.CanReadyCheck()
    if not IsInGroup() then return false, "You are not in a group." end
    if UnitIsGroupLeader("player") then return true end
    if IsInRaid() and UnitIsGroupAssistant("player") then return true end
    return false, "Only the leader (or a raid assistant) can start a ready check."
end

function ns.StartReadyCheck()
    local ok, why = ns.CanReadyCheck()
    if not ok then ns.Print(why) return end
    DoReadyCheck()
end

local function resetStates()
    local rc = ns.readyCheck
    rc.states = {}
    for _, u in ipairs(ns.GroupUnits()) do
        local n = ns.UnitFullName(u)
        if n then rc.states[n] = "waiting" end
    end
end

ns.On("READY_CHECK", function(initiator)
    local rc = ns.readyCheck
    rc.active = true
    rc.started = GetTime()
    resetStates()
    local who = initiator and ns.FullName(initiator)
    if who and rc.states[who] then rc.states[who] = "ready" end
    ns.Fire("READY_CHECK_UPDATED")
end)

ns.On("READY_CHECK_CONFIRM", function(unit, isReady)
    local n = unit and ns.UnitFullName(unit)
    if not n then return end
    ns.readyCheck.states[n] = isReady and "ready" or "notready"
    ns.Fire("READY_CHECK_UPDATED")
end)

ns.On("READY_CHECK_FINISHED", function()
    local rc = ns.readyCheck
    rc.active = false
    local notReady, afk = {}, {}
    for n, s in pairs(rc.states) do
        if s == "notready" then table.insert(notReady, ns.ShortName(n))
        elseif s == "waiting" then
            rc.states[n] = "afk"
            table.insert(afk, ns.ShortName(n))
        end
    end
    if #notReady == 0 and #afk == 0 then
        ns.Print("|cff33ff33Everyone is ready.|r")
    else
        if #notReady > 0 then ns.Print("|cffff4444Not ready:|r " .. table.concat(notReady, ", ")) end
        if #afk > 0 then ns.Print("|cffffaa00No answer:|r " .. table.concat(afk, ", ")) end
    end
    ns.Fire("READY_CHECK_UPDATED")
end)

-- Role of a group member: what their MOO told us, else the game's assigned role.
function ns.MemberRole(name, unit)
    local gi = ns.groupInfo[name]
    if gi and ns.ROLE_LABEL[gi.role] then return gi.role end
    if name == ns.Me() then return MOO_CharDB.role end
    if unit and UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned(unit)
        if r == "TANK" then return "TANK" elseif r == "HEALER" then return "HEAL" elseif r == "DAMAGER" then return "DPS" end
    end
    return nil
end

function ns.GroupRoster()
    local out = {}
    for _, u in ipairs(ns.GroupUnits()) do
        local n = ns.UnitFullName(u)
        if n then
            local _, classFile = UnitClass(u)
            table.insert(out, {
                name = n, unit = u, class = classFile, level = UnitLevel(u),
                role = ns.MemberRole(n, u),
                aol = (n == ns.Me()) or ns.groupInfo[n] ~= nil,
                state = ns.readyCheck.states[n],
                online = UnitIsConnected(u),
            })
        end
    end
    local order = { TANK = 1, HEAL = 2, DPS = 3 }
    table.sort(out, function(a, b)
        local ra, rb = order[a.role] or 4, order[b.role] or 4
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return out
end

function ns.RoleCounts(roster)
    local c = { TANK = 0, HEAL = 0, DPS = 0, unknown = 0 }
    for _, m in ipairs(roster) do
        if m.role then c[m.role] = c[m.role] + 1 else c.unknown = c.unknown + 1 end
    end
    return c
end

ns.READY_ICON = {
    ready    = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",
    notready = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t",
    waiting  = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t",
    afk      = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t",
}

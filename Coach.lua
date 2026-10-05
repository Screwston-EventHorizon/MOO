-- MOO Coach: feedback for your role, built only from what groupmates say.
--
-- MOO can't read combat data in instances (Forever, like Midnight, doesn't allow it),
-- so it never judges damage, healing or threat numbers. Instead:
--   1. Tips from your tags: compliments you get less often than typical players in
--      your role point to something to work on, with a how-to guide.
--   2. Instance trends: dungeons or raids where your rating is clearly below your average.
--   3. Private suggestions: groupmates can pick preset tips after a run. They go straight
--      to you (addon whisper), are never public, never show who sent them, and only
--      appear once 2+ different players have sent you some for that role.
-- Feedback about ratings only unlocks after 3 different players rated you in a role,
-- so nobody can tell which single groupmate rated them low.

local _, ns = ...

local KEEP_SUGGESTIONS_DAYS = 90
local MIN_SUGGESTERS = 2

------------------------------------------------------------------------
-- How-to guides
------------------------------------------------------------------------
-- Class abilities named here are the Classic ones; Forever changes some classes,
-- so guides say what to look for rather than relying on exact spell names.
ns.GUIDES = {
    marking = {
        title = "Marking targets",
        body = {
            "Marks tell the whole group what to kill first and what to crowd control, so nobody has to guess mid-pull.",
            "|cffffd100How to mark:|r Target an enemy, right-click its portrait, and pick an icon from the target marker menu. In a party anyone can mark; in a raid only the leader and assistants can.",
            "|cffffd100Faster:|r Open Options, Key Bindings, and look for the target marker (raid target icon) bindings. Bind Skull and Cross to easy keys and mark with one press.",
            "|cffffd100Common meanings:|r Skull = kill first. Cross (X) = kill second. Moon = Mage Polymorph. Star = Rogue Sap. Square = Hunter Freezing Trap. Diamond = Warlock Banish or Fear. Circle = Priest Shackle Undead. Triangle = Druid Hibernate. Groups vary, so say your system in chat before the first pull.",
            "|cffffd100Good habits:|r Mark before you pull, not during. Skull the most dangerous mob (healers and casters first). When Skull dies, Cross becomes the target, so you only need to re-mark between pulls.",
        },
    },
    pulling = {
        title = "Pulling",
        body = {
            "A good pull is one pack at a time, at a pace the healer can keep up with.",
            "|cffffd100Before pulling:|r Check your healer's mana (their party frame or just ask). Wait if they're drinking. Mark first.",
            "|cffffd100Casters:|r Pull them around a corner (break line of sight) so they have to walk to you instead of casting from range.",
            "|cffffd100Watch for patrols:|r Look around before pulling. A patrol walking into a fight is the most common wipe.",
            "|cffffd100Tell the group:|r A quick \"pulling\" or a countdown helps DPS and healers get ready.",
        },
    },
    threat_tank = {
        title = "Holding threat (tanks)",
        body = {
            "Mobs attack whoever has the most threat on them. Your job is to stay on top of every mob that isn't crowd controlled.",
            "|cffffd100Open on Skull:|r Build threat on the kill target first, since that's where the DPS will hit.",
            "|cffffd100Spread threat:|r Tab between mobs and put a few threat abilities on each, or use your class's area threat ability on packs.",
            "|cffffd100Taunt:|r When a mob runs to someone else, taunt it back right away, then build threat on it again.",
            "|cffffd100Positioning:|r Turn the mobs away from the group so their cleaves and breaths hit only you.",
            "|cffffd100Check yourself:|r The game's threat display on the target frame shows when you're about to lose a mob, if your settings have it turned on.",
        },
    },
    threat_dps = {
        title = "Watching threat (DPS)",
        body = {
            "If you pull a mob off the tank, the healer has to save you and the group slows down.",
            "|cffffd100Give the tank a head start:|r Wait a couple of seconds, or for a few tank attacks, before going all-out.",
            "|cffffd100Hit the right target:|r Attack Skull, the mob the tank is building threat on. Switching to an unmarked mob is the fastest way to pull aggro.",
            "|cffffd100Use your threat tools:|r Many classes have an ability that drops threat (for example Feign Death, Fade or Vanish in Classic). Learn yours and use it when a mob turns to you.",
            "|cffffd100If you pull aggro:|r Stop attacking and move toward the tank so they can grab it. Running away drags the mob out of reach.",
        },
    },
    mana = {
        title = "Managing mana (healers)",
        body = {
            "Running out of mana mid-fight is how groups wipe, so pace yourself across the whole dungeon.",
            "|cffffd100Drink between pulls:|r Drink whenever you're low, and say \"drinking\" or \"need mana\" so the tank waits.",
            "|cffffd100Efficient heals:|r Use your smaller, cheaper heals for steady damage and save the big expensive ones for emergencies.",
            "|cffffd100Regen rule:|r In Classic-style rules, mana regenerates faster once you've stopped casting for about five seconds, so short pauses help.",
            "|cffffd100Don't overheal:|r Start casting a little before damage lands, but avoid topping off someone who's already nearly full.",
        },
    },
    dispels = {
        title = "Dispelling",
        body = {
            "Many debuffs (curses, poisons, diseases, magic) can be removed. Removing them quickly saves health and mana.",
            "|cffffd100Know what you can remove.|r In Classic: Priests remove Magic and Disease, Paladins remove Magic, Poison and Disease, Druids remove Curse and Poison, Mages remove Curses, Shamans remove Poison and Disease. Check your own spellbook, since Forever changes some classes.",
            "|cffffd100See debuffs:|r Turn on debuff display for party frames in the game's options so you can spot them.",
            "|cffffd100Bind it:|r Put your dispel on an easy key or mouse button so it's as quick as a heal.",
            "|cffffd100Prioritize:|r Dispel dangerous debuffs first (silences, fears, heavy damage over time); ignore harmless ones when mana is tight.",
        },
    },
    healing = {
        title = "Keeping the group alive",
        body = {
            "|cffffd100Stay in range and in sight:|r Stand where you can see the tank and the group, out of cleave range. Corners and pillars block your heals.",
            "|cffffd100Watch the tank first:|r Most damage goes to the tank. Keep an eye on them, then the rest of the party.",
            "|cffffd100Get ahead of big damage:|r Learn which bosses hit hardest and start heals early.",
            "|cffffd100Speak up:|r Tell the group if you're low on mana, out of range or need a pause.",
        },
    },
    cc = {
        title = "Crowd control",
        body = {
            "Crowd control takes a mob out of the fight so the group faces fewer at once.",
            "|cffffd100Classic examples:|r Mage Polymorph (beasts, humanoids), Rogue Sap (humanoids, before combat), Hunter Freezing Trap, Warlock Banish (demons, elementals), Priest Shackle Undead, Druid Hibernate (beasts, dragonkin). Forever may change some of these, so check your spellbook.",
            "|cffffd100Use the marks:|r If the tank marks Moon or Star, that mob is yours to control. If no one marks, offer: \"I can sheep one.\"",
            "|cffffd100Don't break it:|r Avoid area attacks near controlled mobs, and recast before it runs out.",
        },
    },
    damage = {
        title = "Doing more damage",
        body = {
            "|cffffd100Use the built-in damage meter:|r Forever has one. Compare your own runs over time rather than worrying about others.",
            "|cffffd100Stay on target and keep attacking:|r Downtime (running, idling, waiting too long) costs more damage than a slightly imperfect rotation.",
            "|cffffd100Learn your class's priority:|r A class guide for your spec explains which abilities to press first.",
            "|cffffd100Bring consumables and buffs:|r Food, elixirs and asking for class buffs add up.",
        },
    },
    fights = {
        title = "Knowing the fights",
        body = {
            "|cffffd100Read up before the run:|r A two-minute look at a dungeon guide covers the dangerous bosses and packs.",
            "|cffffd100Say it's your first time:|r Groups are usually happy to explain, and it beats a surprise wipe.",
            "|cffffd100Forever's new dungeons:|r Everyone is still learning these, so watch others and ask.",
            "|cffffd100Know your job per boss:|r Some fights need you to move, interrupt or dispel at specific moments.",
        },
    },
    loot = {
        title = "Loot etiquette",
        body = {
            "|cffffd100Need only for real upgrades:|r Roll Need on items for your main spec that you'll actually use. Greed otherwise.",
            "|cffffd100Ask first:|r If you want something for an off-spec or a friend, ask the group before rolling Need.",
            "|cffffd100Agree on rules early:|r Settle questions about special items before the first boss, not after it drops.",
        },
    },
    teaching = {
        title = "Helping new players",
        body = {
            "|cffffd100Explain before, not after:|r A short heads-up about a tricky pull prevents the wipe and the blame.",
            "|cffffd100Keep it kind:|r Everyone learns faster when mistakes don't get yelled at.",
            "|cffffd100Point to resources:|r Mention MOO's guides or a dungeon guide when someone wants to learn.",
        },
    },
    etiquette = {
        title = "Being a great groupmate",
        body = {
            "|cffffd100Say hi and say thanks:|r It costs nothing and people remember it.",
            "|cffffd100Communicate:|r Tell the group when you need a break, are low on mana, or have to leave.",
            "|cffffd100Stay to the end:|r Finishing the run you joined is the best way to get invited again.",
        },
    },
}

------------------------------------------------------------------------
-- What each compliment tag means for coaching
------------------------------------------------------------------------
ns.TAG_TIPS = {
    [1]  = { guide = "pulling",     tip = "Groupmates rarely mention your pulls. Steady, one-pack pulls at the healer's pace get noticed." },
    [2]  = { guide = "threat_tank", tip = "Few groupmates call out your threat. Spreading threat across the pack keeps mobs off them." },
    [3]  = { guide = "marking",     tip = "Groupmates rarely mention marks. Marking a kill target before each pull makes runs smoother." },
    [4]  = { guide = "healing",     tip = "\"Kept us alive\" comes up less than usual. Staying in range and watching the tank first helps." },
    [5]  = { guide = "mana",        tip = "\"Smart mana\" comes up less than usual. Pacing mana and drinking between pulls helps." },
    [6]  = { guide = "dispels",     tip = "Quick dispels are rarely mentioned. Binding your dispel to an easy key speeds it up." },
    [7]  = { guide = "damage",      tip = "\"Big damage\" comes up less than usual. Staying on target and cutting downtime adds a lot." },
    [8]  = { guide = "cc",          tip = "Crowd control is rarely mentioned. Offering to control a marked mob helps the whole group." },
    [9]  = { guide = "threat_dps",  tip = "\"Watched threat\" comes up less than usual. Giving the tank a head start avoids pulling aggro." },
    [10] = { guide = "etiquette",   tip = "\"Friendly\" comes up less than usual. A hello and a thanks go a long way." },
    [11] = { guide = "fights",      tip = "\"Knew the fights\" comes up less than usual. A quick read of the bosses before a run helps." },
    [12] = { guide = "loot",        tip = "\"Fair on loot\" comes up less than usual. Asking before rolling Need on off-spec items helps." },
    [13] = { guide = "teaching",    tip = "\"Patient teacher\" is a great tag to aim for. Explaining pulls before they happen helps new players." },
}

------------------------------------------------------------------------
-- Private suggestions groupmates can send (preset only, kind wording)
-- The bit index never changes once released.
------------------------------------------------------------------------
ns.SUGGESTIONS = {
    { bit = 1,  role = "TANK", label = "Mark a kill target",      guide = "marking" },
    { bit = 2,  role = "TANK", label = "One pack at a time",      guide = "pulling" },
    { bit = 3,  role = "TANK", label = "Threat on more mobs",     guide = "threat_tank" },
    { bit = 4,  role = "HEAL", label = "Watch mana before pulls", guide = "mana" },
    { bit = 5,  role = "HEAL", label = "Dispel sooner",           guide = "dispels" },
    { bit = 6,  role = "HEAL", label = "Stay in range",           guide = "healing" },
    { bit = 7,  role = "DPS",  label = "Let the tank get threat", guide = "threat_dps" },
    { bit = 8,  role = "DPS",  label = "Follow the kill order",   guide = "marking" },
    { bit = 9,  role = "DPS",  label = "Use your CC",             guide = "cc" },
    { bit = 10, role = "ANY",  label = "Read up on the bosses",   guide = "fights" },
    { bit = 11, role = "ANY",  label = "Ask before Need",         guide = "loot" },
}
ns.SUGGESTION_BY_BIT = {}
for _, sug in ipairs(ns.SUGGESTIONS) do ns.SUGGESTION_BY_BIT[sug.bit] = sug end

function ns.SuggestionsForRole(role)
    local out = {}
    for _, sug in ipairs(ns.SUGGESTIONS) do
        if sug.role == role or sug.role == "ANY" then table.insert(out, sug) end
    end
    return out
end

------------------------------------------------------------------------
-- Sending and receiving private suggestions
------------------------------------------------------------------------
function ns.SendSuggestions(runId, ratee, mask)
    mask = math.floor(tonumber(mask) or 0)
    if mask <= 0 or not ns.IsOptedIn() then return end
    ns.Send("WHISPER", { "S", runId, mask }, ratee)
end

local function myRun(runId)
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

ns.Handle("S", function(sender, f, dist)
    if dist ~= "WHISPER" then return end
    if not ns.IsOptedIn() or MOO_CharDB.suggestionsOff then return end
    local runId, mask = f[2], ns.Clamp(f[3], 0, 2 ^ 11 - 1, 0)   -- 11 suggestion bits exist
    if type(runId) ~= "string" or #runId > 12 or mask <= 0 then return end
    local r = myRun(runId)
    if not r or not r.roster[sender] then return end   -- only from people who were in that run
    MOO_CharDB.suggestions = MOO_CharDB.suggestions or {}
    local from = ns.Hash("from:" .. sender)            -- never store who sent it, only a hash to count
    for _, e in ipairs(MOO_CharDB.suggestions) do
        if e.run == runId and e.from == from then return end  -- one per person per run
    end
    table.insert(MOO_CharDB.suggestions, 1, {
        run = runId, inst = r.inst, role = r.role, mask = mask, from = from, ts = ns.Now(),
    })
    while #MOO_CharDB.suggestions > 200 do table.remove(MOO_CharDB.suggestions) end
    ns.Fire("COACH_UPDATED")
end)

------------------------------------------------------------------------
-- Building the feedback
------------------------------------------------------------------------
-- Returns { status = "text", strengths = "text", items = { {kind, text, guide}, ... } }
function ns.CoachFeedback(role)
    local out = { items = {} }
    local p = ns.GetProfile(ns.Me())
    local pr = p.roles[role]
    local label = ns.ROLE_LABEL[role] or role

    if not pr then
        out.status = "No ratings as " .. label .. " yet. Run a dungeon with other MOO players."
    elseif pr.nRaters < ns.MIN_RATERS then
        out.status = "Rating feedback unlocks once " .. ns.MIN_RATERS .. " different players rate you as " ..
            label .. " (" .. pr.nRaters .. " so far). This keeps raters anonymous."
    else
        out.status = string.format("As %s: %s from %d ratings by %d players.",
            label, ns.StarsText(pr.avg), pr.count, pr.nRaters)

        -- 1. Tips from tags: compare my tag rates with the typical rate for this role
        -- With little data to compare against, only role tags count, and only after 5 ratings.
        local base = ns.TagBaseline(role)
        local haveBase = base and base.total >= 20
        local strengths, tips = {}, {}
        for _, tag in ipairs(ns.TagsForRole(role)) do
            local mine = (pr.tags[tag.bit] or 0) / pr.count
            local typical = haveBase and ((base.tags[tag.bit] or 0) / base.total) or 0.25
            local eligible = ns.TAG_TIPS[tag.bit] and tag.bit ~= 13 and (haveBase or tag.role ~= "ANY")
            if mine >= math.max(0.2, typical) then
                table.insert(strengths, tag.label)
            elseif eligible and pr.count >= 5 and typical >= 0.1 and mine < typical * 0.5 then
                table.insert(tips, { gap = typical - mine, bit = tag.bit })
            end
        end
        -- the three biggest gaps only, so it reads as advice rather than a list of faults
        table.sort(tips, function(a, b) return a.gap > b.gap end)
        for i = 1, math.min(3, #tips) do
            local t = ns.TAG_TIPS[tips[i].bit]
            table.insert(out.items, { kind = "tip", text = t.tip, guide = t.guide })
        end
        if #strengths > 0 then out.strengths = "Groupmates often say: " .. table.concat(strengths, ", ") .. "." end

        -- 2. Instance trends: clearly below my average, with enough different raters
        for instKey, roles in pairs(p.inst) do
            local pi = roles[role]
            if pi and pi.nRaters >= ns.MIN_RATERS and (pr.avg - pi.avg) >= 0.5 then
                table.insert(out.items, {
                    kind = "inst",
                    text = string.format("Your %s rating in %s is %.1f, below your %.1f average. Reading up on its bosses may help.",
                        label, ns.InstanceName(instKey), pi.avg, pr.avg),
                    guide = "fights",
                })
            end
        end
    end

    -- 3. Private suggestions (separate threshold: 2+ different senders)
    local cutoff = ns.Now() - KEEP_SUGGESTIONS_DAYS * 86400
    local counts, senders, nSenders = {}, {}, 0
    for _, e in ipairs(MOO_CharDB.suggestions or {}) do
        if e.ts >= cutoff and e.role == role then
            if not senders[e.from] then senders[e.from] = true; nSenders = nSenders + 1 end
            for _, sug in ipairs(ns.SUGGESTIONS) do
                if ns.TagMaskHas(e.mask, sug.bit) then counts[sug.bit] = (counts[sug.bit] or 0) + 1 end
            end
        end
    end
    if nSenders >= MIN_SUGGESTERS then
        local list = {}
        for b, c in pairs(counts) do table.insert(list, { bit = b, count = c }) end
        table.sort(list, function(a, b) return a.count > b.count end)
        for _, it in ipairs(list) do
            local sug = ns.SUGGESTION_BY_BIT[it.bit]
            if sug then
                table.insert(out.items, {
                    kind = "sugg",
                    text = string.format("Groupmates suggested \"%s\" %d time%s.", sug.label, it.count, it.count == 1 and "" or "s"),
                    guide = sug.guide,
                })
            end
        end
    elseif nSenders == 1 then
        out.suggestNote = "You have private suggestions from 1 player. They show once a second player sends some, so you can't tell who sent them."
    end

    if #out.items == 0 and pr and pr.shown then
        table.insert(out.items, { kind = "good", text = "Nothing stands out to work on. Keep it up!" })
    end
    return out
end

function ns.SetSuggestionsOn(on)
    MOO_CharDB.suggestionsOff = not on
    ns.Print(on and "You'll receive private suggestions from groupmates." or "Private suggestions are off.")
    ns.Fire("COACH_UPDATED")
end

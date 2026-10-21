# Muster Of Olympus (MOO)

A group finder, ready check and player rating system for **Olympus guilds** in *World of Warcraft: Forever*.

**Only works for members of an Olympus guild.**

*A fan project. Not affiliated with Blizzard Entertainment, Asmongold or the Olympus leadership.*

## What it does

**Group finder (Dungeons, Raids, PvP).** List a group by picking the instance from a dropdown, setting how many Tanks, Healers and DPS you still need, a minimum level and a short note. Other Olympus players see it across every Olympus guild on the realm. Hover a listing to see who's in the group, or click it to open the group card. Battlegrounds and World PvP use the same finder, but **World PvP has no ratings** anywhere. Your own listing sits at the top of its list, marked *(your group)*, so you can see it really went out.

**Quests tab.** Find help with group quests. Pick a quest from your own quest log (Group and Elite quests come first, and the zone fills itself in) or type a custom name for an elite, a rare or anything else, then set how many players you need. Listings for quests you also have are marked with a check and shown first, and you can filter the list by zone. Quest listings come down by themselves after 20 minutes; list again to keep yours up.

**Players tab.** Mark yourself available for anything MOO lists, across categories, in one go: e.g. three dungeons plus "Any World PvP" (up to 12 picks; each category also has an "Any" option), in every role you can play (e.g. Tank and Healer for a Druid or Paladin). Leaders see what you want and which roles you play, can filter to "fits my listing", and click **Invite**. Once your availability has really gone out, you see yourself at the top of the list marked *(you)* with a green check, and a "You're listed" line at the top of the tab. When you join a group while listed in more than one role, MOO reminds you to set the role you'll play, since that's the role you're rated in.

**Applications with gear and stats.** When you apply, your addon sends the leader (and only the leader) your equipped items and basic stats. The leader sees item names with real tooltips, average item level, and stats like Str, Agi, Sta, Int, crit and spell power. Gear is marked *self-reported* until you join the group and stand near the leader. MOO then inspects you once and marks it *verified* or *changed*.

**My Group tab.** Shows applicants with role, item level, rating and gear status, with **Details**, **Invite** and **Decline** buttons. Under them is your group roster with roles, ratings and who has MOO. It also has a **Ready check** button, the live answer of each member and a role count (tanks, healers, DPS).

**Ratings.** Ratings only exist for dungeons and raids. After a dungeon or raid, rate your groupmates with 1 to 5 stars plus compliment tags such as *Great pulls*, *Kept us alive*, *Good CC* or *Patient teacher*. A player's card shows:
- their average for each role they played,
- their average for each dungeon or raid,
- the tags they get most often.

**Coach tab.** Coaching for the role you pick, built only from what groupmates say (MOO can't see combat data, so it never judges your numbers):
- **Tips from your tags:** compliments you get much less often than typical players in your role, with up to three tips.
- **Instance trends:** dungeons or raids where your rating is clearly below your average.
- **Private tips:** in the rating window, groupmates can pick preset tips such as "Mark a kill target" or "Watch mana before pulls". They go only to you, never show who sent them, and appear once 2 different players have sent some. Turn them off with `/moo suggestions off`.
- **How-to guides:** every tip has a "How to" button, e.g. how to mark targets, what each marker usually means, pulling, threat, mana, dispels, crowd control and loot etiquette. `/moo guide marking` opens one directly.

Rating feedback unlocks after 3 different players rate you in a role, so you can't tell which groupmate rated you low.

**Update notices.** When a newer MOO is out on CurseForge, MOO tells you once per session in chat and in the window title. Only releases the author has marked count, so test builds never trigger it.

**Tell my guild.** A button in the window header (and under any empty group list) shows a short line about MOO and a link, and posts it to your guild chat only when you click "Post to guild chat". Once every 3 hours per character.

**Feedback tab.** Send a bug report, idea or comment to MOO's author from inside the game. It's delivered when the author is next online and saved on the author's computer.

## How ratings work

Ratings stay private and travel only where they're needed. There's no shared database and nothing is broadcast.

1. **After a dungeon or raid**, each rating is whispered straight to the player it's about, and resent (for up to 7 days) until their MOO confirms it arrived.
2. **Each player's MOO keeps the ratings about them**, and only accepts ratings from players its own record shows were in that run with them. The role and instance come from the rated player's own record.
3. **When you apply to a group**, your rating summary goes to the leader with your gear. **When you join a group**, it's shared with the group. Nobody else ever sees it: listings and the Players tab don't show ratings.
4. **The leader's MOO quietly double-checks** a few of your ratings with the players who gave them, if they're online. If one doesn't match, your rating just isn't shown to that leader.
5. A role's score shows only once **3 different players** have rated it, so nobody can tell which groupmate gave which rating. Ratings older than 180 days drop off.
6. **Rating is opt-in.** You opt in to list, apply or mark yourself available; `/moo optout` stops new ratings reaching you.

## Requirements and how "Olympus only" works

> **Alpha:** cross-guild works right away on an open hidden channel, with no officer setup (`ns.REQUIRE_KEY = false` in `Core.lua`). Officers can still seal it with `/moo key`. Setting `REQUIRE_KEY = true` makes the key mandatory, as described below.

- **Your guild must be an Olympus guild.** MOO checks your guild's name (OLYMPVS, Olympos, Olimpo and other spellings count; "Anti Olympus", "Olympia" and "Olympic" don't). Outside one, MOO stays off and ignores everything.
- **Cross-guild features need an officer key.** Until a guild master or officer (the rank right below) types `/moo key <secret>`, MOO only works inside your own guild, where every sender is a guildmate. The key reaches guildmates automatically over guild addon messages, and MOO only accepts it from someone your own roster shows as an officer. Officers of different Olympus guilds use the same secret (agree on it in the officers' Discord) so all guilds share one sealed channel. `/moo key clear` turns it off.
- **Other players' guilds are checked when the game shows them.** When a player is in your group, targeted, moused over or on a nameplate, MOO remembers their guild. Players seen in a non-Olympus guild are marked "(not Olympus)" and their messages are ignored; players MOO hasn't seen yet are marked "(unverified)". Hover a name for details.
- **The Olympus addon is recommended** (optional dependency). MOO keeps working if it's missing or changes; when it's loaded, the MOO window has a button to open it.

## With the Olympus addon

The Olympus addon has its own group finder on its Board. When an Olympus version with its group API is installed, MOO can work as the heavier layer on top of it instead of running a second group finder next to it. Everyone with Olympus then sees every group, whether they run MOO or not.

- **You choose.** MOO's line appears on Olympus's privacy page (`/oly privacy`). Until you answer, and after a No, MOO works on its own exactly as described above.
- **After a Yes:**
  - Groups and players looking come from Olympus's Board, and MOO shows them on its Dungeons, Raids, PvP, Quests and Players tabs (quest groups for a quest in your own log come first, marked, and the zone filter works on the Board's quest groups too). "List a group" and "Apply" open Olympus's own dialog and group card, so you apply there yourself. MOO sends no listings or "available" flags of its own and stays off its hidden channel. "Raise a flag" on the Players tab opens Olympus's own flag, and "Invite" there invites a player looking as a role your listing needs, the way the Board does.
  - MOO's My Group panel (applicants with gear, iLvl and rating, your roster, the ready check) appears in the Board's "Your group" area. A switch above it ("Olympus's own") brings Olympus's own panel back at any time. Invite, Decline and Delist go through Olympus; to change what your listing needs, "Edit listing" opens Olympus's dialog.
  - MOO takes your Olympus membership from Olympus instead of checking your guild's name.
  - Gear, stats and your rating summary still go only by MOO whisper, and only to a leader who also runs MOO, after you applied to their listing on the Board.
  - Ratings, the Coach, the ready check and the Feedback tab work as always.
- `/moo status` shows whether MOO is working with the Board or on its own, and why.

## Commands

`/moo` is shared with the game's own `/moo` emote, on purpose. Plain `/moo` (or `/moo PlayerName`) still moos, like always. `/moo` followed by a MOO command runs the addon. Anything that isn't a MOO command moos, so if you forget a command, you moo at someone.

| Command | |
|---|---|
| `/mooo` or `/moo open` | open or close the window |
| `/moo help` | list the commands |
| `/moo optin` / `/moo optout` | join or leave ratings and groups |
| `/moo role tank\|heal\|dps` | your default role |
| `/moo rc` | start a ready check (leader or raid assistant) |
| `/moo rate` | reopen the rating window for your last run |
| `/moo who Name` | show a player's ratings |
| `/moo quests` | open the Quests tab (group quests) |
| `/moo share` | tell your guild about MOO (same as the "Tell my guild" button) |
| `/moo coach` | open the Coach tab (tips for your role) |
| `/moo feedback` | send feedback to MOO's author |
| `/moo guide <topic>` | open a how-to guide (e.g. marking, pulling, mana) |
| `/moo suggestions on\|off` | receive private tips from groupmates or not |
| `/moo key <secret>` / `clear` | officers: turn cross-guild features on (or off) for your guild |
| `/moo instance` | the current instance's ID; MOO remembers it |
| `/moo instance link KEY` / `forget` / `keys` | fix a match, undo it, or list the keys |
| `/moo instances` / `export` | every instance you've visited, in chat or a copy window |
| `/moo minimap` | show or hide the minimap button |
| `/moo sound on`/`off` | applicant and recruit alert sounds (also a button on the My Group tab) |
| `/moo theme dark`/`classic` | dark look or the game's classic look (also a button in the window header) |
| `/moo status` | diagnostics |
| `/moo bug` | a copyable bug report (version, status, recent errors) |
| `/moo recruit on\|off` | (author only) while on, tester requests in whispers pop up with a one-click reply |
| `/moo recruit link <link>` | the download link the reply sends |
| `/moo recruit message <text>` | your own reply text (`{link}` marks where the link goes) |
| `/moo recruit list` | everyone who asked and when you replied, in a copy window |
| `/moo release <version>` / `off` | (author only) once a version is live on CurseForge, tell older MOOs to update |

Players whose character is literally named after a command (e.g. "Rate") can't be mooed at by name. Left-click the minimap button to open MOO; right-click it for My Group and the ready check.

## Staying within Blizzard's and CurseForge's rules

- **Free and readable.** MOO is MIT licensed, with no obfuscated code, no ads, no donation requests and no paid features.
- **No automation.** Every invite, decline, ready check and raid conversion is a click by the player. MOO never accepts invites, queues, joins or answers a ready check for anyone.
- **No combat data.** MOO reads no combat logs, damage, healing, health or cooldowns. Ratings are opinions from people, not calculations. Gear and stats are your own character's, read out of combat.
- **Respects Forever's addon restrictions.** MOO sends nothing from inside a dungeon, raid or battleground. Messages wait until you're out, and the rating window only opens outside instances. API values the game marks "secret" are skipped.
- **Light on the servers.** MOO sends at most one message every 1.2 seconds. Listings repeat every 90 seconds. Each client resends only its own ratings, 8 records every 10 minutes.
- **Privacy.** Gear goes only to a leader you apply to, or to a leader with an open listing while you're marked available (with Olympus's Board: only to a leader running MOO whose listing you applied to). Nothing leaves the game, and there's no website or server.
- **Typed text is reportable.** Notes on listings, availability and applications (and the names of instances MOO added) go through Blizzard's logged addon-message API, which Blizzard asks addons to use for player-written text so abuse can be reported under the Code of Conduct.
- **Positive tags only.** This keeps the rating system from becoming a harassment tool, in line with Blizzard's Code of Conduct and CurseForge's content policies.

### Security

Every message from another player is treated as untrusted:
- **No injected text.** Names, roles, classes, categories, instance keys and numbers are validated; notes and instance names have escape codes stripped. Nobody can put colors, textures or fake links into MOO's windows.
- **Flood guard.** A player sending more than 40 MOO messages a minute is ignored for 10 minutes. Application alerts play at most once per applicant per 30 seconds, and gear requests are answered once a minute per leader.
- **Small, private storage.** MOO only stores ratings about you and ratings you gave, capped and dropped after 180 days. Ratings are only accepted from players who were in that run with you.
- **No unsolicited data.** Gear and stats are only accepted from your applicants, players you asked, and your group. Instance names other players send are display-only and never enter your menus.
- **Logged text.** Anything a player types travels through Blizzard's logged addon messages and is only accepted that way, so it can be reported.

Known limits: anyone can create a guild with "Olympus" in its name, and players whose guild MOO hasn't seen yet are only marked "unverified"; the officer key reaches every member's MOO, so a member could leak it (an officer can change it any time); a player with a modified addon could hide their own bad ratings (spot-checks catch made-up ratings, not missing ones); friends who group together can rate each other; and anyone with a listing can ask available players for their gear (the same gear anyone can inspect in the world).

### CurseForge page checklist

- Describe exactly what MOO does on the project page (CurseForge rejects vague descriptions).
- Disclose that AI helped write the code, per CurseForge's AI disclosure policy.
- Keep the "fan project, not affiliated" line, and add the project's license.

### A note on the name

"MOO" stands for Muster Of Olympus. Before publishing, search CurseForge for "MOO" to make sure no other WoW addon already uses it, and consider getting a nod from the Olympus leadership since the addon uses the guild's name.

## Testing

See `TESTING.md` for the tester checklist. Install BugSack and BugGrabber to catch errors, and use `/moo bug` to copy a report.

## Before you publish: test on the Forever beta

This code was written against the Midnight-era API that Forever uses. It has not been run in the game yet. Check these first:

1. **Interface number.** `16001` is confirmed for the Forever beta (build 1.60.1).
2. **Instance IDs.** MOO remembers every instance ID it sees, on its own, for your whole account. Entering an instance (or typing `/moo instance` inside one) matches it to MOO's list by ID or by the game's instance name and saves the ID. An instance MOO doesn't know is added under the game's name, so it shows in the group finder and its runs can be rated. `/moo instance link KEY` fixes a wrong match, `/moo instance forget` undoes one, and `/moo instances export` opens a copyable list to send to the author for `Data.lua`.
3. **Gear APIs.** Check that `GetAverageItemLevel`, `UnitStat` and the crit and spell power functions return numbers on Forever. Anything that errors or comes back secret shows as 0 or is hidden.
4. **`/moo` sharing.** Check that plain `/moo` and `/moo Name` still play the emote, and that `/moo help` and `/mooo` open MOO.
5. **Two-client test.** Have two opted-in players finish a short dungeon. Both should get the rating window, and the ratings should show on a third client after 3 players rate.

## Install

Put the `MOO` folder in `World of Warcraft\_classic_beta_\Interface\AddOns\` (or the Forever folder at launch), so you end up with `AddOns\MOO\MOO.toc`. Then restart the game.

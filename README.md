# Muster Of Olympus (MOO)

A group finder, ready check and player rating system for **Olympus guilds** in *World of Warcraft: Forever*.

**Only works for members of an Olympus guild.**

*A fan project. Not affiliated with Blizzard Entertainment, Asmongold or the Olympus leadership.*

## What it does

**Group finder (Dungeons, Raids, PvP).** List a group by picking the instance from a dropdown, setting how many Tanks, Healers and DPS you still need, a minimum level and a short note. Other Olympus players see it across every Olympus guild on the realm. Each listing shows the group's combined rating; hover it to see every member's rating, or click it to open the group card with each member's role, rating and best-known tags. Battlegrounds and World PvP use the same finder, but **World PvP has no ratings** anywhere.

**Players tab.** Mark yourself available for several dungeons, raids or battlegrounds at once (up to 12, or "Anything"), in every role you can play (e.g. Tank and Healer for a Druid or Paladin). Leaders see what you want and your rating in each role, can filter to "fits my listing", and click **Invite**. When you join a group while listed in more than one role, MOO reminds you to set the role you'll play, since that's the role you're rated in.

**Applications with gear and stats.** When you apply, your addon sends the leader (and only the leader) your equipped items and basic stats. The leader sees item names with real tooltips, average item level, and stats like Str, Agi, Sta, Int, crit and spell power. Gear is marked *self-reported* until you join the group and stand near the leader. MOO then inspects you once and marks it *verified* or *changed*.

**My Group tab.** Shows applicants with role, item level, rating and gear status, with **Details**, **Invite** and **Decline** buttons. Under them is your group roster with roles, ratings and who has MOO. It also has a **Ready check** button, the live answer of each member and a role count (tanks, healers, DPS).

**Ratings.** Ratings only exist for dungeons and raids. After a dungeon or raid, rate your groupmates with 1 to 5 stars plus compliment tags such as *Great pulls*, *Kept us alive*, *Good CC* or *Patient teacher*. A player's card shows:
- their average for each role they played,
- their average for each dungeon or raid,
- the tags they get most often.

**Feedback tab.** Coaching for the role you pick, built only from what groupmates say (MOO can't see combat data, so it never judges your numbers):
- **Tips from your tags:** compliments you get much less often than typical players in your role, with up to three tips.
- **Instance trends:** dungeons or raids where your rating is clearly below your average.
- **Private tips:** in the rating window, groupmates can pick preset tips such as "Mark a kill target" or "Watch mana before pulls". They go only to you, never show who sent them, and appear once 2 different players have sent some. Turn them off with `/moo suggestions off`.
- **How-to guides:** every tip has a "How to" button, e.g. how to mark targets, what each marker usually means, pulling, threat, mana, dispels, crowd control and loot etiquette. `/moo guide marking` opens one directly.

Rating feedback unlocks after 3 different players rate you in a role, so you can't tell which groupmate rated you low.

## How ratings stay honest (no server needed)

1. MOO notices when your group enters a dungeon or raid and remembers who was in it.
2. When you leave and stay out for 90 seconds, your addon confirms the run: which instance, the role you played, and who you were with.
3. A rating from A about B counts **only if both A's and B's addons confirmed the same run naming each other**. The game puts each sender's name on every message, so nobody can confirm or rate in someone else's name.
4. The role on a rating comes from the rated player's own confirmation, not from the rater.
5. A score is hidden until **3 different players** have rated that role.
6. The same leader running the same instance on the same day counts as one run. This stops friends farming stars for each other.
7. Runs shorter than 5 minutes aren't rated. Ratings older than 180 days drop off.
8. Tags are compliments only. Low stars are the only way to rate a bad run, so no one can be insulted through MOO.

**Opt-in.** Rating is opt-in, and you must opt in to list, apply or mark yourself available. `/moo optout` stops new runs counting for you right away.

## Requirements and how "Olympus only" works

> **Alpha:** cross-guild works right away on an open hidden channel, with no officer setup (`ns.REQUIRE_KEY = false` in `Core.lua`). Officers can still seal it with `/moo key`. Setting `REQUIRE_KEY = true` makes the key mandatory, as described below.

- **Your guild must be an Olympus guild.** MOO checks your guild's name (OLYMPVS, Olympos, Olimpo and other spellings count; "Anti Olympus", "Olympia" and "Olympic" don't). Outside one, MOO stays off and ignores everything.
- **Cross-guild features need an officer key.** Until a guild master or officer (the rank right below) types `/moo key <secret>`, MOO only works inside your own guild, where every sender is a guildmate. The key reaches guildmates automatically over guild addon messages, and MOO only accepts it from someone your own roster shows as an officer. Officers of different Olympus guilds use the same secret (agree on it in the officers' Discord) so all guilds share one sealed channel. `/moo key clear` turns it off.
- **Other players' guilds are checked when the game shows them.** When a player is in your group, targeted, moused over or on a nameplate, MOO remembers their guild. Players seen in a non-Olympus guild are marked "(not Olympus)" and their messages are ignored; players MOO hasn't seen yet are marked "(unverified)". Hover a name for details.
- **The Olympus addon is recommended** (optional dependency). MOO keeps working if it's missing or changes; when it's loaded, the MOO window has a button to open it.

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
| `/moo feedback` | open the Feedback tab |
| `/moo guide <topic>` | open a how-to guide (e.g. marking, pulling, mana) |
| `/moo suggestions on\|off` | receive private tips from groupmates or not |
| `/moo key <secret>` / `clear` | officers: turn cross-guild features on (or off) for your guild |
| `/moo instance` | the current instance's ID; MOO remembers it |
| `/moo instance link KEY` / `forget` / `keys` | fix a match, undo it, or list the keys |
| `/moo instances` / `export` | every instance you've visited, in chat or a copy window |
| `/moo minimap` | show or hide the minimap button |
| `/moo theme dark`/`classic` | dark look or the game's classic look (also a button in the window header) |
| `/moo status` | diagnostics |
| `/moo bug` | a copyable bug report (version, status, recent errors) |
| `/moo recruit on\|off` | (author only) while on, tester requests in whispers pop up with a one-click reply |
| `/moo recruit link <link>` | the download link the reply sends |
| `/moo recruit message <text>` | your own reply text (`{link}` marks where the link goes) |
| `/moo recruit list` | everyone who asked and when you replied, in a copy window |

Players whose character is literally named after a command (e.g. "Rate") can't be mooed at by name. Left-click the minimap button to open MOO; right-click it for My Group and the ready check.

## Staying within Blizzard's and CurseForge's rules

- **Free and readable.** MOO is MIT licensed, with no obfuscated code, no ads, no donation requests and no paid features.
- **No automation.** Every invite, decline, ready check and raid conversion is a click by the player. MOO never accepts invites, queues, joins or answers a ready check for anyone.
- **No combat data.** MOO reads no combat logs, damage, healing, health or cooldowns. Ratings are opinions from people, not calculations. Gear and stats are your own character's, read out of combat.
- **Respects Forever's addon restrictions.** MOO sends nothing from inside a dungeon, raid or battleground. Messages wait until you're out, and the rating window only opens outside instances. API values the game marks "secret" are skipped.
- **Light on the servers.** MOO sends at most one message every 1.2 seconds. Listings repeat every 90 seconds. Each client resends only its own ratings, 8 records every 10 minutes.
- **Privacy.** Gear goes only to a leader you apply to, or to a leader with an open listing while you're marked available. Nothing leaves the game, and there's no website or server.
- **Typed text is reportable.** Notes on listings, availability and applications (and the names of instances MOO added) go through Blizzard's logged addon-message API, which Blizzard asks addons to use for player-written text so abuse can be reported under the Code of Conduct.
- **Positive tags only.** This keeps the rating system from becoming a harassment tool, in line with Blizzard's Code of Conduct and CurseForge's content policies.

### Security

Every message from another player is treated as untrusted:
- **No injected text.** Names, roles, classes, categories, instance keys and numbers are validated; notes and instance names have escape codes stripped. Nobody can put colors, textures or fake links into MOO's windows.
- **Flood guard.** A player sending more than 40 MOO messages a minute is ignored for 10 minutes. Application alerts play at most once per applicant per 30 seconds, and gear requests are answered once a minute per leader.
- **Bounded storage.** Each player can add at most 30 runs and 200 ratings a day to your saved data; ratings never confirmed by both players are dropped after 3 days, unrated runs after 14 days, and totals are capped.
- **No unsolicited data.** Gear and stats are only accepted from your applicants, players you asked, and your group. Instance names other players send are display-only and never enter your menus.
- **Logged text.** Anything a player types travels through Blizzard's logged addon messages and is only accepted that way, so it can be reported.

Known limits: anyone can create a guild with "Olympus" in its name, and players whose guild MOO hasn't seen yet are only marked "unverified"; the officer key reaches every member's MOO, so a member could leak it (an officer can change it any time); three or more colluding accounts with modified addons could fake runs and rate each other; and anyone with a listing can ask available players for their gear (the same gear anyone can inspect in the world). Run confirmations are public to MOO users, so they show who grouped with whom.

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

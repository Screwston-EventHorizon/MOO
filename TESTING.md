# MOO tester checklist (alpha)

Thanks for testing! Install **BugSack + BugGrabber** first so errors get caught. When something breaks, type `/moo bug`, copy the text, and post it with what you did.

Testers from **different Olympus guilds** are especially useful: MOO connects all Olympus guilds on your realm automatically, no setup needed.

Note: the Forever beta sometimes forgets addon data at login, so ratings may reset between sessions. Test ratings within one play session.

## Solo (5 minutes)
- [ ] `/mooo` opens the window; all 7 tabs load; the header says "Cross-guild: on"
- [ ] Dropdowns open and pick correctly (Dungeons, Raids, PvP, Players, Feedback)
- [ ] Minimap button sits on the ring; left-click opens, right-click opens My Group; `/moo minimap` hides it
- [ ] Plain `/moo` still moos (and `/moo Name` moos at them); `/moo help` lists commands
- [ ] The Olympus button opens Olympus (if you have it)
- [ ] `/moo status` says you're in an Olympus guild and the channel is joined
- [ ] Opt in from the welcome screen

## Across guilds (2+ people in different Olympus guilds)
- [ ] A listing from someone in another Olympus guild shows up for you, and yours for them
- [ ] Their name shows "(unverified)" until you group with, target or see them; then the mark goes away
- [ ] Hovering a name shows their guild

## Group finder (2+ people)
- [ ] List a group; it shows for others with Tank / Healer / DPS needs and "Group ratings"
- [ ] Hover a listing: every member and their rating; click it: the group card
- [ ] Apply; the leader hears a sound and sees you in My Group with gear and stats
- [ ] Invite, Decline and Cancel all work; your button updates
- [ ] World PvP listings show no ratings anywhere

## Players tab (2+ people)
- [ ] List yourself for several dungeons and several roles
- [ ] A leader with a listing sees you, can filter "fits my listing", and can Invite you
- [ ] Joining a group while listed in 2+ roles reminds you to set your role

## Ratings and feedback (3+ people)
- [ ] Run a dungeon for 5+ minutes, leave, and stay out 90 seconds: the rating window appears
- [ ] Give stars, compliments and a private tip
- [ ] A rated player's score appears once 3 different players have rated them in that role
- [ ] Feedback tab: tips and "How to" guides open; private tips show once 2 players sent some
- [ ] Gear changes from "self-reported" to "verified" when you stand near a new groupmate

## Ready check
- [ ] Leader clicks Ready check in My Group; answers and role counts show live

## Officers (optional)
- [ ] `/moo key <secret>` seals the channel; guildmates get the key automatically
- [ ] Officers of another guild set the same secret: you still see each other
- [ ] `/moo key clear` goes back to the open channel

## Instances
- [ ] In each dungeon you visit, `/moo instance` shows its ID; at the end, post `/moo instances export`

---
name: wow-character
description: Read the user's World of Warcraft character from the ClaudeExport addon's SavedVariables file (quests and objectives, completed quests, talents, gear with stats, bags, stats, professions, spellbook, action bars with key bindings, buffs/debuffs, reputation, durability, history journal of quests/deaths/loot/dungeons), analyze the game's combat log (damage, healing, tanking, deaths, boss kills), and write a step-by-step plan the user opens in game with /cplan. Use whenever the user asks for WoW advice that depends on their character — leveling route, what to do next, quest help, talent build, gear upgrades, professions, dungeon prep, how a fight or dungeon run went — or says "read my export", "читай экспорт", "/cexp done", "готово, читай".
---

# WoW character from ClaudeExport

The **ClaudeExport** addon snapshots the character into the SavedVariables table `ClaudeExportDB`.
You read that file and advise from real data instead of asking for screenshots.

The addon is read-only (standard game API only, no automation). Never offer to read game memory,
inject into the client, or automate gameplay — that breaks the game's Terms of Service.

## 1. Find the file

The file is account-wide:

```
<WoW install>/<flavor folder>/WTF/Account/<ACCOUNT>/SavedVariables/ClaudeExport.lua
```

- Typical install roots: `C:\Program Files (x86)\World of Warcraft`, `C:\Games\World of Warcraft`,
  `D:\World of Warcraft`, macOS `/Applications/World of Warcraft`.
- Flavor folders: `_retail_`, `_classic_`, `_classic_era_`, `_anniversary_`, `_forever_`, `_ptr_`, `_beta_`…
- If the working directory is not the WoW folder, glob for `**/WTF/Account/*/SavedVariables/ClaudeExport.lua`
  under likely roots, or ask the user for the install path once. Remember the path if you have memory.
- Several accounts/flavors can each have a file: pick the one with the newest modification time, or ask.

Also check the file's modification time. It changes only on `/reload` or logout.

## 2. Read it efficiently

The file is a Lua table literal and can be 30–100 KB. Don't dump it all into context if you need one section:

- `ClaudeExportDB["last"]` = key of the most recently snapshotted character (`"Name-Realm"` or `"Name"`).
  Other keys are other characters on the account. A key ending in `-` is a stale entry from an
  old addon version; ignore it if a newer key for the same name exists.
- Each character entry has these sections. Grep for `["section"] = {` and read from there:

| Section | Contents |
|---|---|
| `meta` | addon version, client version/build, interface number, locale, snapshot time |
| `character` | name, realm, level, race, class, faction, xp / xpMax, rested, money (copper), zone, subzone, map position `pos` |
| `stats` | primary stats, armor, attack power, crit / hit / dodge / parry / block, spell power, weapon damage & speed |
| `talents` | `trees` (classic API: per tab, talents with tier/column/rank/maxRank) **or** `traits.nodes` (modern trees: name, spellID, rank, maxRank, x, y). `unspent` points |
| `quests` | active log: title, level, zone header, id, `complete`, objectives as `[x]` / `[ ]` lines, sometimes description |
| `completed` | `[questID] = "title"` or `= true` (title not cached). Every quest the character has turned in |
| `gear` | per slot: name, id, ilvl, quality (0 grey … 4 epic), reqLevel, type/subtype, stats (localized names) |
| `bags` | `items` (name, id, count, type, ilvl, quality), `freeSlots`, `totalSlots` (older versions: plain list) |
| `skills` | professions, secondary skills, weapon skills, armor proficiencies with rank / max |
| `spells` | spellbook by tab: `"Name (Rank N) #spellID"`, `[passive]` marked |
| `actionBars` | per bar (`MainBar`, `BottomLeftBar`, `RightBar`, …): buttons with `slot`, `button` 1–12, `type` (spell/item/macro), `name`, `key` binding, macro `body`. `mainBarKeys`, `currentPage` |
| `auras` | `buffs` / `debuffs` on the player at snapshot time: name, spellID, `stacks`, `secondsLeft`, `duration`, `dispelType`, `fromSelf`. A snapshot, not live: in-combat state is not visible |
| `durability` | percent per equipped slot, `lowest` |
| `reputation` | factions: name, group, standing label, value / max within the standing |
| `plan` | progress on the current `/cplan` plan: id, title, checked step indexes, done / total |
| `api` | which API families exist on this client (debug aid) |

Besides the per-character entries, `ClaudeExportDB.history["Name-Realm"]` is a running journal
(not reset by snapshots):

| Field | Contents |
|---|---|
| `events` | last 1000 events, each with `t` (time), `zone`, `level`, `type`: `login`, `logout` (also fired by /reload), `quest_accepted`, `quest_turned_in` (xp, money), `level_up`, `death` (killer, spell, last 5 hits, group), `loot` (item, count, quality), `instance_enter` (name, group members) / `instance_leave` (minutes), `group_joined` / `group_left` |
| `xpByZone`, `secondsByZone`, `killsByZone`, `deathsByZone` | totals per zone: use them for XP/hour and "where do I die" analysis |
| `money` | `earned` / `spent` in copper since the journal started |

On WoW Forever and Midnight-era clients addons may not read combat log events, so `killsByZone` and
the `killer` / `lastHits` of deaths stay empty there. Use the game's combat log file instead (section 5).

Each character entry also has `reason`: what triggered the snapshot (`login`, `manual` = /cexp, `logout`).
Money is in copper: 10000 = 1 gold, 100 = 1 silver.

With `traits.nodes`, group nodes into trees by `x` ranges (each tree is a separate x band) and
rows by `y`. Only nodes with `rank > 0` are learned.

## 3. Advise

- Check `meta.clientVersion` and `meta.interface` first. Private-server and seasonal flavors (Forever,
  Season of Discovery, Anniversary, etc.) change talents, quests and items. Verify specifics against a
  database for **that** flavor (e.g. wowhead.com/classic, /cata, /forever, /mop-classic) rather than
  answering from memory of another version.
- Quest names are in the client's language. Answer in the user's language, keep in-game names as
  they appear in the export so the user can find them.
- Use `completed` to avoid recommending quests already done, and to find where long chains stopped.
  Quest IDs without a title can be resolved on the flavor's database (`/quest=<id>`).
- Compare the quest level with `character.level`: within 2 levels is comfortable,
  3–4 above is hard solo, 5+ needs a group.
- Point out empty gear slots and items in bags that are better than what's equipped.
- With `actionBars`, check that key abilities for the user's role are on bound buttons, and
  suggest concrete moves ("put Consecration on key 5"). With `auras`, check missing self-buffs,
  food/scroll buffs, or debuffs like resurrection sickness before a dungeon.
- Note: `/reload` itself fires a logout snapshot, so `reason = "logout"` right after a reload is normal.
- Be concrete: an ordered route (where to go, what to turn in, what to pick up, what dungeon) beats
  a general essay.

## 4. Send a plan into the game (/cplan)

The addon shows a checklist window when the user types `/cplan`. You can write that plan:

1. Write `<WoW>/<flavor>/Interface/AddOns/ClaudeExport/Plan.lua` (replace the whole file):

```lua
ClaudeExportPlan = {
  id = "2026-11-21-deadmines",      -- NEW id for every new plan (resets checkmarks)
  title = "Deadmines and turn-ins",
  updated = "2026-11-21 14:30",
  note = "Optional paragraph above the list.",
  steps = {
    { header = "Before the instance" },
    { text = "Collect 4 Miners' Union Cards", questID = 168, when = "ready" }, -- ticks when objectives done
    { text = "Turn in at Sentinel Hill", questID = 166, mapID = 1436, x = 56.3, y = 47.5 }, -- ticks when turned in; ">" sets a map pin
    { text = "Manual step: the user ticks it" },
  },
}
```

2. Ask the user to type `/reload`, then `/cplan`. The window never opens by itself; a one-line chat
   hint appears on login when a new plan id arrives.
3. Later, read `plan` in the export to see which steps the user ticked (and `questID` steps tick
   themselves), and update the plan with a new `id`.

Rules: valid Lua only (escape `"` and `\` inside strings, or use «» quotes), UTF-8, keep the
quest/NPC names exactly as in the user's client language. Use `questID` from the export's `quests`
section so steps tick automatically; `mapID` comes from `character.mapID` when the user was in that
zone, or the flavor's database. Don't invent coordinates you're unsure of: omit `x`/`y` instead.
Editing `Plan.lua` needs only `/reload`; installing a new addon version needs a full client restart.

## 5. Combat log analysis

For fights, dungeon runs, deaths and tanking, read the game's own combat log. It is written by the
game itself (allowed on every client, it's what Warcraft Logs uses), with a short delay.

1. The user types `/combatlog` in game once per session (it stays on until logout or `/combatlog` again).
   Files: `<flavor>/Logs/WoWCombatLog-MMDDYY_HHMMSS.txt`, one per session, several MB per hour.
2. Summarize with the bundled script (POSIX awk, runs in Git Bash / macOS / Linux in well under a second
   for a 10 MB file). The script is in this skill's directory:

```bash
awk -f "<skill dir>/scripts/combatlog.awk" -v me="CharName" [-v from="14:16" -v to="14:41"] "<flavor>/Logs/WoWCombatLog-<newest>.txt"
```

   `me` is part of the character name (from `character.name` in the export). `from`/`to` limit the time
   window (time of day). Use the journal's `instance_enter` / `instance_leave` times to cut out one
   dungeon run.

   Output: zones and boss encounters (kill / wipe), each group member's damage, effective healing,
   overheal, damage taken, creature melee attacks taken and deaths, the **tank share** (% of creature
   melee attacks on the group that hit `me`), `me`'s damage and healing by ability, top sources of damage
   taken, and every group death with the last hits before it.
3. Interpret, don't just paste numbers. For a tank: share under ~80% means mobs regularly ran to others;
   look at who took hits and when. For damage: compare abilities with the rotation you'd expect for the
   spec. For deaths: name the mob/ability and what would have prevented it.

For a question the script doesn't answer, grep the file directly. Line format:

```
MM/DD/YYYY HH:MM:SS.ffff  EVENT,srcGUID,"srcName",srcFlags,srcRaidFlags,dstGUID,"dstName",dstFlags,dstRaidFlags,...
```

- Spell events add `spellId,"spellName",school` (fields 10–12).
- With advanced logging (the header line says `COMBAT_LOG_VERSION,…,ADVANCED_LOG_ENABLED`, and Forever
  writes the advanced block regardless) 19 unit fields follow: info GUID, owner, hp, max hp, attack power,
  spell power, armor, absorb, power type / current / max / cost, x, y, uiMapID, facing, level. So the
  amount is field **29** for `SWING_DAMAGE`, **32** for `SPELL_DAMAGE` / `SPELL_PERIODIC_DAMAGE` /
  `RANGE_DAMAGE` / `SPELL_HEAL` (overheal is 34). Without advanced logging: 10 and 13.
- Flags: last hex digit is affiliation: `1` me, `2` party, `4` raid, `8` outsider. Player names are
  `Name-Realm-Region`; creature names may contain hyphens.
- Useful events: `UNIT_DIED`, `PARTY_KILL`, `ENCOUNTER_START` / `ENCOUNTER_END` (last-but-one field
  `1` = kill), `ZONE_CHANGE`, `SPELL_INTERRUPT`, `SPELL_DISPEL`, `SPELL_AURA_APPLIED`.
- On PvP realms the log also contains strangers fighting nearby: filter by affiliation, as the script does.

## 6. When the data is missing or stale

Ask the user to refresh. Use these exact steps:

1. In game: `/reload` is enough (it takes a snapshot and writes the file). `/cexp` additionally
   freezes a snapshot earlier, e.g. buffs before a fight.
2. A **newly installed** addon is only detected after a **full client restart**, not after `/reload`.
   The addon must also be enabled on the character select screen (AddOns button). If the game
   flags it as out of date, enable "Load out of date AddOns".
3. If the file's time didn't change after the user said they reloaded, the game probably wasn't running
   (logout saves whatever code was loaded when the session started).
4. Empty `talents` / `spells` / `skills` on a new client version: look at the `api` section to see which
   API families exist and tell the user which section is unsupported; don't invent the missing data.

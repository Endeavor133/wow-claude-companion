---
name: wow-character
description: Read the user's World of Warcraft character from the ClaudeExport addon's SavedVariables file (quests and objectives, completed quests, talents, gear with stats, bags, stats, professions, spellbook, action bars with key bindings, buffs/debuffs, reputation, durability, history journal of quests/deaths/loot/dungeons) and write a step-by-step plan the user opens in game with /cplan. Use whenever the user asks for WoW advice that depends on their character — leveling route, what to do next, quest help, talent build, gear upgrades, professions, dungeon prep — or says "read my export", "читай экспорт", "/cexp done", "готово, читай".
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

On WoW Forever and Midnight-era clients addons may not read combat log events, so `killsByZone` and
the `killer` / `lastHits` of deaths stay empty there. For combat details read the game's own combat
log file instead: the user types `/combatlog`, the game writes `<flavor>/Logs/WoWCombatLog-*.txt`
(CSV-like lines: timestamp, event, source, target, spell, amounts). Match a `death` event's time
against `UNIT_DIED` lines and the damage lines just before it.
| `money` | `earned` / `spent` in copper since the journal started |
| `reason` | what triggered the snapshot: `login`, `manual` (/cexp) or `logout` |

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

## 5. When the data is missing or stale

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

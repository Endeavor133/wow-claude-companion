# Changelog

## 1.2.0 — 2026-11-21

- History journal (`ClaudeExportDB.history`): quests accepted / turned in, level-ups, deaths with the
  last hits taken, loot, dungeon runs with group and duration, sessions; XP, time, kills and deaths
  per zone; money earned / spent.
- Plan window: `/cplan` shows `Plan.lua` (written by the assistant) as a checklist with auto-ticking
  quest steps and map pins. Never opens on its own. `/cplan reset` clears checkmarks.
- Minimap button: left click opens/closes the plan, right click takes a snapshot, drag to move. `/cplan minimap` hides/shows it.
- New snapshot sections: `durability`, `reputation`, `plan` (progress).
- A plain `/reload` is enough to refresh the file.
- Upgrading from 1.1 adds new files: restart the game client once.
- The journal does not register combat log events on WoW Forever and Midnight-era clients, where that is
  a Blizzard-only action and the game would block the addon. Kill counts and killer info are recorded
  only on clients that allow it; elsewhere use the game's combat log file.

## 1.1.0 — 2026-11-21

- New `actionBars` section: every action bar button with spell/item/macro name, key binding and
  macro text; current bar page.
- New `auras` section: player buffs and debuffs with stacks and time left at snapshot time.
- Skill: describes the new sections and how to use them for advice.

## 1.0.0 — 2026-11-21

First public release.

- Addon: snapshots character, stats, talents (classic tabs and modern trait trees), active quests
  with objectives, completed quests, gear with stats, bags with free slots, skills/professions,
  spellbook, client metadata and an API probe.
- Snapshots on login (after 5 s), on logout and on `/cexp`. Logout no longer wipes sections that the
  client stops answering during logout.
- English and Russian chat messages.
- Claude Code plugin `wow-companion` with the `wow-character` skill.

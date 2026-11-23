# ClaudeExport — your WoW character, readable by Claude

*[Русская версия ниже](#русский)*

**ClaudeExport** is a small World of Warcraft addon that saves your character to a file:
active quests with objectives, completed quests, talents, gear with stats, bags, stats,
professions with known recipes, spellbook, action bars with key bindings, and buffs/debuffs. The **wow-companion** plugin for Claude Code teaches Claude
where that file is and how to read it. Then you can just ask *"what should I do next?"*,
and Claude answers from the real state of your character, without screenshots.

- **Read-only.** Only the standard addon API. No automation, no memory reading, nothing
  that touches gameplay. Allowed like any other addon.
- **Works across clients.** Tries the classic API first and the modern `C_*` API second. Tested on
  WoW Forever (1.60). The `.toc` also lists Classic Era, TBC/Wrath/Cata/MoP Classic and retail
  interface numbers.
- **No dependencies.** Plain Lua addon plus a Markdown skill. Nothing to install besides the two folders.

## Contents

```
addon/ClaudeExport/          the WoW addon (copy into Interface/AddOns)
plugin/wow-companion/        the Claude Code plugin (skill "wow-character")
.claude-plugin/marketplace.json   lets Claude Code install the plugin from this repo
```

Download the latest zips from [Releases](https://github.com/Endeavor133/wow-claude-companion/releases).

## 1. Install the addon

1. Copy `addon/ClaudeExport` into `<WoW>/<flavor>/Interface/AddOns/`,
   for example `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\ClaudeExport`.
2. **Fully restart the game.** New addons are not detected by `/reload`.
3. On the character select screen, open **AddOns** and make sure **ClaudeExport** is checked.
   If it's marked out of date, tick **Load out of date AddOns**.

## 2. Install the Claude Code plugin

**From GitHub:**

```
/plugin marketplace add Endeavor133/wow-claude-companion
/plugin install wow-companion@claudeexport
```

**From a local folder:**

```
/plugin marketplace add C:\path\to\ClaudeExport-release
/plugin install wow-companion@claudeexport
```

**Update to a new version:**

```
claude plugin marketplace update claudeexport
claude plugin update wow-companion@claudeexport
```

Then restart Claude Code. For the addon, replace the `ClaudeExport` folder with the one from the new
release zip (keep your `Plan.lua` if you want), and restart the game if the release notes say new files were added.

Without plugins, you can copy `plugin/wow-companion/skills/wow-character` into `~/.claude/skills/`.
It works the same as a personal skill.

Start Claude Code in your WoW folder (or give it access to it). The skill finds
`WTF/Account/<ACCOUNT>/SavedVariables/ClaudeExport.lua` by itself.

## 3. Use it

1. In game: `/reload` takes a snapshot and writes it to disk. A snapshot is also taken
   automatically on login and logout.
2. Ask Claude: *"Read my export. Where should I level next?"*, *"Which talents should I take at 30?"*,
   *"Which of my quests are too high for me?"*, *"Is anything in my bags better than my gear?"*

3. Ask Claude to *make a plan*: it writes `Plan.lua` into the addon folder. After `/reload`, type `/cplan` to open the checklist (quest steps tick themselves, `>` sets a map pin). `/cplan reset` clears checkmarks. The **minimap button** does the same with one click (right click takes a snapshot; `/cplan minimap` hides it).

The addon also keeps a **history journal**: quests taken and turned in, level-ups, deaths, loot, dungeon runs with group and duration, XP and time per zone, gold earned and spent. Ask *"where do I lose the most time?"* or *"how much XP did the Deadmines give?"*.

> **Combat details on newer clients.** On WoW Forever and Midnight-era clients (12.x), addons are not allowed to read combat log events, so the journal records *that* you died, but not who killed you, and doesn't count kills. For that, type `/combatlog` in game: the game itself writes `Logs/WoWCombatLog-*.txt`, and Claude can read that file to break down deaths, damage taken and lost aggro. On Classic Era, TBC/Wrath/Cata/MoP Classic the addon still records killers and kills itself.

A plain `/reload` refreshes the file; `/cexp` freezes a snapshot earlier (e.g. buffs before a fight). `/cexp help` prints a short help.

**Recipes:** the game lists recipes only while a profession window is open. Open each profession once (and again after learning new recipes), then `/reload`.

4. **Fight and dungeon analysis.** Type `/combatlog` in game before a dungeon. Afterwards ask Claude
   *"how did the run go?"*: the plugin summarizes the game's combat log: damage and healing per group
   member, boss kills and wipes, deaths with the last hits taken, and for tanks how many of the mobs'
   attacks you actually held.

Not using Claude Code? You can attach the `ClaudeExport.lua` file to a chat in Claude (or any assistant)
and ask the same questions.

## Data and privacy

The file stays on your computer. It contains the character's name, realm, level, position, quests,
items and gold. No account name, e-mail or password. Nothing is sent anywhere by the addon. When you
ask Claude about it, the parts it reads are sent to Claude as part of your conversation.

## Troubleshooting

| Symptom | Fix |
|---|---|
| No `ClaudeExport.lua` file | Fully restart the game after installing; enable the addon on character select |
| `/cexp` does nothing | Addon not loaded — see above; check for a Lua error popup |
| File didn't update | It's written only on `/reload` or logout; the game must be running |
| Empty `talents`/`spells`/`skills` | Your client exposes a different API. See the `api` section of the file and open an issue |

## License

MIT, see [LICENSE](LICENSE).

---

## Русский

**ClaudeExport** — небольшой аддон для World of Warcraft. Он сохраняет персонажа в файл:
активные квесты с целями, выполненные квесты, таланты, снаряжение со статами, сумки,
характеристики, профессии с изученными рецептами, книгу заклинаний, панели с биндами, баффы и дебаффы. Плагин **wow-companion** для Claude Code
объясняет Claude, где лежит этот файл и как его читать. После этого можно просто спросить
«что делать дальше?», и Claude ответит по реальному состоянию персонажа, без скриншотов.

- **Только чтение.** Аддон использует обычное API аддонов: ничего не автоматизирует, не читает
  память клиента и не влияет на игру. Разрешён, как любой другой аддон.
- **Разные клиенты.** Сначала пробует классическое API, потом современное `C_*`. Проверен на
  WoW Forever (1.60). В `.toc` указаны версии интерфейса Classic Era, TBC/Wrath/Cata/MoP Classic и retail.
- **Без зависимостей.** Обычный Lua-аддон плюс скилл в Markdown.

Готовые архивы: [Releases](https://github.com/Endeavor133/wow-claude-companion/releases).

### 1. Установка аддона

1. Скопируй `addon/ClaudeExport` в `<WoW>/<папка версии>/Interface/AddOns/`,
   например `C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\ClaudeExport`.
2. **Полностью перезапусти игру.** `/reload` новые аддоны не находит.
3. На экране выбора персонажа открой **Модификации** и проверь, что **ClaudeExport** включён.
   Если он помечен как устаревший, включи **Загружать устаревшие модификации**.

### 2. Установка плагина для Claude Code

Из GitHub:

```
/plugin marketplace add Endeavor133/wow-claude-companion
/plugin install wow-companion@claudeexport
```

Из локальной папки:

```
/plugin marketplace add C:\путь\к\ClaudeExport-release
/plugin install wow-companion@claudeexport
```

**Обновление до новой версии:**

```
claude plugin marketplace update claudeexport
claude plugin update wow-companion@claudeexport
```

Затем перезапусти Claude Code. Аддон обновляется заменой папки `ClaudeExport` на папку из архива нового
релиза (свой `Plan.lua` можно сохранить). Если в описании релиза сказано, что добавлены новые файлы,
перезапусти игру.

Без плагинов можно скопировать `plugin/wow-companion/skills/wow-character` в `~/.claude/skills/`.

Запускай Claude Code в папке игры или дай ему к ней доступ. Скилл сам найдёт
`WTF/Account/<АККАУНТ>/SavedVariables/ClaudeExport.lua`.

### 3. Использование

1. В игре: `/reload` делает снимок и записывает его на диск. Снимок также делается
   сам при входе в игру и при выходе.
2. Спроси Claude: «Прочитай экспорт. Куда идти качаться?», «Какие таланты брать на 30?»,
   «Какие мои квесты слишком высокие?», «Есть ли в сумках что-то лучше надетого?»

3. Попроси Claude *составить план*: он запишет `Plan.lua` в папку аддона. После `/reload` набери `/cplan`, откроется чек-лист (квестовые шаги отмечаются сами, кнопка `>` ставит метку на карте). `/cplan reset` сбрасывает отметки. То же делает **кнопка на миникарте** (ПКМ делает снимок, `/cplan minimap` скрывает кнопку).

Аддон также ведёт **журнал событий**: взятые и сданные квесты, уровни, смерти, добыча, походы в подземелья (с составом группы и длительностью), опыт и время по зонам, заработанное и потраченное золото. Можно спросить «где я теряю больше всего времени?» или «сколько опыта дали Мёртвые копи?».

> **Подробности боя на новых клиентах.** В WoW Forever и клиентах эпохи Midnight (12.x) аддонам запрещено читать события журнала боя. Поэтому журнал записывает сам факт смерти, но не то, кто убил, и не считает убийства. Для этого набери в игре `/combatlog`: игра сама пишет `Logs/WoWCombatLog-*.txt`, и Claude может разобрать этот файл (смерти, полученный урон, сорванные мобы). На Classic Era и TBC/Wrath/Cata/MoP Classic аддон по-прежнему сам записывает убийц и убийства.

Для обновления файла достаточно `/reload`. `/cexp` фиксирует снимок раньше (например, баффы перед боем).

**Рецепты:** игра показывает их только при открытом окне профессии. Открой каждую профессию один раз (и снова после изучения новых рецептов), затем `/reload`.

4. **Разбор боёв и подземелий.** Перед подземельем набери в игре `/combatlog`. После похода спроси
   Claude «как прошёл поход?»: плагин разберёт журнал боя игры. Покажет урон и лечение каждого
   участника, убийства боссов и вайпы, смерти с последними ударами, а танку — какую долю атак мобов
   он действительно держал на себе.

Если не пользуешься Claude Code, можно прикрепить файл `ClaudeExport.lua` к чату с Claude
(или с любым ассистентом) и задать те же вопросы.

### Данные и приватность

Файл хранится только на твоём компьютере. В нём имя персонажа, сервер, уровень, положение, квесты,
предметы и золото. Имени аккаунта, почты и пароля там нет. Аддон ничего никуда не отправляет. Когда
ты спрашиваешь Claude, прочитанные им части файла уходят в Claude как часть разговора.

### Если что-то не работает

| Проблема | Что сделать |
|---|---|
| Нет файла `ClaudeExport.lua` | Полностью перезапусти игру после установки, включи аддон на экране персонажей |
| `/cexp` ничего не пишет | Аддон не загрузился (см. выше). Проверь, не было ли ошибки Lua |
| Файл не обновился | Он записывается только при `/reload` или выходе, игра должна быть запущена |
| Пустые `talents`/`spells`/`skills` | У клиента другое API. Посмотри раздел `api` в файле и напиши об этом |

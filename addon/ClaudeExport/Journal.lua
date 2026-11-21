-- ClaudeExport journal: a running history of what happened, kept in
-- ClaudeExportDB.history["Name-Realm"] and written to disk with the other SavedVariables.
--   events          last MAX_EVENTS events (quests, levels, deaths, loot, dungeons, sessions)
--   xpByZone        experience earned per zone
--   secondsByZone   time spent per zone
--   killsByZone     killing blows by you or your group per zone (only where the combat log API is allowed)
--   deathsByZone    your deaths per zone
--   money           copper earned / spent
local _, ns = ...

local MAX_EVENTS = 1000
local H -- history table of the current character

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(f, ...)
  if ok then return a, b, c, d, e end
end

local function zone()
  local z = try(GetRealZoneText) or try(GetZoneText)
  return (z and z ~= "") and z or "?"
end

local function add(t, k, v) t[k] = (t[k] or 0) + v end

local function push(ev)
  if not H then return end
  ev.t = date("%Y-%m-%d %H:%M:%S")
  ev.zone = ev.zone or zone()
  ev.level = ev.level or UnitLevel("player")
  table.insert(H.events, ev)
  while #H.events > MAX_EVENTS do table.remove(H.events, 1) end
end
ns.journalPush = push

local function questTitle(id)
  return (C_QuestLog and try(C_QuestLog.GetTitleForQuestID, id)) or nil
end

local function itemName(link)
  return link and link:match("%[(.-)%]")
end

-- "You receive loot: %s." -> Lua pattern capturing the item link
local function fmtToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end
local LOOT_PATTERNS = {}

------------------------------------------------------------------ state
local playerGUID
local lastXP, lastXPMax, lastLevel
local lastMoney
local zoneName, zoneSince
local inInstance, instanceName, instanceSince
local recentHits = {} -- last damage taken, for death reports

local function flushZoneTime()
  if zoneName and zoneSince then add(H.secondsByZone, zoneName, math.floor(GetTime() - zoneSince)) end
  zoneName, zoneSince = zone(), GetTime()
end

local function groupMembers()
  local list = {}
  local n = try(GetNumGroupMembers) or 0
  for i = 1, n do
    local unit = (try(IsInRaid) and "raid" or "party") .. i
    if UnitExists(unit) and not UnitIsUnit(unit, "player") then
      table.insert(list, string.format("%s (%s %d)", UnitName(unit) or "?",
        select(1, UnitClass(unit)) or "?", UnitLevel(unit) or 0))
    end
  end
  return list
end

local function checkInstance()
  local isIn, itype = try(IsInInstance)
  if isIn and not inInstance then
    inInstance, instanceSince = true, GetTime()
    instanceName = (try(GetInstanceInfo)) or zone()
    push({ type = "instance_enter", name = instanceName, kind = itype, group = groupMembers() })
  elseif not isIn and inInstance then
    push({ type = "instance_leave", name = instanceName, minutes = math.floor((GetTime() - instanceSince) / 60 + 0.5) })
    inInstance, instanceName, instanceSince = false, nil, nil
  end
end

------------------------------------------------------------------ init
local function init()
  ClaudeExportDB = ClaudeExportDB or {}
  ClaudeExportDB.history = ClaudeExportDB.history or {}
  local key = ns.charKey and ns.charKey() or (UnitName("player") or "?")
  local h = ClaudeExportDB.history[key] or {}
  h.events = h.events or {}
  h.xpByZone = h.xpByZone or {}
  h.secondsByZone = h.secondsByZone or {}
  h.killsByZone = h.killsByZone or {}
  h.deathsByZone = h.deathsByZone or {}
  h.money = h.money or { earned = 0, spent = 0 }
  ClaudeExportDB.history[key] = h
  H = h

  playerGUID = UnitGUID("player")
  lastXP, lastXPMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  lastMoney = try(GetMoney)
  zoneName, zoneSince = zone(), GetTime()
  for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
    local p = fmtToPattern(_G[g])
    if p then table.insert(LOOT_PATTERNS, p) end
  end
  push({ type = "login", xp = lastXP, xpMax = lastXPMax, money = lastMoney })
end

------------------------------------------------------------------ events
local f = CreateFrame("Frame")
local handlers = {}

function handlers.PLAYER_LOGIN() init() end

function handlers.PLAYER_ENTERING_WORLD()
  if not H then return end
  flushZoneTime()
  checkInstance()
end

function handlers.ZONE_CHANGED_NEW_AREA()
  if not H then return end
  flushZoneTime()
  checkInstance()
end

function handlers.PLAYER_LOGOUT()
  if not H then return end
  flushZoneTime()
  push({ type = "logout", xp = UnitXP("player"), money = try(GetMoney) })
end

function handlers.PLAYER_XP_UPDATE()
  if not H then return end
  local xp, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  local delta
  if lvl > (lastLevel or lvl) then delta = ((lastXPMax or 0) - (lastXP or 0)) + xp
  else delta = xp - (lastXP or xp) end
  if delta > 0 then add(H.xpByZone, zone(), delta) end
  lastXP, lastXPMax, lastLevel = xp, max, lvl
end

function handlers.PLAYER_LEVEL_UP(level)
  push({ type = "level_up", newLevel = level })
end

function handlers.QUEST_ACCEPTED(a, b)
  local id = b or a
  if type(id) ~= "number" then return end
  push({ type = "quest_accepted", questID = id, title = questTitle(id) })
end

function handlers.QUEST_TURNED_IN(id, xp, money)
  push({ type = "quest_turned_in", questID = id, title = questTitle(id), xp = xp, money = money })
end

function handlers.PLAYER_DEAD()
  if not H then return end
  add(H.deathsByZone, zone(), 1)
  local last = recentHits[#recentHits]
  local copy = {}
  for i, h in ipairs(recentHits) do copy[i] = h end
  push({ type = "death", killer = last and last.source, spell = last and last.spell, lastHits = copy,
         inInstance = inInstance or nil, group = groupMembers() })
  wipe(recentHits)
end

function handlers.PLAYER_MONEY()
  if not H then return end
  local m = try(GetMoney) or 0
  local d = m - (lastMoney or m)
  if d > 0 then H.money.earned = H.money.earned + d elseif d < 0 then H.money.spent = H.money.spent - d end
  lastMoney = m
end

function handlers.CHAT_MSG_LOOT(msg)
  if not H or type(msg) ~= "string" then return end
  for _, p in ipairs(LOOT_PATTERNS) do
    local link, count = msg:match(p)
    if link then
      local id = tonumber(link:match("item:(%d+)"))
      local quality = id and C_Item and try(C_Item.GetItemQualityByID, id)
      if quality == nil or quality >= 1 then
        push({ type = "loot", item = itemName(link), itemID = id, count = tonumber(count) or 1, quality = quality })
      end
      return
    end
  end
end

function handlers.GROUP_ROSTER_UPDATE()
  -- only note when a group forms or ends; individual joins are in instance_enter
  local n = try(GetNumGroupMembers) or 0
  local grouped = n > 0
  if grouped ~= f.grouped then
    f.grouped = grouped
    push({ type = grouped and "group_joined" or "group_left", group = grouped and groupMembers() or nil })
  end
end

-- NOTE: no COMBAT_LOG_EVENT_UNFILTERED. On WoW Forever and Midnight-era clients ("addon apocalypse")
-- registering it is a Blizzard-only action and the game blocks the whole addon. Who killed you and
-- what you killed come from the game's own combat log file (/combatlog -> Logs/WoWCombatLog-*.txt).
-- On older clients (Classic Era, Wrath, Cata, MoP Classic) it is still allowed, so use it there.
local function combatLogAllowed()
  local _, _, _, toc = GetBuildInfo()
  toc = tonumber(toc) or 0
  if toc >= 120000 then return false end            -- Midnight and later
  if toc >= 16001 and toc < 20000 then return false end -- WoW Forever
  return CombatLogGetCurrentEventInfo ~= nil
end

if combatLogAllowed() then
  local AFFIL = (COMBATLOG_OBJECT_AFFILIATION_MINE or 1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 2) + (COMBATLOG_OBJECT_AFFILIATION_RAID or 4)
  function handlers.COMBAT_LOG_EVENT_UNFILTERED()
    if not H then return end
    local _, sub, _, _, srcName, srcFlags, _, dstGUID, _, _, _, a12, a13, _, a15 = CombatLogGetCurrentEventInfo()
    if sub == "PARTY_KILL" then
      if srcFlags and bit.band(srcFlags, AFFIL) ~= 0 then add(H.killsByZone, zone(), 1) end
    elseif dstGUID == playerGUID and sub and (sub == "SWING_DAMAGE" or sub:find("_DAMAGE$")) then
      local spell, amount
      if sub == "SWING_DAMAGE" then spell, amount = "melee", a12 else spell, amount = a13, a15 end
      table.insert(recentHits, { source = srcName or "?", spell = spell, amount = amount })
      while #recentHits > 5 do table.remove(recentHits, 1) end
    end
  end
end

for ev in pairs(handlers) do f:RegisterEvent(ev) end
f:SetScript("OnEvent", function(_, ev, ...)
  local h = handlers[ev]
  if h then pcall(h, ...) end
end)

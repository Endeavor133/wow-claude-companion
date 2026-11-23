-- ClaudeExport — snapshots the current character into the SavedVariables table ClaudeExportDB,
-- so an assistant (Claude Code or any tool) can read it from disk.
--
-- The game writes SavedVariables only on /reload and on logout:
--   WTF/Account/<ACCOUNT>/SavedVariables/ClaudeExport.lua
--
-- Read-only: the addon only queries the standard game API. It never casts, clicks, or automates anything.
-- Every API call is wrapped in pcall, and each section tries the classic API first and the modern
-- C_* namespaces second, so one addon works on Classic Era, Forever, Cata/MoP Classic and retail clients.

local _, ns = ...
local VERSION = "1.4.0"
local FORMAT = 1 -- bump when the layout of ClaudeExportDB changes

------------------------------------------------------------------ helpers
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local res = { pcall(f, ...) }
  if not res[1] then return nil end
  table.remove(res, 1)
  return unpack(res)
end

local function pack(...) return { n = select("#", ...), ... } end

local function isEmpty(t) return type(t) ~= "table" or next(t) == nil end

local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then return try(C_Spell.GetSpellName, id) end
  return (try(GetSpellInfo, id))
end

-- one level of plain values, so unknown API shapes still land in the file
local function flat(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then o[k] = v end
  end
  return o
end

local L = {
  saved = "snapshot saved (%d quests, %d completed). Type /reload to write it to disk.",
  help = "/cexp — take a snapshot now; then /reload to write the file.",
}
if GetLocale and GetLocale() == "ruRU" then
  L.saved = "снимок сохранён (квестов: %d, выполнено: %d). Напиши /reload, чтобы записать его на диск."
  L.help = "/cexp — сделать снимок; затем /reload, чтобы записать файл."
end

------------------------------------------------------------------ items
local function getItemInfo(x)
  if C_Item and C_Item.GetItemInfo then
    local r = pack(try(C_Item.GetItemInfo, x))
    if r[1] then return unpack(r, 1, r.n) end
  end
  return try(GetItemInfo, x)
end

local function itemShort(link, withStats)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  local name, _, quality, ilvl, reqLvl, itype, isub, _, equipLoc = getItemInfo(link)
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    ilvl = try(C_Item.GetDetailedItemLevelInfo, link) or ilvl
  end
  local stats
  if withStats then
    local st = try((C_Item and C_Item.GetItemStats) or GetItemStats, link)
    if type(st) == "table" and next(st) then
      stats = {}
      for k, v in pairs(st) do stats[(_G[k] or k)] = v end
    end
  end
  return {
    id = tonumber(id),
    name = name or link:match("%[(.-)%]"),
    quality = quality, ilvl = ilvl, reqLevel = reqLvl,
    type = itype, subtype = isub, equipLoc = equipLoc,
    stats = stats,
  }
end

------------------------------------------------------------------ meta / api probe
local function snapMeta()
  local version, build, _, toc = try(GetBuildInfo)
  return {
    addonVersion = VERSION, format = FORMAT,
    clientVersion = version, clientBuild = build, interface = toc,
    locale = try(GetLocale),
    time = date("%Y-%m-%d %H:%M:%S"),
  }
end

local PROBE = {
  "GetNumTalentTabs", "GetTalentInfo", "C_Traits", "C_ClassTalents",
  "GetNumSpellTabs", "C_SpellBook", "GetNumSkillLines", "C_SkillInfo",
  "GetQuestLogTitle", "C_QuestLog", "GetItemInfo", "C_Item", "C_Container",
  "C_TradeSkillUI", "GetNumTradeSkills", "GetNumCrafts",
}

local function snapApi()
  local a = {}
  for _, n in ipairs(PROBE) do a[n] = type(_G[n]) end
  return a
end

------------------------------------------------------------------ character
local function snapChar()
  local c = {}
  c.name = UnitName("player")
  c.realm = try(GetRealmName)
  c.level = UnitLevel("player")
  c.race = select(1, UnitRace("player"))
  c.class = select(1, UnitClass("player"))
  c.classFile = select(2, UnitClass("player"))
  c.faction = select(1, UnitFactionGroup("player"))
  c.xp = UnitXP("player")
  c.xpMax = UnitXPMax("player")
  c.rested = try(GetXPExhaustion)
  c.money = try(GetMoney)
  c.health = UnitHealthMax("player")
  c.power = UnitPowerMax("player")
  c.zone = try(GetZoneText)
  c.subzone = try(GetSubZoneText)
  local map = C_Map and try(C_Map.GetBestMapForUnit, "player")
  if map then
    c.mapID = map
    local pos = try(C_Map.GetPlayerMapPosition, map, "player")
    if pos then
      local x, y = pos:GetXY()
      c.pos = string.format("%.1f, %.1f", x * 100, y * 100)
    end
  end
  c.time = date("%Y-%m-%d %H:%M:%S")
  return c
end

local function snapStats()
  local s = {}
  local names = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
  for i = 1, 5 do
    local base, eff = try(UnitStat, "player", i)
    s[names[i]] = eff or base
  end
  local _, armor = try(UnitArmor, "player")
  s.armor = armor
  local apBase, apPos, apNeg = try(UnitAttackPower, "player")
  if apBase then s.attackPower = apBase + (apPos or 0) + (apNeg or 0) end
  local rapBase, rapPos, rapNeg = try(UnitRangedAttackPower, "player")
  if rapBase then s.rangedAttackPower = rapBase + (rapPos or 0) + (rapNeg or 0) end
  s.meleeCrit = try(GetCritChance)
  s.rangedCrit = try(GetRangedCritChance)
  s.spellCrit = try(GetSpellCritChance, 2)
  s.spellPower = try(GetSpellBonusDamage, 2)
  s.healingPower = try(GetSpellBonusHealing)
  s.hitMelee = try(GetHitModifier)
  s.hitSpell = try(GetSpellHitModifier)
  s.dodge = try(GetDodgeChance)
  s.parry = try(GetParryChance)
  s.block = try(GetBlockChance)
  s.mainHandSpeed = try(UnitAttackSpeed, "player")
  local minD, maxD = try(UnitDamage, "player")
  if minD then s.mainHandDamage = string.format("%.0f-%.0f", minD, maxD) end
  return s
end

------------------------------------------------------------------ talents
local function talentsClassic()
  local t = {}
  for tab = 1, try(GetNumTalentTabs) or 0 do
    local info = pack(try(GetTalentTabInfo, tab))
    local tabName, points
    for i = 1, info.n do
      local v = info[i]
      if type(v) == "string" and not tabName and not v:find("[/\\]") then tabName = v end
    end
    for i = 1, info.n do if type(info[i]) == "number" then points = info[i] end end
    local entry = { name = tabName, points = points, talents = {} }
    for i = 1, try(GetNumTalents, tab) or 0 do
      local name, _, tier, column, rank, maxRank = try(GetTalentInfo, tab, i)
      if name then
        table.insert(entry.talents, { name = name, tier = tier, column = column, rank = rank, maxRank = maxRank })
      end
    end
    table.sort(entry.talents, function(a, b)
      if (a.tier or 0) ~= (b.tier or 0) then return (a.tier or 0) < (b.tier or 0) end
      return (a.column or 0) < (b.column or 0)
    end)
    if #entry.talents > 0 or points then table.insert(t, entry) end
  end
  return t
end

-- modern trait-based trees (Forever, retail). Nodes keep their x/y so trees can be rebuilt.
local function talentsTraits()
  if not (C_ClassTalents and C_Traits) then return {} end
  local configID = try(C_ClassTalents.GetActiveConfigID)
  if not configID then return {} end
  local cfg = try(C_Traits.GetConfigInfo, configID)
  local out = { configID = configID, nodes = {} }
  for _, treeID in ipairs((cfg and cfg.treeIDs) or {}) do
    for _, nodeID in ipairs(try(C_Traits.GetTreeNodes, treeID) or {}) do
      local node = try(C_Traits.GetNodeInfo, configID, nodeID)
      if node and node.maxRanks and node.maxRanks > 0 then
        local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
        local name, spellID
        if entryID then
          local e = try(C_Traits.GetEntryInfo, configID, entryID)
          local def = e and e.definitionID and try(C_Traits.GetDefinitionInfo, e.definitionID)
          spellID = def and (def.spellID or def.overriddenSpellID)
          name = spellName(spellID) or (def and def.overrideName)
        end
        table.insert(out.nodes, {
          name = name, spellID = spellID, rank = node.activeRank or node.currentRank,
          maxRank = node.maxRanks, x = node.posX, y = node.posY,
        })
      end
    end
  end
  table.sort(out.nodes, function(a, b)
    if (a.x or 0) ~= (b.x or 0) then return (a.x or 0) < (b.x or 0) end
    return (a.y or 0) < (b.y or 0)
  end)
  return out
end

local function snapTalents()
  local t = { unspent = try(UnitCharacterPoints, "player") }
  local classic = talentsClassic()
  if not isEmpty(classic) then t.trees = classic end
  local traits = talentsTraits()
  if not isEmpty(traits.nodes) then t.traits = traits end
  return t
end

------------------------------------------------------------------ quests
local function snapQuests()
  local q = {}
  if GetNumQuestLogEntries and GetQuestLogTitle then
    local prevSel = try(GetQuestLogSelection)
    try(ExpandQuestHeader, 0) -- collapsed headers hide their quests from the API
    local header
    for i = 1, try(GetNumQuestLogEntries) or 0 do
      local title, level, group, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
      if isHeader then
        header = title
      elseif title then
        local entry = {
          title = title, level = level, zone = header, id = questID,
          group = (group and group > 0) and group or nil,
          complete = (isComplete == 1 and "done") or (isComplete == -1 and "failed") or nil,
          objectives = {},
        }
        for j = 1, try(GetNumQuestLeaderBoards, i) or 0 do
          local text, _, done = try(GetQuestLogLeaderBoard, j, i)
          table.insert(entry.objectives, (done and "[x] " or "[ ] ") .. tostring(text))
        end
        if SelectQuestLogEntry and GetQuestLogQuestText then
          try(SelectQuestLogEntry, i)
          entry.description, entry.summary = try(GetQuestLogQuestText)
        end
        table.insert(q, entry)
      end
    end
    if prevSel then try(SelectQuestLogEntry, prevSel) end
  elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    local header
    for i = 1, try(C_QuestLog.GetNumQuestLogEntries) or 0 do
      local info = try(C_QuestLog.GetInfo, i)
      if info then
        if info.isHeader then header = info.title
        else
          local entry = { title = info.title, level = info.level, zone = header, id = info.questID, objectives = {} }
          if try(C_QuestLog.IsComplete, info.questID) then entry.complete = "done" end
          for _, o in ipairs(try(C_QuestLog.GetQuestObjectives, info.questID) or {}) do
            table.insert(entry.objectives, (o.finished and "[x] " or "[ ] ") .. tostring(o.text))
          end
          table.insert(q, entry)
        end
      end
    end
  end
  return q
end

-- every quest this character has turned in: { [questID] = "title" or true }
local function snapCompleted()
  local ids = C_QuestLog and try(C_QuestLog.GetAllCompletedQuestIDs)
  if type(ids) ~= "table" then
    local t = try(GetQuestsCompleted)
    if type(t) ~= "table" then return {} end
    ids = {}
    for id in pairs(t) do table.insert(ids, id) end
  end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local title = C_QuestLog and try(C_QuestLog.GetTitleForQuestID, id)
    out[id] = (title and title ~= "") and title or true
  end
  return out
end

------------------------------------------------------------------ gear & bags
local SLOTS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger1", [12] = "Finger2",
  [13] = "Trinket1", [14] = "Trinket2", [15] = "Back", [16] = "MainHand", [17] = "OffHand",
  [18] = "Ranged", [19] = "Tabard",
}

local function snapGear()
  local g = {}
  for slot, name in pairs(SLOTS) do
    local link = try(GetInventoryItemLink, "player", slot)
    if link then g[name] = itemShort(link, true) end
  end
  return g
end

local function snapBags()
  local b = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local itemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
  local byName, free, total = {}, 0, 0
  for bag = 0, 4 do
    local n = try(numSlots, bag) or 0
    total = total + n
    for slot = 1, n do
      local link = try(itemLink, bag, slot)
      if link then
        local info = pack(try(itemInfo, bag, slot))
        local count = 1
        if type(info[1]) == "table" then count = info[1].stackCount or 1
        elseif type(info[2]) == "number" then count = info[2] end
        local it = itemShort(link, false)
        -- equippable items get their stats (random suffixes like "of the Boar" only show in the link)
        if it.equipLoc and it.equipLoc ~= "" and it.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
          it.stats = itemShort(link, true).stats
        end
        local key = it.name or link
        if byName[key] then byName[key].count = byName[key].count + count
        else
          it.count = count
          byName[key] = it
          table.insert(b, it)
        end
      else
        free = free + 1
      end
    end
  end
  return { items = b, freeSlots = free, totalSlots = total }
end

------------------------------------------------------------------ skills & spells
local function skillRow(...)
  local a = ...
  if type(a) == "table" then
    return a.skillName or a.name or a.skillLineName or a.professionName,
      a.isHeader or a.header,
      a.skillRank or a.rank or a.skillLevel,
      a.skillMaxRank or a.maxRank or a.maxSkillLevel,
      a
  end
  local name, isHeader, _, rank, _, _, maxRank = ...
  return name, isHeader, rank, maxRank
end

local function snapSkills()
  local s = {}
  local sources = {
    { C_SkillInfo and C_SkillInfo.GetNumSkillLines, C_SkillInfo and C_SkillInfo.GetSkillLineInfo },
    { GetNumSkillLines, GetSkillLineInfo },
  }
  for _, src in ipairs(sources) do
    local n = try(src[1])
    if type(n) == "number" and n > 0 then
      local header, seen = nil, {}
      for i = 1, n do
        local name, isHeader, rank, maxRank, raw = skillRow(try(src[2], i))
        if isHeader then header = name
        elseif name and not seen[tostring(header) .. name] then
          seen[tostring(header) .. name] = true
          local row = { name = name, group = header, rank = rank, max = maxRank }
          if raw and not rank then row.raw = flat(raw) end
          table.insert(s, row)
        end
      end
      if #s > 0 then return s end
    end
  end
  -- retail: professions only
  if GetProfessions and GetProfessionInfo then
    for _, idx in pairs({ try(GetProfessions) }) do
      local name, _, rank, maxRank = try(GetProfessionInfo, idx)
      if name then table.insert(s, { name = name, group = "Professions", rank = rank, max = maxRank }) end
    end
  end
  return s
end

local function snapSpells()
  local out = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for line = 1, try(C_SpellBook.GetNumSpellBookSkillLines) or 0 do
      local info = try(C_SpellBook.GetSpellBookSkillLineInfo, line)
      if info and info.name then
        local list = {}
        for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local item = try(C_SpellBook.GetSpellBookItemInfo, index, bank)
          if item and item.name then
            local label = item.name
            if item.subName and item.subName ~= "" then label = label .. " (" .. item.subName .. ")" end
            if item.isPassive then label = label .. " [passive]" end
            if item.spellID then label = label .. " #" .. item.spellID end
            table.insert(list, label)
          end
        end
        out[info.name] = list
      end
    end
    if not isEmpty(out) then return out end
  end
  for tab = 1, try(GetNumSpellTabs) or 0 do
    local tabName, _, offset, num = try(GetSpellTabInfo, tab)
    if tabName and num then
      local list = {}
      for i = offset + 1, offset + num do
        local name, rank = try(GetSpellBookItemName, i, BOOKTYPE_SPELL or "spell")
        if name then table.insert(list, (rank and rank ~= "") and (name .. " (" .. rank .. ")") or name) end
      end
      out[tabName] = list
    end
  end
  return out
end

------------------------------------------------------------------ action bars & key bindings
-- action slot ranges -> the bar they belong to and the key-binding command of their buttons
local BARS = {
  { first = 1,   name = "MainBar",        bind = "ACTIONBUTTON" },
  { first = 13,  name = "MainBarPage2",   bind = nil },
  { first = 25,  name = "RightBar",       bind = "MULTIACTIONBAR3BUTTON" },
  { first = 37,  name = "RightBar2",      bind = "MULTIACTIONBAR4BUTTON" },
  { first = 49,  name = "BottomRightBar", bind = "MULTIACTIONBAR2BUTTON" },
  { first = 61,  name = "BottomLeftBar",  bind = "MULTIACTIONBAR1BUTTON" },
  { first = 73,  name = "StanceBar1",     bind = "ACTIONBUTTON" },
  { first = 85,  name = "StanceBar2",     bind = "ACTIONBUTTON" },
  { first = 97,  name = "StanceBar3",     bind = "ACTIONBUTTON" },
  { first = 109, name = "StanceBar4",     bind = "ACTIONBUTTON" },
  { first = 121, name = "BonusBar",       bind = "ACTIONBUTTON" },
  { first = 133, name = "Possess",        bind = "ACTIONBUTTON" },
  { first = 145, name = "Bar5",           bind = "MULTIACTIONBAR5BUTTON" },
  { first = 157, name = "Bar6",           bind = "MULTIACTIONBAR6BUTTON" },
  { first = 169, name = "Bar7",           bind = "MULTIACTIONBAR7BUTTON" },
}

local function bindingFor(cmd)
  local keys = { try(GetBindingKey, cmd) }
  if #keys == 0 then return nil end
  return table.concat(keys, " / ")
end

local function actionLabel(slot)
  local atype, id, subType = try(GetActionInfo, slot)
  if not atype then return nil end
  local e = { type = atype, id = id }
  if atype == "spell" then
    e.name = spellName(id)
  elseif atype == "item" then
    e.name = (getItemInfo(id))
    e.count = try(GetActionCount, slot)
  elseif atype == "macro" then
    e.name = try(GetActionText, slot)
    local mname, _, body = try(GetMacroInfo, e.name or id)
    e.name = e.name or mname
    if body then e.body = body:sub(1, 255) end
  else
    e.name = try(GetActionText, slot)
    e.subType = subType
  end
  return e
end

local function snapActionBars()
  local out = {}
  for _, bar in ipairs(BARS) do
    local buttons = {}
    for i = 1, 12 do
      local slot = bar.first + i - 1
      if try(HasAction, slot) then
        local e = actionLabel(slot)
        if e then
          e.slot, e.button = slot, i
          if bar.bind then e.key = bindingFor(bar.bind .. i) end
          table.insert(buttons, e)
        end
      end
    end
    if #buttons > 0 then out[bar.name] = buttons end
  end
  -- unbound bars still show which keys exist for the main bar
  out.mainBarKeys = {}
  for i = 1, 12 do out.mainBarKeys[i] = bindingFor("ACTIONBUTTON" .. i) or "" end
  out.currentPage = try(GetActionBarPage)
  return out
end

------------------------------------------------------------------ buffs & debuffs
local function auraList(filter)
  local list, now = {}, GetTime()
  for i = 1, 40 do
    local a
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      a = try(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
    end
    if not a and UnitAura then
      local name, _, count, dispel, duration, expires, source, _, _, spellId = try(UnitAura, "player", i, filter)
      if name then
        a = { name = name, applications = count, dispelName = dispel, duration = duration,
              expirationTime = expires, sourceUnit = source, spellId = spellId }
      end
    end
    if not a or not a.name then break end
    local left
    if a.expirationTime and a.expirationTime > 0 then left = math.floor(a.expirationTime - now + 0.5) end
    table.insert(list, {
      name = a.name, spellID = a.spellId,
      stacks = (a.applications and a.applications > 1) and a.applications or nil,
      secondsLeft = left, duration = (a.duration and a.duration > 0) and a.duration or nil,
      dispelType = a.dispelName,
      fromSelf = (a.sourceUnit == "player") or nil,
    })
  end
  return list
end

local function snapAuras()
  return {
    buffs = auraList("HELPFUL"),
    debuffs = auraList("HARMFUL"),
    time = date("%H:%M:%S"),
  }
end

------------------------------------------------------------------ durability & reputation
local function snapDurability()
  local out, lowest = {}, nil
  for slot, name in pairs(SLOTS) do
    local cur, max = try(GetInventoryItemDurability, slot)
    if cur and max and max > 0 then
      local pct = math.floor(cur / max * 100 + 0.5)
      out[name] = pct
      if not lowest or pct < lowest then lowest = pct end
    end
  end
  out.lowest = lowest
  return out
end

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local function snapReputation()
  local out = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    try(C_Reputation.ExpandAllFactionHeaders)
    local header
    for i = 1, try(C_Reputation.GetNumFactions) or 0 do
      local d = try(C_Reputation.GetFactionDataByIndex, i)
      if d and d.name then
        if d.isHeader and not d.isHeaderWithRep then header = d.name
        else
          table.insert(out, {
            name = d.name, group = header,
            standing = _G["FACTION_STANDING_LABEL" .. (d.reaction or 0)] or STANDING[d.reaction or 0],
            value = d.currentStanding and d.currentReactionThreshold and (d.currentStanding - d.currentReactionThreshold),
            max = d.nextReactionThreshold and d.currentReactionThreshold and (d.nextReactionThreshold - d.currentReactionThreshold),
          })
        end
      end
    end
    if #out > 0 then return out end
  end
  if GetNumFactions and GetFactionInfo then
    try(ExpandAllFactionHeaders)
    local header
    for i = 1, try(GetNumFactions) or 0 do
      local name, _, standingID, bottom, top, earned, _, _, isHeader, _, hasRep = try(GetFactionInfo, i)
      if name then
        if isHeader and not hasRep then header = name
        else
          table.insert(out, {
            name = name, group = header,
            standing = _G["FACTION_STANDING_LABEL" .. (standingID or 0)] or STANDING[standingID or 0],
            value = earned and bottom and (earned - bottom), max = top and bottom and (top - bottom),
          })
        end
      end
    end
  end
  return out
end

-- progress on the current plan (checkmarks are kept by PlanUI.lua)
local function snapPlan()
  local p = type(ClaudeExportPlan) == "table" and ClaudeExportPlan or nil
  local ps = ClaudeExportDB and ClaudeExportDB.planState
  if not p then return {} end
  local checked = {}
  if type(ps) == "table" and type(ps.checked) == "table" then
    for i in pairs(ps.checked) do table.insert(checked, i) end
    table.sort(checked)
  end
  return { id = p.id, title = p.title, steps = #(p.steps or {}), checked = checked,
           done = ps and ps.done, total = ps and ps.total }
end

------------------------------------------------------------------ recipes
-- The game lists known recipes only while a profession window is open, so every time the user opens
-- one we scan it and keep the result in ClaudeExportDB.recipes[charKey][profession]. Snapshots copy
-- that cache. Professions that were never opened since installing this version are simply missing.
local DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" } -- orange/yellow/green/grey

local function recipeStore()
  ClaudeExportDB = ClaudeExportDB or {}
  ClaudeExportDB.recipes = ClaudeExportDB.recipes or {}
  local key = ns.charKey()
  ClaudeExportDB.recipes[key] = ClaudeExportDB.recipes[key] or {}
  return ClaudeExportDB.recipes[key]
end

local function str(s) return (type(s) == "string" and s ~= "") and s or nil end
local function num(n) return (type(n) == "number" and n > 0) and n or nil end

-- rank / max from the skills section when the trade skill API doesn't say
local function skillRank(name)
  for _, row in ipairs(snapSkills()) do
    if row.name == name then return row.rank, row.max end
  end
end

-- Forever returns empty strings from some of these, so try every source until one gives a name
local function modernProfession(firstRecipeID)
  local T = C_TradeSkillUI
  local name, rank, max, lineID
  for _, fn in ipairs({ T.GetChildProfessionInfo, T.GetBaseProfessionInfo }) do
    local info = fn and try(fn)
    if type(info) == "table" then
      name = name or str(info.parentProfessionName) or str(info.professionName)
      rank, max = rank or num(info.skillLevel), max or num(info.maxSkillLevel)
      lineID = lineID or num(info.professionID) or num(info.parentProfessionID)
    end
  end
  if T.GetTradeSkillLine then
    local id, n, r, m = try(T.GetTradeSkillLine)
    name, rank, max, lineID = name or str(n), rank or num(r), max or num(m), lineID or num(id)
  end
  if not name and lineID and T.GetTradeSkillDisplayName then name = str(try(T.GetTradeSkillDisplayName, lineID)) end
  if not name and lineID and T.GetProfessionInfoBySkillLineID then
    local info = try(T.GetProfessionInfoBySkillLineID, lineID)
    if type(info) == "table" then name = str(info.parentProfessionName) or str(info.professionName) end
  end
  if not name and firstRecipeID and T.GetTradeSkillLineForRecipe then
    local _, lineName, _, parentName = try(T.GetTradeSkillLineForRecipe, firstRecipeID)
    name = str(parentName) or str(lineName)
  end
  if name and not (rank and max) then
    local r, m = skillRank(name)
    rank, max = rank or r, max or m
  end
  return name, rank, max
end

local function scanModern()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return nil end
  if T.IsTradeSkillReady and not try(T.IsTradeSkillReady) then return nil end
  if T.IsTradeSkillLinked and try(T.IsTradeSkillLinked) then return nil end -- someone else's link
  if T.IsTradeSkillGuild and try(T.IsTradeSkillGuild) then return nil end
  local ids = try(T.GetAllRecipeIDs)
  if type(ids) ~= "table" or #ids == 0 then return nil end
  local name, rank, max = modernProfession(ids[1])
  if not name then name = "? recipe " .. tostring(ids[1]) end -- unnamed, but never merged with another profession
  local list = {}
  for _, id in ipairs(ids) do
    local r = try(T.GetRecipeInfo, id)
    if type(r) == "table" and r.learned and r.name then
      table.insert(list, { name = r.name, id = id, difficulty = DIFFICULTY[r.relativeDifficulty] or r.relativeDifficulty,
                           skillUps = (r.numSkillUps and r.numSkillUps > 1) and r.numSkillUps or nil })
    end
  end
  return name, rank, max, list
end

local function scanClassic()
  if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return nil end
  local name, rank, max = try(GetTradeSkillLine)
  if not name or name == "UNKNOWN" then return nil end
  local n = try(GetNumTradeSkills) or 0
  if n == 0 then return nil end
  local list, header = {}, nil
  for i = 1, n do
    local rname, rtype = try(GetTradeSkillInfo, i)
    if rtype == "header" or rtype == "subheader" then header = rname
    elseif rname then
      local link = GetTradeSkillItemLink and try(GetTradeSkillItemLink, i)
      table.insert(list, { name = rname, difficulty = rtype, category = header,
                           item = link and tonumber(link:match("item:(%d+)")) or nil })
    end
  end
  return name, rank, max, list
end

local function scanCraft() -- Classic Era enchanting / beast training use the separate craft window
  if not (GetNumCrafts and GetCraftInfo) then return nil end
  local name, rank, max = try(GetCraftDisplaySkillLine)
  if not name then return nil end
  local list = {}
  for i = 1, (try(GetNumCrafts) or 0) do
    local rname, sub, rtype = try(GetCraftInfo, i)
    if rname and rtype ~= "header" then table.insert(list, { name = rname, rank = sub ~= "" and sub or nil, difficulty = rtype }) end
  end
  if #list == 0 then return nil end
  return name, rank, max, list
end

local function scanRecipes(craft)
  local name, rank, max, list
  if craft then name, rank, max, list = scanCraft()
  else
    name, rank, max, list = scanModern()
    if not name then name, rank, max, list = scanClassic() end
  end
  if not name or not list then return end
  table.sort(list, function(a, b) return a.name < b.name end)
  local store = recipeStore()
  store[""] = nil -- 1.3.2 test build stored every profession under an empty name
  local old = store[name]
  -- a search box or "have materials" filter can hide recipes: never shrink the list because of it
  if old and old.recipes and #old.recipes > #list and old.rank and rank and rank <= old.rank then return end
  store[name] = { rank = rank, max = max, count = #list, scanned = date("%Y-%m-%d %H:%M:%S"), recipes = list }
end

local function snapRecipes()
  local store = recipeStore()
  if next(store) == nil then return { note = "open each profession window once, then /reload" } end
  return store
end

local rf = CreateFrame("Frame")
for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "NEW_RECIPE_LEARNED",
                      "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(rf.RegisterEvent, rf, ev)
end
local pending = {}
rf:SetScript("OnEvent", function(_, ev)
  local craft = ev:find("^CRAFT") ~= nil
  if pending[craft] then return end
  pending[craft] = true
  C_Timer.After(0.5, function() pending[craft] = nil; pcall(scanRecipes, craft) end)
end)

------------------------------------------------------------------ main
local SECTIONS = {
  meta = snapMeta, character = snapChar, stats = snapStats, talents = snapTalents,
  quests = snapQuests, completed = snapCompleted, gear = snapGear, bags = snapBags,
  skills = snapSkills, spells = snapSpells, api = snapApi,
  actionBars = snapActionBars, auras = snapAuras,
  durability = snapDurability, reputation = snapReputation, plan = snapPlan,
  recipes = snapRecipes,
}

local function charKey()
  local key = UnitName("player") or "?"
  local realm = try(GetRealmName)
  if realm and realm ~= "" then key = key .. "-" .. realm end
  return key
end
ns.charKey = charKey

local function snapshot(reason)
  ClaudeExportDB = ClaudeExportDB or {}
  local key = charKey()
  local old = ClaudeExportDB[key] or {}
  local d = { reason = reason }
  for name, fn in pairs(SECTIONS) do
    local ok, res = pcall(fn)
    if not ok then res = { error = tostring(res) } end
    -- during logout many APIs return nothing: keep the earlier data instead of wiping it
    local emptyTalents = name == "talents" and type(res) == "table" and not res.trees and not res.traits
    local emptyBags = name == "bags" and type(res) == "table" and isEmpty(res.items)
    if isEmpty(res) or emptyTalents or emptyBags then
      if not isEmpty(old[name]) then res = old[name] end
    end
    d[name] = res
  end
  ClaudeExportDB[key] = d
  ClaudeExportDB.last = key
  ClaudeExportDB.format = FORMAT
  return d
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then
    snapshot("logout")
  else
    -- talents and item data arrive a few seconds after login
    C_Timer.After(5, function() snapshot("login") end)
  end
end)

SLASH_CLAUDEEXPORT1 = "/cexp"
SLASH_CLAUDEEXPORT2 = "/claudeexport"
SlashCmdList.CLAUDEEXPORT = function(msg)
  if msg and msg:lower():find("help") then
    print("|cff66ccffClaudeExport|r " .. L.help)
    return
  end
  local d = snapshot("manual")
  local done = 0
  for _ in pairs(d.completed or {}) do done = done + 1 end
  print("|cff66ccffClaudeExport|r: " .. string.format(L.saved, #(d.quests or {}), done))
end

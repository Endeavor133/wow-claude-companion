-- ClaudeExport plan window: shows ClaudeExportPlan (from Plan.lua, written by Claude) as a checklist.
-- Opened only on demand: /cplan or the minimap button (/cplan reset clears checkmarks,
-- /cplan minimap hides/shows the minimap button).
-- Checkmarks are saved in ClaudeExportDB.planState so the assistant can see your progress.
local _, ns = ...

local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c = pcall(f, ...)
  if ok then return a, b, c end
end

local RU = GetLocale and GetLocale() == "ruRU"
local T = {
  noPlan = RU and "Плана пока нет. Попроси Claude составить план, затем /reload и /cplan."
    or "No plan yet. Ask Claude to write one, then /reload and /cplan.",
  newPlan = RU and "есть новый план: %s. Открыть: /cplan" or "new plan available: %s. Open with /cplan",
  reset = RU and "отметки плана сброшены." or "plan checkmarks cleared.",
  waypoint = RU and "Метка на карте: %s %.1f, %.1f" or "Map pin: %s %.1f, %.1f",
  updated = RU and "Обновлён: %s" or "Updated: %s",
  progress = RU and "Готово %d из %d" or "%d of %d done",
  mmLeft = RU and "ЛКМ: открыть / закрыть план" or "Left click: open / close the plan",
  mmRight = RU and "ПКМ: сделать снимок (/cexp)" or "Right click: take a snapshot (/cexp)",
  mmDrag = RU and "Перетащить: переместить кнопку" or "Drag: move the button",
  mmHidden = RU and "кнопка на миникарте скрыта. Вернуть: /cplan minimap" or "minimap button hidden. Bring it back: /cplan minimap",
  mmShown = RU and "кнопка на миникарте показана." or "minimap button shown.",
}

local function plan() return type(ClaudeExportPlan) == "table" and ClaudeExportPlan or nil end
local function planId()
  local p = plan()
  return p and tostring(p.id or p.updated or p.title or "plan") or nil
end

local function state()
  ClaudeExportDB = ClaudeExportDB or {}
  local id = planId() or "none"
  local ps = ClaudeExportDB.planState
  if type(ps) ~= "table" or ps.id ~= id then
    ps = { id = id, checked = {} }
    ClaudeExportDB.planState = ps
  end
  return ps
end

-- quest-driven steps tick themselves: when="done" (default) = turned in, when="ready" = objectives complete
local function questReady(id)
  if C_QuestLog and C_QuestLog.IsComplete then
    local r = try(C_QuestLog.IsComplete, id)
    if r ~= nil then return r end
  end
  if GetQuestLogIndexByID and GetQuestLogTitle then
    local idx = try(GetQuestLogIndexByID, id)
    if idx and idx > 0 then
      local _, _, _, _, _, isComplete = try(GetQuestLogTitle, idx)
      return isComplete == 1
    end
  end
  return false
end

local function questDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    return try(C_QuestLog.IsQuestFlaggedCompleted, id) and true or false
  end
  return try(IsQuestFlaggedCompleted, id) and true or false
end

local function stepDone(i, step)
  if state().checked[i] then return true end
  if step.questID then
    if questDone(step.questID) then return true end
    if step.when == "ready" and questReady(step.questID) then return true end
  end
  return false
end

local function setWaypoint(step)
  local mapID, x, y = step.mapID, step.x, step.y
  if not (mapID and x and y) then return end
  local ok = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local point = try(UiMapPoint.CreateFromCoordinates, mapID, x / 100, y / 100)
    if point then
      try(C_Map.SetUserWaypoint, point)
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        try(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
      ok = true
    end
  end
  local mapName = (C_Map and C_Map.GetMapInfo and (try(C_Map.GetMapInfo, mapID) or {}).name) or tostring(mapID)
  print("|cff66ccffClaudeExport|r " .. string.format(T.waypoint, mapName, x, y) .. (ok and "" or " (no map API)"))
end

------------------------------------------------------------------ frame
local frame, content, titleText, subText, progressText
local rows = {}
local WIDTH = 440

local function savePos()
  local point, _, rel, x, y = frame:GetPoint(1)
  ClaudeExportDB.planWindow = { point = point, rel = rel, x = x, y = y }
end

local function build()
  frame = CreateFrame("Frame", "ClaudeExportPlanFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 480)
  local pos = ClaudeExportDB and ClaudeExportDB.planWindow
  if pos and pos.point then frame:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
  else frame:SetPoint("CENTER") end
  frame:SetFrameStrata("DIALOG")
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
  table.insert(UISpecialFrames, "ClaudeExportPlanFrame") -- Esc closes it

  titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOPLEFT", 20, -18)
  titleText:SetPoint("RIGHT", -40, 0)
  titleText:SetJustifyH("LEFT")

  subText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)

  progressText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  progressText:SetPoint("TOPRIGHT", -40, -40)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -60)
  scroll:SetPoint("BOTTOMRIGHT", -34, 16)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 56, 10)
  scroll:SetScrollChild(content)
  frame:Hide()
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, content)
  r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.check:SetSize(22, 22)
  r.check:SetPoint("TOPLEFT", 0, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.text:SetJustifyH("LEFT")
  r.text:SetJustifyV("TOP")
  if r.text.SetWordWrap then r.text:SetWordWrap(true) end
  r.pin = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.pin:SetSize(26, 20)
  r.pin:SetText(">")
  r.pin:SetPoint("TOPRIGHT", 0, 0)
  rows[i] = r
  return r
end

local function refresh()
  if not frame or not frame:IsShown() then return end
  local p = plan()
  for _, r in ipairs(rows) do r:Hide() end
  if not p then
    titleText:SetText("ClaudeExport")
    subText:SetText("")
    progressText:SetText("")
    local r = getRow(1)
    r.check:Hide(); r.pin:Hide()
    r.text:ClearAllPoints()
    r.text:SetFontObject("GameFontHighlight")
    r.text:SetTextColor(1, 1, 1)
    r.text:SetPoint("TOPLEFT", 0, 0); r.text:SetWidth(content:GetWidth())
    r.text:SetText(T.noPlan)
    r:SetSize(content:GetWidth(), r.text:GetStringHeight() + 6)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, 0)
    r:Show()
    return
  end

  titleText:SetText(p.title or "Plan")
  subText:SetText(p.updated and string.format(T.updated, p.updated) or "")
  local y, total, done, idx = 0, 0, 0, 0
  local width = content:GetWidth()

  local items = {}
  if p.note then table.insert(items, { note = p.note }) end
  for i, step in ipairs(p.steps or {}) do table.insert(items, { step = step, index = i }) end

  for _, it in ipairs(items) do
    idx = idx + 1
    local r = getRow(idx)
    local step = it.step
    r.text:ClearAllPoints()
    if it.note or (step and step.header) then
      r.check:Hide(); r.pin:Hide()
      r.text:SetFontObject(it.note and "GameFontHighlightSmall" or "GameFontNormal")
      r.text:SetPoint("TOPLEFT", 0, -2)
      r.text:SetWidth(width)
      r.text:SetText(it.note or step.header)
      r.text:SetTextColor(it.note and 0.85 or 1, it.note and 0.85 or 0.82, it.note and 0.85 or 0)
      if step and step.header then y = y - 6 end
    else
      total = total + 1
      local isDone = stepDone(it.index, step)
      if isDone then done = done + 1 end
      r.check:Show()
      r.check:SetChecked(isDone)
      r.check:SetScript("OnClick", function(self)
        state().checked[it.index] = self:GetChecked() and true or nil
        refresh()
      end)
      local hasPin = step.mapID and step.x and step.y
      r.pin:SetShown(hasPin and true or false)
      r.pin:SetScript("OnClick", function() setWaypoint(step) end)
      r.text:SetFontObject("GameFontHighlight")
      r.text:SetPoint("TOPLEFT", 26, -4)
      r.text:SetWidth(width - 26 - (hasPin and 30 or 0))
      local label = step.text or "?"
      if step.x and step.y then label = string.format("%s |cff999999(%.1f, %.1f)|r", label, step.x, step.y) end
      r.text:SetText(label)
      if isDone then r.text:SetTextColor(0.5, 0.5, 0.5) else r.text:SetTextColor(1, 1, 1) end
    end
    local h = math.max(it.note and 0 or 22, r.text:GetStringHeight() + 8)
    r:SetSize(width, h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r:Show()
    y = y - h
  end
  content:SetHeight(math.max(10, -y))
  progressText:SetText(total > 0 and string.format(T.progress, done, total) or "")
  local ps = state()
  ps.done, ps.total = done, total
end

local function toggle()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show(); refresh() end
end

------------------------------------------------------------------ minimap button
-- Left click: open/close the plan. Right click: take a snapshot (/cexp). Drag: move around the minimap.
local mmButton
local atan2 = math.atan2 or atan2

local function mmSettings()
  ClaudeExportDB = ClaudeExportDB or {}
  ClaudeExportDB.minimap = ClaudeExportDB.minimap or { angle = 200 }
  return ClaudeExportDB.minimap
end

local function mmPlace()
  local angle = math.rad(mmSettings().angle or 200)
  local r = (Minimap:GetWidth() / 2) + 10
  local x, y = math.cos(angle), math.sin(angle)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  if shape == "SQUARE" then
    -- push the button to the edge of a square minimap (e.g. Leatrix Plus square minimap)
    local diag = math.sqrt(2) * r
    x = math.max(-r, math.min(r, x * diag))
    y = math.max(-r, math.min(r, y * diag))
  else
    x, y = x * r, y * r
  end
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function mmDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local s = Minimap:GetEffectiveScale()
  mmSettings().angle = math.deg(atan2(py / s - my, px / s - mx)) % 360
  mmPlace()
end

local function createMinimapButton()
  if mmButton or not Minimap then return end
  local b = CreateFrame("Button", "ClaudeExportMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if SlashCmdList.CLAUDEEXPORT then SlashCmdList.CLAUDEEXPORT("") end
    else
      ns.togglePlan()
    end
  end)
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", mmDragUpdate) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ClaudeExport")
    local p = plan()
    if p then
      local ps = state()
      GameTooltip:AddLine(p.title or "Plan", 1, 1, 1)
      if ps.total and ps.total > 0 then GameTooltip:AddLine(string.format(T.progress, ps.done or 0, ps.total), 0.8, 0.8, 0.8) end
    end
    GameTooltip:AddLine(T.mmLeft, 0.6, 0.8, 1)
    GameTooltip:AddLine(T.mmRight, 0.6, 0.8, 1)
    GameTooltip:AddLine(T.mmDrag, 0.6, 0.8, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  mmButton = b
  mmPlace()
  if mmSettings().hide then b:Hide() end
end

ns.togglePlan = toggle

SLASH_CLAUDEEXPORTPLAN1 = "/cplan"
SlashCmdList.CLAUDEEXPORTPLAN = function(msg)
  msg = (msg or ""):lower()
  if msg:find("minimap") or msg:find("миникарт") then
    createMinimapButton()
    local s = mmSettings()
    s.hide = not s.hide
    if mmButton then mmButton:SetShown(not s.hide) end
    print("|cff66ccffClaudeExport|r " .. (s.hide and T.mmHidden or T.mmShown))
    return
  end
  if msg:find("reset") then
    local ps = state()
    ps.checked = {}
    print("|cff66ccffClaudeExport|r " .. T.reset)
    refresh()
    return
  end
  toggle()
end

-- keep quest-driven ticks current; tell the player once when a new plan arrives
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "QUEST_TURNED_IN")
pcall(ev.RegisterEvent, ev, "QUEST_LOG_UPDATE")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    createMinimapButton()
    local id = planId()
    if id and ClaudeExportDB and ClaudeExportDB.planSeen ~= id then
      ClaudeExportDB.planSeen = id
      C_Timer.After(6, function()
        print("|cff66ccffClaudeExport|r " .. string.format(T.newPlan, plan().title or id))
      end)
    end
    state()
  else
    refresh()
  end
end)

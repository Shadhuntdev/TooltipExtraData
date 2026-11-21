local addonName, TED = ...

TooltipExtraDataDB = TooltipExtraDataDB or {}

-- =========================
-- Defaults
-- =========================
local defaults = {
  enabled = true,
  colorGray = "808080",

  inspect = {
    cacheExpire = 600,
    delay = 0.05,
  },

  modules = {
    stack      = true,  -- current/max stack, or owned/max in AH/Auctionator
    itemid     = true,  -- ItemID on item tooltips
    spellid    = true,  -- SpellID on spell tooltips
    iconid     = true,  -- IconID (texture FileID) below ItemID/SpellID
    playerinfo = true,  -- target player's spec, average item level, and repair percentage via inspect
    playerself = true,  -- own player's spec/item level/repair shown on your own tooltip
    proficons  = true,  -- icons of the professions that use the item as a reagent
  },

  professionIcons = {
    position = "bottom", -- "bottom" (end of tooltip) | "title" (below the item name)
    size     = "medium", -- "small" | "medium" | "large"
    filter   = "all",    -- "all" | "learned" | "manual"
    -- Manual selection, keyed by profession SkillLine ID
    selected = {
      [171] = true, [164] = true, [333] = true, [202] = true, [182] = true,
      [773] = true, [755] = true, [165] = true, [186] = true, [393] = true,
      [197] = true, [185] = true, [356] = true, [129] = true,
    },
  },
}

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = {}
      end
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function Gray(text)
  local hex = (TooltipExtraDataDB and TooltipExtraDataDB.colorGray) or "808080"
  return "|cff" .. hex .. tostring(text) .. "|r"
end

local function Enabled()
  return TooltipExtraDataDB and TooltipExtraDataDB.enabled
end

local function ModuleOn(key)
  return Enabled() and TooltipExtraDataDB.modules and TooltipExtraDataDB.modules[key]
end

local function GetInspectCacheExpire()
  local value = TooltipExtraDataDB
    and TooltipExtraDataDB.inspect
    and TooltipExtraDataDB.inspect.cacheExpire

  value = tonumber(value)
  if value and value > 0 then
    return value
  end

  return 600
end

local function GetInspectDelay()
  local value = TooltipExtraDataDB
    and TooltipExtraDataDB.inspect
    and TooltipExtraDataDB.inspect.delay

  value = tonumber(value)
  if value and value >= 0 then
    return value
  end

  return 0.05
end

-- =========================
-- Safe helpers
-- =========================
local function SafeCall(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end

-- Detecta valores secretos de Retail (no se pueden comparar ni indexar).
local function IsSecret(value)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret and true or false
  end
  return false
end

-- Devuelve un número utilizable, o nil si es secreto o no numérico.
local function SafeNumber(value)
  if value == nil or IsSecret(value) then
    return nil
  end

  local ok, n = pcall(tonumber, value)
  if not ok or type(n) ~= "number" then
    return nil
  end

  -- Si la comparación falla, el número sigue siendo secreto.
  local okCmp = pcall(function() return n > 0 end)
  if not okCmp then
    return nil
  end

  return n
end

local function SafeCompare(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then
    return false
  end

  if ta == "nil" then
    return true
  end

  if ta == "number" or ta == "boolean" then
    return a == b
  end

  -- Evita comparar strings tainted/secret strings directamente.
  if ta == "string" then
    return false
  end

  local ok, result = pcall(function()
    return a == b
  end)

  return ok and result or false
end

local function IsSafeTableKey(key)
  local test = {}
  local ok = pcall(function()
    test[key] = true
    test[key] = nil
  end)

  return ok
end

local function SafeTableGet(tbl, key)
  if type(tbl) ~= "table" or key == nil then
    return nil
  end

  local ok, value = pcall(function()
    return tbl[key]
  end)

  if ok then
    return value
  end

  return nil
end

local function SafeTableSet(tbl, key, value)
  if type(tbl) ~= "table" or key == nil then
    return false
  end

  local ok = pcall(function()
    tbl[key] = value
  end)

  return ok
end

-- =========================
-- Tooltip state helpers
-- =========================
local function ensureTooltipState(tooltip)
  if not tooltip then return nil end
  tooltip.TED_State = tooltip.TED_State or {}
  return tooltip.TED_State
end

local function wasAdded(tooltip, key, value)
  local state = ensureTooltipState(tooltip)
  if not state then return false end

  if value == nil then
    return state[key] and true or false
  end

  return SafeCompare(state[key], value)
end

local function markAdded(tooltip, key, value)
  local state = ensureTooltipState(tooltip)
  if not state then return end

  if value == nil then
    state[key] = true
  else
    state[key] = value
  end
end

local function clearTooltipState(tooltip)
  if tooltip then
    tooltip.TED_State = nil
    tooltip.TED_InspectPending = nil
    tooltip.TED_NextPlayerInfoCheck = nil
  end
end

-- =========================
-- Tooltip helpers
-- =========================
local function getTooltipName(tooltip)
  return tooltip and tooltip.GetName and tooltip:GetName() or nil
end

local function addDoubleLine(tooltip, leftText, rightText)
  if not tooltip or not tooltip.AddDoubleLine then return end

  local ok = SafeCall(
    tooltip.AddDoubleLine,
    tooltip,
    leftText,
    rightText,
    nil, nil, nil,
    WHITE_FONT_COLOR.r,
    WHITE_FONT_COLOR.g,
    WHITE_FONT_COLOR.b
  )

  if ok then
    SafeCall(tooltip.Show, tooltip)
  end
end

local function addSingleLine(tooltip, text, r, g, b)
  if not tooltip or not tooltip.AddLine or not text or text == "" then return end

  local ok = SafeCall(tooltip.AddLine, tooltip, text, r or 1, g or 1, b or 1, true)
  if ok then
    SafeCall(tooltip.Show, tooltip)
  end
end

local function SafeHookScript(frame, scriptName, fn)
  if frame and frame.HasScript and frame:HasScript(scriptName) then
    frame:HookScript(scriptName, fn)
  end
end

local function GetUnitClassColor(unit)
  if not unit or not UnitClass then
    return 1, 1, 1
  end

  local _, classFile = UnitClass(unit)
  if not classFile then
    return 1, 1, 1
  end

  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if color then
    return color.r or 1, color.g or 1, color.b or 1
  end

  return 1, 1, 1
end

local function ColorizeText(text, r, g, b)
  if not text then return "" end
  r = math.max(0, math.min(1, tonumber(r) or 1))
  g = math.max(0, math.min(1, tonumber(g) or 1))
  b = math.max(0, math.min(1, tonumber(b) or 1))
  return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, tostring(text))
end

local function GetItemIDFromLink(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function GetItemIDFromItemKey(...)
  local a1, a2 = ...
  if type(a1) == "table" then
    return tonumber(a1.itemID or a1.itemId or a1.id)
  end
  if type(a1) == "number" then
    return tonumber(a1)
  end
  if type(a2) == "number" then
    return tonumber(a2)
  end
  return nil
end

local function NormalizeCount(count)
  if count == nil then
    return nil
  end

  local ok, n = pcall(function()
    return tonumber(count)
  end)

  if ok and n ~= nil then
    return n
  end

  return nil
end

local function ExtractCountFromTooltipData(data)
  if type(data) ~= "table" then return nil end

  local count = data.stackCount
    or data.quantity
    or data.count
    or data.itemCount
    or data.stackSize
    or data.charges

  return NormalizeCount(count)
end

local function ExtractItemIDFromAny(data)
  if type(data) ~= "table" then return nil end

  return tonumber(
    data.itemID
    or data.itemId
    or data.id
    or (type(data.itemKey) == "table" and (data.itemKey.itemID or data.itemKey.itemId))
    or (type(data.itemKeyInfo) == "table" and (data.itemKeyInfo.itemID or data.itemKeyInfo.itemId))
    or (type(data.auctionInfo) == "table" and (data.auctionInfo.itemID or data.auctionInfo.itemId))
  )
end

local function ExtractCountFromAny(data)
  if type(data) ~= "table" then return nil end

  return NormalizeCount(
    data.quantity
    or data.stackCount
    or data.count
    or data.itemCount
    or data.stackSize
  )
end

local function GetOwnedItemCount(itemId)
  if not itemId or not GetItemCount then
    return 0
  end

  local ok, count = pcall(GetItemCount, itemId)
  if not ok or count == nil then
    return 0
  end

  local normalized = NormalizeCount(count)
  if normalized == nil then
    return 0
  end

  return normalized
end

-- =========================
-- API wrappers
-- =========================
local GetItemMaxStackSizeByID = (C_Item and C_Item.GetItemMaxStackSizeByID) and C_Item.GetItemMaxStackSizeByID
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID or GetItemIconByID
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) and C_Spell.GetSpellTexture or GetSpellTexture

-- =========================
-- Safe unit resolution for inspect
-- =========================
local function ResolveInspectableUnit(tooltip)
  if tooltip ~= GameTooltip then
    return nil
  end

  local unit = "mouseover"

  if not UnitExists(unit) then return nil end
  if not UnitIsPlayer(unit) then return nil end
  if UnitIsUnit and UnitIsUnit(unit, "player") then
    if not ModuleOn("playerself") then
      return nil
    end
  end
  if UnitIsConnected and not UnitIsConnected(unit) then return nil end
  if CanInspect and not CanInspect(unit, true) then return nil end

  return unit
end

-- =========================
-- Inspect cache / queue
-- =========================
TED.InspectCache = TED.InspectCache or {}
TED.InspectQueue = TED.InspectQueue or {}

local inspectFrame = CreateFrame("Frame")
local inspectTickerActive = false
local pendingInspectUnit = nil
local pendingInspectTooltip = nil
local lastInspectRequestByKey = {}

local function GetSafeUnitKey(unit)
  -- Avoid UnitFullName() for inspect cache keys.
  -- In modern Retail, UnitFullName() can return secret/tainted strings from tooltip-driven flows,
  -- and comparing/concatenating those values can throw secure execution errors.
  if unit ~= "mouseover" then return nil end
  if not UnitExists or not UnitExists(unit) then return nil end
  if not UnitIsPlayer or not UnitIsPlayer(unit) then return nil end

  local okGuid, guid = pcall(UnitGUID, unit)
  if okGuid and type(guid) == "string" and IsSafeTableKey(guid) then
    return guid
  end

  return nil
end

local function GetCachedInspectData(unit)
  local key = GetSafeUnitKey(unit)
  if not key then return nil end

  local data = SafeTableGet(TED.InspectCache, key)
  if type(data) ~= "table" then
    return nil
  end

  local age = time() - (data.timestamp or 0)
  if age >= GetInspectCacheExpire() then
    SafeTableSet(TED.InspectCache, key, nil)
    return nil
  end

  return data
end

local function SetCachedInspectData(unit, data)
  local key = GetSafeUnitKey(unit)
  if not key or type(data) ~= "table" then return end

  data.timestamp = time()
  SafeTableSet(TED.InspectCache, key, data)
end

local function QueueInspect(unit, tooltip)
  if not ModuleOn("playerinfo") then return end
  if not unit or not tooltip then return end
  if type(unit) ~= "string" then return end
  if not UnitExists or not UnitExists(unit) then return end
  if not UnitIsPlayer or not UnitIsPlayer(unit) then return end
  if UnitIsUnit and UnitIsUnit(unit, "player") then return end
  if UnitIsConnected and not UnitIsConnected(unit) then return end
  if CanInspect and not CanInspect(unit, true) then return end

  if InCombatLockdown and InCombatLockdown() then return end

  local key = GetSafeUnitKey(unit)
  if not key then return end

  if GetCachedInspectData(unit) then
    return
  end

  local now = GetTime and GetTime() or time()
  local lastInspectRequest = SafeTableGet(lastInspectRequestByKey, key)
  if lastInspectRequest and (now - lastInspectRequest) < 3 then
    return
  end

  if tooltip.TED_InspectPending then
    return
  end

  for i = 1, #TED.InspectQueue do
    local entry = TED.InspectQueue[i]
    if entry and entry.tooltip == tooltip then
      return
    end
  end

  tooltip.TED_InspectPending = true

  table.insert(TED.InspectQueue, {
    unit = unit,
    tooltip = tooltip,
    key = key,
  })
end

local function ProcessInspectQueue()
  if pendingInspectUnit then
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    return
  end

  while #TED.InspectQueue > 0 do
    local entry = table.remove(TED.InspectQueue, 1)
    if entry then
      local tooltip = entry.tooltip
      local unit = ResolveInspectableUnit(tooltip)

      if tooltip and tooltip:IsShown() and unit then
        if CanInspect and CanInspect(unit, true) then
          pendingInspectUnit = unit
          pendingInspectTooltip = tooltip
          if entry.key then
            SafeTableSet(lastInspectRequestByKey, entry.key, GetTime and GetTime() or time())
          end
          SafeCall(NotifyInspect, unit)
          return
        end
      end

      if tooltip then
        tooltip.TED_InspectPending = nil
      end
    end
  end
end

local function StartInspectTicker()
  if inspectTickerActive then return end
  inspectTickerActive = true

  C_Timer.NewTicker(0.35, function()
    if not Enabled() or not ModuleOn("playerinfo") then
      return
    end
    ProcessInspectQueue()
  end)
end

local function GetSpecNameByID(specID)
  specID = SafeNumber(specID)
  if not specID or specID <= 0 then
    return nil
  end

  local ok, _, name = SafeCall(GetSpecializationInfoByID, specID)
  if not ok or IsSecret(name) then
    return nil
  end
  return name
end

-- Forever (1.60.1) no expone las funciones globales de especialización; usa C_SpecializationInfo.
local GetInspectSpecializationAPI = GetInspectSpecialization
  or (C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization)
local GetSpecializationAPI = GetSpecialization
  or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
local GetSpecializationInfoAPI = GetSpecializationInfo
  or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)

local function GetInspectSpecID(unit)
  local ok, specID = SafeCall(GetInspectSpecializationAPI, unit)
  return ok and SafeNumber(specID) or nil
end

local function FormatItemLevel(value)
  value = SafeNumber(value)
  if not value or value <= 0 then
    return nil
  end

  return tostring(math.floor(value + 0.5))
end

local function FormatRepairPercent(value)
  value = SafeNumber(value)
  if not value or value < 0 then
    return nil
  end

  if value > 100 then
    value = 100
  end

  return tostring(math.floor(value + 0.5)) .. "%"
end

local durableInventorySlots = {
  1,  -- Head
  3,  -- Shoulder
  5,  -- Chest
  6,  -- Waist
  7,  -- Legs
  8,  -- Feet
  9,  -- Wrist
  10, -- Hands
  16, -- Main hand
  17, -- Off hand
}

local function ParseDurabilityLine(text)
  if type(text) ~= "string" then
    return nil, nil
  end

  local ok, current, max = pcall(function()
    local currentText, maxText = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(currentText), tonumber(maxText)
  end)

  if ok and current and max and max > 0 and current >= 0 and current <= max then
    return current, max
  end

  return nil, nil
end

local function GetInspectRepairPercent(unit)
  if not unit or type(unit) ~= "string" then return nil end
  if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end

  local totalCurrent = 0
  local totalMax = 0

  for _, slot in ipairs(durableInventorySlots) do
    if slot then
      local okTooltip, tooltipData = pcall(C_TooltipInfo.GetInventoryItem, unit, slot)
      if okTooltip and tooltipData and type(tooltipData.lines) == "table" then
        for _, line in ipairs(tooltipData.lines) do
          local current, max = ParseDurabilityLine(line and line.leftText)
          if current and max then
            totalCurrent = totalCurrent + current
            totalMax = totalMax + max
            break
          end
        end
      end
    end
  end

  if totalMax <= 0 then
    return nil
  end

  return (totalCurrent / totalMax) * 100
end

-- =========================
-- Modules
-- =========================
TED.Modules = {}

-- ---- Stack module
function TED.Modules.Stack(tooltip, itemId, currentCount)
  if not ModuleOn("stack") then return end
  if not GetItemMaxStackSizeByID then return end
  if not tooltip or not itemId or currentCount == nil then return end

  local itemIdNum = tonumber(itemId)
  local currentNum = NormalizeCount(currentCount)
  if not itemIdNum or currentNum == nil then return end

  local okMax, maxStack = pcall(GetItemMaxStackSizeByID, itemIdNum)
  if not okMax or not maxStack then return end

  local maxNum = NormalizeCount(maxStack)
  if maxNum == nil or maxNum <= 1 then return end

  local name = getTooltipName(tooltip)
  if not name then return end

  local right1 = _G[name .. "TextRight1"]
  if not right1 or not right1.SetText then return end

  if wasAdded(tooltip, "stack") then return end

  local displayText = tostring(currentNum) .. "/" .. tostring(maxNum)

  local ok = SafeCall(right1.SetText, right1, Gray(displayText))
  if ok then
    SafeCall(right1.Show, right1)
    SafeCall(tooltip.Show, tooltip)
    markAdded(tooltip, "stack")
  end
end

-- ---- ItemID module
function TED.Modules.ItemID(tooltip, itemId)
  if not ModuleOn("itemid") then return end
  if not tooltip or not itemId then return end

  itemId = tonumber(itemId)
  if not itemId then return end

  if wasAdded(tooltip, "itemid", itemId) then return end
  addDoubleLine(tooltip, "ItemID", tostring(itemId))
  markAdded(tooltip, "itemid", itemId)
end

-- ---- SpellID module
function TED.Modules.SpellID(tooltip, spellId)
  if not ModuleOn("spellid") then return end
  if not tooltip or not spellId then return end

  spellId = tonumber(spellId)
  if not spellId then return end

  if wasAdded(tooltip, "spellid", spellId) then return end
  addDoubleLine(tooltip, "SpellID", tostring(spellId))
  markAdded(tooltip, "spellid", spellId)
end

-- ---- IconID module
function TED.Modules.IconID(tooltip, iconId)
  if not ModuleOn("iconid") then return end
  if not tooltip or not iconId then return end

  iconId = tonumber(iconId)
  if not iconId then return end

  if wasAdded(tooltip, "iconid", iconId) then return end
  addDoubleLine(tooltip, "IconID", tostring(iconId))
  markAdded(tooltip, "iconid", iconId)
end

-- ---- ProfessionIcons module
-- Bit order must match $Professions in scripts/build-profession-data.ps1 (bit = 2^(index-1)).
local PROFESSION_ORDER = { 171, 164, 333, 202, 182, 773, 755, 165, 186, 393, 197, 185, 356, 129 }

local PROFESSION_NAMES = {
  [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
  [182] = "Herbalism", [773] = "Inscription", [755] = "Jewelcrafting", [165] = "Leatherworking",
  [186] = "Mining", [393] = "Skinning", [197] = "Tailoring", [185] = "Cooking",
  [356] = "Fishing", [129] = "First Aid",
}

local PROFESSION_ICON_SIZES = { small = 14, medium = 18, large = 24 }

local PROFESSION_BITS = {}
for index, skillLine in ipairs(PROFESSION_ORDER) do
  PROFESSION_BITS[skillLine] = 2 ^ (index - 1)
end

local function HasBit(mask, bitValue)
  return math.floor(mask / bitValue) % 2 == 1
end

local function GetProfessionIconSettings()
  return (TooltipExtraDataDB and TooltipExtraDataDB.professionIcons) or defaults.professionIcons
end

local function GetProfessionDisplayName(skillLine)
  if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
    local ok, name = SafeCall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then
      return name
    end
  end
  return PROFESSION_NAMES[skillLine] or tostring(skillLine)
end

-- Professions available in this client (Forever has no Inscription/Jewelcrafting, Retail no First Aid).
local function GetAvailableProfessions()
  local data = TED.ProfessionData
  local list = {}
  for _, skillLine in ipairs(PROFESSION_ORDER) do
    if data and data.icons and data.icons[skillLine] then
      list[#list + 1] = skillLine
    end
  end
  return list
end

-- Learned professions mask, invalidated on SKILL_LINES_CHANGED.
local learnedProfessionMask

local function GetLearnedProfessionMask()
  if learnedProfessionMask then return learnedProfessionMask end

  local mask = 0
  local okList, p1, p2, archaeology, fishing, cooking = SafeCall(GetProfessions)
  if okList then
    local indices = { p1, p2, archaeology, fishing, cooking }
    for i = 1, 5 do
      local index = SafeNumber(indices[i])
      if index then
        local okInfo, _, _, _, _, _, _, skillLine = SafeCall(GetProfessionInfo, index)
        skillLine = okInfo and SafeNumber(skillLine) or nil
        local bitValue = skillLine and PROFESSION_BITS[skillLine]
        if bitValue and not HasBit(mask, bitValue) then
          mask = mask + bitValue
        end
      end
    end
  end

  learnedProfessionMask = mask
  return mask
end

local function BuildProfessionIconsText(itemId)
  local data = TED.ProfessionData
  if not data or not data.items or not data.icons then return nil end

  local itemMask = data.items[itemId]
  if not itemMask then return nil end

  local settings = GetProfessionIconSettings()
  local filter = settings.filter
  local learnedMask = (filter == "learned") and GetLearnedProfessionMask() or nil
  local size = PROFESSION_ICON_SIZES[settings.size] or PROFESSION_ICON_SIZES.medium

  local parts = {}
  for _, skillLine in ipairs(PROFESSION_ORDER) do
    local bitValue = PROFESSION_BITS[skillLine]
    local icon = data.icons[skillLine]
    if icon and HasBit(itemMask, bitValue) then
      local show = true
      if filter == "learned" then
        show = HasBit(learnedMask, bitValue)
      elseif filter == "manual" then
        show = settings.selected and settings.selected[skillLine] and true or false
      end
      if show then
        parts[#parts + 1] = "|T" .. icon .. ":" .. size .. ":" .. size .. "|t"
      end
    end
  end

  if #parts == 0 then return nil end
  return table.concat(parts, " ")
end

-- Puts the icons at the start of line 2 so they appear right below the item name.
-- The title line is left untouched because other addons read the item name from it.
local function InsertBelowTitle(tooltip, text)
  local name = getTooltipName(tooltip)
  if not name or not tooltip.NumLines then return false end

  local okLines, numLines = SafeCall(tooltip.NumLines, tooltip)
  numLines = okLines and SafeNumber(numLines) or nil
  if not numLines or numLines < 2 then return false end

  local line = _G[name .. "TextLeft2"]
  if not line or not line.GetText or not line.SetText then return false end

  local okText, current = SafeCall(line.GetText, line)
  if not okText or IsSecret(current) then return false end

  local newText = text
  if type(current) == "string" and current ~= "" then
    newText = text .. "\n" .. current
  end

  local ok = SafeCall(line.SetText, line, newText)
  if ok then
    SafeCall(tooltip.Show, tooltip)
  end
  return ok
end

function TED.Modules.ProfessionIcons(tooltip, itemId)
  if not ModuleOn("proficons") then return end
  if not tooltip or not itemId then return end

  itemId = tonumber(itemId)
  if not itemId then return end

  if wasAdded(tooltip, "proficons", itemId) then return end

  local text = BuildProfessionIconsText(itemId)
  if not text then return end

  local placed = false
  if GetProfessionIconSettings().position == "title" then
    placed = InsertBelowTitle(tooltip, text)
  end
  if not placed then
    -- Blank line to separate the icons from the previous line.
    addSingleLine(tooltip, " ")
    addSingleLine(tooltip, text)
  end

  markAdded(tooltip, "proficons", itemId)
end

-- Tooltip line scanning intentionally disabled for player info to avoid secret string comparisons.

-- ---- PlayerInfo module
function TED.Modules.PlayerInfo(tooltip, unit, specName, itemLevel, repairPercent)
  -- Allow for target info (`playerinfo`) or own-player tooltip when `playerself` enabled
  if not (ModuleOn("playerinfo") or (unit == "player" and ModuleOn("playerself"))) then return end
  if not tooltip or not unit then return end

  local ilevelText = FormatItemLevel(itemLevel)
  local repairText = FormatRepairPercent(repairPercent)
  if not specName and not ilevelText and not repairText then return end

  local r, g, b = GetUnitClassColor(unit)
  local coloredSpec = specName and ColorizeText(specName, r, g, b) or nil

  local lineText
  if coloredSpec and ilevelText then
    lineText = coloredSpec .. " " .. Gray("[" .. ilevelText .. "]")
  elseif coloredSpec then
    lineText = coloredSpec
  elseif ilevelText then
    lineText = Gray("[" .. ilevelText .. "]")
  end

  -- Do not scan existing tooltip font strings here.
  -- FontString:GetText() may return secret/tainted strings, and comparing them can throw
  -- "attempt to compare ... secret string value" errors. Use our own per-tooltip state instead.
  if lineText and not wasAdded(tooltip, "playerinfo") then
    addSingleLine(tooltip, lineText)
    markAdded(tooltip, "playerinfo")
  end

  if repairText and not wasAdded(tooltip, "playerrepair") then
    addSingleLine(tooltip, Gray("Repair: [" .. repairText .. "]"))
    markAdded(tooltip, "playerrepair")
  end
end

-- =========================
-- Common item/spell appliers
-- =========================
local function ApplyItemModules(tooltip, itemId, count)
  if not Enabled() then return end
  if not tooltip or not itemId then return end

  itemId = tonumber(itemId)
  if not itemId then return end

  if count ~= nil then
    count = NormalizeCount(count)
    if count ~= nil then
      TED.Modules.Stack(tooltip, itemId, count)
    end
  end

  TED.Modules.ItemID(tooltip, itemId)

  local okIcon, iconId = pcall(function()
    return GetItemIconByID and GetItemIconByID(itemId)
  end)

  if okIcon and iconId then
    TED.Modules.IconID(tooltip, iconId)
  end

  TED.Modules.ProfessionIcons(tooltip, itemId)
end

local function ApplySpellModules(tooltip, spellId)
  if not Enabled() then return end
  if not tooltip or not spellId then return end

  spellId = tonumber(spellId)
  if not spellId then return end

  TED.Modules.SpellID(tooltip, spellId)

  local okIcon, iconId = pcall(function()
    return GetSpellTexture and GetSpellTexture(spellId)
  end)

  if okIcon and iconId then
    TED.Modules.IconID(tooltip, iconId)
  end
end

local function ApplyAHOwnedStack(tooltip, itemId)
  if not Enabled() then return end
  if not ModuleOn("stack") then return end
  if not tooltip or not itemId then return end

  itemId = tonumber(itemId)
  if not itemId then return end

  local ownedCount = GetOwnedItemCount(itemId)
  ApplyItemModules(tooltip, itemId, ownedCount)
end

local function ApplyPlayerInfoToTooltip(tooltip, unit)
  if not Enabled() then return end
  if not (ModuleOn("playerinfo") or ModuleOn("playerself")) then return end
  if not tooltip or not unit then return end
  if type(unit) ~= "string" then return end
  if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
  -- Special-case: if the unit is the player themselves and the `playerself` option
  -- is enabled, fetch local data immediately (no inspect queue).
  if UnitIsUnit and UnitIsUnit(unit, "player") and ModuleOn("playerself") then
    local specName = nil
    local okIndex, specIndex = SafeCall(GetSpecializationAPI)
    specIndex = okIndex and SafeNumber(specIndex) or nil
    if specIndex and specIndex > 0 then
      local okInfo, _, name = SafeCall(GetSpecializationInfoAPI, specIndex)
      if okInfo and type(name) == "string" and not IsSecret(name) then
        specName = name
      end
    end

    -- Fallback: try inspect-style API to get spec ID/name for player
    if not specName then
      local specID = GetInspectSpecID("player")
      if specID and specID > 0 then
        specName = GetSpecNameByID(specID)
      end
    end

    local itemLevel = (C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and C_PaperDollInfo.GetInspectItemLevel("player"))
    -- Fallback: use GetAverageItemLevel when available
    itemLevel = SafeNumber(itemLevel)
    if (not itemLevel or itemLevel == 0) and GetAverageItemLevel then
      local ok, avg = pcall(function() return GetAverageItemLevel() end)
      if ok and avg and tonumber(avg) then
        itemLevel = avg
      end
    end
    local repairPercent = GetInspectRepairPercent("player")

    TED.Modules.PlayerInfo(tooltip, unit, specName, itemLevel, repairPercent)
    return
  end

  local cached = GetCachedInspectData(unit)
  if cached then
    TED.Modules.PlayerInfo(tooltip, unit, cached.specName, cached.itemLevel, cached.repairPercent)
    return
  end

  local capturedUnit = unit
  local capturedTooltip = tooltip
  local delay = GetInspectDelay()

  if delay <= 0 then
    QueueInspect(capturedUnit, capturedTooltip)
    ProcessInspectQueue()
    return
  end

  C_Timer.After(delay, function()
    if not capturedTooltip or not capturedTooltip:IsShown() then return end
    if type(capturedUnit) ~= "string" then return end
    if not UnitExists(capturedUnit) then return end
    if not UnitIsPlayer(capturedUnit) then return end
    if UnitIsUnit and UnitIsUnit(capturedUnit, "player") then return end

    QueueInspect(capturedUnit, capturedTooltip)
    ProcessInspectQueue()
  end)
end

-- =========================
-- Generic frame/data scanning
-- =========================
local function FindCountInFrameChain(frame, maxDepth)
  local depth = 0
  local current = frame
  maxDepth = maxDepth or 8

  while current and depth < maxDepth do
    local directCount = NormalizeCount(
      current.quantity
      or current.stackCount
      or current.count
      or current.itemCount
    )
    if directCount ~= nil then
      return directCount
    end

    if current.GetElementData then
      local ok, data = pcall(current.GetElementData, current)
      if ok and type(data) == "table" then
        local count = NormalizeCount(
          data.quantity
          or data.stackCount
          or data.count
          or data.itemCount
        )
        if count ~= nil then
          return count
        end

        if type(data.itemKeyInfo) == "table" then
          count = NormalizeCount(
            data.itemKeyInfo.quantity
            or data.itemKeyInfo.stackCount
            or data.itemKeyInfo.count
            or data.itemKeyInfo.itemCount
          )
          if count ~= nil then
            return count
          end
        end

        if type(data.auctionInfo) == "table" then
          count = NormalizeCount(
            data.auctionInfo.quantity
            or data.auctionInfo.stackCount
            or data.auctionInfo.count
            or data.auctionInfo.itemCount
          )
          if count ~= nil then
            return count
          end
        end
      end
    end

    current = current.GetParent and current:GetParent() or nil
    depth = depth + 1
  end

  return nil
end

local function IsAuctionatorFrame(frame)
  local depth = 0
  local current = frame

  while current and depth < 12 do
    local name = current.GetName and current:GetName()
    if type(name) == "string" and name:find("Auctionator", 1, true) then
      return true
    end

    if current.AuctionatorSellingFrame
      or current.AuctionatorShoppingFrame
      or current.AuctionatorCancellingFrame
      or current.AuctionatorTabMixin
      or current.Search
      or current.ResultsListing
      or current.BuyDisplay
    then
      return true
    end

    current = current.GetParent and current:GetParent() or nil
    depth = depth + 1
  end

  return false
end

local function ReadAuctionatorDataObject(data, wantedItemID, depth)
  if type(data) ~= "table" then return nil end
  depth = depth or 0
  if depth > 5 then return nil end

  local foundItemID = ExtractItemIDFromAny(data)
  local foundCount = ExtractCountFromAny(data)

  if foundCount ~= nil then
    if wantedItemID == nil or foundItemID == nil or foundItemID == wantedItemID then
      return foundCount
    end
  end

  local keys = {
    "data",
    "itemKey",
    "itemKeyInfo",
    "auctionInfo",
    "selectedData",
    "selectedRowData",
    "selectedResult",
    "selectedListing",
    "selectedItem",
    "selectedEntry",
    "rowData",
    "result",
    "listing",
    "searchResult",
    "currentRowData",
    "elementData",
    "searchData",
    "purchaseData",
    "buyData",
    "resultsData",
  }

  for _, key in ipairs(keys) do
    local sub = data[key]
    if type(sub) == "table" then
      local count = ReadAuctionatorDataObject(sub, wantedItemID, depth + 1)
      if count ~= nil then
        return count
      end
    end
  end

  return nil
end

local function ReadAuctionatorObject(obj, wantedItemID)
  if type(obj) ~= "table" then return nil end

  local count = ReadAuctionatorDataObject(obj, wantedItemID, 0)
  if count ~= nil then
    return count
  end

  local methods = {
    "GetElementData",
    "GetData",
    "GetSelectedData",
    "GetSelectedResult",
    "GetSelectedRowData",
    "GetResult",
    "GetListingData",
  }

  for _, methodName in ipairs(methods) do
    local method = obj[methodName]
    if type(method) == "function" then
      local ok, result = pcall(method, obj)
      if ok and type(result) == "table" then
        count = ReadAuctionatorDataObject(result, wantedItemID, 0)
        if count ~= nil then
          return count
        end
      end
    end
  end

  return nil
end

-- =========================
-- Owner/context-based stack detection
-- =========================
local function GetOwnerItemID(tooltip)
  if not tooltip or not tooltip.GetItem then return nil end
  local _, link = tooltip:GetItem()
  return GetItemIDFromLink(link)
end

local function GetMerchantStackFromOwner(tooltip)
  local owner = tooltip and tooltip:GetOwner()
  if not owner then return nil end

  local name = owner.GetName and owner:GetName()
  local id = owner.GetID and owner:GetID()

  if id and name and name:match("^MerchantItem%d+$") and GetMerchantItemInfo then
    local _, _, _, quantity = GetMerchantItemInfo(id)
    return NormalizeCount(quantity)
  end

  if owner.index and GetMerchantItemInfo then
    local _, _, _, quantity = GetMerchantItemInfo(owner.index)
    return NormalizeCount(quantity)
  end

  return nil
end

local function IsAHLikeOwner(tooltip)
  local owner = tooltip and tooltip:GetOwner()
  if not owner then return false end

  local current = owner
  local depth = 0

  while current and depth < 12 do
    local name = current.GetName and current:GetName()
    if type(name) == "string" then
      if name:find("Auctionator", 1, true)
        or name:find("AuctionHouse", 1, true)
        or name:find("BrowseResults", 1, true)
        or name:find("Commodities", 1, true)
        or name:find("ItemBuyFrame", 1, true)
      then
        return true
      end
    end

    if IsAuctionatorFrame(current) then
      return true
    end

    current = current.GetParent and current:GetParent() or nil
    depth = depth + 1
  end

  return false
end

local function GetAuctionStackFromOwner(tooltip)
  local owner = tooltip and tooltip:GetOwner()
  if not owner then return nil end

  local itemId = GetOwnerItemID(tooltip)
  if not itemId then return nil end

  local count = FindCountInFrameChain(owner, 8)
  if count ~= nil then
    return GetOwnedItemCount(itemId)
  end

  return GetOwnedItemCount(itemId)
end

local function GetAuctionatorShoppingStack(tooltip)
  local owner = tooltip and tooltip:GetOwner()
  if not owner then return nil end

  local wantedItemID = GetOwnerItemID(tooltip)
  if not wantedItemID then return nil end

  local current = owner
  local depth = 0

  while current and depth < 12 do
    if IsAuctionatorFrame(current) then
      local count = ReadAuctionatorObject(current, wantedItemID)
      if count ~= nil then
        return GetOwnedItemCount(wantedItemID)
      end
    end

    current = current.GetParent and current:GetParent() or nil
    depth = depth + 1
  end

  local globalsToCheck = {
    "AuctionatorShoppingFrame",
    "AuctionatorShoppingTabFrame",
    "AuctionatorShoppingResultsListing",
    "AuctionatorShoppingResults",
    "AuctionatorResultsListing",
    "AuctionatorBuyCommodityFrame",
    "AuctionatorBuyItemFrame",
    "AuctionHouseFrame",
  }

  for _, globalName in ipairs(globalsToCheck) do
    local obj = rawget(_G, globalName)
    if type(obj) == "table" then
      local count = ReadAuctionatorObject(obj, wantedItemID)
      if count ~= nil then
        return GetOwnedItemCount(wantedItemID)
      end
    end
  end

  return GetOwnedItemCount(wantedItemID)
end

local function GetAuctionatorStackFromOwner(tooltip)
  local owner = tooltip and tooltip:GetOwner()
  if not owner then return nil end

  local itemId = GetOwnerItemID(tooltip)
  if not itemId then return nil end

  if not IsAuctionatorFrame(owner) then
    return GetAuctionatorShoppingStack(tooltip)
  end

  local count = FindCountInFrameChain(owner, 12)
  if count ~= nil then
    return GetOwnedItemCount(itemId)
  end

  count = ReadAuctionatorObject(owner, itemId)
  if count ~= nil then
    return GetOwnedItemCount(itemId)
  end

  return GetAuctionatorShoppingStack(tooltip)
end

local function ApplyContextStackFromOwner(tooltip)
  if not Enabled() then return end
  if not ModuleOn("stack") then return end
  if not tooltip then return end

  local itemId = GetOwnerItemID(tooltip)
  if not itemId then return end

  local merchantCount = GetMerchantStackFromOwner(tooltip)
  if merchantCount ~= nil then
    ApplyItemModules(tooltip, itemId, merchantCount)
    return
  end

  if IsAHLikeOwner(tooltip) then
    ApplyAHOwnedStack(tooltip, itemId)
    return
  end

  local auctionatorCount = GetAuctionatorStackFromOwner(tooltip)
  if auctionatorCount ~= nil then
    ApplyItemModules(tooltip, itemId, auctionatorCount)
    return
  end

  local auctionCount = GetAuctionStackFromOwner(tooltip)
  if auctionCount ~= nil then
    ApplyItemModules(tooltip, itemId, auctionCount)
    return
  end
end

-- =========================
-- Data extraction / hooks
-- =========================
local function handleItemFromTooltip(tooltip, data)
  if not Enabled() then return end
  if not tooltip or not tooltip.GetItem then return end

  local _, link = tooltip:GetItem()
  if not link then return end

  local itemId = GetItemIDFromLink(link)
  if not itemId then return end

  if IsAHLikeOwner(tooltip) then
    ApplyAHOwnedStack(tooltip, itemId)
    return
  end

  local count = ExtractCountFromTooltipData(data)
  ApplyItemModules(tooltip, itemId, count)

  if count == nil then
    ApplyContextStackFromOwner(tooltip)
  end
end

local function handleSpellFromTooltip(tooltip)
  if not Enabled() then return end
  if not tooltip or not tooltip.GetSpell then return end

  local _, spellId = tooltip:GetSpell()
  if not spellId then return end

  ApplySpellModules(tooltip, spellId)
end

local function handleUnitFromTooltip(tooltip)
  if not Enabled() then return end
  if not ModuleOn("playerinfo") then return end
  if not tooltip then return end

  local unit = ResolveInspectableUnit(tooltip)
  if not unit then return end

  ApplyPlayerInfoToTooltip(tooltip, unit)
end

local function onSetHyperlink(tooltip, link)
  if not Enabled() then return end
  if not link then return end

  local kind, id = link:match("^(%a+):(%d+)")
  id = tonumber(id)
  if not id then return end

  if kind == "item" then
    if IsAHLikeOwner(tooltip) then
      ApplyAHOwnedStack(tooltip, id)
    else
      ApplyItemModules(tooltip, id, nil)
    end
  elseif kind == "spell" then
    ApplySpellModules(tooltip, id)
  end
end

local function onSetItemKey(tooltip, ...)
  if not Enabled() then return end

  local itemId = GetItemIDFromItemKey(...)
  if not itemId then return end

  ApplyAHOwnedStack(tooltip, itemId)
  ApplyContextStackFromOwner(tooltip)
end

-- Bags
local function hookBags()
  if not (C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemID) then return end

  hooksecurefunc(GameTooltip, "SetBagItem", function(tooltip, bag, slot)
    if not Enabled() then return end

    local itemId = C_Container.GetContainerItemID(bag, slot)
    if not itemId then return end

    local info = C_Container.GetContainerItemInfo(bag, slot)
    local current = info and (info.stackCount or info.quantity)
    ApplyItemModules(tooltip, itemId, current)
  end)
end

-- Loot
local function hookLoot()
  if GetLootSlotLink and GetLootSlotInfo then
    hooksecurefunc(GameTooltip, "SetLootItem", function(tooltip, slot)
      if not Enabled() then return end

      local link = GetLootSlotLink(slot)
      if not link then return end

      local itemId = GetItemIDFromLink(link)
      local qty = select(3, GetLootSlotInfo(slot))

      if itemId then
        ApplyItemModules(tooltip, itemId, qty)
      end
    end)
  end

  if GetLootRollItemLink and GetLootRollItemInfo then
    hooksecurefunc(GameTooltip, "SetLootRollItem", function(tooltip, rollID)
      if not Enabled() then return end

      local link = GetLootRollItemLink(rollID)
      if not link then return end

      local itemId = GetItemIDFromLink(link)
      local qty = select(3, GetLootRollItemInfo(rollID))

      if itemId then
        ApplyItemModules(tooltip, itemId, qty)
      end
    end)
  end
end

-- Action bars
-- Resuelve el ItemID del objeto que muestra una macro en la barra de acción.
local function GetMacroActionItemID(tooltip, slot)
  local macroIndex

  if GetActionText and GetMacroIndexByName then
    local okName, macroName = SafeCall(GetActionText, slot)
    if okName and type(macroName) == "string" and not IsSecret(macroName) then
      local okIndex, index = SafeCall(GetMacroIndexByName, macroName)
      index = okIndex and SafeNumber(index) or nil
      if index and index > 0 then
        macroIndex = index
      end
    end
  end

  if macroIndex and GetMacroItem then
    local okItem, itemName, itemLink = SafeCall(GetMacroItem, macroIndex)
    if okItem then
      if not IsSecret(itemLink) then
        local okLink, itemId = pcall(GetItemIDFromLink, itemLink)
        if okLink and itemId then
          return itemId
        end
      end

      if type(itemName) == "string" and not IsSecret(itemName) and C_Item and C_Item.GetItemInfoInstant then
        local okInfo, itemId = SafeCall(C_Item.GetItemInfoInstant, itemName)
        itemId = okInfo and SafeNumber(itemId) or nil
        if itemId then
          return itemId
        end
      end
    end
  end

  -- Fallback: el objeto que Blizzard ya cargó en el tooltip de la macro.
  if tooltip and tooltip.GetItem then
    local okTip, _, link = SafeCall(tooltip.GetItem, tooltip)
    if okTip and link and not IsSecret(link) then
      local okLink, itemId = pcall(GetItemIDFromLink, link)
      if okLink and itemId then
        return itemId
      end
    end
  end

  return nil
end

local function hookActions()
  if not GetActionInfo then return end

  hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
    if not Enabled() then return end
    if not slot then return end

    local actionType, id = GetActionInfo(slot)

    local itemId
    if actionType == "item" and id then
      itemId = tonumber(id)
    elseif actionType == "macro" then
      itemId = GetMacroActionItemID(tooltip, slot)
    end
    if not itemId then return end

    local count
    if actionType == "macro" then
      -- En macros GetActionCount puede devolver 0 o un valor secreto; se usa el total en bolsas.
      count = GetOwnedItemCount(itemId)
    else
      count = NormalizeCount(GetActionCount and GetActionCount(slot))
      if count == nil and GetItemCount then
        count = GetOwnedItemCount(itemId)
      end
    end

    ApplyItemModules(tooltip, itemId, count)
  end)
end

-- Merchants / vendors
local function hookMerchants()
  if GetMerchantItemLink and GetMerchantItemInfo then
    hooksecurefunc(GameTooltip, "SetMerchantItem", function(tooltip, index)
      if not Enabled() then return end
      if not index then return end

      local link = GetMerchantItemLink(index)
      if not link then return end

      local itemId = GetItemIDFromLink(link)
      if not itemId then return end

      local _, _, _, quantity = GetMerchantItemInfo(index)
      ApplyItemModules(tooltip, itemId, quantity)
    end)
  end
end

-- Auction House
local function hookAuctionHouse()
  if GameTooltip and GameTooltip.SetAuctionItem and GetAuctionItemLink and GetAuctionItemInfo then
    hooksecurefunc(GameTooltip, "SetAuctionItem", function(tooltip, list, index)
      if not Enabled() then return end
      if not list or not index then return end

      local link = GetAuctionItemLink(list, index)
      if not link then return end

      local itemId = GetItemIDFromLink(link)
      if not itemId then return end

      ApplyAHOwnedStack(tooltip, itemId)
    end)
  end
end

-- Auctionator / SetItemKey paths
local function hookItemKeyTooltips()
  if GameTooltip and GameTooltip.SetItemKey then
    hooksecurefunc(GameTooltip, "SetItemKey", function(tooltip, ...)
      onSetItemKey(tooltip, ...)
    end)
  end

  if ItemRefTooltip and ItemRefTooltip.SetItemKey then
    hooksecurefunc(ItemRefTooltip, "SetItemKey", function(tooltip, ...)
      onSetItemKey(tooltip, ...)
    end)
  end
end

-- =========================
-- Init (Retail-safe)
-- =========================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

inspectFrame:RegisterEvent("INSPECT_READY")
inspectFrame:SetScript("OnEvent", function(_, event, guid)
  if event ~= "INSPECT_READY" then return end
  if not pendingInspectUnit then return end
  if not guid then
    if pendingInspectTooltip then
      pendingInspectTooltip.TED_InspectPending = nil
    end
    pendingInspectUnit = nil
    pendingInspectTooltip = nil
    if ClearInspectPlayer then
      SafeCall(ClearInspectPlayer)
    end
    ProcessInspectQueue()
    return
  end

  local currentTooltip = pendingInspectTooltip
  local currentUnit = pendingInspectUnit

  local specID = GetInspectSpecID(currentUnit)
  local specName = GetSpecNameByID(specID)

  local itemLevel
  if C_PaperDollInfo then
    local okIlvl, value = SafeCall(C_PaperDollInfo.GetInspectItemLevel, currentUnit)
    itemLevel = okIlvl and SafeNumber(value) or nil
  end
  local repairPercent = SafeNumber(GetInspectRepairPercent(currentUnit))

  if specName or (itemLevel and itemLevel > 0) or repairPercent then
    SetCachedInspectData(currentUnit, {
      specID = specID,
      specName = specName,
      itemLevel = itemLevel,
      repairPercent = repairPercent,
    })
  end

  if currentTooltip and currentTooltip:IsShown() then
    local liveUnit = ResolveInspectableUnit(currentTooltip)
    if liveUnit then
      local cached = GetCachedInspectData(liveUnit)
      if cached then
        TED.Modules.PlayerInfo(currentTooltip, liveUnit, cached.specName, cached.itemLevel, cached.repairPercent)
      end
    end
  end

  if currentTooltip then
    currentTooltip.TED_InspectPending = nil
  end

  pendingInspectUnit = nil
  pendingInspectTooltip = nil

  if ClearInspectPlayer then
    SafeCall(ClearInspectPlayer)
  end

  ProcessInspectQueue()
end)

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    if type(TooltipExtraDataDB) ~= "table" then
      TooltipExtraDataDB = {}
    end
    CopyDefaults(TooltipExtraDataDB, defaults)
  end

  if event == "PLAYER_LOGIN" then
    StartInspectTicker()

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not Enabled() then return end
        handleItemFromTooltip(tooltip, data)
      end)

      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if not Enabled() then return end
        handleSpellFromTooltip(tooltip, data)
      end)
    else
      SafeHookScript(GameTooltip, "OnTooltipSetItem", function(self)
        handleItemFromTooltip(self, nil)
      end)
      SafeHookScript(GameTooltip, "OnTooltipSetSpell", handleSpellFromTooltip)

      SafeHookScript(ItemRefTooltip, "OnTooltipSetItem", function(self)
        handleItemFromTooltip(self, nil)
      end)
      SafeHookScript(ItemRefTooltip, "OnTooltipSetSpell", handleSpellFromTooltip)
    end

    hooksecurefunc(GameTooltip, "SetHyperlink", onSetHyperlink)
    hooksecurefunc(ItemRefTooltip, "SetHyperlink", onSetHyperlink)

    hookBags()
    hookLoot()
    hookActions()
    hookMerchants()
    hookAuctionHouse()
    hookItemKeyTooltips()

    SafeHookScript(GameTooltip, "OnTooltipSetItem", function(self)
      ApplyContextStackFromOwner(self)
    end)

    SafeHookScript(ItemRefTooltip, "OnTooltipSetItem", function(self)
      ApplyContextStackFromOwner(self)
    end)

    SafeHookScript(GameTooltip, "OnTooltipSetUnit", function(self)
      self.TED_NextPlayerInfoCheck = nil
      handleUnitFromTooltip(self)
    end)

    SafeHookScript(GameTooltip, "OnUpdate", function(self)
      if not Enabled() or not ModuleOn("playerinfo") then return end
      if not self:IsShown() then return end

      local now = GetTime and GetTime() or time()
      if self.TED_NextPlayerInfoCheck and now < self.TED_NextPlayerInfoCheck then return end
      self.TED_NextPlayerInfoCheck = now + 0.35

      local unit = ResolveInspectableUnit(self)
      if not unit then return end

      local cached = GetCachedInspectData(unit)
      if cached then
        TED.Modules.PlayerInfo(self, unit, cached.specName, cached.itemLevel, cached.repairPercent)
      elseif not self.TED_InspectPending then
        ApplyPlayerInfoToTooltip(self, unit)
      end
    end)

    SafeHookScript(GameTooltip, "OnTooltipCleared", function(self)
      clearTooltipState(self)
    end)
    SafeHookScript(GameTooltip, "OnHide", function(self)
      clearTooltipState(self)
    end)

    SafeHookScript(ItemRefTooltip, "OnTooltipCleared", function(self)
      clearTooltipState(self)
    end)
    SafeHookScript(ItemRefTooltip, "OnHide", function(self)
      clearTooltipState(self)
    end)

    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:RegisterEvent("SKILL_LINES_CHANGED")
  elseif event == "SKILL_LINES_CHANGED" then
    learnedProfessionMask = nil
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    if not Enabled() or not ModuleOn("playerinfo") then return end
    local unit = "mouseover"
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end

    ApplyPlayerInfoToTooltip(GameTooltip, unit)
  end
end)

-- =========================
-- Slash command
-- =========================
SLASH_TOOLTIPEXTRADATA1 = "/ted"
SlashCmdList.TOOLTIPEXTRADATA = function(msg)
  msg = (msg or ""):lower()

  if msg == "on" then
    TooltipExtraDataDB.enabled = true
    print("TooltipExtraData: enabled")

  elseif msg == "off" then
    TooltipExtraDataDB.enabled = false
    print("TooltipExtraData: disabled")

  elseif msg == "stack" then
    TooltipExtraDataDB.modules.stack = not TooltipExtraDataDB.modules.stack
    print("TooltipExtraData: stack = " .. tostring(TooltipExtraDataDB.modules.stack))

  elseif msg == "itemid" then
    TooltipExtraDataDB.modules.itemid = not TooltipExtraDataDB.modules.itemid
    print("TooltipExtraData: itemid = " .. tostring(TooltipExtraDataDB.modules.itemid))

  elseif msg == "spellid" then
    TooltipExtraDataDB.modules.spellid = not TooltipExtraDataDB.modules.spellid
    print("TooltipExtraData: spellid = " .. tostring(TooltipExtraDataDB.modules.spellid))

  elseif msg == "iconid" then
    TooltipExtraDataDB.modules.iconid = not TooltipExtraDataDB.modules.iconid
    print("TooltipExtraData: iconid = " .. tostring(TooltipExtraDataDB.modules.iconid))

  elseif msg == "playerinfo" or msg == "ilvl" or msg == "spec" then
    TooltipExtraDataDB.modules.playerinfo = not TooltipExtraDataDB.modules.playerinfo
    print("TooltipExtraData: playerinfo = " .. tostring(TooltipExtraDataDB.modules.playerinfo))

  elseif msg == "playerself" or msg == "self" then
    TooltipExtraDataDB.modules.playerself = not TooltipExtraDataDB.modules.playerself
    print("TooltipExtraData: playerself = " .. tostring(TooltipExtraDataDB.modules.playerself))

  elseif msg == "proficons" then
    TooltipExtraDataDB.modules.proficons = not TooltipExtraDataDB.modules.proficons
    print("TooltipExtraData: proficons = " .. tostring(TooltipExtraDataDB.modules.proficons))

  elseif msg:match("^proficons ") then
    local arg = msg:match("^proficons%s+(.-)%s*$")
    local settings = TooltipExtraDataDB.professionIcons
    local key, value

    if arg == "bottom" or arg == "title" then
      key, value = "position", arg
    elseif arg == "small" or arg == "medium" or arg == "large" then
      key, value = "size", arg
    elseif arg == "all" or arg == "learned" or arg == "manual" then
      key, value = "filter", arg
    end

    if key then
      settings[key] = value
      print("TooltipExtraData: proficons " .. key .. " = " .. value)
    else
      print("/ted proficons bottom | title | small | medium | large | all | learned | manual")
    end

  else
    print("TooltipExtraData commands:")
    print("/ted on | off")
    print("/ted stack | itemid | spellid | iconid | playerinfo | playerself | proficons  (toggle)")
    print("/ted proficons bottom | title  (position)")
    print("/ted proficons small | medium | large  (icon size)")
    print("/ted proficons all | learned | manual  (profession filter)")
  end
end

-- =========================
-- Options panel
-- =========================
local panel = CreateFrame("Frame")
panel.name = "TooltipExtraData"

local function CreateCheck(parent, label, tooltipText, getter, setter)
  local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
  cb.Text:SetText(label)
  if tooltipText then
    cb.tooltip = tooltipText
  end

  function cb:Refresh()
    local ok, val = pcall(getter)
    if ok then
      self:SetChecked(val and true or false)
    else
      self:SetChecked(false)
    end
  end

  cb:SetScript("OnClick", function(self)
    setter(self:GetChecked() and true or false)
    self:Refresh()
  end)

  cb:Refresh()
  return cb
end

-- options: { { value = ..., text = ... }, ... }; buttons are laid out in `columns` columns.
local function CreateRadioGroup(parent, label, options, getter, setter, columns)
  columns = columns or 1
  local columnWidth, rowHeight = 110, 22

  local group = CreateFrame("Frame", nil, parent)
  group.buttons = {}

  local header = group:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", 0, 0)
  header:SetText(label)

  for i, option in ipairs(options) do
    local column = (i - 1) % columns
    local row = math.floor((i - 1) / columns)

    local rb = CreateFrame("CheckButton", nil, group, "UIRadioButtonTemplate")
    rb:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4 + column * columnWidth, -6 - row * rowHeight)
    rb.value = option.value

    local text = rb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    text:SetText(option.text)

    rb:SetScript("OnClick", function()
      setter(option.value)
      group:Refresh()
    end)

    group.buttons[#group.buttons + 1] = rb
  end

  local rows = math.ceil(#options / columns)
  group:SetSize(columns * columnWidth, 18 + rows * rowHeight)

  function group:Refresh()
    local ok, current = pcall(getter)
    for _, rb in ipairs(self.buttons) do
      rb:SetChecked(ok and rb.value == current)
    end
    if self.OnRefresh then
      self:OnRefresh(ok and current or nil)
    end
  end

  group:Refresh()
  return group
end

panel:SetScript("OnShow", function(self)
  if type(TooltipExtraDataDB) ~= "table" then
    TooltipExtraDataDB = {}
  end
  CopyDefaults(TooltipExtraDataDB, defaults)

  if self._init then
    for _, c in ipairs(self._checks or {}) do
      if c and c.Refresh then
        c:Refresh()
      end
    end
    if self.UpdateContentHeight then
      self.UpdateContentHeight()
    end
    return
  end

  self._init = true
  self._checks = {}

  -- All options live in a scrollable content frame so the panel fits any window height.
  local scroll = CreateFrame("ScrollFrame", nil, self, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(math.max((self:GetWidth() or 0) - 28, 400), 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 then
      content:SetWidth(width)
    end
  end)

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("TooltipExtraData")

  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText("Toggle what data is shown in tooltips.")

  local enabledCB = CreateCheck(
    content,
    "Enabled",
    "Master enable/disable for the addon.",
    function() return TooltipExtraDataDB.enabled end,
    function(v) TooltipExtraDataDB.enabled = v end
  )
  enabledCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
  table.insert(self._checks, enabledCB)

  local stackCB = CreateCheck(
    content,
    "Show Stack",
    "Shows current/max normally, and owned/max in AH/Auctionator.",
    function() return TooltipExtraDataDB.modules.stack end,
    function(v) TooltipExtraDataDB.modules.stack = v end
  )
  stackCB:SetPoint("TOPLEFT", enabledCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, stackCB)

  local itemIdCB = CreateCheck(
    content,
    "Show ItemID",
    "Adds ItemID to item tooltips.",
    function() return TooltipExtraDataDB.modules.itemid end,
    function(v) TooltipExtraDataDB.modules.itemid = v end
  )
  itemIdCB:SetPoint("TOPLEFT", stackCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, itemIdCB)

  local spellIdCB = CreateCheck(
    content,
    "Show SpellID",
    "Adds SpellID to spell tooltips.",
    function() return TooltipExtraDataDB.modules.spellid end,
    function(v) TooltipExtraDataDB.modules.spellid = v end
  )
  spellIdCB:SetPoint("TOPLEFT", itemIdCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, spellIdCB)

  local iconIdCB = CreateCheck(
    content,
    "Show IconID",
    "Adds IconID (texture FileID) below ItemID/SpellID.",
    function() return TooltipExtraDataDB.modules.iconid end,
    function(v) TooltipExtraDataDB.modules.iconid = v end
  )
  iconIdCB:SetPoint("TOPLEFT", spellIdCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, iconIdCB)

  local playerInfoCB = CreateCheck(
    content,
    "Show Player Spec + ItemLvl + Repair",
    "Uses inspect data to add specialization, average item level, and equipment repair percentage to player tooltips.",
    function() return TooltipExtraDataDB.modules.playerinfo end,
    function(v) TooltipExtraDataDB.modules.playerinfo = v end
  )
  playerInfoCB:SetPoint("TOPLEFT", iconIdCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, playerInfoCB)

  local playerSelfCB = CreateCheck(
    content,
    "Show Own Spec + ItemLvl + Repair",
    "Shows your own specialization, average item level, and equipment repair percentage on your own player tooltip.",
    function() return TooltipExtraDataDB.modules.playerself end,
    function(v) TooltipExtraDataDB.modules.playerself = v end
  )
  playerSelfCB:SetPoint("TOPLEFT", playerInfoCB, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, playerSelfCB)

  -- ---- Profession icons
  local profHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  profHeader:SetPoint("TOPLEFT", playerSelfCB, "BOTTOMLEFT", 2, -20)
  profHeader:SetText("Profession Icons")

  local profIconsCB = CreateCheck(
    content,
    "Show Profession Icons",
    "Shows the icons of the professions that use the item as a reagent in some recipe.",
    function() return TooltipExtraDataDB.modules.proficons end,
    function(v) TooltipExtraDataDB.modules.proficons = v end
  )
  profIconsCB:SetPoint("TOPLEFT", profHeader, "BOTTOMLEFT", -2, -8)
  table.insert(self._checks, profIconsCB)

  local positionGroup = CreateRadioGroup(
    content,
    "Position",
    {
      { value = "bottom", text = "End of tooltip" },
      { value = "title",  text = "Below item name" },
    },
    function() return TooltipExtraDataDB.professionIcons.position end,
    function(v) TooltipExtraDataDB.professionIcons.position = v end,
    2
  )
  positionGroup:SetPoint("TOPLEFT", profIconsCB, "BOTTOMLEFT", 4, -10)
  table.insert(self._checks, positionGroup)

  local sizeGroup = CreateRadioGroup(
    content,
    "Icon Size",
    {
      { value = "small",  text = "Small" },
      { value = "medium", text = "Medium" },
      { value = "large",  text = "Large" },
    },
    function() return TooltipExtraDataDB.professionIcons.size end,
    function(v) TooltipExtraDataDB.professionIcons.size = v end,
    3
  )
  sizeGroup:SetPoint("TOPLEFT", positionGroup, "BOTTOMLEFT", 0, -10)
  table.insert(self._checks, sizeGroup)

  local filterGroup = CreateRadioGroup(
    content,
    "Professions",
    {
      { value = "all",     text = "All" },
      { value = "learned", text = "Learned only" },
      { value = "manual",  text = "Manual selection" },
    },
    function() return TooltipExtraDataDB.professionIcons.filter end,
    function(v) TooltipExtraDataDB.professionIcons.filter = v end,
    3
  )
  filterGroup:SetPoint("TOPLEFT", sizeGroup, "BOTTOMLEFT", 0, -10)

  -- Only professions that exist in this client. The checks always show which professions the
  -- current filter displays (all, learned or manual); they can only be changed in manual mode.
  local professionChecks = {}
  local lastProfessionCheck = filterGroup
  for i, skillLine in ipairs(GetAvailableProfessions()) do
    local cb = CreateCheck(
      content,
      GetProfessionDisplayName(skillLine),
      nil,
      function()
        local settings = TooltipExtraDataDB.professionIcons
        if settings.filter == "all" then
          return true
        elseif settings.filter == "learned" then
          return HasBit(GetLearnedProfessionMask(), PROFESSION_BITS[skillLine])
        end
        return settings.selected[skillLine]
      end,
      function(v) TooltipExtraDataDB.professionIcons.selected[skillLine] = v end
    )
    local column = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    cb:SetPoint("TOPLEFT", filterGroup, "BOTTOMLEFT", column * 150, -4 - row * 24)
    professionChecks[#professionChecks + 1] = cb
    if column == 0 then
      lastProfessionCheck = cb
    end
  end

  function filterGroup:OnRefresh(current)
    local manual = current == "manual"
    for _, cb in ipairs(professionChecks) do
      cb:SetEnabled(manual)
      if manual then
        cb.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
      else
        cb.Text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
      end
      cb:Refresh()
    end
  end
  filterGroup:Refresh()
  table.insert(self._checks, filterGroup)

  local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", lastProfessionCheck, "BOTTOMLEFT", 2, -14)
  hint:SetText("Tip: Use /ted for quick toggles. /reload refreshes existing tooltips.")

  -- Size the scroll child to its content once the layout has been resolved.
  local function UpdateContentHeight()
    local top, bottom = content:GetTop(), hint:GetBottom()
    if top and bottom then
      content:SetHeight(top - bottom + 16)
    end
  end
  self.UpdateContentHeight = UpdateContentHeight
  C_Timer.After(0, UpdateContentHeight)
end)

if InterfaceOptions_AddCategory then
  InterfaceOptions_AddCategory(panel)
elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
end

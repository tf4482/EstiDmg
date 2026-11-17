-- EstiDmg: shows the estimated damage of enemy casts on nameplates and target/focus frames

local _, ns = ...

-- estimate cache by spell ID; false means no damage number found
local estimates = {}
-- damage words that must follow the number in the spell description
local WORDS = { "damage", "schaden", "dégâts", "daño", "dano" }
-- text per host frame (nameplate, TargetFrame, FocusFrame)
local texts = {}

-- first number in a description that is followed by a damage word
local function ParseDamage(desc)
  desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local from = 1
  while true do
    local s, e, num = desc:find("(%d[%d%.,]*)", from)
    if not s then return nil end
    local after = desc:sub(e + 1, e + 24):lower()
    for _, word in ipairs(WORDS) do
      if after:find(word, 1, true) then
        -- drop thousands separators
        local value = tonumber((num:gsub("[%.,](%d%d%d)", "%1")))
        if value then return value end
      end
    end
    from = e + 1
  end
end

-- cached damage estimate for a spell; requests spell data while it is missing
local function Estimate(spellID)
  local cached = estimates[spellID]
  if cached ~= nil then return cached or nil end
  local desc = C_Spell.GetSpellDescription(spellID)
  if not desc or desc == "" then
    C_Spell.RequestLoadSpellData(spellID)
    return nil
  end
  estimates[spellID] = ParseDamage(desc) or false
  return estimates[spellID] or nil
end

-- text and host frame for a unit, created on first use
local function GetText(unit)
  local host
  if unit == "target" then
    host = TargetFrame
  elseif unit == "focus" then
    host = FocusFrame
  else
    host = C_NamePlate.GetNamePlateForUnit(unit)
  end
  if not host or host:IsForbidden() then return nil end
  local fs = texts[host]
  if not fs then
    local layer = CreateFrame("Frame", nil, host)
    layer:SetAllPoints(host)
    fs = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetTextColor(1, 0.35, 0.2)
    texts[host] = fs
  end
  return fs, host
end

-- whether this unit type is switched on in the settings
local function Wanted(unit)
  if unit == "target" or unit == "focus" then return ns.db.frames end
  return ns.db.nameplates and unit:sub(1, 9) == "nameplate"
end

-- spell ID of the unit's current cast or channel
local function CastSpellID(unit)
  local spellID = select(9, UnitCastingInfo(unit))
  if not spellID then spellID = select(8, UnitChannelInfo(unit)) end
  return spellID
end

-- show or clear the estimate for one unit
local function Update(unit)
  if ns.db == nil or not unit then return end
  local fs, host = GetText(unit)
  if not fs then return end
  fs:SetText("")
  if not (ns.db.enabled and Wanted(unit) and UnitCanAttack("player", unit)) then return end
  local spellID = CastSpellID(unit)
  -- enemy spell IDs can be secret: nothing to estimate
  if not spellID or (issecretvalue and issecretvalue(spellID)) then return end
  local damage = Estimate(spellID)
  if not damage then return end
  fs:ClearAllPoints()
  if unit == "target" or unit == "focus" then
    fs:SetPoint("BOTTOM", host, "TOP", 0, 2)
  else
    fs:SetPoint("BOTTOM", host, "TOP", 0, 14)
  end
  fs:SetText("~" .. BreakUpLargeNumbers(damage))
end

-- update every visible unit
local function Refresh()
  Update("target")
  Update("focus")
  for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
    Update(plate.namePlateUnitToken)
  end
end

-- current state, with a hint while the feature is off
local function Status()
  local hint = ""
  if not ns.db.enabled then
    hint = " (turn on with " .. ns.Color("command", ns.slash .. " on") .. ")"
  end
  ns.Print(ns.OnOff(ns.db.enabled) .. hint)
end

-- switch the feature and report the new state
local function Switch(enabled)
  ns.db.enabled = enabled
  Refresh()
  Status()
end

-- event handlers by event name
local events = {}

-- cast state of a unit changed
local function OnCast(unit) Update(unit) end
for _, event in ipairs({
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
  "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_CHANNEL_UPDATE", "NAME_PLATE_UNIT_ADDED",
}) do
  events[event] = OnCast
end

-- plates are pooled: clear the text when released
function events.NAME_PLATE_UNIT_REMOVED(unit)
  local fs = GetText(unit)
  if fs then fs:SetText("") end
end

-- target or focus switched
function events.PLAYER_TARGET_CHANGED() Update("target") end
function events.PLAYER_FOCUS_CHANGED() Update("focus") end

-- spell text arrived after a request
function events.SPELL_DATA_LOAD_RESULT()
  if ns.db ~= nil and ns.db.enabled then Refresh() end
end

-- one frame dispatching all events above
local frame = CreateFrame("Frame")
for event in pairs(events) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  events[event](...)
end)

-- saved state; settings page once loaded
ns.Store("EstiDmgDB", { enabled = false, nameplates = true, frames = true }, function()
  ns.Settings()
  ns.Checkbox("enabled", "Enabled", "Show the estimated damage of enemy casts", Refresh)
  ns.Checkbox("nameplates", "Nameplates", "Show the estimate above enemy nameplates", Refresh)
  ns.Checkbox("frames", "Target and focus", "Show the estimate above the target and focus frames", Refresh)
end)

-- chat commands
ns.Command({ name = "on", help = "turn the estimates on", run = function() Switch(true) end })
ns.Command({ name = "off", help = "turn the estimates off", run = function() Switch(false) end })
ns.Command({ name = "config", help = "open the settings page", run = ns.OpenSettings })
ns.Slash({ "/estidmg", "/edmg" }, Status)

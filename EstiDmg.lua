-- EstiDmg: shows estimated damage on enemy frames, as text and as a health bar overlay

local _, ns = ...

-- estimate cache by spell ID; false means no damage number found
local estimates = {}
-- damage words that must follow the number in the spell description
local WORDS = { "damage", "schaden", "dégâts", "daño", "dano" }
-- text per host frame (nameplate, TargetFrame, FocusFrame)
local texts = {}
-- bar overlay per health bar
local overlays = {}
-- last player cast ID and player cast events seen, for the debug command
local lastSpell, castEvents = nil, 0
-- units currently showing an estimate, by unit token
local showing = {}

-- number from text with thousands separators dropped
local function ToNumber(text)
  return tonumber((text:gsub("[%.,](%d%d%d)", "%1")))
end

-- first damage value in a description; a range like "10 to 20" gives its middle
local function ParseDamage(desc)
  desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local from = 1
  while true do
    local _, e, num = desc:find("(%d[%d%.,]*)", from)
    if not num then return nil end
    local rest = desc:sub(e + 1)
    -- optional upper end of a range: "- 20" or a short word like "to" or "bis"
    local high = rest:match("^%s*%-%s*(%d[%d%.,]*)") or rest:match("^%s+%a%a?%a?%s+(%d[%d%.,]*)")
    local after = rest:sub(1, high and 40 or 24):lower()
    for _, word in ipairs(WORDS) do
      if after:find(word, 1, true) then
        local low, top = ToNumber(num), high and ToNumber(high)
        if low then return top and (low + top) / 2 or low end
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

-- host frame and health bar of a unit, nil when unavailable
local function GetHost(unit)
  if unit == "target" or unit == "focus" then
    local host = unit == "target" and TargetFrame or FocusFrame
    if not host then return nil end
    local content = host.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    local container = main and main.HealthBarsContainer
    local name = host:GetName()
    -- Retail-like layout first, then older frame fields and global names
    return host, (container and container.HealthBar) or (main and main.HealthBar)
      or host.healthbar or host.healthBar or (name and _G[name .. "HealthBar"])
  end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or plate:IsForbidden() then return nil end
  local uf = plate.UnitFrame
  return plate, uf and uf.healthBar
end

-- text on the host frame, created on first use
local function GetText(host)
  local fs = texts[host]
  if not fs then
    local layer = CreateFrame("Frame", nil, host)
    layer:SetAllPoints(host)
    fs = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetTextColor(1, 0.35, 0.2)
    texts[host] = fs
  end
  return fs
end

-- overlay texture on a health bar, created on first use
local function GetOverlay(bar)
  local tex = overlays[bar]
  if not tex then
    local layer = CreateFrame("Frame", nil, bar)
    layer:SetAllPoints(bar)
    tex = layer:CreateTexture(nil, "OVERLAY")
    tex:SetColorTexture(1, 0.1, 0.1, 0.55)
    overlays[bar] = tex
  end
  return tex
end

-- draw the damage as the part of the bar that would be lost
local function DrawBar(bar, unit, damage)
  local tex = GetOverlay(bar)
  local health, max = UnitHealth(unit), UnitHealthMax(unit)
  if issecretvalue and (issecretvalue(health) or issecretvalue(max)) then
    tex:Hide()
    return
  end
  local width = bar:GetWidth()
  if not max or max <= 0 or width <= 0 then
    tex:Hide()
    return
  end
  local lost = math.min(damage, health) / max * width
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", bar, "TOPLEFT", health / max * width - lost, 0)
  tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", health / max * width - lost, 0)
  tex:SetWidth(math.max(lost, 1))
  tex:Show()
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
  if not spellID or (issecretvalue and issecretvalue(spellID)) then return nil end
  if unit == "player" then lastSpell = spellID end
  return spellID
end

-- damage to show: own cast on the target first, then the enemy's own cast
local function DamageFor(unit)
  local spellID
  if ns.db.own and UnitIsUnit(unit, "target") then spellID = CastSpellID("player") end
  spellID = spellID or CastSpellID(unit)
  return spellID and Estimate(spellID)
end

-- show or clear the estimate for one unit
local function Update(unit)
  if ns.db == nil or not unit then return end
  -- only target, focus, and nameplates; other tokens are not allowed
  if unit ~= "target" and unit ~= "focus" and unit:sub(1, 9) ~= "nameplate" then return end
  local host, bar = GetHost(unit)
  if not host then return end
  local fs = GetText(host)
  fs:SetText("")
  if bar then GetOverlay(bar):Hide() end
  showing[unit] = nil
  if not (ns.db.enabled and Wanted(unit) and UnitCanAttack("player", unit)) then return end
  local damage = DamageFor(unit)
  if not damage then return end
  showing[unit] = true
  fs:ClearAllPoints()
  fs:SetPoint("BOTTOM", host, "TOP", 0, (unit == "target" or unit == "focus") and 2 or 14)
  fs:SetText("~" .. BreakUpLargeNumbers(math.floor(damage + 0.5)))
  if bar and ns.db.bars then DrawBar(bar, unit, damage) end
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

-- print every step of the pipeline for the target and the last own cast
local function Debug()
  local host, bar = GetHost("target")
  ns.Status("enabled", tostring(ns.db.enabled))
  ns.Status("own cast events", castEvents)
  ns.Status("target hostile", tostring(UnitCanAttack("player", "target")))
  ns.Status("target host frame", host and (host:GetName() or "unnamed") or "none")
  ns.Status("health bar", bar and (bar:GetName() or "unnamed") or "none")
  ns.Status("last own spell", tostring(lastSpell))
  if lastSpell then
    local desc = C_Spell.GetSpellDescription(lastSpell)
    ns.Status("description", desc and desc:sub(1, 160):gsub("|", "||") or "nil")
    ns.Status("estimate", tostring(Estimate(lastSpell)))
  end
end

-- event handlers by event name
local events = {}

-- cast state changed: the player's casts affect the target, others only their unit
local function OnCast(unit)
  if unit == "player" then
    castEvents = castEvents + 1
    Refresh()
  else
    Update(unit)
  end
end
for _, event in ipairs({
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
  "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_CHANNEL_UPDATE", "NAME_PLATE_UNIT_ADDED",
}) do
  events[event] = OnCast
end

-- plates are pooled: clear the estimate when released
function events.NAME_PLATE_UNIT_REMOVED(unit)
  Update(unit)
  showing[unit] = nil
end

-- target or focus switched: old plates must lose their estimate too
function events.PLAYER_TARGET_CHANGED() Refresh() end
function events.PLAYER_FOCUS_CHANGED() Update("focus") end

-- health changed while an estimate is shown: redraw the bar
local function OnHealth(unit)
  if showing[unit] then Update(unit) end
end
events.UNIT_HEALTH = OnHealth
events.UNIT_MAXHEALTH = OnHealth

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
ns.Store("EstiDmgDB", { enabled = true, nameplates = true, frames = true, bars = true, own = true }, function()
  ns.Settings()
  ns.Checkbox("enabled", "Enabled", "Show estimated damage on enemy frames", Refresh)
  ns.Checkbox("nameplates", "Nameplates", "Show the estimate on enemy nameplates", Refresh)
  ns.Checkbox("frames", "Target and focus", "Show the estimate on the target and focus frames", Refresh)
  ns.Checkbox("bars", "Health bar overlay", "Mark the expected health loss on the health bar", Refresh)
  ns.Checkbox("own", "Own casts", "Show the damage of your own cast on your target", Refresh)
end)

-- chat commands
ns.Command({ name = "on", help = "turn the estimates on", run = function() Switch(true) end })
ns.Command({ name = "off", help = "turn the estimates off", run = function() Switch(false) end })
ns.Command({ name = "debug", help = "show why no estimate appears", run = Debug })
ns.Command({ name = "config", help = "open the settings page", run = ns.OpenSettings })
ns.Slash({ "/estidmg", "/edmg" }, Status)

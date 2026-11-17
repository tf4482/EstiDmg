-- EstiDmg: marks the estimated damage of casts on enemy health bars

local _, ns = ...

-- estimate cache by spell ID; false means no damage number found
local estimates = {}
-- damage words that must follow the number in the spell description
local WORDS = { "damage", "schaden", "dégâts", "daño", "dano" }
-- bar overlay per health bar
local overlays = {}
-- last player cast ID and player cast events seen, for the debug command
local lastSpell, castEvents = nil, 0
-- selectable bar colors: value, label, red, green, blue
local COLORS = {
  { "darkred", "Dark red", 0.6, 0.05, 0.05 },
  { "red", "Red", 1, 0.1, 0.1 },
  { "orange", "Orange", 1, 0.5, 0.1 },
  { "purple", "Purple", 0.6, 0.2, 0.8 },
  { "blue", "Blue", 0.2, 0.4, 1 },
  { "black", "Black", 0, 0, 0 },
}
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

-- damage texture on a health bar, between the fill and the text, created on first use
local function GetOverlay(bar)
  local o = overlays[bar]
  if not o then
    local edge = bar:GetStatusBarTexture()
    -- invisible helper bar: its fill spans the damage part, even with secret health
    local ov = CreateFrame("StatusBar", nil, bar)
    ov:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    ov:SetAlpha(0)
    ov:SetReverseFill(true)
    ov:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    ov:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    -- visible texture on the bar itself, stretched between the helper fill and the health edge
    local tex = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    tex:SetPoint("TOPLEFT", ov:GetStatusBarTexture(), "TOPLEFT")
    tex:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    -- same shape mask as the green fill, when the frame has one
    local parent = bar:GetParent()
    local mask = parent and parent.HealthBarMask
    if mask then tex:AddMaskTexture(mask) end
    tex:Hide()
    o = { ov = ov, tex = tex }
    overlays[bar] = o
  end
  return o
end

-- red, green, blue of the chosen bar color
local function ColorOf()
  if ns.db.color == "custom" then return unpack(ns.db.custom) end
  for _, c in ipairs(COLORS) do
    if c[1] == ns.db.color then return c[3], c[4], c[5] end
  end
  return 0.6, 0.05, 0.05
end

-- bar color and opacity from the settings
local function ApplyColor(tex)
  local r, g, b = ColorOf()
  tex:SetColorTexture(r, g, b, ns.db.opacity)
end

-- mark the damage as the part of the bar that would be lost; works with secret health
local function DrawBar(bar, unit, damage)
  local o = GetOverlay(bar)
  o.ov:SetWidth(bar:GetWidth())
  o.ov:SetMinMaxValues(0, UnitHealthMax(unit))
  o.ov:SetValue(damage)
  ApplyColor(o.tex)
  o.tex:Show()
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

-- show or clear the damage bar for one unit
local function Update(unit)
  if ns.db == nil or not unit then return end
  -- only target, focus, and nameplates; other tokens are not allowed
  if unit ~= "target" and unit ~= "focus" and unit:sub(1, 9) ~= "nameplate" then return end
  local host, bar = GetHost(unit)
  if not host or not bar then return end
  GetOverlay(bar).tex:Hide()
  showing[unit] = nil
  if not (ns.db.enabled and Wanted(unit) and UnitCanAttack("player", unit)) then return end
  local damage = DamageFor(unit)
  if not damage then return end
  showing[unit] = true
  DrawBar(bar, unit, damage)
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
    local damage = Estimate(lastSpell)
    ns.Status("estimate", tostring(damage))
    -- draw the bar now and report its state
    if damage and bar then
      DrawBar(bar, "target", damage)
      local o = GetOverlay(bar)
      ns.Status("health secret", tostring(issecretvalue and issecretvalue(UnitHealthMax("target"))))
      ns.Status("bar width / visible", tostring(bar:GetWidth()) .. " / " .. tostring(bar:IsVisible()))
      ns.Status("overlay width / shown", tostring(o.ov:GetWidth()) .. " / " .. tostring(o.tex:IsVisible()))
    end
  end
end

-- open the color picker for a free bar color
local function PickColor()
  local r, g, b = ColorOf()
  local previous = { r, g, b }
  ColorPickerFrame:SetupColorPickerAndShow({
    r = r, g = g, b = b, hasOpacity = false,
    -- live update while the color changes
    swatchFunc = function()
      ns.db.color = "custom"
      ns.db.custom = { ColorPickerFrame:GetColorRGB() }
      Refresh()
    end,
    -- keep the old color on cancel
    cancelFunc = function()
      ns.db.custom = previous
      Refresh()
    end,
  })
end

-- color dropdown changed: "custom" opens the picker
local function OnColor(value)
  if value == "custom" then PickColor() end
  Refresh()
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
ns.Store("EstiDmgDB", { enabled = true, nameplates = true, frames = true, own = true, color = "darkred", custom = { 0.6, 0.05, 0.05 }, opacity = 0.85 }, function()
  ns.Settings()
  ns.Checkbox("enabled", "Enabled", "Mark estimated damage on enemy health bars", Refresh)
  ns.Checkbox("nameplates", "Nameplates", "Mark the damage on enemy nameplates", Refresh)
  ns.Checkbox("frames", "Target and focus", "Mark the damage on the target and focus frames", Refresh)
  local choices = {}
  for i, c in ipairs(COLORS) do choices[i] = { c[1], c[2] } end
  choices[#choices + 1] = { "custom", "Custom..." }
  ns.Dropdown("color", "Bar color", choices, "Color of the damage bar; Custom opens the color picker", OnColor)
  ns.Slider("opacity", "Bar opacity", 0.2, 1, 0.05, "How solid the damage bar is", Refresh)
  ns.Checkbox("own", "Own casts", "Show the damage of your own cast on your target", Refresh)
end)

-- chat commands
ns.Command({ name = "on", help = "turn the estimates on", run = function() Switch(true) end })
ns.Command({ name = "off", help = "turn the estimates off", run = function() Switch(false) end })
ns.Command({ name = "debug", help = "show why no estimate appears", run = Debug })
ns.Command({ name = "color", help = "pick a free bar color", run = PickColor })
ns.Command({ name = "config", help = "open the settings page", run = ns.OpenSettings })
ns.Slash({ "/estidmg", "/edmg", "/esd" }, Status)

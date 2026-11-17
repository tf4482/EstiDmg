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

-- target and focus frame names of common unit frame addons
local UNIT_FRAMES = {
  target = { "TargetFrame", "ElvUF_Target", "SUFUnittarget", "PitBull4_Frames_Target", "XPerl_Target", "UUF_Target" },
  focus = { "FocusFrame", "ElvUF_Focus", "SUFUnitfocus", "PitBull4_Frames_Focus", "XPerl_Focus", "UUF_Focus" },
}
-- bar found per frame
local barCache = setmetatable({}, { __mode = "k" })
-- name parts that mark a status bar as something other than health
local NOT_HEALTH = { "power", "mana", "cast", "absorb", "shield", "prediction" }

-- whether a value is a status bar
local function IsBar(x)
  return type(x) == "table" and x.GetObjectType ~= nil and x:GetObjectType() == "StatusBar"
end

-- health bar from the known field names of Blizzard, oUF, SUF, X-Perl, PitBull, and UUF frames
local function KnownBar(frame)
  local content = frame.TargetFrameContent
  local main = content and content.TargetFrameContentMain
  local container = (main and main.HealthBarsContainer) or frame.HealthBarsContainer
  local stats = frame.statsFrame
  local name = frame.GetName and frame:GetName()
  for _, bar in ipairs({
    container and container.HealthBar or false, container and container.healthBar or false,
    main and main.HealthBar or false, frame.Health or false, frame.healthBar or false,
    frame.HealthBar or false, frame.healthbar or false, stats and stats.healthBar or false,
    frame.unitHealthBar or false, name and _G[name .. "HealthBar"] or false,
  }) do
    if IsBar(bar) then return bar end
  end
end

-- last resort: the visible status bar below a frame that looks most like health
local function ScanBar(root, skip)
  local best, area = nil, 0
  local function walk(f, depth)
    if f == skip or depth > 4 or f:IsForbidden() then return end
    if IsBar(f) and f:IsVisible() then
      local name = (f:GetName() or ""):lower()
      local w, h = f:GetWidth(), f:GetHeight()
      local bad = issecretvalue and (issecretvalue(w) or issecretvalue(h))
      for _, word in ipairs(NOT_HEALTH) do
        if name:find(word, 1, true) then bad = true end
      end
      -- a bar named health wins, else the largest
      local score = name:find("health", 1, true) and math.huge or (not bad and w * h or 0)
      if not bad and score > area then best, area = f, score end
    end
    for _, child in ipairs({ f:GetChildren() }) do walk(child, depth + 1) end
  end
  walk(root, 0)
  return best
end

-- health bar of one frame: known fields first, then a scan; cached when found
local function BarOf(frame, skip)
  local bar = barCache[frame] or KnownBar(frame)
  if not bar then
    local ok, found = pcall(ScanBar, frame, skip)
    bar = ok and found or nil
  end
  barCache[frame] = bar
  return bar
end

-- health bar on a nameplate: replacement addons first, the Blizzard bar only while it is shown
local function PlateBar(plate)
  local cached = barCache[plate]
  if cached then return cached end
  local tp = plate.TPFrame and plate.TPFrame.visual
  local bar = (plate.unitFrame and KnownBar(plate.unitFrame))
    or (tp and IsBar(tp.Healthbar) and tp.Healthbar)
    or (plate.kui and IsBar(plate.kui.HealthBar) and plate.kui.HealthBar)
  local blizzard = plate.UnitFrame
  if not bar and blizzard and blizzard:IsVisible() and blizzard:GetAlpha() > 0 then
    bar = KnownBar(blizzard)
  end
  if not bar then
    local ok, found = pcall(ScanBar, plate, blizzard)
    bar = ok and found or nil
  end
  barCache[plate] = bar
  return bar
end

-- health bars of a unit: every visible unit frame for target and focus, the plate otherwise
local function BarsFor(unit)
  local bars = {}
  if unit == "target" or unit == "focus" then
    for _, name in ipairs(UNIT_FRAMES[unit]) do
      local frame = _G[name]
      if frame and frame:IsVisible() then
        local bar = BarOf(frame)
        if bar then bars[#bars + 1] = bar end
      end
    end
    return bars
  end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if plate and not plate:IsForbidden() then
    local bar = PlateBar(plate)
    if bar then bars[1] = bar end
  end
  return bars
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
  local bars = BarsFor(unit)
  for _, bar in ipairs(bars) do GetOverlay(bar).tex:Hide() end
  showing[unit] = nil
  if not (ns.db.enabled and Wanted(unit) and UnitCanAttack("player", unit)) then return end
  local damage = DamageFor(unit)
  if not damage then return end
  showing[unit] = true
  for _, bar in ipairs(bars) do DrawBar(bar, unit, damage) end
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
  local bars = BarsFor("target")
  local bar = bars[1]
  ns.Status("enabled", tostring(ns.db.enabled))
  ns.Status("own cast events", castEvents)
  ns.Status("target hostile", tostring(UnitCanAttack("player", "target")))
  ns.Status("target health bars", #bars)
  for _, b in ipairs(bars) do
    local parent = b:GetParent()
    ns.Status("  bar / parent", (b:GetName() or "unnamed") .. " / " .. ((parent and parent:GetName()) or "unnamed"))
  end
  local plate = C_NamePlate.GetNamePlateForUnit("target")
  local plateBar = plate and PlateBar(plate)
  ns.Status("target plate bar", plateBar and (plateBar:GetName() or "unnamed") or "none")
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

-- EstiDmg: marks the estimated damage of casts, and optionally a crit extension, on enemy health bars

local _, ns = ...
local L = ns.L

-- estimate cache by spell ID; false means no damage number found
local estimates = {}
-- spell IDs whose data was requested once; the game answers at once, so no repeats
local requested = {}
-- damage words that must follow the number in the spell description
local WORDS = { "damage", "schaden", "dégâts", "daño", "dano" }
-- bar overlay per health bar
local overlays = {}
-- last player cast ID and player cast events seen, for the debug command
local lastSpell, castEvents = nil, 0
-- selectable bar colors: value, label, red, green, blue
local COLORS = {
  { "darkred", L["Dark red"], 0.6, 0.05, 0.05 },
  { "red", L["Red"], 1, 0.1, 0.1 },
  { "orange", L["Orange"], 1, 0.5, 0.1 },
  { "purple", L["Purple"], 0.6, 0.2, 0.8 },
  { "blue", L["Blue"], 0.2, 0.4, 1 },
  { "black", L["Black"], 0, 0, 0 },
}
-- unit tokens of the visible nameplates, kept from the plate events
local plateUnits = {}
-- units currently showing an estimate, by unit token
local showing = {}

-- spell school masks: holy 2, fire 4, nature 8, frost 16, shadow 32, arcane 64
local SCHOOL_MASKS = { 2, 4, 8, 16, 32, 64 }
-- localized school names by mask, built on first use
local schoolNames
-- talents that raise the spell crit damage bonus: English name, spell ID of the talent, class, schools or spell IDs
local CRIT_TALENTS = {
  { name = "Elemental Fury", id = 16089, class = "SHAMAN", schools = { 4, 8, 16 } },
  { name = "Ice Shards", id = 11207, class = "MAGE", schools = { 16 } },
  { name = "Ruin", id = 17959, class = "WARLOCK", schools = { 4, 32 } },
  { name = "Vengeance", id = 16909, class = "DRUID", spellIDs = { 5176, 2912, 8921 } },
}
-- talent ranks as fraction of the maximum, by talent name; nil until read
local talentRanks

-- number from text with thousands separators dropped
local function ToNumber(text)
  return tonumber((text:gsub("[%.,](%d%d%d)", "%1")))
end

-- spell school mask named in a lowercase text
local function SchoolOf(text)
  if not schoolNames then
    schoolNames = {}
    local get = (C_Spell and C_Spell.GetSchoolString) or GetSchoolString
    for _, mask in ipairs(SCHOOL_MASKS) do
      local name = get and get(mask)
      if name then schoolNames[mask] = name:lower() end
    end
  end
  for mask, name in pairs(schoolNames) do
    if text:find(name, 1, true) then return mask end
  end
end

-- first damage value and its school in a description; a range like "10 to 20" gives its middle
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
        if low then return top and (low + top) / 2 or low, SchoolOf(after) end
      end
    end
    from = e + 1
  end
end

-- cached damage estimate and school for a spell; requests spell data while it is missing
local function Estimate(spellID)
  local cached = estimates[spellID]
  if cached ~= nil then
    if cached then return cached[1], cached[2] end
    return nil
  end
  local desc = C_Spell.GetSpellDescription(spellID)
  if not desc or desc == "" then
    if not requested[spellID] then
      requested[spellID] = true
      C_Spell.RequestLoadSpellData(spellID)
    end
    return nil
  end
  local damage, school = ParseDamage(desc)
  estimates[spellID] = damage and { damage, school } or false
  return damage, school
end

-- read talent ranks as fraction of the maximum rank, by name; guarded for other clients
local function ReadTalents()
  talentRanks = {}
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
  pcall(function()
    for tab = 1, GetNumTalentTabs() do
      for i = 1, GetNumTalents(tab) do
        local name, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
        if name and maxRank and maxRank > 0 then talentRanks[name] = rank / maxRank end
      end
    end
  end)
end

-- localized spell name from a spell ID, nil when unknown
local function NameOf(id)
  local info = C_Spell.GetSpellInfo(id)
  return info and info.name
end

-- spell crit multiplier of the player: base 1.5, matching talents add to the crit bonus
local function CritMultiplier(spellID, school)
  if not talentRanks then ReadTalents() end
  local _, class = UnitClass("player")
  local info = C_Spell.GetSpellInfo(spellID)
  local spellName = info and info.name
  local extra = 0
  for _, talent in ipairs(CRIT_TALENTS) do
    -- the talent is found by its English name or by the localized name of its spell
    local fraction = talent.class == class
      and (talentRanks[talent.name] or (talent.id and talentRanks[NameOf(talent.id) or ""]))
    if fraction and fraction > 0 then
      local applies = false
      for _, mask in ipairs(talent.schools or {}) do
        if mask == school then applies = true end
      end
      for _, id in ipairs(talent.spellIDs or {}) do
        if spellName and spellName == NameOf(id) then applies = true end
      end
      if applies then extra = extra + fraction end
    end
  end
  return 1 + 0.5 * (1 + extra)
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
    tex:Hide()
    -- second helper and texture for the crit extension, placed in front of the damage part
    local critOv = CreateFrame("StatusBar", nil, bar)
    critOv:SetStatusBarTexture("Interface/Buttons/WHITE8X8")
    critOv:SetAlpha(0)
    critOv:SetReverseFill(true)
    critOv:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    critOv:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    local critTex = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    critTex:SetPoint("TOPLEFT", critOv:GetStatusBarTexture(), "TOPLEFT")
    critTex:SetPoint("BOTTOMRIGHT", ov:GetStatusBarTexture(), "BOTTOMLEFT")
    critTex:Hide()
    o = { ov = ov, tex = tex, critOv = critOv, critTex = critTex, masks = {} }
    overlays[bar] = o
  end
  return o
end

-- settings keys of the color and custom color: unit frames or nameplates, damage or crit
local function ColorKeys(unit, crit)
  if unit == "target" or unit == "focus" then
    if crit then return "critColor", "critCustom" end
    return "color", "custom"
  end
  if crit then return "plateCritColor", "plateCritCustom" end
  return "plateColor", "plateCustom"
end

-- red, green, blue of the chosen bar color for a unit
local function ColorOf(unit, crit)
  local colorKey, customKey = ColorKeys(unit, crit)
  if ns.Get(colorKey) == "custom" then return unpack(ns.db[customKey]) end
  for _, c in ipairs(COLORS) do
    if c[1] == ns.Get(colorKey) then return c[3], c[4], c[5] end
  end
  return 0.6, 0.05, 0.05
end

-- bar color and opacity from the settings
local function ApplyColor(tex, unit, crit)
  local r, g, b = ColorOf(unit, crit)
  tex:SetColorTexture(r, g, b, ns.Get("opacity") / 100)
end

-- copy the shape masks of the bar fill onto the damage texture, so it follows the bar frame
local function SyncMasks(o, bar)
  local fill = bar:GetStatusBarTexture()
  local parent = bar:GetParent()
  local list = {}
  for i = 1, fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0 do
    list[#list + 1] = fill:GetMaskTexture(i)
  end
  -- Blizzard frames keep their mask on the container
  if #list == 0 and parent and parent.HealthBarMask then list[1] = parent.HealthBarMask end
  for _, mask in ipairs(list) do
    if not o.masks[mask] then
      o.masks[mask] = true
      o.tex:AddMaskTexture(mask)
      o.critTex:AddMaskTexture(mask)
    end
  end
end

-- hide the damage and crit parts of a bar
local function HideOverlay(bar)
  local o = GetOverlay(bar)
  o.tex:Hide()
  o.critTex:Hide()
end

-- bar width for the helper bars; the game can hide it, then the last readable width is used
local function BarWidth(o, bar)
  local width = bar:GetWidth()
  if issecretvalue and issecretvalue(width) then return o.width end
  o.width = width
  return width
end

-- mark the damage, and the crit extension when given, on the bar; works with secret health;
-- look is the unit whose colors to use, default unit
local function DrawBar(bar, unit, damage, crit, look)
  local o = GetOverlay(bar)
  local width = BarWidth(o, bar)
  -- without a known width the bar cannot be scaled
  if not width then
    o.tex:Hide()
    o.critTex:Hide()
    return
  end
  SyncMasks(o, bar)
  o.ov:SetWidth(width)
  o.ov:SetMinMaxValues(0, UnitHealthMax(unit))
  o.ov:SetValue(damage)
  ApplyColor(o.tex, look or unit)
  o.tex:Show()
  if crit then
    o.critOv:SetWidth(width)
    o.critOv:SetMinMaxValues(0, UnitHealthMax(unit))
    o.critOv:SetValue(crit)
    ApplyColor(o.critTex, look or unit, true)
    o.critTex:Show()
  else
    o.critTex:Hide()
  end
end

-- whether this unit type is switched on in the settings
local function Wanted(unit)
  if unit == "target" or unit == "focus" then return ns.Get("frames") end
  return ns.Get("nameplates") and unit:sub(1, 9) == "nameplate"
end

-- spell ID of the unit's current cast or channel
local function CastSpellID(unit)
  local spellID = select(9, UnitCastingInfo(unit))
  if not spellID then spellID = select(8, UnitChannelInfo(unit)) end
  if not spellID or (issecretvalue and issecretvalue(spellID)) then return nil end
  if unit == "player" then lastSpell = spellID end
  return spellID
end

-- damage and crit damage to show: own cast on the target first, then the enemy cast
local function DamageFor(unit)
  local own = ns.Get("own") and UnitIsUnit(unit, "target") and CastSpellID("player")
  local spellID = own or CastSpellID(unit)
  if not spellID then return nil end
  local damage, school = Estimate(spellID)
  if not damage then return nil end
  -- the crit estimate uses the player talents, so only for the player cast
  local crit = own and ns.Get("crit") and damage * CritMultiplier(spellID, school) or nil
  return damage, crit
end

-- show or clear the damage bar for one unit
local function Update(unit)
  if ns.db == nil or not unit then return end
  -- only target, focus, and nameplates; other tokens are not allowed
  if unit ~= "target" and unit ~= "focus" and unit:sub(1, 9) ~= "nameplate" then return end
  local bars = BarsFor(unit)
  for _, bar in ipairs(bars) do HideOverlay(bar) end
  showing[unit] = nil
  if not (ns.Get("enabled") and Wanted(unit) and UnitCanAttack("player", unit)) then return end
  local damage, crit = DamageFor(unit)
  if not damage then return end
  showing[unit] = true
  ns.Debug(unit .. ": damage " .. damage .. (crit and ", crit " .. crit or "") .. " on " .. #bars .. " bars")
  for _, bar in ipairs(bars) do DrawBar(bar, unit, damage, crit) end
end

-- update every visible unit
local function Refresh()
  Update("target")
  Update("focus")
  for unit in pairs(plateUnits) do
    Update(unit)
  end
end


-- current state, with a hint while the feature is off
local function Status()
  local hint = ""
  if not ns.Get("enabled") then
    hint = " " .. L["(turn on with %s)"]:format(ns.Color("command", ns.slash .. " on"))
  end
  ns.Print(ns.OnOff(ns.Get("enabled")) .. hint)
  ns.Status(L["per character"], ns.OnOff(ns.char.perCharacter))
end

-- switch the feature and report the new state
local function Switch(enabled)
  ns.Set("enabled", enabled)
  Status()
end

-- switch per-character settings and report the new state
local function PerCharacter(enabled)
  ns.Set("perCharacter", enabled)
  Status()
end

-- printable text of a value, "secret" when the game hides it
local function Safe(value)
  if issecretvalue and issecretvalue(value) then return "secret" end
  return tostring(value)
end

-- print the state of the pipeline in a few short lines
local function DebugState()
  local bars = BarsFor("target")
  local plate = C_NamePlate.GetNamePlateForUnit("target")
  ns.Status("state", "enabled " .. tostring(ns.Get("enabled")) .. ", casts " .. castEvents
    .. ", hostile " .. tostring(UnitCanAttack("player", "target")))
  ns.Status("bars", #bars .. " on target frame, " .. ((plate and PlateBar(plate)) and "1" or "0") .. " on plate")
  if not lastSpell then return end
  local damage, school = Estimate(lastSpell)
  ns.Status("spell", lastSpell .. ", estimate " .. tostring(damage) .. ", school " .. tostring(school)
    .. ", crit x" .. string.format("%.2f", CritMultiplier(lastSpell, school)))
  if not damage then
    -- no number found: show the start of the description
    local desc = C_Spell.GetSpellDescription(lastSpell)
    ns.Status("text", desc and desc:sub(1, 90):gsub("|", "||") or "nil")
    return
  end
  -- draw on the target frame and the plate now and report whether they are shown
  local plateBar = plate and PlateBar(plate)
  for _, bar in ipairs({ bars[1] or false, plateBar or false }) do
    if bar then DrawBar(bar, "target", damage, ns.Get("crit") and damage * CritMultiplier(lastSpell, school) or nil) end
  end
  ns.Status("bar", "health secret " .. Safe(issecretvalue and issecretvalue(UnitHealthMax("target")))
    .. ", frame " .. (bars[1] and Safe(GetOverlay(bars[1]).tex:IsVisible()) or "none")
    .. ", plate " .. (plateBar and Safe(GetOverlay(plateBar).tex:IsVisible()) or "none"))
end

-- draw a sample estimate of a quarter of the target's health on its frames and plate
local function Test()
  local max = UnitExists("target") and UnitCanAttack("player", "target") and UnitHealthMax("target")
  if not max or (issecretvalue and issecretvalue(max)) then
    return ns.Warn(L["test: target an enemy out of combat first"])
  end
  local damage = max / 4
  local crit = ns.Get("crit") and damage * 1.5 or nil
  local count = 0
  for _, bar in ipairs(BarsFor("target")) do
    DrawBar(bar, "target", damage, crit)
    count = count + 1
  end
  local plate = C_NamePlate.GetNamePlateForUnit("target")
  local plateBar = plate and not plate:IsForbidden() and PlateBar(plate)
  if plateBar then
    DrawBar(plateBar, "target", damage, crit, "nameplate")
    count = count + 1
  end
  -- cleared by the next health, cast, or target update
  showing.target = true
  ns.Print(L["test: sample damage on %s bars"]:format(ns.Color("value", count)))
end

-- unit and crit flag of a color kind
local function KindOf(kind)
  return kind:find("plates", 1, true) and "nameplate" or "target", kind:sub(1, 4) == "crit"
end

-- true while the picker sets the color choice, so the dropdown handler does not reopen it
local picking = false

-- open the color picker for a free bar color; "frames", "plates", "critframes", or "critplates";
-- choice is the color choice to restore on cancel, default the current one
local function PickColor(kind, choice)
  local unit, crit = KindOf(kind)
  local colorKey, customKey = ColorKeys(unit, crit)
  local r, g, b = ColorOf(unit, crit)
  choice = choice or ns.Get(colorKey)
  local previous = { unpack(ns.db[customKey]) }
  ColorPickerFrame:SetupColorPickerAndShow({
    r = r, g = g, b = b, hasOpacity = false,
    -- live update while the color changes
    swatchFunc = function()
      ns.db[customKey] = { ColorPickerFrame:GetColorRGB() }
      picking = true
      ns.Set(colorKey, "custom")
      picking = false
      Refresh()
    end,
    -- restore the old choice and custom color on cancel
    cancelFunc = function()
      ns.db[customKey] = previous
      picking = true
      ns.Set(colorKey, choice)
      picking = false
      Refresh()
    end,
  })
end

-- color dropdown handler for a kind: "custom" opens the picker
local function OnColor(kind)
  -- choice before the latest change, restored if the picker is cancelled
  local last = ns.Get((ColorKeys(KindOf(kind))))
  return function(value)
    if value == "custom" and not picking then PickColor(kind, last) end
    last = value
    Refresh()
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
  "UNIT_SPELLCAST_CHANNEL_UPDATE",
}) do
  events[event] = OnCast
end

-- a plate got a unit: remember the token and mark it
function events.NAME_PLATE_UNIT_ADDED(unit)
  plateUnits[unit] = true
  Update(unit)
end

-- plates are pooled: clear the estimate when released
function events.NAME_PLATE_UNIT_REMOVED(unit)
  Update(unit)
  showing[unit] = nil
  plateUnits[unit] = nil
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

-- talents changed: read them again on the next crit estimate
local function OnTalents()
  talentRanks = nil
  ns.Debug("talents changed")
  if ns.db ~= nil then Refresh() end
end
events.PLAYER_TALENT_UPDATE = OnTalents
events.CHARACTER_POINTS_CHANGED = OnTalents
events.ACTIVE_TALENT_GROUP_CHANGED = OnTalents
events.TRAIT_CONFIG_UPDATED = OnTalents

-- spell text arrived after a request
function events.SPELL_DATA_LOAD_RESULT(spellID)
  if requested[spellID] and ns.db ~= nil and ns.Get("enabled") then Refresh() end
end

-- one frame dispatching all events above
local frame = CreateFrame("Frame")
for event in pairs(events) do
  -- skip events this client does not know, e.g. some talent events
  if C_EventUtils.IsEventValid(event) then frame:RegisterEvent(event) end
end
frame:SetScript("OnEvent", function(_, event, ...)
  events[event](...)
end)

-- set the opacity in percent from the settings page or a command
local function SetOpacity(percent)
  local value = math.max(20, math.min(100, math.floor(percent + 0.5)))
  -- the settings value also moves the slider and runs Refresh
  ns.Set("opacity", value)
  return value
end

-- color choices: preset values, then the free color
local choices = {}
for i, c in ipairs(COLORS) do choices[i] = { c[1], c[2] } end
choices[#choices + 1] = { "custom", L["Custom..."] }

-- saved state; settings page once loaded
ns.Store("EstiDmgDB", {
  _version = 0,
  enabled = true, nameplates = true, frames = true, own = true, crit = false, opacity = 85,
  color = "darkred", custom = { 0.6, 0.05, 0.05 },
  plateColor = "darkred", plateCustom = { 0.6, 0.05, 0.05 },
  critColor = "orange", critCustom = { 1, 0.5, 0.1 },
  plateCritColor = "orange", plateCritCustom = { 1, 0.5, 0.1 },
}, function(db)
  -- opacity is a percent now; older versions saved a fraction
  if db.opacity <= 1 then db.opacity = math.floor(db.opacity * 100 + 0.5) end
  -- version 1: per-character settings and changed commands; one notice line once
  if db._version < 1 then
    db._version = 1
    ns.Print(L["new: per-character settings and more commands, see %s"]:format(ns.Color("command", "/estidmg help")))
  end
  ns.Settings()
  ns.Checkbox("enabled", L["Enabled"], L["Mark estimated damage on enemy health bars"], Refresh)
  ns.Checkbox("nameplates", L["Nameplates"], L["Mark the damage on enemy nameplates"], Refresh)
  ns.Checkbox("frames", L["Target and focus"], L["Mark the damage on the target and focus frames"], Refresh)
  ns.Checkbox("own", L["Own casts"], L["Show the damage of your own cast on your target"], Refresh)
  ns.Checkbox("crit", L["Crit extension"], L["Add a bar part for a possible crit of your own cast, with your crit damage talents"], Refresh)
  ns.Dropdown("color", L["Unit frame color"], choices, L["Bar color on target and focus frames; Custom opens the color picker"], OnColor("frames"))
  ns.Dropdown("plateColor", L["Nameplate color"], choices, L["Bar color on nameplates; Custom opens the color picker"], OnColor("plates"))
  ns.Dropdown("critColor", L["Unit frame crit color"], choices, L["Crit extension color on target and focus frames"], OnColor("critframes"))
  ns.Dropdown("plateCritColor", L["Nameplate crit color"], choices, L["Crit extension color on nameplates"], OnColor("critplates"))
  ns.Slider("opacity", L["Bar opacity (%)"], 20, 100, 5, L["How solid the damage bar is"], Refresh)
end)

-- chat commands
ns.Command({ name = "on", help = "turn the estimates on", run = function() Switch(true) end })
ns.Command({ name = "off", help = "turn the estimates off", run = function() Switch(false) end })

-- one on|off subcommand per checkbox setting besides enabled
for _, flag in ipairs({
  { "nameplates", "mark the damage on enemy nameplates" },
  { "frames", "mark the damage on the target and focus frames" },
  { "own", "show the damage of your own cast on your target" },
  { "crit", "add a bar part for a possible crit of your own cast" },
}) do
  local key = flag[1]
  ns.Command({
    name = key,
    help = flag[2],
    args = { { name = "state", choices = { "on", "off" } } },
    run = function(args)
      ns.Set(key, args.state == "on")
      ns.Status(key, ns.OnOff(ns.Get(key)))
    end,
  })
end

-- color values for the color command: presets and custom
local colorValues = {}
for i, c in ipairs(choices) do colorValues[i] = c[1] end
ns.Command({
  name = "color",
  help = "set a bar color; custom or no color opens the color picker",
  args = {
    { name = "where", choices = { "frames", "plates", "critframes", "critplates" } },
    { name = "color", choices = colorValues, optional = true },
  },
  run = function(args)
    if not args.color or args.color == "custom" then return PickColor(args.where) end
    local colorKey = ColorKeys(KindOf(args.where))
    ns.Set(colorKey, args.color)
    ns.Status(args.where, ns.Color("value", args.color))
  end,
})
ns.Command({
  name = "opacity",
  help = "set the bar opacity in percent",
  args = { { name = "percent", type = "number", min = 20, max = 100 } },
  run = function(args) ns.Print(L["opacity %s"]:format(ns.Color("value", SetOpacity(args.percent) .. "%"))) end,
})
ns.Command({
  name = "character",
  help = "use settings for this character only, or the account's",
  args = { { name = "state", choices = { "on", "off" } } },
  run = function(args) PerCharacter(args.state == "on") end,
})
ns.Command({ name = "test", help = "draw a sample estimate on your target", run = Test })
ns.Command({
  name = "reset",
  help = "reset the active profile's settings to defaults",
  run = function()
    ns.ResetSettings()
    ns.Success("settings reset to defaults")
    Status()
  end,
})
ns.Command({
  name = "debug",
  help = "show what the addon does in chat, until /reload; on also prints the pipeline state",
  args = { { name = "state", choices = { "on", "off" } } },
  run = function(args)
    ns.debug = args.state == "on"
    ns.Status("debug", ns.OnOff(ns.debug))
    if ns.debug then DebugState() end
  end,
})
ns.Command({ name = "config", help = "open the settings page", run = ns.OpenSettings })
ns.Slash({ "/estidmg", "/edmg", "/esd" }, Status)

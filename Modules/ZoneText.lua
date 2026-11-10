-- ---------------------------------------------------------------------------
-- Tweaks > Zone text: a second box under (or above) EllesmereUI's minimap zone
-- text that shows the sub zone. It copies the zone box's look (background
-- color, font, text color, height) and sits at an X/Y offset from it. Hidden
-- when there is no sub zone or when the zone box already shows it
-- (EllesmereUI's own "Display Sub Zone"). Parented to the zone box, so it hides
-- with it. Nothing is created while the switch is off.
-- ---------------------------------------------------------------------------
local _, ns = ...
local EUI = ns.EUI

local Zone = ns.Module("zonetext",
    { on = false, side = "below", x = 0, y = -2 },
    { x = { -100, 100, 1 }, y = { -50, 50, 1 } })
ns.ZoneText = Zone

Zone.SIDES = { below = true, above = true }

function Zone.Side()
    local s = Zone.Get("side")
    return Zone.SIDES[s] and s or "below"
end

local box, text        -- ours
local zoneBox, zoneFS  -- EllesmereUI's
local active = false

local function Build(parent)
    box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    text = box:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    ns.zoneSubBox = box
end

-- the look of EllesmereUI's box, read again on every update (it follows its settings)
local function CopyStyle()
    local r, g, b, a = zoneBox:GetBackdropColor()
    box:SetBackdropColor(r or 0, g or 0, b or 0, a or 1)
    local font, size, flags = zoneFS:GetFont()
    if font then text:SetFont(font, size or 10, flags or "") end
    text:SetTextColor(zoneFS:GetTextColor())
    if zoneFS.GetShadowOffset then
        text:SetShadowOffset(zoneFS:GetShadowOffset())
        text:SetShadowColor(zoneFS:GetShadowColor())
    end
    box:SetFrameLevel(zoneBox:GetFrameLevel())
end

local function Place()
    box:ClearAllPoints()
    local x, y = Zone.Get("x"), Zone.Get("y")
    if Zone.Side() == "above" then
        box:SetPoint("BOTTOM", zoneBox, "TOP", x, -y)
    else
        box:SetPoint("TOP", zoneBox, "BOTTOM", x, y)
    end
end

function Zone.Update()
    if not active then
        if box then box:Hide() end
        return
    end
    if not zoneBox then
        zoneBox, zoneFS = EUI.ZoneTextBox()
        if not zoneBox then return end
    end
    if not box then Build(zoneBox) end
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local shown = zoneFS:GetText()
    if ns.IsSecret(sub) or sub == "" or sub == shown then
        box:Hide()
        return
    end
    CopyStyle()
    text:SetText(sub)
    box:SetSize((text:GetStringWidth() or 0) + 20, zoneBox:GetHeight() or 18)
    Place()
    box:Show()
end

-- EllesmereUI's "Display Sub Zone" puts the sub zone into its own box, which would
-- leave ours empty: switching on turns it off (the old value is kept), switching off
-- puts it back. The value belongs to an EllesmereUI profile, so it is kept per profile
-- name (store.eui[<profile>] = { prev = <old value> }); a profile switch takes the new
-- profile's value too, and switching off gives back every profile's value.
-- Changed only on these occasions, never behind the player's back.
local function KeptValues()
    local s = Zone.Store()
    if type(s.eui) ~= "table" then s.eui = {} end
    -- a value kept before profiles were told apart belongs to the profile that is active now
    if s.euiTaken then
        local name = EUI.ActiveProfileName()
        if name and not s.eui[name] then s.eui[name] = { prev = s.euiPrev and true or false } end
        s.euiTaken, s.euiPrev = nil, nil
    end
    return s.eui
end

local function TakeEuiSubZone(on)
    local kept = KeptValues()
    local changed = false
    if on then
        local name = EUI.ActiveProfileName()
        local mm = EUI.MinimapSettings()
        if mm and name and not kept[name] then
            kept[name] = { prev = mm.zoneShowSubZone and true or false }
            mm.zoneShowSubZone = false
            changed = true
        end
    else
        for name, entry in pairs(kept) do
            local mm = EUI.MinimapSettings(name)
            if mm then
                mm.zoneShowSubZone = entry.prev or nil
                kept[name] = nil
                changed = true
            end
        end
        if next(kept) == nil then Zone.Store().eui = nil end
    end
    if not changed then return end
    if not zoneBox then zoneBox, zoneFS = EUI.ZoneTextBox() end
    EUI.RefreshZoneText(zoneBox)
end

-- EllesmereUI keeps one value per profile: after a switch the new profile is taken as well
local watching = false
local function WatchProfiles()
    if watching then return end
    watching = true
    EUI.OnProfileChange(function()
        if not active then return end
        TakeEuiSubZone(true)
        Zone.Update()
    end)
end

-- a reset forgets the kept value: give it back first
local baseReset = Zone.Reset
function Zone.Reset()
    TakeEuiSubZone(false)
    baseReset()
end

Zone.OnApply(function()
    active = Zone.Get("on")
    TakeEuiSubZone(active)
    if active then WatchProfiles() end
    Zone.Update()
    -- EllesmereUI builds the minimap after login: look again shortly
    if active and not zoneBox then C_Timer.After(2, Zone.Update) end
end)

-- EllesmereUI updates its own text on the same events; ours follows one frame later
local function Later() if active then C_Timer.After(0, Zone.Update) end end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED" }) do
    ns.RegisterEvent(ev, Later)
end

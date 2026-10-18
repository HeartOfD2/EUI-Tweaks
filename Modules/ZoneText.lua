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
-- puts it back. Changed only on these switches, never behind the player's back.
local function TakeEuiSubZone(on)
    local mm = EUI.MinimapSettings()
    local s = Zone.Store()
    if not mm then return end
    if on and not s.euiTaken then
        s.euiPrev = mm.zoneShowSubZone and true or false
        s.euiTaken = true
        mm.zoneShowSubZone = false
    elseif not on and s.euiTaken then
        mm.zoneShowSubZone = s.euiPrev or nil
        s.euiTaken, s.euiPrev = nil, nil
    else
        return
    end
    if not zoneBox then zoneBox, zoneFS = EUI.ZoneTextBox() end
    EUI.RefreshZoneText(zoneBox)
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

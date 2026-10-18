-- ---------------------------------------------------------------------------
-- Tweaks > Hide chat (ported from EverFrame): a button hides all chat windows
-- with their tabs, edit boxes and chat menu buttons, and brings them back.
-- With EllesmereUI Chat the chat is hidden through EllesmereUI's own
-- visibility rule (its "visibilityOverride" = "never"), which fades its
-- background, sidebar, borders and tab strip as well; the previous value is put
-- back on show and before logout, so EllesmereUI never saves our override.
-- Without EllesmereUI Chat the Blizzard frames are hidden (Hide/Show only).
-- Enter, a reply or Edit Mode reveal the chat. The button uses the
-- EllesmereUI accent unless a color is picked.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI, EUI = ns.L, ns.UI, ns.EUI

local Chat = ns.Module("chathide",
    { on = false, hidden = false, locked = true, corner = "BOTTOMLEFT", size = 20, alpha = 0.9 },
    { size = { 16, 48 }, alpha = { 0.2, 1 } })
ns.ChatHide = Chat

Chat.CORNERS = { BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function Global(name) return rawget(_G, name) end

function Chat.Corner()
    local c = Chat.Get("corner")
    return Chat.CORNERS[c] and c or "BOTTOMLEFT"
end

-- the picked color { r, g, b }; nil = the EllesmereUI accent
function Chat.GetColor()
    local c = Chat.Store().color
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then return c end
end

function Chat.SetColor(r, g, b)
    Chat.Store().color = r and { r, g, b } or nil
    Chat.Layout()
end

function Chat.Color()
    local c = Chat.GetColor()
    if c then return c[1], c[2], c[3] end
    return EUI.Accent()
end

function Chat.GetPos()
    local p = Chat.Store().pos
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
end

function Chat.ResetAnchor()
    local s = Chat.Store()
    s.pos, s.corner, s.size, s.alpha, s.color, s.locked = nil, nil, nil, nil, nil, nil
    Chat.Apply()
end

-- ---------------------------------------------------------------- EllesmereUI Chat
local OVERRIDE = "visibilityOverride"
local overriding = false

local function EuiHide()
    local store = EUI.ChatStore()
    if not store then return false end
    if not overriding then
        local s = Chat.Store()
        s.prevOverride = store[OVERRIDE]
        s.overrideSaved = true
        overriding = true
    end
    store[OVERRIDE] = "never"
    EUI.RequestVisibilityUpdate()
    return true
end

local function EuiShow()
    local s = Chat.Store()
    if not (overriding or s.overrideSaved) then return end
    local store = EUI.ChatStore()
    if store then
        store[OVERRIDE] = s.prevOverride
        EUI.RequestVisibilityUpdate()
    end
    overriding, s.prevOverride, s.overrideSaved = false, nil, nil
end

-- ---------------------------------------------------------------- Blizzard frames
local SINGLES = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }
local managed, order, wasShown = {}, {}, {}
local active, editMode, installed = false, false, false

local function Hidden() return active and Chat.Get("hidden") and not editMode end
local function UseEui() return EUI.ChatStore() ~= nil end

local function Add(f, edit)
    if type(f) ~= "table" or managed[f] or type(f.Hide) ~= "function" then return end
    managed[f] = {}
    order[#order + 1] = f
    if edit then return end   -- an edit box shows itself while typing; the hooks reveal the chat
    -- the game shows tabs and windows again when it docks them: keep them away while hidden
    hooksecurefunc(f, "Show", function(self)
        if Hidden() and not UseEui() and not managed[self].forcing then
            wasShown[self] = true
            self:Hide()
        end
    end)
    hooksecurefunc(f, "SetShown", function(self, shown)
        if shown and Hidden() and not UseEui() and not managed[self].forcing then
            wasShown[self] = true
            self:Hide()
        end
    end)
end

local function Collect()
    local n = tonumber(Global("NUM_CHAT_WINDOWS")) or 10
    local i = 1
    while i <= n or Global("ChatFrame" .. i) do
        local name = "ChatFrame" .. i
        Add(Global(name))
        Add(Global(name .. "Tab"))
        Add(Global(name .. "ButtonFrame"))
        Add(Global(name .. "EditBox"), true)
        i = i + 1
    end
    for _, name in ipairs(SINGLES) do Add(Global(name)) end
end

local function BlizzHide()
    Collect()
    for _, f in ipairs(order) do
        if f:IsShown() then wasShown[f] = true end
        f:Hide()
    end
end

local function BlizzShow()
    for _, f in ipairs(order) do
        if wasShown[f] then
            wasShown[f] = nil
            managed[f].forcing = true
            f:Show()
            managed[f].forcing = false
        end
    end
end

function Chat.Update()
    if not installed then return end
    if Hidden() then
        if not EuiHide() then BlizzHide() end
    else
        EuiShow()
        BlizzShow()
    end
    Chat.Layout()
end

function Chat.SetHidden(v)
    Chat.Store().hidden = v and true or false
    Chat.Update()
end

-- ---------------------------------------------------------------- the button
local btn

local function BuildButton()
    btn = CreateFrame("Button", "EUITweaksChatButton", UIParent)
    btn:SetFrameStrata("HIGH")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    UI.Skin(btn, UI.BG, 0.85)
    btn.dots = {}
    for i = 1, 3 do btn.dots[i] = btn:CreateTexture(nil, "ARTWORK") end
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetColorTexture(1, 1, 1, 0.12)
    -- the plate that marks the drag area while unlocked
    btn.mover = CreateFrame("Frame", nil, btn)
    btn.mover:SetPoint("TOPLEFT", -3, 3)
    btn.mover:SetPoint("BOTTOMRIGHT", 3, -3)
    btn.mover:SetFrameLevel(btn:GetFrameLevel())
    UI.Skin(btn.mover, UI.BG, 0.4)
    btn.mover.text = UI.Text(btn.mover, 11)
    btn.mover.text:SetText(L["Drag to move"])
    btn.mover:Hide()
    btn:SetScript("OnClick", function() Chat.SetHidden(not Chat.Get("hidden")) end)
    btn:SetScript("OnDragStart", function(self)
        if not Chat.Get("locked") then self:StartMoving() end
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetBottom()
        if x and y then Chat.Store().pos = { x = x, y = y } end
        Chat.Layout()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Chat.Get("hidden") and L["Show chat"] or L["Hide chat"])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    UI.OnAccent(function() Chat.Layout() end)
end

-- the label of the drag plate reads towards the middle of the screen
local function PlaceMoverText()
    local t = btn.mover.text
    local cx, cy = btn:GetCenter()
    local right = not (cx and cx > UIParent:GetWidth() / 2)
    local above = not (cy and cy > UIParent:GetHeight() / 2)
    local h = right and "LEFT" or "RIGHT"
    t:ClearAllPoints()
    t:SetPoint((above and "BOTTOM" or "TOP") .. h, btn, (above and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"),
        right and 4 or -4, above and 6 or -6)
    t:SetJustifyH(h)
end

function Chat.Layout()
    if not btn then return end
    local size = Chat.Get("size")
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    local p = Chat.GetPos()
    if p then
        btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        local c = Chat.Corner()
        btn:SetPoint(c, UIParent, c, Chat.CORNERS[c][1], Chat.CORNERS[c][2])
    end
    btn:SetAlpha(Chat.Get("alpha"))
    local r, g, b = Chat.Color()
    UI.EdgeColor(btn, r, g, b, 1)
    UI.EdgeColor(btn.mover, r, g, b, 1)
    btn.mover.text:SetTextColor(r, g, b, 1)
    local d = math.max(2, math.floor(size / 7 + 0.5))
    local on = not Chat.Get("hidden")
    for i, t in ipairs(btn.dots) do
        t:SetSize(d, d)
        t:ClearAllPoints()
        t:SetPoint("CENTER", btn, "CENTER", (i - 2) * (d * 2), 0)
        t:SetColorTexture(r, g, b, on and 1 or 0.35)
    end
    btn.mover:SetShown(not Chat.Get("locked"))
    PlaceMoverText()
end

-- ---------------------------------------------------------------- hooks (once, on first use)
local function Reveal()
    if active and Chat.Get("hidden") then Chat.SetHidden(false) end
end

local function Install()
    if installed then return end
    installed = true
    BuildButton()
    -- typing or replying shows the chat again
    for _, name in ipairs({ "ChatEdit_ActivateChat", "ChatFrame_OpenChat" }) do
        if type(Global(name)) == "function" then hooksecurefunc(name, Reveal) end
    end
    local util = Global("ChatFrameUtil")
    if type(util) == "table" and type(util.OpenChat) == "function" then hooksecurefunc(util, "OpenChat", Reveal) end
    -- new and re-docked windows are taken in
    for _, name in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_DockFrame", "FCF_DockUpdate" }) do
        if type(Global(name)) == "function" then
            hooksecurefunc(name, function() if active then C_Timer.After(0, Chat.Update) end end)
        end
    end
    -- Edit Mode shows the chat while it is open
    local em = Global("EditModeManagerFrame")
    if type(em) == "table" and type(em.HookScript) == "function" then
        em:HookScript("OnShow", function() editMode = true Chat.Update() end)
        em:HookScript("OnHide", function() editMode = false Chat.Update() end)
        editMode = em:IsShown() and true or false
    end
end

Chat.OnApply(function()
    active = Chat.Get("on")
    if active then Install() end
    -- an override left behind by an earlier session (crash) is cleared first
    if not active then EuiShow() end
    if not installed then return end
    btn:SetShown(active)
    Chat.Update()
end)

for _, ev in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    ns.RegisterEvent(ev, function() if active then Chat.Update() end end)
end

-- EllesmereUI saves its profile at logout: never with our override in it
ns.RegisterEvent("PLAYER_LOGOUT", function()
    if overriding then
        local store = EUI.ChatStore()
        if store then store[OVERRIDE] = Chat.Store().prevOverride end
        overriding = false
        Chat.Store().prevOverride, Chat.Store().overrideSaved = nil, nil
    end
end)

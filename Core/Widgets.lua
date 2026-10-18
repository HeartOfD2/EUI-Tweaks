-- ---------------------------------------------------------------------------
-- A small widget kit for the addon's own windows and overlays (the copy
-- window, the icon search bar, the filter menu). It copies the look of
-- EllesmereUI (dark panel, thin light border, accent highlights) without using
-- its internals. Options pages use EllesmereUI.Widgets instead (Options.lua).
-- Colors that follow the accent are listed and repainted on an accent change.
-- ---------------------------------------------------------------------------
local _, ns = ...
local UI = {}
ns.UI = UI

UI.BG = { 0.077, 0.068, 0.058 }
UI.FIELD = { 0.12, 0.12, 0.12 }
UI.EDGE = { 1, 1, 1, 0.15 }
UI.TEXT = { 1, 1, 1, 0.9 }
UI.DIM = { 1, 1, 1, 0.55 }

-- ---------------------------------------------------------------- accent painting
local painters = {}   -- fn(r, g, b)
function UI.OnAccent(fn)
    painters[#painters + 1] = fn
    fn(ns.EUI.Accent())
end
ns.On("LOGIN", function()
    ns.EUI.OnAccent(function()
        local r, g, b = ns.EUI.Accent()
        for i = 1, #painters do painters[i](r, g, b) end
    end)
end)

-- ---------------------------------------------------------------- basics
function UI.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(ns.EUI.Font(), size or 12, "")
    local c = color or UI.TEXT
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- one physical screen pixel in the frame's own units: a 1-unit line in a scaled
-- frame (EllesmereUI popups are scaled down) can fall between two pixels and vanish
function UI.Pixel(frame)
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local _, h = 0, 0
    if type(GetPhysicalScreenSize) == "function" then _, h = GetPhysicalScreenSize() end
    if not (type(h) == "number" and h > 0 and scale > 0) then return 1 end
    return 768 / h / scale
end

-- sizes the border to exactly one physical pixel (call again when the scale changes)
function UI.FitEdges(frame)
    if not frame.edges then return end
    local px = UI.Pixel(frame)
    local t, b, l, r = frame.edges[1], frame.edges[2], frame.edges[3], frame.edges[4]
    t:SetHeight(px) b:SetHeight(px) l:SetWidth(px) r:SetWidth(px)
end

-- background plus a 1 px border; returns the four edge textures
function UI.Skin(frame, bg, alpha, edge)
    local c = bg or UI.BG
    frame.bgTex = frame.bgTex or frame:CreateTexture(nil, "BACKGROUND")
    frame.bgTex:SetAllPoints()
    frame.bgTex:SetColorTexture(c[1], c[2], c[3], alpha or 0.97)
    local e = edge or UI.EDGE
    if not frame.edges then
        frame.edges = {}
        for i = 1, 4 do
            local tex = frame:CreateTexture(nil, "BORDER")
            -- no snapping: the line stays on whole pixels instead of being rounded away
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) tex:SetTexelSnappingBias(0) end
            frame.edges[i] = tex
        end
        local t, b, l, r = frame.edges[1], frame.edges[2], frame.edges[3], frame.edges[4]
        t:SetPoint("TOPLEFT") t:SetPoint("TOPRIGHT")
        b:SetPoint("BOTTOMLEFT") b:SetPoint("BOTTOMRIGHT")
        l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMLEFT")
        r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMRIGHT")
    end
    UI.FitEdges(frame)
    UI.EdgeColor(frame, e[1], e[2], e[3], e[4] or 1)
    return frame.edges
end

function UI.EdgeColor(frame, r, g, b, a)
    for _, t in ipairs(frame.edges or {}) do t:SetColorTexture(r, g, b, a or 1) end
end

-- ---------------------------------------------------------------- button
function UI.Button(parent, w, h, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h or 24)
    UI.Skin(b, UI.FIELD, 0.9)
    b.text = UI.Text(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(text or "")
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    b:SetScript("OnEnter", function(self)
        local r, g, bl = ns.EUI.Accent()
        UI.EdgeColor(self, r, g, bl, 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip[1], 1, 1, 1)
            if self.tip[2] then GameTooltip:AddLine(self.tip[2], 1, 0.82, 0, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:Paint()
        GameTooltip:Hide()
    end)
    -- an "on" button keeps an accent border (e.g. an active filter)
    function b:SetActive(on) self.active = on self:Paint() end
    function b:Paint()
        if self.active then
            local r, g, bl = ns.EUI.Accent()
            UI.EdgeColor(self, r, g, bl, 1)
        else
            UI.EdgeColor(self, UI.EDGE[1], UI.EDGE[2], UI.EDGE[3], UI.EDGE[4])
        end
    end
    return b
end

-- ---------------------------------------------------------------- edit box
function UI.Edit(parent, w, h, placeholder)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h or 24)
    e:SetAutoFocus(false)
    e:SetFont(ns.EUI.Font(), 12, "")
    e:SetTextColor(1, 1, 1, 0.9)
    e:SetTextInsets(8, 8, 0, 0)
    UI.Skin(e, { 0, 0, 0 }, 0.5, { 1, 1, 1, 0.2 })
    e.hint = UI.Text(e, 12, UI.DIM)
    e.hint:SetPoint("LEFT", 8, 0)
    e.hint:SetText(placeholder or "")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:HookScript("OnTextChanged", function(self) self.hint:SetShown((self:GetText() or "") == "") end)
    e:HookScript("OnEditFocusGained", function(self)
        local r, g, b = ns.EUI.Accent()
        UI.EdgeColor(self, r, g, b, 1)
    end)
    e:HookScript("OnEditFocusLost", function(self) UI.EdgeColor(self, 1, 1, 1, 0.2) end)
    return e
end

-- ---------------------------------------------------------------- check box
function UI.Check(parent, label, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(20)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(14, 14)
    c.box:SetPoint("LEFT")
    UI.Skin(c.box, { 0, 0, 0 }, 0.5, { 1, 1, 1, 0.3 })
    c.mark = c.box:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.text = UI.Text(c, 12)
    c.text:SetPoint("LEFT", c.box, "RIGHT", 6, 0)
    c.text:SetText(label)
    c:SetWidth(20 + c.text:GetStringWidth() + 4)
    function c:Refresh()
        local r, g, b = ns.EUI.Accent()
        self.mark:SetColorTexture(r, g, b, 1)
        self.mark:SetShown(get() and true or false)
    end
    c:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    c:Refresh()
    return c
end

-- ---------------------------------------------------------------- slider
function UI.Slider(parent, w, lo, hi, step, get, set)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(w, 14)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.track = s:CreateTexture(nil, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(4)
    s.track:SetColorTexture(1, 1, 1, 0.15)
    s.thumb = s:CreateTexture(nil, "OVERLAY")
    s.thumb:SetSize(10, 14)
    s:SetThumbTexture(s.thumb)
    s.value = UI.Text(s, 11, UI.DIM)
    s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local busy = false
    s:SetScript("OnValueChanged", function(self, v)
        if busy then return end
        v = math.floor(v / step + 0.5) * step
        self.value:SetText(tostring(v))
        set(v)
    end)
    function s:Refresh()
        busy = true
        local v = get()
        self:SetValue(v)
        self.value:SetText(tostring(v))
        busy = false
    end
    UI.OnAccent(function(r, g, b) s.thumb:SetColorTexture(r, g, b, 1) end)
    s:Refresh()
    return s
end

-- ---------------------------------------------------------------- window
-- movable, resizable, closes on Escape; name is needed for UISpecialFrames
function UI.Window(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(420, 260, 1400, 1000) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.Skin(f)
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT", 1, -1)
    f.bar:SetPoint("TOPRIGHT", -1, -1)
    f.bar:SetHeight(2)
    UI.OnAccent(function(r, g, b) f.bar:SetColorTexture(r, g, b, 1) end)
    f.title = UI.Text(f, 14)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(title or "")
    f.close = UI.Button(f, 22, 22, "x", function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -8, -8)
    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(14, 14)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip.tex = f.grip:CreateTexture(nil, "OVERLAY")
    f.grip.tex:SetAllPoints()
    f.grip.tex:SetColorTexture(1, 1, 1, 0.15)
    f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end
    return f
end

-- ---------------------------------------------------------------- menu
-- items: { label, desc, checked, divider, fn }; the menu closes on a click
-- outside. One shared menu, like EllesmereUI's dropdowns.
local menu, catcher
local ROW = 20

local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
UI.CloseMenu = CloseMenu

function UI.OpenMenu(anchor, items, width)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetScript("OnClick", CloseMenu)
        catcher:SetFrameLevel(400)   -- above EllesmereUI's popups (same strata)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(410)
        menu:EnableMouse(true)
        UI.Skin(menu, UI.BG, 0.98)
        menu.rows = {}
    end
    width = width or 200
    for i, it in ipairs(items) do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetHeight(ROW)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.08)
            r.mark = r:CreateTexture(nil, "ARTWORK")
            r.mark:SetSize(8, 8)
            r.mark:SetPoint("LEFT", 8, 0)
            r.text = UI.Text(r, 12)
            r.text:SetPoint("LEFT", 22, 0)
            r.desc = UI.Text(r, 11, UI.DIM)
            r.desc:SetPoint("RIGHT", -8, 0)
            r.line = r:CreateTexture(nil, "ARTWORK")
            r.line:SetPoint("TOPLEFT", 4, 0)
            r.line:SetPoint("TOPRIGHT", -4, 0)
            r.line:SetHeight(1)
            r.line:SetColorTexture(1, 1, 1, 0.1)
            menu.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * ROW)
        r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * ROW)
        r.text:SetText(it.label or "")
        r.desc:SetText(it.desc or "")
        local ar, ag, ab = ns.EUI.Accent()
        r.mark:SetColorTexture(ar, ag, ab, 1)
        r.mark:SetShown(it.checked and true or false)
        r.line:SetShown(it.divider and true or false)
        r:SetScript("OnClick", function()
            CloseMenu()
            if it.fn then it.fn() end
        end)
        r:Show()
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(width, #items * ROW + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    -- the menu scales with the frame it opens from (EllesmereUI popups are scaled)
    menu:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    catcher:Show()
    menu:Show()
end

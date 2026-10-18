-- ---------------------------------------------------------------------------
-- Tweaks > Copy chat: the copy window of EverFrame (search, timestamps,
-- channel colors, font size, line limit) behind EllesmereUI's "Copy Chat"
-- sidebar button. Like EllesmereUI's own popup it opens with the text focused,
-- fully selected and scrolled to the newest line, so Ctrl+C copies at once.
-- Without the EllesmereUI button (EUI Chat off) a small icon on every chat
-- window opens it instead. Nothing is hooked while the switch is off; the
-- EllesmereUI button gets its own click handler back.
-- Lines are read through GetNumMessages / GetMessageInfo; a line whose text is
-- a secret value is never read or joined, only counted.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI, EUI = ns.L, ns.UI, ns.EUI

local Copy = ns.Module("chatcopy",
    { on = false, corner = "BOTTOMRIGHT", hover = true, iconSize = 18, size = 13, limit = 300,
      time = false, colors = true },
    { iconSize = { 14, 32 }, size = { 9, 24 }, limit = { 50, 1000 } })
ns.ChatCopy = Copy

Copy.CORNERS = { TOPLEFT = { 3, -3 }, TOPRIGHT = { -3, -3 }, BOTTOMLEFT = { 3, 3 }, BOTTOMRIGHT = { -3, 3 } }
Copy.TEXTURE = ns.MEDIA .. "ChatCopy"

local function Global(name) return rawget(_G, name) end
local IsSecret = ns.IsSecret

function Copy.Corner()
    local c = Copy.Get("corner")
    return Copy.CORNERS[c] and c or "BOTTOMRIGHT"
end

-- ---------------------------------------------------------------- reading the chat
-- the clock time of each line, counted from the newest message (kept per chat window)
local stamps, hooked = {}, {}
local active = false

local function HookAdd(cf)
    if hooked[cf] or type(cf.AddMessage) ~= "function" then return end
    hooked[cf] = true
    stamps[cf] = { n = 0 }
    hooksecurefunc(cf, "AddMessage", function(self)
        local s = stamps[self]
        if not (active and s) then return end
        s.n = s.n + 1
        s[s.n] = time()
        s[s.n - 2000] = nil
    end)
end

local function HookAll()
    local n = tonumber(Global("NUM_CHAT_WINDOWS")) or 10
    local i = 1
    while i <= n or Global("ChatFrame" .. i) do
        local cf = Global("ChatFrame" .. i)
        if type(cf) == "table" then HookAdd(cf) end
        i = i + 1
    end
end

-- links show their text, icons go; with colors on, the class color of a player name stays
-- and the line color resumes after it, other color codes go (the line gets its channel color)
local function Clean(text, colors, resume)
    text = text:gsub("|Hplayer:.-|h(.-)|h", function(inner)
        if colors then inner = inner:gsub("|c(%x%x%x%x%x%x%x%x)(.-)|r", "\001%1%2\002") end
        return inner
    end)
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|n", " ")
    if colors then
        text = text:gsub("\001(%x%x%x%x%x%x%x%x)", "|c%1"):gsub("\002", resume)
    else
        text = text:gsub("[\001\002]", "")
    end
    return text
end

local function Byte(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end

-- the lines of a chat window (newest last): lines, protected count
function Copy.Lines(cf, query)
    local out, secret = {}, 0
    if type(cf) ~= "table" or type(cf.GetNumMessages) ~= "function" or type(cf.GetMessageInfo) ~= "function" then
        return out, secret
    end
    local okN, n = pcall(cf.GetNumMessages, cf)
    if not okN or type(n) ~= "number" or IsSecret(n) then return out, secret end
    local first = math.max(1, n - Copy.Get("limit") + 1)
    local st = stamps[cf]
    local colors, withTime = Copy.Get("colors"), Copy.Get("time")
    query = query and query ~= "" and ns.Fold(query) or nil
    for i = first, n do
        local ok, text, r, g, b = pcall(cf.GetMessageInfo, cf, i)
        if ok and IsSecret(text) then
            secret = secret + 1
        elseif ok and type(text) == "string" then
            local tint = colors and type(r) == "number" and type(g) == "number" and type(b) == "number"
                and not IsSecret(r) and not IsSecret(g) and not IsSecret(b)
            local base = tint and ("|cff%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b)) or nil
            local line = Clean(text, colors, base or "|r")
            if not query or ns.Fold(line):find(query, 1, true) then
                if withTime and st then
                    local t = st[st.n - (n - i)]
                    if t then line = date("%H:%M:%S", t) .. "  " .. line end
                end
                if base then line = base .. line .. "|r" end
                out[#out + 1] = line
            end
        end
    end
    return out, secret
end

local function FrameName(cf)
    local id = type(cf.GetID) == "function" and cf:GetID() or nil
    local info = Global("GetChatWindowInfo")
    if type(info) == "function" and type(id) == "number" then
        local ok, name = pcall(info, id)
        if ok and type(name) == "string" and not IsSecret(name) and name ~= "" then return name end
    end
    return L["Chat window %d"]:format(type(id) == "number" and id or 1)
end

-- the window EllesmereUI's button copies: the selected tab of the main dock
local function SelectedChat()
    local dock, get = Global("GENERAL_CHAT_DOCK"), Global("FCFDock_GetSelectedWindow")
    if dock and type(get) == "function" then
        local ok, cf = pcall(get, dock)
        if ok and type(cf) == "table" then return cf end
    end
    return Global("ChatFrame1")
end

-- ---------------------------------------------------------------- the window
local win

local function SetStatus()
    local lines, secret = win.shown or 0, win.secret or 0
    if secret > 0 then
        win.status:SetText(L["%d lines · %d lines protected by the game · Ctrl+C to copy"]:format(lines, secret))
    else
        win.status:SetText(L["%d lines · Ctrl+C to copy"]:format(lines))
    end
end

-- focus, select everything, newest line in view (EllesmereUI's behaviour)
local function SelectAll(keepFocus)
    local eb = win.edit
    if not keepFocus then eb:SetFocus() end
    eb:SetCursorPosition(#(win.full or ""))
    eb:HighlightText()
    local sb = win.box.GetScrollBox and win.box:GetScrollBox()
    if sb and sb.ScrollToEnd then pcall(sb.ScrollToEnd, sb, true) end
end

local function ApplyFont()
    win.edit:SetFont(EUI.Font(), Copy.Get("size"), "")
end

function Copy.Refresh(fromSearch)
    if not (win and win:IsShown() and win.cf) then return end
    local lines, secret = Copy.Lines(win.cf, win.search:GetText())
    win.shown, win.secret = #lines, secret
    win.full = table.concat(lines, "\n")
    ApplyFont()
    win.box:SetText(win.full)
    SetStatus()
    -- after the layout pass: the text has its height, the selection covers it all
    C_Timer.After(0.05, function()
        if win:IsShown() then SelectAll(fromSearch) end
    end)
end

local function BuildWindow()
    win = UI.Window("EUITweaksChatCopy", 720, 500, L["Copy chat"])

    win.search = UI.Edit(win, 200, 24, L["Search"])
    win.search:SetPoint("TOPLEFT", 14, -40)
    win.search:SetScript("OnTextChanged", function(self, user)
        self.hint:SetShown((self:GetText() or "") == "")
        if user then Copy.Refresh(true) end
    end)
    win.search:SetScript("OnEnterPressed", function() SelectAll() end)

    win.timeCheck = UI.Check(win, L["Timestamps"], function() return Copy.Get("time") end,
        function(v) Copy.Store().time = v Copy.Refresh() end)
    win.timeCheck:SetPoint("LEFT", win.search, "RIGHT", 14, 0)
    win.colorCheck = UI.Check(win, L["Channel colors"], function() return Copy.Get("colors") end,
        function(v) Copy.Store().colors = v Copy.Refresh() end)
    win.colorCheck:SetPoint("LEFT", win.timeCheck, "RIGHT", 12, 0)

    win.sizeSlider = UI.Slider(win, 90, 9, 24, 1, function() return Copy.Get("size") end, function(v)
        Copy.Store().size = v
        ApplyFont()
    end)
    win.sizeSlider:SetPoint("TOPRIGHT", -40, -46)
    win.sizeLabel = UI.Text(win, 11, UI.DIM)
    win.sizeLabel:SetPoint("RIGHT", win.sizeSlider, "LEFT", -8, 0)
    win.sizeLabel:SetText(L["Font size"])

    -- Blizzard's scrolling edit box (EllesmereUI uses the same template for its popup)
    local area = CreateFrame("Frame", nil, win)
    area:SetPoint("TOPLEFT", 14, -76)
    area:SetPoint("BOTTOMRIGHT", -14, 30)
    UI.Skin(area, { 0, 0, 0 }, 0.35, { 1, 1, 1, 0.1 })
    win.box = CreateFrame("Frame", nil, area, "ScrollingEditBoxTemplate")
    win.box:SetPoint("TOPLEFT", 6, -6)
    win.box:SetPoint("BOTTOMRIGHT", -6, 6)
    win.edit = win.box:GetEditBox()
    win.edit:SetTextColor(1, 1, 1, 0.9)
    -- read-only: typing puts the text back and selects it again
    win.edit:SetScript("OnChar", function(self)
        if win.full then
            self:SetText(win.full)
            self:HighlightText()
        end
    end)
    win.edit:SetScript("OnEscapePressed", function() win:Hide() end)

    win.status = UI.Text(win, 11, UI.DIM)
    win.status:SetPoint("BOTTOMLEFT", 16, 10)

    win:SetScript("OnShow", function()
        win.sizeSlider:Refresh()
        win.timeCheck:Refresh()
        win.colorCheck:Refresh()
    end)
    win:SetScript("OnHide", function() win.edit:ClearFocus() win.search:ClearFocus() end)
end

function Copy.Open(cf)
    if not active then return end
    if not win then BuildWindow() end   -- plain frames only: fine in combat too
    cf = cf or SelectedChat()
    if win:IsShown() and win.cf == cf then win:Hide() return end
    win.cf = cf
    win.title:SetText(L["Copy chat"] .. " - " .. FrameName(cf))
    win:Show()
    Copy.Refresh()
end

function Copy.Window() return win end

-- ---------------------------------------------------------------- the EllesmereUI button
local euiBtn, euiOrig

local function TakeEuiButton()
    local b = EUI.ChatCopyButton()
    if not b then return false end
    if euiBtn ~= b then
        euiBtn, euiOrig = b, b:GetScript("OnClick")
    end
    b:SetScript("OnClick", function() Copy.Open(SelectedChat()) end)
    return true
end

local function GiveBackEuiButton()
    if euiBtn and euiOrig then euiBtn:SetScript("OnClick", euiOrig) end
end

-- ---------------------------------------------------------------- fallback icons
local buttons = {}   -- chat window -> icon button
local watch

local function MakeButton(cf)
    local b = CreateFrame("Button", nil, cf)
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("LeftButtonUp")
    UI.Skin(b, UI.BG, 0.75, { 0, 0, 0, 0 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexture(Copy.TEXTURE)
    b:SetScript("OnClick", function() Copy.Open(cf) end)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(EUI.Accent())
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Copy chat"])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:Hide()
    end)
    buttons[cf] = b
    return b
end

local function LayoutIcon(cf, b)
    local size, corner = Copy.Get("iconSize"), Copy.Corner()
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint(corner, cf, corner, Copy.CORNERS[corner][1], Copy.CORNERS[corner][2])
    b:SetAlpha(Copy.Get("hover") and 0 or 0.9)
end

local function UpdateIcons(show)
    if show then
        local n = tonumber(Global("NUM_CHAT_WINDOWS")) or 10
        local i = 1
        while i <= n or Global("ChatFrame" .. i) do
            local cf = Global("ChatFrame" .. i)
            if type(cf) == "table" and type(cf.SetScript) == "function" then
                local b = buttons[cf] or MakeButton(cf)
                LayoutIcon(cf, b)
                b:Show()
            end
            i = i + 1
        end
        if not watch then
            watch = CreateFrame("Frame")
            local acc = 0
            watch:SetScript("OnUpdate", function(_, dt)
                acc = acc + dt
                if acc < 0.1 then return end
                acc = 0
                for cf, b in pairs(buttons) do
                    b:SetAlpha((b:IsMouseOver() or cf:IsMouseOver()) and 0.9 or 0)
                end
            end)
        end
        watch:SetShown(Copy.Get("hover"))
    else
        for _, b in pairs(buttons) do b:Hide() end
        if watch then watch:Hide() end
    end
end

-- true when the EllesmereUI button carries the window (no own icons needed)
function Copy.UsesEuiButton() return active and euiBtn ~= nil and EUI.ChatCopyButton() == euiBtn end

local function Update()
    if active then
        HookAll()
        local viaEui = TakeEuiButton()
        UpdateIcons(not viaEui)
    else
        GiveBackEuiButton()
        UpdateIcons(false)
        if win then win:Hide() end
    end
end

Copy.OnApply(function()
    active = Copy.Get("on")
    Update()
    -- EllesmereUI builds its sidebar a moment after login: look again
    if active and not euiBtn then C_Timer.After(2, function() if active then Update() end end) end
end)

for _, ev in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
    ns.RegisterEvent(ev, function() if active then Update() end end)
end

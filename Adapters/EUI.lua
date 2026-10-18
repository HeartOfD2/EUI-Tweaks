-- ---------------------------------------------------------------------------
-- Adapter: every access to EllesmereUI (and the EverFrame conflict checks)
-- lives in this file. The rest of the addon asks ns.EUI only. Each access is
-- checked and falls back quietly, so an EllesmereUI update breaks at most one
-- function here instead of the whole addon.
-- Checked against EllesmereUI 9.6.
-- ---------------------------------------------------------------------------
local _, ns = ...
local EUI = {}
ns.EUI = EUI

local FALLBACK_ACCENT = { 0.161, 0.741, 0.675 }

local function Lib() local e = rawget(_G, "EllesmereUI") return type(e) == "table" and e or nil end
local function Fn(t, key) return t and type(t[key]) == "function" and t[key] or nil end

local function Loaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end
EUI.Loaded = Loaded

-- ---------------------------------------------------------------- accent and font
function EUI.Accent()
    local get = Fn(Lib(), "GetAccentColor")
    if get then
        local ok, r, g, b = pcall(get)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3]
end

local accentListeners, accentHooked = {}, false
-- fn() runs whenever the EllesmereUI accent changes
function EUI.OnAccent(fn)
    accentListeners[#accentListeners + 1] = fn
    if accentHooked then return end
    local reg = Fn(Lib(), "RegAccent")
    if not reg then return end
    accentHooked = true
    pcall(reg, { type = "callback", fn = function()
        for i = 1, #accentListeners do pcall(accentListeners[i]) end
    end })
end

function EUI.Font()
    local get = Fn(Lib(), "GetFontPath")
    if get then
        local ok, path = pcall(get)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    local e = Lib()
    return (e and type(e.EXPRESSWAY) == "string" and e.EXPRESSWAY) or STANDARD_TEXT_FONT
end

-- ---------------------------------------------------------------- options panel
function EUI.RegisterPlugin(id, spec)
    local reg = Fn(Lib(), "RegisterPlugin")
    if not reg then return false end
    local ok, res = pcall(reg, id, spec)
    return ok and res and true or false
end

function EUI.Widgets() local e = Lib() return e and e.Widgets end

function EUI.IsSearchPrebuild()
    local fn = Fn(Lib(), "IsSearchPrebuild")
    if not fn then return false end
    local ok, v = pcall(fn)
    return ok and v and true or false
end

-- repaint the visible page (fast path: widgets re-read their values; force: rebuild)
function EUI.RefreshPage(force)
    local e = Lib()
    if not (e and type(e.RefreshPage) == "function") then return end
    pcall(e.RefreshPage, e, force)
end

function EUI.ContentPad()
    local e = Lib()
    return (e and type(e.CONTENT_PAD) == "number") and e.CONTENT_PAD or 45
end

function EUI.PanelShown()
    local f = rawget(_G, "EllesmereUIFrame")
    return type(f) == "table" and f.IsShown and f:IsShown() or false
end

-- ---------------------------------------------------------------- chat
function EUI.ChatActive()
    return Loaded("EllesmereUIChat") and type(rawget(_G, "_ECHAT_DB")) == "table"
end

-- the chat settings of the active EllesmereUI profile (nil without EUI Chat)
function EUI.ChatStore()
    if not EUI.ChatActive() then return nil end
    local db = rawget(_G, "_ECHAT_DB")
    local p = type(db.profile) == "table" and db.profile or nil
    return p and type(p.chat) == "table" and p.chat or nil
end

function EUI.RequestVisibilityUpdate()
    local fn = Fn(Lib(), "RequestVisibilityUpdate")
    if fn then pcall(fn) end
end

-- EllesmereUI's per-chat-frame data (sidebar buttons, background ...); internal, read only
local function ChatData(cf)
    local fn = Fn(Lib(), "_chatCFD")
    if not (fn and cf) then return nil end
    local ok, d = pcall(fn, cf)
    return ok and type(d) == "table" and d or nil
end

-- the "Copy Chat" button of the EllesmereUI chat sidebar, if there is one
function EUI.ChatCopyButton()
    if not EUI.ChatActive() then return nil end
    local d = ChatData(rawget(_G, "ChatFrame1"))
    local b = d and d.copyBtn
    if type(b) == "table" and type(b.GetScript) == "function" then return b end
    return nil
end

-- ---------------------------------------------------------------- minimap zone text
-- EllesmereUI Minimap draws the zone name as an unnamed backdrop box on the
-- minimap ("Interface\\ChatFrame\\ChatFrameBackground", text = zone or sub zone).
-- Returns the box and its font string, or nil while it does not exist.
local function TextOf(region)
    local ok, t = pcall(region.GetText, region)
    return ok and type(t) == "string" and not ns.IsSecret(t) and t or nil
end

function EUI.ZoneTextBox()
    if not Loaded("EllesmereUIMinimap") then return nil end
    local map = rawget(_G, "Minimap")
    if type(map) ~= "table" or type(map.GetChildren) ~= "function" then return nil end
    local zone = type(GetZoneText) == "function" and GetZoneText() or nil
    local sub = type(GetSubZoneText) == "function" and GetSubZoneText() or nil
    for _, child in ipairs({ map:GetChildren() }) do
        local info = child.backdropInfo
        if type(child.GetBackdropColor) == "function" and type(info) == "table"
            and info.bgFile == "Interface\\ChatFrame\\ChatFrameBackground" and child ~= ns.zoneSubBox then
            for _, region in ipairs({ child:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "FontString" then
                    local t = TextOf(region)
                    if t and t ~= "" and (t == zone or t == sub) then return child, region end
                end
            end
        end
    end
    return nil
end

-- EllesmereUI Minimap settings of the active profile (EllesmereUIDB.profiles[<active>]
-- .addons.EllesmereUIMinimap.minimap), nil when there are none yet
function EUI.MinimapSettings()
    local db = rawget(_G, "EllesmereUIDB")
    local name = EUI.ActiveProfileName()
    local p = type(db) == "table" and type(db.profiles) == "table" and name and db.profiles[name]
    local addons = type(p) == "table" and p.addons
    local mm = type(addons) == "table" and addons.EllesmereUIMinimap
    return type(mm) == "table" and type(mm.minimap) == "table" and mm.minimap or nil
end

-- makes EllesmereUI write its zone text again (its box updates on the zone events)
function EUI.RefreshZoneText(box)
    local fn = box and box.GetScript and box:GetScript("OnEvent")
    if fn then pcall(fn, box, "ZONE_CHANGED") end
end

-- ---------------------------------------------------------------- macro icon picker
-- The popup EllesmereUI builds for "Choose Icon" (Forever Essentials > Macros):
-- BuildPopupShell("EUIMacroIconPicker") makes the globals <name>Dimmer / <name>Popup.
function EUI.IconPicker()
    local dimmer, popup = rawget(_G, "EUIMacroIconPickerDimmer"), rawget(_G, "EUIMacroIconPickerPopup")
    if type(dimmer) == "table" and type(popup) == "table" then return dimmer, popup end
    return nil
end

-- one of the picker's own icon buttons: clicking it with a value picks that value
-- through EllesmereUI's own code (close the popup, hand the icon to the macro)
function EUI.IconPickerCell(popup)
    for _, child in ipairs({ popup:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button" and child.plus ~= nil
            and child.GetScript and child:GetScript("OnClick") then
            return child
        end
    end
    return nil
end

-- ---------------------------------------------------------------- saved data (ColorRewrite)
function EUI.ActiveProfileName()
    local fn = Fn(Lib(), "GetActiveProfileName")
    if fn then
        local ok, name = pcall(fn)
        if ok and type(name) == "string" then return name end
    end
    local db = rawget(_G, "EllesmereUIDB")
    return type(db) == "table" and type(db.activeProfile) == "string" and db.activeProfile or nil
end

-- the global tables EllesmereUI saves: { name, table }, EllesmereUIDB first
function EUI.SavedTables()
    local out = {}
    local main = rawget(_G, "EllesmereUIDB")
    if type(main) == "table" then out[1] = { "EllesmereUIDB", main } end
    local names = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and name ~= "EllesmereUIDB"
            and name:match("^EllesmereUI%w*DB$") then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do out[#out + 1] = { name, _G[name] } end
    return out
end

-- ---------------------------------------------------------------- EverFrame (same functions twice)
local function EverFrameButtonOn(cf, needle)
    if type(cf) ~= "table" or type(cf.GetChildren) ~= "function" then return false end
    for _, child in ipairs({ cf:GetChildren() }) do
        if child.icon and child.icon.GetTexture and child:IsShown() then
            local ok, tex = pcall(child.icon.GetTexture, child.icon)
            if ok and type(tex) == "string" and tex:find(needle, 1, true) then return true end
        end
    end
    return false
end

-- true when EverFrame runs the same function right now
function EUI.EverFrameHas(feature)
    if not Loaded("EverFrame") then return false end
    if feature == "camera" then
        -- EverFrame's fast zoom binds the zoom keys to its button while it is on
        if type(GetBindingKey) ~= "function" or type(GetBindingAction) ~= "function" then return false end
        for _, key in ipairs({ GetBindingKey("CAMERAZOOMIN") }) do
            local ok, action = pcall(GetBindingAction, key, true)
            if ok and type(action) == "string" and action:find("EverFrameZoom", 1, true) then return true end
        end
        return false
    elseif feature == "chathide" then
        local b = rawget(_G, "EverFrameChatButton")
        return type(b) == "table" and b.IsShown and b:IsShown() or false
    elseif feature == "chatcopy" then
        return EverFrameButtonOn(rawget(_G, "ChatFrame1"), "EverFrame\\Media\\ChatCopy")
    end
    return false
end

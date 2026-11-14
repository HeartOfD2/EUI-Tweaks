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

function EUI.MinimapLoaded() return Loaded("EllesmereUIMinimap") end

-- EllesmereUI's language setting (General > Language): a locale such as "deDE", or nil for none / "auto"
function EUI.DisplayLocale()
    local db = rawget(_G, "EllesmereUIDB")
    local v = type(db) == "table" and db.displayLocale or nil
    if type(v) == "string" and v ~= "" and v ~= "auto" then return v end
    return nil
end

-- opens our page in the EllesmereUI window; true when it opened
function EUI.OpenPlugin(id, moduleKey)
    local e = Lib()
    local fn = Fn(e, "OpenPlugin")
    if not fn then return false end
    local ok, opened = pcall(fn, id, moduleKey)
    return ok and opened and true or false
end

-- the saved-variable roots (see SavedTables): the main one holds the profiles
local MAIN_ROOT = "EllesmereUIDB"
function EUI.IsMainRoot(name) return name == MAIN_ROOT end
-- "EllesmereUIMinimapDB" -> "Minimap"
function EUI.RootLabel(name) return (name:gsub("^EllesmereUI", ""):gsub("DB$", "")) end

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

-- the chat settings a named EllesmereUI profile holds (EllesmereUIDB.profiles[<name>].addons.EllesmereUIChat.chat),
-- also while another profile is active; nil when there are none
function EUI.ChatStoreOf(profileName)
    local db = rawget(_G, "EllesmereUIDB")
    local p = type(db) == "table" and type(db.profiles) == "table" and profileName and db.profiles[profileName]
    local addons = type(p) == "table" and p.addons
    local c = type(addons) == "table" and addons.EllesmereUIChat
    return type(c) == "table" and type(c.chat) == "table" and c.chat or nil
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

-- The panels EllesmereUI Chat draws around the chat: the background and the sidebar of ChatFrame1, and the
-- frames it hangs on them (tab strip with the channel tabs, the background above the tabs, the border). They
-- fade out over a second on their own; hiding them lets the chat vanish at once. They are unnamed frames in
-- EllesmereUI's own namespace, so they are found by their anchors: every frame anchored to the chat background,
-- the sidebar or the chat dock. Returns the list and the set of frames found by anchor (EllesmereUI shows those
-- again on its own, so Hide() does not hold: the caller parks them out of sight instead).
-- Internal, read only; empty without EUI Chat.
-- other addons' frames (the aura buttons, for one) can answer with secret values: such a frame is skipped
local function AnchoredTo(f, targets)
    local ok, found = pcall(function()
        local n = f:GetNumPoints()
        if type(n) ~= "number" or ns.IsSecret(n) then return false end
        for i = 1, n do
            local _, rel = f:GetPoint(i)
            if rel and not ns.IsSecret(rel) and targets[rel] then return true end
        end
        return false
    end)
    return ok and found
end

function EUI.ChatPanels()
    local out, found = {}, {}
    if not EUI.ChatActive() then return out, found end
    local targets = {}
    local dock = rawget(_G, "GeneralDockManager")
    if type(dock) == "table" then targets[dock] = true end
    for i = 1, 10 do
        local d = ChatData(rawget(_G, "ChatFrame" .. i))
        if d then
            for _, key in ipairs(i == 1 and { "bg", "sidebar", "scrollBtn" } or { "bg" }) do
                local f = d[key]
                if type(f) == "table" and type(f.Hide) == "function" then
                    out[#out + 1] = f
                    if key ~= "scrollBtn" then targets[f] = true end
                end
            end
        end
    end
    if type(EnumerateFrames) == "function" then
        local f = EnumerateFrames()
        while f do
            if f ~= UIParent and not targets[f] and type(f.Hide) == "function" and AnchoredTo(f, targets) then
                local okProt, protected = pcall(f.IsProtected, f)
                if okProt and not protected then
                    out[#out + 1] = f
                    -- the game's own frames (the dock's overflow button ...) have names and read their parent: never moved
                    if not f:GetName() then found[f] = true end
                end
            end
            f = EnumerateFrames(f)
        end
    end
    return out, found
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
function EUI.MinimapSettings(profileName)
    local db = rawget(_G, "EllesmereUIDB")
    local name = profileName or EUI.ActiveProfileName()
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

-- ---------------------------------------------------------------- Shifter (Quality of Life)
-- EllesmereUI's Shifter saves a moved window by its frame name in EllesmereUIDB.shifterPositions
-- and its zoom in EllesmereUIDB.shifterScales. "Reset Specific Window" clears both entries and
-- reloads; the window takes its default place on the new load (checked against EllesmereUI 9.7.2).
local function ShifterTables()
    local db = rawget(_G, "EllesmereUIDB")
    if type(db) ~= "table" then return nil, nil end
    local p, s = db.shifterPositions, db.shifterScales
    return type(p) == "table" and p or nil, type(s) == "table" and s or nil
end

function EUI.ShifterOn()
    local db = rawget(_G, "EllesmereUIDB")
    return type(db) == "table" and db.shifterEnabled == true
end

-- set of frame names with a saved position or zoom
function EUI.ShifterSaved()
    local out = {}
    local p, s = ShifterTables()
    for name in pairs(p or {}) do if type(name) == "string" then out[name] = true end end
    for name in pairs(s or {}) do if type(name) == "string" then out[name] = true end end
    return out
end

function EUI.ShifterForget(name)
    local p, s = ShifterTables()
    if p then p[name] = nil end
    if s then s[name] = nil end
end

-- EllesmereUI's confirm popup. With reload = true its confirm click asks for the reload first
-- and runs onConfirm after it (WoW Forever reloads only from a click or a key press, and only
-- when the reload comes first). Fallback: a Blizzard popup that does the same.
function EUI.ConfirmReload(title, message, confirmText, onConfirm)
    local e = Lib()
    if e and type(e.ShowConfirmPopup) == "function" then
        local ok = pcall(e.ShowConfirmPopup, e, { title = title, message = message, confirmText = confirmText,
            cancelText = CANCEL, reload = true, onConfirm = function() onConfirm() end })
        if ok then return end
    end
    StaticPopupDialogs.EUITWEAKS_CONFIRM_RELOAD = {
        text = message, button1 = confirmText, button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            ReloadUI()
            onConfirm()
        end,
    }
    StaticPopup_Show("EUITWEAKS_CONFIRM_RELOAD")
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

-- EllesmereUI switches profiles live and announces nothing we may listen to (hooking its functions is not
-- allowed), so the name is compared once a second. The timer starts with the first caller: a module that is
-- off never asks. fn(newName, oldName) runs after a change.
local profileWatchers, profileSeen, profileTicker = {}, nil, nil
function EUI.OnProfileChange(fn)
    profileWatchers[#profileWatchers + 1] = fn
    if profileTicker then return end
    profileSeen = EUI.ActiveProfileName()
    profileTicker = C_Timer.NewTicker(1, function()
        local now = EUI.ActiveProfileName()
        if now == profileSeen then return end
        local old = profileSeen
        profileSeen = now
        for i = 1, #profileWatchers do pcall(profileWatchers[i], now, old) end
    end)
end

-- the global tables EllesmereUI saves: { name, table }, EllesmereUIDB first
function EUI.SavedTables()
    local out = {}
    local main = rawget(_G, MAIN_ROOT)
    if type(main) == "table" then out[1] = { MAIN_ROOT, main } end
    local names = {}
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and name ~= MAIN_ROOT
            and name:match("^EllesmereUI%w*DB$") then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do out[#out + 1] = { name, _G[name] } end
    return out
end

-- ---------------------------------------------------------------- BeautifulRogue (same functions twice)
-- BeautifulRogue was called EverFrame up to 1.0; both names are checked (frame names follow the addon name).
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

local function RogueHas(name, feature)
    if not Loaded(name) then return false end
    if feature == "camera" then
        -- the fast zoom binds the zoom keys to its button while it is on
        if type(GetBindingKey) ~= "function" or type(GetBindingAction) ~= "function" then return false end
        for _, key in ipairs({ GetBindingKey("CAMERAZOOMIN") }) do
            local ok, action = pcall(GetBindingAction, key, true)
            if ok and type(action) == "string" and action:find(name .. "Zoom", 1, true) then return true end
        end
        return false
    elseif feature == "chathide" then
        local b = rawget(_G, name .. "ChatButton")
        return type(b) == "table" and b.IsShown and b:IsShown() or false
    elseif feature == "chatcopy" then
        return EverFrameButtonOn(rawget(_G, "ChatFrame1"), name .. "\\Media\\ChatCopy")
    end
    return false
end

-- true when BeautifulRogue (or the old EverFrame) runs the same function right now
function EUI.EverFrameHas(feature)
    return RogueHas("BeautifulRogue", feature) or RogueHas("EverFrame", feature)
end

-- ---------------------------------------------------------------------------
-- Core: namespace, saved variables with defaults, event dispatch, small
-- helpers, slash command and the addon compartment entry.
-- Every module keeps its settings in its own sub-table of EUITweaksDB and
-- registers an Apply function; Apply runs after login and after each change.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local L = ns.L

ns.ADDON = addonName
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
ns.PLUGIN_ID = "EUITweaks"

-- ---------------------------------------------------------------- helpers
function ns.IsSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

function ns.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- lower case for ASCII, German umlauts and Cyrillic, so searches ignore case in every client language
function ns.Fold(s)
    s = (s or ""):gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
    s = s:gsub("\195([\128-\158])", function(c) return "\195" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    return s
end

function ns.Clamp(v, lo, hi)
    if type(v) ~= "number" or v ~= v then return lo end
    return math.max(lo, math.min(hi, v))
end

function ns.Say(text)
    local chat = DEFAULT_CHAT_FRAME
    if chat then chat:AddMessage("|cff29bdac[EUI Tweaks]|r " .. tostring(text)) end
end

-- ---------------------------------------------------------------- events
local frame = CreateFrame("Frame")
local handlers = {}

function ns.RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end)

-- internal messages between modules (no game event)
local listeners = {}
function ns.On(msg, fn)
    listeners[msg] = listeners[msg] or {}
    local list = listeners[msg]
    list[#list + 1] = fn
end

function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

-- ---------------------------------------------------------------- settings
-- Each module declares its defaults; a value that does not fit the default's
-- type (or its range) reads as the default.
local modules = {}   -- key -> { defaults, ranges, apply }
local order = {}

function ns.Module(key, defaults, ranges)
    local m = { key = key, defaults = defaults or {}, ranges = ranges or {}, appliers = {} }
    modules[key] = m
    order[#order + 1] = m

    function m.Store()
        local db = ns.db
        if not db then return {} end
        if type(db[key]) ~= "table" then db[key] = {} end
        return db[key]
    end

    function m.Get(k)
        local d = m.defaults[k]
        local v = m.Store()[k]
        if type(d) == "number" then
            if type(v) ~= "number" or v ~= v then return d end
            local r = m.ranges[k]
            return r and ns.Clamp(v, r[1], r[2]) or v
        end
        if d == nil then return v end
        if type(v) ~= type(d) then return d end
        return v
    end

    function m.Set(k, v)
        m.Store()[k] = v
        m.Apply()
    end

    function m.Reset()
        if ns.db then ns.db[key] = nil end
        m.Apply()
    end

    function m.OnApply(fn) m.appliers[#m.appliers + 1] = fn end

    function m.Apply()
        if not ns.ready then return end
        for i = 1, #m.appliers do m.appliers[i]() end
    end

    return m
end

function ns.ApplyAll()
    for _, m in ipairs(order) do m.Apply() end
end

ns.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    if type(EUITweaksDB) ~= "table" then EUITweaksDB = {} end
    ns.db = EUITweaksDB
    ns.Fire("DB_READY")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.ready = true
    ns.Fire("LOGIN")
    ns.ApplyAll()
end)

-- ---------------------------------------------------------------- combat queue
local pending = {}
function ns.AfterCombat(fn)
    if InCombatLockdown() then pending[#pending + 1] = fn else fn() end
end
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local list = pending
    pending = {}
    for i = 1, #list do list[i]() end
end)

-- ---------------------------------------------------------------- opening the options
function ns.OpenOptions(moduleKey)
    if InCombatLockdown() then
        ns.Say(L["The options open after combat."])
        return
    end
    local eui = rawget(_G, "EllesmereUI")
    if type(eui) == "table" and type(eui.OpenPlugin) == "function" then
        local ok, opened = pcall(eui.OpenPlugin, ns.PLUGIN_ID, moduleKey)
        if ok and opened then return end
    end
    ns.Say(L["The EllesmereUI options could not be opened."])
end

SLASH_EUITWEAKS1 = "/euitweaks"
SLASH_EUITWEAKS2 = "/eut"
SlashCmdList.EUITWEAKS = function(msg)
    local cmd = ns.Trim(msg):lower()
    if cmd == "camera" then ns.OpenOptions("Tweaks")
    elseif cmd == "icons" then ns.OpenOptions("Extensions")
    elseif cmd == "colors" then ns.OpenOptions("ColorRewrite")
    elseif cmd == "copy" and ns.ChatCopy then ns.ChatCopy.Open(DEFAULT_CHAT_FRAME)
    else ns.OpenOptions() end
end

-- compartment callbacks are globals named in the TOC
function EUITweaks_OnCompartmentClick() ns.OpenOptions() end

function EUITweaks_OnCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("EUI Tweaks")
    GameTooltip:AddLine(L["Click: open the options"], 1, 1, 1)
    GameTooltip:Show()
end

function EUITweaks_OnCompartmentLeave() GameTooltip:Hide() end

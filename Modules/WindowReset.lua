-- ---------------------------------------------------------------------------
-- Tweaks > Window reset: a key (game key bindings > AddOns > EUI Tweaks, see
-- Bindings.xml) that resets the window under the mouse to its default position
-- and zoom, like "Reset Specific Window" of EllesmereUI's Shifter (Quality of
-- Life > Shifter). EllesmereUI places a window back only on a new load, so the
-- key reloads the UI: after EllesmereUI's confirm popup, or at once when
-- "without asking" is on. Nothing is hooked; while the switch is off the key
-- only says so.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, EUI = ns.L, ns.EUI

local Reset = ns.Module("windowreset", { on = false, noAsk = false })
ns.WindowReset = Reset

Reset.BINDING = "EUITWEAKS_RESETWINDOW"
BINDING_HEADER_EUITWEAKS = "EUI Tweaks"
-- the name needs the chosen language: set once the saved variables are there
ns.On("DB_READY", function()
    _G["BINDING_NAME_" .. Reset.BINDING] = L["Reset the window under the mouse"]
end)

-- the name EllesmereUI's list shows: "CharacterFrame" -> "Character", "AuctionHouseFrame" -> "Auction House"
function Reset.Pretty(name)
    local pretty = name:gsub("Frame$", "")
    pretty = pretty:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    return pretty
end

-- a frame method that may fail (forbidden frame) or answer a secret: nil then
local function Call(obj, method)
    local ok, v = pcall(function() return obj[method](obj) end)
    if ok and not ns.IsSecret(v) then return v end
    return nil
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8 }

local function MouseFoci()
    local get = rawget(_G, "GetMouseFoci")
    if type(get) ~= "function" then return {} end
    local ok, r = pcall(get)
    if not ok or type(r) ~= "table" then return {} end
    if r.GetObjectType then return { r } end   -- a single region instead of a list
    return r
end

-- the saved window the mouse is on: up the parents of what the mouse points at;
-- else the topmost visible saved window under the cursor (for a child that
-- takes no mouse or a tab laid over its window)
function Reset.Hovered()
    local saved = EUI.ShifterSaved()
    if not next(saved) then return nil end
    for _, f in ipairs(MouseFoci()) do
        local depth = 0
        while f and depth < 40 do
            local name = Call(f, "GetName")
            if type(name) == "string" and saved[name] then return name end
            f = Call(f, "GetParent")
            depth = depth + 1
        end
    end
    local best, bestRank
    for name in pairs(saved) do
        local f = rawget(_G, name)
        if type(f) == "table" and Call(f, "IsVisible") and Call(f, "IsMouseOver") then
            local level = Call(f, "GetFrameLevel")
            local rank = (STRATA[Call(f, "GetFrameStrata") or ""] or 0) * 100000 + (type(level) == "number" and level or 0)
            if not bestRank or rank > bestRank then best, bestRank = name, rank end
        end
    end
    return best
end

-- the key set in the game's key bindings, as the game writes it; nil without one
function Reset.KeyText()
    local key = GetBindingKey(Reset.BINDING)
    if type(key) ~= "string" or key == "" then return nil end
    local text = type(GetBindingText) == "function" and GetBindingText(key) or nil
    return type(text) == "string" and text ~= "" and text or key
end

function Reset.Run()
    if not Reset.Get("on") then
        ns.Say(L["Window reset is off: turn it on under Tweaks+ > Tweaks > Window reset."])
        return
    end
    local name = Reset.Hovered()
    if not name then
        ns.Say(L["No window under the mouse with a position or zoom saved by EllesmereUI's Shifter."])
        return
    end
    local function Forget() EUI.ShifterForget(name) end
    if Reset.Get("noAsk") then
        -- reload first: WoW Forever refuses a reload asked for late in the key press
        ReloadUI()
        Forget()
        return
    end
    EUI.ConfirmReload(L["Reset window"],
        L["Reset %s to its default position and zoom and reload the UI?"]:format(Reset.Pretty(name)),
        L["Reset"], Forget)
end

-- called by the key binding (Bindings.xml)
function EUITweaks_ResetHoveredWindow() Reset.Run() end

-- ---------------------------------------------------------------------------
-- Tweaks > Camera: fast zoom (ported from EverFrame). While the switch is on,
-- CameraZoomIn/Out are replaced: the mouse wheel moves a target distance, the
-- step grows while the wheel keeps turning, and the camera follows along the
-- chosen curve within the chosen zoom time (MoveViewIn/OutStart). Off: the
-- originals and the key bindings are put back. Nothing is touched before.
-- The wheel does not call the Lua globals on this client, so the keys bound to
-- the zoom actions are overridden to click two buttons as well.
-- ---------------------------------------------------------------------------
local _, ns = ...

local Camera = ns.Module("camera",
    { on = false, base = 1.5, accel = 0.8, speed = 0.8, curve = "direct" },
    { base = { 0.25, 5, 0.25 }, accel = { 0, 2, 0.1 }, speed = { 0, 1, 0.05 } })
ns.Camera = Camera

Camera.CURVES = { soft = true, direct = true }

local STREAK_GAP = 0.3       -- seconds without a notch end a fast turn
local MAX_FACTOR = 10        -- the step never grows beyond this multiple of the base step
local DEFAULT_SPEED = 20     -- the game's own cameraZoomSpeed
local ZOOM_PER_FACTOR = 15   -- largest distance at cameraDistanceMaxZoomFactor 1

local function Curve()
    local c = Camera.Get("curve")
    return Camera.CURVES[c] and c or "direct"
end

local origIn, origOut, ourIn, ourOut
local driver
local target, t0, from, change, duration, lastDir = 0, 0, 0, 0, 0, 0
local lastNotch, streak = -10, 0
local moving = false

local function MaxDistance()
    local f = tonumber(GetCVar("cameraDistanceMaxZoomFactor")) or 1
    return ZOOM_PER_FACTOR * f
end

-- seconds the camera may need for the whole way: speed 0 = 1 s, speed 1 = 0.05 s
local function ZoomTime() return 1 - Camera.Get("speed") * 0.95 end

local CURVES = {
    soft   = function(t, b, c, d) return c * t / d + b end,                    -- linear
    direct = function(t, b, c, d) t = t / d return -c * t * (t - 2) + b end,   -- out quad
}

local function ZoomSpeed()
    local zs = tonumber(GetCVar("cameraZoomSpeed")) or DEFAULT_SPEED
    return zs > 0 and zs or DEFAULT_SPEED
end

local function StopMove()
    lastDir = 0
    if type(MoveViewOutStart) ~= "function" then return end
    pcall(MoveViewOutStart, 0)
    pcall(MoveViewInStart, 0)
    pcall(MoveViewInStop)
    pcall(MoveViewOutStop)
end

local function Stop()
    moving = false
    StopMove()
    if driver then driver:Hide() end
end

local function Finish()
    local rest = target - GetCameraZoom()
    Stop()
    if math.abs(rest) > 0.05 then   -- missed the target: the client's own zoom closes the gap
        if rest < 0 then pcall(origIn, -rest) else pcall(origOut, rest) end
    end
end

local function Step(_, dt)
    local now = GetTime()
    local zoom = GetCameraZoom()
    local t = now - t0
    if t >= duration or (change > 0 and zoom >= target) or (change < 0 and zoom <= target) then
        Finish()
        return
    end
    dt = math.max(dt, 1 / 120)
    local ahead = CURVES[Curve()]
    local speed = (ahead(math.min(t + dt, duration), from, change, duration) - zoom) / dt
    local zs = ZoomSpeed()
    local dir = speed > 0 and 1 or speed < 0 and -1 or 0
    if dir ~= lastDir then StopMove() end
    lastDir = dir
    if dir > 0 then MoveViewOutStart(speed / zs) elseif dir < 0 then MoveViewInStart(-speed / zs) end
end

-- one wheel notch (or a macro call): dir -1 = closer, +1 = further away
local function Notch(dir, increments)
    if not driver then return end
    local now = GetTime()
    local zoom = GetCameraZoom()
    if not moving then target = zoom end
    if now - lastNotch > STREAK_GAP then streak = 0 end
    lastNotch = now
    local factor = math.min(1 + Camera.Get("accel") * streak, MAX_FACTOR)
    streak = streak + 1
    local step = Camera.Get("base") * factor * (tonumber(increments) or 1)
    target = math.max(0, math.min(math.max(MaxDistance(), zoom), target + dir * step))
    from, change, t0 = zoom, target - zoom, now
    duration = math.min(ZoomTime(), math.abs(change) / ZoomSpeed())
    if type(MoveViewOutStart) ~= "function" or duration < 1 / 60 then
        -- too short to follow a curve: one step of the client
        Stop()
        if change < 0 then pcall(origIn, -change) elseif change > 0 then pcall(origOut, change) end
        return
    end
    moving = true
    driver:Show()
end

-- ---------------------------------------------------------------- key bindings
local binder, bindPending

-- One press of a key sends a down and an up click, the wheel both in the same moment: only the
-- press counts. An up click with no down before it (a client that sends only that) counts once.
local function Click(dir)
    local pressed = false
    return function(_, _, down)
        if down == false then
            if pressed then pressed = false return end   -- the release of a press that was counted
        else
            pressed = true
        end
        Notch(dir, 1)
    end
end

local applied   -- the keys bound now ("KEY=button" list as text); nil while nothing is bound

local function OnEvent(_, event)
    if event == "UPDATE_BINDINGS" then
        -- the player changed the key bindings: follow them (only while the camera tweak is on)
        if Camera.Get("on") then Camera.Apply() end
        return
    end
    binder:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if bindPending then
        bindPending = false
        Camera.Apply()
    end
end

local function WantedBindings()
    local list = {}
    for action, name in pairs({ CAMERAZOOMIN = "EUITweaksZoomIn", CAMERAZOOMOUT = "EUITweaksZoomOut" }) do
        for _, key in ipairs({ GetBindingKey(action) }) do
            list[#list + 1] = key .. "=" .. name
        end
    end
    table.sort(list)
    return list
end

local function BindWheel()
    if type(SetOverrideBindingClick) ~= "function" or type(GetBindingKey) ~= "function" then return end
    if not binder then
        binder = CreateFrame("Frame")
        binder:SetScript("OnEvent", OnEvent)
        for dir, name in pairs({ [-1] = "EUITweaksZoomIn", [1] = "EUITweaksZoomOut" }) do
            local b = CreateFrame("Button", name, UIParent)
            b:RegisterForClicks("AnyDown", "AnyUp")
            b:SetScript("OnClick", Click(dir))
        end
    end
    binder:RegisterEvent("UPDATE_BINDINGS")
    if InCombatLockdown() then
        bindPending = true
        binder:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local wanted = WantedBindings()
    local signature = table.concat(wanted, ";")
    if signature == applied then return end   -- nothing changed: no need to touch the bindings
    ClearOverrideBindings(binder)
    for _, entry in ipairs(wanted) do
        local key, name = entry:match("^(.*)=([^=]+)$")
        SetOverrideBindingClick(binder, true, key, name, "LeftButton")
    end
    applied = signature
end

local function UnbindWheel()
    bindPending = false
    applied = nil
    if not binder then return end
    binder:UnregisterEvent("UPDATE_BINDINGS")
    if InCombatLockdown() then
        bindPending = true
        binder:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ClearOverrideBindings(binder)
    end
end

-- ---------------------------------------------------------------- install
local function Install()
    if ourIn then return end
    local zin, zout = rawget(_G, "CameraZoomIn"), rawget(_G, "CameraZoomOut")
    if type(zin) ~= "function" or type(zout) ~= "function" or type(GetCameraZoom) ~= "function" then return end
    origIn, origOut = zin, zout
    driver = driver or CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", Step)
    ourIn = function(increments) Notch(-1, increments) end
    ourOut = function(increments) Notch(1, increments) end
    _G.CameraZoomIn, _G.CameraZoomOut = ourIn, ourOut
end

local function Uninstall()
    if not ourIn then return end
    Stop()
    -- another addon may have replaced them after us: then it keeps its version
    if rawget(_G, "CameraZoomIn") == ourIn then _G.CameraZoomIn = origIn end
    if rawget(_G, "CameraZoomOut") == ourOut then _G.CameraZoomOut = origOut end
    origIn, origOut, ourIn, ourOut = nil, nil, nil, nil
end

function Camera.Owns() return ourIn ~= nil end

function Camera.ResetValues()
    local s = Camera.Store()
    s.base, s.accel, s.speed, s.curve = nil, nil, nil, nil
    Camera.Apply()
end

Camera.OnApply(function()
    if Camera.Get("on") then
        Install()
        BindWheel()
    else
        Uninstall()
        UnbindWheel()
    end
end)

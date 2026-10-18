-- ---------------------------------------------------------------------------
-- Options: the "Tweaks+" section in the EllesmereUI options panel, through the
-- official plugin API (EllesmereUI.RegisterPlugin). Rows are built with
-- EllesmereUI.Widgets so the EllesmereUI search finds them. Hints and the
-- ColorRewrite hit list are own frames and are skipped during the search's
-- hidden pre-build pass.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI, EUI = ns.L, ns.UI, ns.EUI
local Camera, ChatHide, ChatCopy, ZoneText = ns.Camera, ns.ChatHide, ns.ChatCopy, ns.ZoneText
local IconSearch, Rewrite = ns.IconSearch, ns.ColorRewrite

local PAGE_CAMERA, PAGE_HIDE, PAGE_COPY, PAGE_ZONE = L["Camera"], L["Hide chat"], L["Copy chat"], L["Zone text"]
local PAGE_ICONS = L["Icon search"]
local PAGE_COLORS = L["Replace colors"]

local function Refresh() EUI.RefreshPage() end
local function Rebuild() EUI.RefreshPage(true) end

-- a wrapped hint line under a row (own font string; not part of the search index)
local function Hint(parent, y, text, color)
    if EUI.IsSearchPrebuild() then return 0 end
    local pad = EUI.ContentPad()
    local fs = UI.Text(parent, 12, color or UI.DIM)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", pad + 20, y - 6)
    fs:SetWidth(parent:GetWidth() - 2 * pad - 40)
    fs:SetWordWrap(true)
    fs:SetText(text)
    return fs:GetStringHeight() + 14
end

local WARN = { 1, 0.6, 0.3, 1 }

local function Conflict(parent, y, feature)
    if EUI.IsSearchPrebuild() or not EUI.EverFrameHas(feature) then return 0 end
    return Hint(parent, y, L["This function is also on in EverFrame. Turn one of them off."], WARN)
end

-- ---------------------------------------------------------------- Tweaks > Camera
local function BuildCamera(W, parent, y)
    local _, h
    local function off() return not Camera.Get("on") end
    _, h = W:SectionHeader(parent, L["FAST ZOOM"], y); y = y - h
    _, h = W:Toggle(parent, L["Fast zoom"], y, function() return Camera.Get("on") end,
        function(v) Camera.Set("on", v) Refresh() end,
        L["Turn the mouse wheel quickly to cover much more distance; turn it slowly for small steps."]); y = y - h
    y = y - Conflict(parent, y, "camera")
    local r = Camera.ranges
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["Base step"], min = r.base[1], max = r.base[2], step = r.base[3],
          getValue = function() return Camera.Get("base") end, setValue = function(v) Camera.Set("base", v) end,
          disabled = off },
        { type = "slider", text = L["Acceleration"], min = r.accel[1], max = r.accel[2], step = r.accel[3],
          getValue = function() return Camera.Get("accel") end, setValue = function(v) Camera.Set("accel", v) end,
          disabled = off }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["Zoom speed (slow to fast)"], min = r.speed[1], max = r.speed[2], step = r.speed[3],
          getValue = function() return Camera.Get("speed") end, setValue = function(v) Camera.Set("speed", v) end,
          disabled = off },
        { type = "dropdown", text = L["Zoom curve"], values = { soft = L["Soft"], direct = L["Direct"] },
          order = { "soft", "direct" }, getValue = function() return Camera.Get("curve") end,
          setValue = function(v) Camera.Set("curve", v) end, disabled = off }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = L["Reset values"], width = 180, onClick = function() Camera.ResetValues() Refresh() end },
        { type = "label", text = "" }); y = y - h
    y = y - Hint(parent, y, L["Switching off puts the game's own zoom back; /reload leaves nothing of the change behind."])
    return y
end

-- ---------------------------------------------------------------- Tweaks > Hide chat
local function BuildHide(W, parent, y)
    local _, h
    local function off() return not ChatHide.Get("on") end
    _, h = W:SectionHeader(parent, L["HIDE CHAT"], y); y = y - h
    _, h = W:Toggle(parent, L["Hide chat button"], y, function() return ChatHide.Get("on") end,
        function(v) ChatHide.Set("on", v) Refresh() end); y = y - h
    y = y - Hint(parent, y, L["A button hides the chat windows, their tabs, the input box and the chat menu buttons (with EllesmereUI Chat also its background and sidebar). Enter, Edit Mode or a click bring them back."])
    y = y - Conflict(parent, y, "chathide")
    _, h = W:SectionHeader(parent, L["BUTTON"], y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = L["Lock button"], getValue = function() return ChatHide.Get("locked") end,
          setValue = function(v) ChatHide.Set("locked", v) end, disabled = off },
        { type = "dropdown", text = L["Quick place"],
          values = { BOTTOMLEFT = L["Bottom left"], BOTTOMRIGHT = L["Bottom right"] }, order = { "BOTTOMLEFT", "BOTTOMRIGHT" },
          getValue = function() return ChatHide.Corner() end,
          setValue = function(v) ChatHide.Store().pos = nil ChatHide.Set("corner", v) end, disabled = off }); y = y - h
    local r = ChatHide.ranges
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["Size"], min = r.size[1], max = r.size[2], step = 2,
          getValue = function() return ChatHide.Get("size") end, setValue = function(v) ChatHide.Set("size", v) end,
          disabled = off },
        { type = "slider", text = L["Opacity"], min = r.alpha[1], max = r.alpha[2], step = 0.05,
          getValue = function() return ChatHide.Get("alpha") end, setValue = function(v) ChatHide.Set("alpha", v) end,
          disabled = off }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "colorpicker", text = L["Button color"], getValue = function() return ChatHide.Color() end,
          setValue = function(cr, cg, cb) ChatHide.SetColor(cr, cg, cb) end, disabled = off },
        { type = "button", text = L["Use accent color"], width = 180,
          onClick = function() ChatHide.SetColor(nil) Refresh() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = L["Reset anchor"], width = 180, onClick = function() ChatHide.ResetAnchor() Refresh() end },
        { type = "label", text = "" }); y = y - h
    y = y - Hint(parent, y, L["Unlock the button to drag it anywhere. Without a picked color it follows the EllesmereUI accent."])
    return y
end

-- ---------------------------------------------------------------- Tweaks > Copy chat
local function BuildCopy(W, parent, y)
    local _, h
    local function off() return not ChatCopy.Get("on") end
    _, h = W:SectionHeader(parent, L["COPY CHAT"], y); y = y - h
    _, h = W:Toggle(parent, L["Better copy window"], y, function() return ChatCopy.Get("on") end,
        function(v) ChatCopy.Set("on", v) Refresh() end); y = y - h
    y = y - Hint(parent, y, L["EllesmereUI's Copy Chat button opens a window with search, timestamps and font size. On opening, all text is selected: Ctrl+C copies at once. Without EllesmereUI Chat a small icon on every chat window opens it. Lines the game protects are skipped and counted."])
    y = y - Conflict(parent, y, "chatcopy")
    _, h = W:SectionHeader(parent, L["WINDOW"], y); y = y - h
    local r = ChatCopy.ranges
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["Font size"], min = r.size[1], max = r.size[2], step = 1,
          getValue = function() return ChatCopy.Get("size") end, setValue = function(v) ChatCopy.Set("size", v) end,
          disabled = off },
        { type = "slider", text = L["Line limit"], min = r.limit[1], max = r.limit[2], step = 50,
          getValue = function() return ChatCopy.Get("limit") end, setValue = function(v) ChatCopy.Set("limit", v) end,
          disabled = off }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = L["Timestamps"], getValue = function() return ChatCopy.Get("time") end,
          setValue = function(v) ChatCopy.Set("time", v) end, disabled = off },
        { type = "toggle", text = L["Channel colors"], getValue = function() return ChatCopy.Get("colors") end,
          setValue = function(v) ChatCopy.Set("colors", v) end, disabled = off }); y = y - h
    y = y - Hint(parent, y, L["Timestamps count from switching on. For clean text when copying, turn the channel colors off."])
    _, h = W:SectionHeader(parent, L["ICON (WITHOUT ELLESMEREUI CHAT)"], y); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = L["Corner"],
          values = { TOPLEFT = L["Top left"], TOPRIGHT = L["Top right"], BOTTOMLEFT = L["Bottom left"], BOTTOMRIGHT = L["Bottom right"] },
          order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
          getValue = function() return ChatCopy.Corner() end, setValue = function(v) ChatCopy.Set("corner", v) end, disabled = off },
        { type = "toggle", text = L["Only on mouse over"], getValue = function() return ChatCopy.Get("hover") end,
          setValue = function(v) ChatCopy.Set("hover", v) end, disabled = off }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["Icon size"], min = r.iconSize[1], max = r.iconSize[2], step = 2,
          getValue = function() return ChatCopy.Get("iconSize") end, setValue = function(v) ChatCopy.Set("iconSize", v) end,
          disabled = off },
        { type = "button", text = L["Open copy window"], width = 180,
          onClick = function() ChatCopy.Open() end, disabled = off }); y = y - h
    return y
end

-- ---------------------------------------------------------------- Tweaks > Zone text
local function BuildZone(W, parent, y)
    local _, h
    local function off() return not ZoneText.Get("on") end
    local function Set(k, v) ZoneText.Set(k, v) end
    _, h = W:SectionHeader(parent, L["SUB ZONE"], y); y = y - h
    _, h = W:Toggle(parent, L["Show sub zone"], y, function() return ZoneText.Get("on") end,
        function(v) Set("on", v) Refresh() end); y = y - h
    y = y - Hint(parent, y, L["Shows the sub zone in a second box next to the EllesmereUI minimap zone text, in the same style. Switching on turns off EllesmereUI's own \"Display Sub Zone\" (Minimap > Zone Text Settings), so the zone box keeps the zone name; switching off turns it back on."])
    if not EUI.Loaded("EllesmereUIMinimap") then
        y = y - Hint(parent, y, L["EllesmereUI Minimap is not loaded: the box has nothing to attach to."], WARN)
    end
    local r = ZoneText.ranges
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = L["Position"], values = { below = L["Below the zone text"], above = L["Above the zone text"] },
          order = { "below", "above" }, getValue = function() return ZoneText.Side() end,
          setValue = function(v) Set("side", v) end, disabled = off },
        { type = "label", text = "" }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = L["X offset"], min = r.x[1], max = r.x[2], step = r.x[3],
          getValue = function() return ZoneText.Get("x") end, setValue = function(v) Set("x", v) end, disabled = off },
        { type = "slider", text = L["Y offset"], min = r.y[1], max = r.y[2], step = r.y[3],
          getValue = function() return ZoneText.Get("y") end, setValue = function(v) Set("y", v) end, disabled = off }); y = y - h
    return y
end

-- ---------------------------------------------------------------- Extensions > Icon search
local function IconDataInstalled()
    local exists = C_AddOns and C_AddOns.DoesAddOnExist
    if not exists then return true end
    local ok, v = pcall(exists, "EUITweaks_Icons")
    return not ok or v
end

local function BuildIcons(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, L["ICON SEARCH"], y); y = y - h
    _, h = W:Toggle(parent, L["Searchable icon picker"], y, function() return IconSearch.Get("on") end,
        function(v) IconSearch.Set("on", v) end); y = y - h
    y = y - Hint(parent, y, L["Adds a search line and a category filter to EllesmereUI's \"Choose Icon\" window (Forever Essentials > Macros). Search spell and item names, icon names or file IDs; the filter narrows by category (classes, weapons, armor, magic, professions ...). Empty search shows the normal list."])
    if not IconDataInstalled() then
        y = y - Hint(parent, y, L["The icon data (folder EUITweaks_Icons) is missing: only spell and item names can be searched, the filter is not available."], WARN)
    else
        y = y - Hint(parent, y, L["The icon data (EUITweaks_Icons, about 33,000 icons) loads only when the window opens for the first time."])
    end
    return y
end

-- ---------------------------------------------------------------- ColorRewrite
local SCOPE_VALUES = { active = L["Active profile and global settings"], all = L["All profiles"] }

local function Swatch(hex) return Rewrite.HexToRGB(hex) end

local function ConfirmAndReload(text, action)
    StaticPopupDialogs.EUITWEAKS_CONFIRM = {
        text = text, button1 = ACCEPT, button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local n = action()
            if n > 0 then ReloadUI() end
        end,
    }
    StaticPopup_Show("EUITWEAKS_CONFIRM")
end

local function HitList(parent, y)
    if EUI.IsSearchPrebuild() then return 0 end
    local hits = Rewrite.Hits()
    local pad = EUI.ContentPad()
    local width = parent:GetWidth() - 2 * pad
    local list = CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    list:SetWidth(width)
    local top = 8
    local head = UI.Text(list, 13)
    head:SetPoint("TOPLEFT", 20, -top)
    if not Rewrite.HitsCurrent() then
        head:SetText(L["Press \"Search\" to list the places that use the color."])
        list:SetHeight(top + 24)
        return top + 24
    end
    local on = 0
    for _, hit in ipairs(hits) do if hit.on then on = on + 1 end end
    head:SetText(L["%d places found, %d selected"]:format(#hits, on))
    local rowY = top + 24
    local MAX = 400
    for i, hit in ipairs(hits) do
        if i > MAX then
            local more = UI.Text(list, 12, UI.DIM)
            more:SetPoint("TOPLEFT", 20, -rowY)
            more:SetText(L["... and %d more (all are replaced when selected)"]:format(#hits - MAX))
            rowY = rowY + 22
            break
        end
        local c = UI.Check(list, Rewrite.Describe(hit), function() return hit.on end, function(v)
            hit.on = v
            local n = 0
            for _, x in ipairs(hits) do if x.on then n = n + 1 end end
            head:SetText(L["%d places found, %d selected"]:format(#hits, n))
        end)
        c:SetPoint("TOPLEFT", 20, -rowY)
        rowY = rowY + 22
    end
    list:SetHeight(rowY + 8)
    return rowY + 8
end

local function BuildColors(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, L["REPLACE A COLOR"], y); y = y - h
    y = y - Hint(parent, y, L["Finds one color everywhere in the EllesmereUI settings (also where you typed it by hand) and replaces it with another. Check the list, then replace: the UI reloads, and \"Undo\" puts the old colors back."])
    _, h = W:DualRow(parent, y,
        { type = "input", text = L["Find color (hex)"], inputWidth = 90,
          getValue = function() return "#" .. Rewrite.Source() end,
          setValue = function(v)
              local hex = Rewrite.NormalizeHex(v or "")
              if hex then Rewrite.Store().source = hex Refresh() end
          end },
        { type = "colorpicker", text = L["Find color"],
          getValue = function() return Swatch(Rewrite.Source()) end,
          setValue = function(r, g, b) Rewrite.Store().source = Rewrite.RGBToHex(r, g, b) Refresh() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "input", text = L["New color (hex)"], inputWidth = 90,
          getValue = function() return "#" .. Rewrite.Target() end,
          setValue = function(v)
              local hex = Rewrite.NormalizeHex(v or "")
              if hex then Rewrite.Store().target = hex Refresh() end
          end },
        { type = "colorpicker", text = L["New color"],
          getValue = function() return Swatch(Rewrite.Target()) end,
          setValue = function(r, g, b) Rewrite.Store().target = Rewrite.RGBToHex(r, g, b) Refresh() end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = L["Search in"], values = SCOPE_VALUES, order = { "active", "all" },
          dropdownWidth = 230, getValue = function() return Rewrite.Scope() end,
          setValue = function(v) Rewrite.Store().scope = v Rebuild() end },
        { type = "slider", text = L["Tolerance"], min = 0, max = 5, step = 1,
          getValue = function() return Rewrite.Get("tolerance") end,
          setValue = function(v) Rewrite.Store().tolerance = v end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = L["Use accent as find color"], width = 220, onClick = function()
            Rewrite.Store().source = Rewrite.RGBToHex(EUI.Accent())
            Rebuild()
        end },
        { type = "button", text = L["Swap colors"], width = 180, onClick = function()
            local s = Rewrite.Store()
            s.source, s.target = Rewrite.Target(), Rewrite.Source()
            Rebuild()
        end }); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "button", text = L["Search"], width = 180, onClick = function()
            if InCombatLockdown() then ns.Say(L["Not in combat."]) return end
            Rewrite.Search()
            Rebuild()
        end },
        { type = "button", text = L["Replace and reload"], width = 220, onClick = function()
            if InCombatLockdown() then ns.Say(L["Not in combat."]) return end
            if not Rewrite.HitsCurrent() then Rewrite.Search() end
            local n = 0
            for _, hit in ipairs(Rewrite.Hits()) do if hit.on then n = n + 1 end end
            if n == 0 then ns.Say(L["Nothing to replace."]) Rebuild() return end
            ConfirmAndReload(L["Replace #%s with #%s in %d places and reload the UI?"]:format(Rewrite.Source(), Rewrite.Target(), n),
                Rewrite.Replace)
        end }); y = y - h
    local undo = Rewrite.UndoInfo()
    _, h = W:DualRow(parent, y,
        { type = "button", text = L["Undo last replace"], width = 220, disabled = function() return Rewrite.UndoInfo() == nil end,
          onClick = function()
            local info = Rewrite.UndoInfo()
            if not info then return end
            ConfirmAndReload(L["Put #%s back in %d places (instead of #%s) and reload the UI?"]:format(info.source, info.count, info.target),
                Rewrite.Undo)
        end },
        { type = "button", text = L["Reload UI"], width = 180, onClick = function() ReloadUI() end }); y = y - h
    if undo then
        y = y - Hint(parent, y, L["Last replace: #%s -> #%s in %d places (can be undone)."]:format(undo.source, undo.target, undo.count))
    end
    y = y - HitList(parent, y)
    return y
end

-- ---------------------------------------------------------------- registration
local BUILDERS = {
    [PAGE_CAMERA] = BuildCamera, [PAGE_HIDE] = BuildHide, [PAGE_COPY] = BuildCopy, [PAGE_ZONE] = BuildZone,
    [PAGE_ICONS] = BuildIcons, [PAGE_COLORS] = BuildColors,
}

local function BuildPage(pageName, parent, yOffset)
    local W = EUI.Widgets()
    local build = BUILDERS[pageName]
    if not (W and build) then return 0 end
    local y = build(W, parent, yOffset)
    return math.abs(y) + 20
end

local registered = false
local function Register()
    if registered then return end
    registered = EUI.RegisterPlugin(ns.PLUGIN_ID, {
        label = "Tweaks+",
        position = "top",
        modules = {
            { key = "Tweaks", title = L["Tweaks"],
              description = L["Camera zoom, hide chat, a better copy-chat window and the sub zone on the minimap."],
              pages = { PAGE_CAMERA, PAGE_HIDE, PAGE_COPY, PAGE_ZONE }, buildPage = BuildPage,
              onPageCacheRestore = Refresh,
              onReset = function()
                  ChatHide.SetHidden(false)   -- bring the chat back before its settings go
                  Camera.Reset() ChatHide.Reset() ChatCopy.Reset() ZoneText.Reset()
                  Rebuild()
              end },
            { key = "Extensions", title = L["Extensions"],
              description = L["Additions to EllesmereUI windows."],
              pages = { PAGE_ICONS }, buildPage = BuildPage, onPageCacheRestore = Refresh,
              onReset = function() IconSearch.Reset() Rebuild() end },
            { key = "ColorRewrite", title = "ColorRewrite",
              description = L["Replace one color everywhere in the EllesmereUI settings."],
              pages = { PAGE_COLORS }, buildPage = BuildPage, onPageCacheRestore = Refresh, searchPrebuild = false,
              onReset = function()
                  local s = Rewrite.Store()
                  s.source, s.target, s.scope, s.tolerance = nil, nil, nil, nil
                  Rebuild()
              end },
        },
    })
end

-- from the main chunk would also work; after DB_READY the getters read real values
ns.On("DB_READY", Register)

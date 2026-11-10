-- ---------------------------------------------------------------------------
-- Extensions > Icon search: a search line and a category filter on top of
-- EllesmereUI's "Choose Icon" popup (Forever Essentials > Macros). The bar
-- covers the popup's hint line; while a search or filter is active, our own
-- grid covers EllesmereUI's grid. A click on one of our icons is handed to one
-- of EllesmereUI's own grid buttons, so the icon is taken exactly as if it had
-- been clicked there. Empty search and no filter = EllesmereUI's grid as is.
-- The search looks at spell and item names (client language, indexed in the
-- background on first use) and, with EUITweaks_Icons, at icon file names, file
-- IDs and categories. Nothing is created while the switch is off.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI, EUI = ns.L, ns.UI, ns.EUI
local IconFilter = ns.IconFilter

local Search = ns.Module("iconsearch", { on = false })
ns.IconSearch = Search

-- EllesmereUI's picker geometry (EUI_ForeverEssentials_Macros_Options.lua, OpenPicker):
-- a 10 x 6 grid of 40-unit cells at (20, -70). While the extension is on, the popup
-- grows to fit our larger grid; its own size comes back when the extension is off.
local EUI_COLS, EUI_ROWS = 10, 6
local COLS, ROWS, SIZE = 14, 9, 40
local GRID_X, GRID_Y = 20, -70
local QUESTION = 134400   -- INV_Misc_QuestionMark: the macro shows its spell's icon (#showtooltip)
local origW, origH         -- the popup size EllesmereUI gave it

local active = false
local dimmer, popup        -- EllesmereUI's frames, once found
local bar, grid            -- ours
local cells = {}
local query, scroll = "", 0
local icons, view          -- the game's macro icon list; what our grid shows
local dataList, dataKey, dataDone, dataProgress = nil, nil, true, 1

-- ---------------------------------------------------------------- spell and item names
local nameIndex, indexDone, indexNext = nil, false, 1
-- spell IDs reach well past a million in the current client; each frame reads chunks of INDEX_STEP IDs
-- until INDEX_BUDGET milliseconds are used up, so the game stays smooth while the index grows
local INDEX_MAX_SPELL, INDEX_STEP, INDEX_BUDGET = 1600000, 2500, 6

local function AddName(icon, name)
    if not icon or type(name) ~= "string" or name == "" or ns.IsSecret(name) then return end
    local e = nameIndex[icon]
    if not e then
        e = { names = {}, key = "" }
        nameIndex[icon] = e
    end
    for _, n in ipairs(e.names) do if n == name then return end end
    if #e.names < 6 then e.names[#e.names + 1] = name end
    e.key = e.key .. "\n" .. ns.Fold(name)
end

local function IndexQuickSources()
    local book = C_SpellBook
    if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local ok, lines = pcall(book.GetNumSpellBookSkillLines)
        for line = 1, (ok and lines or 0) do
            local okL, info = pcall(book.GetSpellBookSkillLineInfo, line)
            if okL and info and info.itemIndexOffset and info.numSpellBookItems then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okI, item = pcall(book.GetSpellBookItemInfo, i, bank)
                    if okI and item then AddName(item.iconID, item.name) end
                end
            end
        end
    end
    local bags = C_Container
    if bags and bags.GetContainerNumSlots and bags.GetContainerItemInfo then
        for bag = 0, 4 do
            local okS, slots = pcall(bags.GetContainerNumSlots, bag)
            for slot = 1, (okS and slots or 0) do
                local okI, info = pcall(bags.GetContainerItemInfo, bag, slot)
                if okI and type(info) == "table" and info.iconFileID and info.hyperlink then
                    AddName(info.iconFileID, info.hyperlink:match("%[(.-)%]"))
                end
            end
        end
    end
end

local RunSearch
local indexer = CreateFrame("Frame")
indexer:Hide()
local function IndexChunk()
    local first = indexNext
    local last = math.min(INDEX_MAX_SPELL, first + INDEX_STEP - 1)
    indexNext = last + 1
    pcall(function()
        for id = first, last do
            local info = C_Spell.GetSpellInfo(id)
            if info and info.iconID then AddName(info.iconID, info.name) end
        end
    end)
end

indexer:SetScript("OnUpdate", function(self)
    if not (C_Spell and C_Spell.GetSpellInfo) then indexDone = true self:Hide() RunSearch() return end
    local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
    local started = clock and clock()
    repeat
        IndexChunk()
    until indexNext > INDEX_MAX_SPELL or not clock or clock() - started >= INDEX_BUDGET
    if indexNext > INDEX_MAX_SPELL then
        indexDone = true
        self:Hide()
    end
    RunSearch()
end)

local function EnsureIndex()
    if nameIndex then return end
    nameIndex = {}
    IndexQuickSources()
    indexer:Show()
end

-- ---------------------------------------------------------------- the icon lists
-- EllesmereUI's order: the question mark, the spellbook icons, then every macro icon of the game
local function SpellbookIcons(add)
    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo) then
        return
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local ok, lines = pcall(book.GetNumSpellBookSkillLines)
    for line = 1, (ok and lines or 0) do
        local okL, info = pcall(book.GetSpellBookSkillLineInfo, line)
        if okL and info and info.itemIndexOffset and info.numSpellBookItems then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local okI, item = pcall(book.GetSpellBookItemInfo, i, bank)
                if okI and item and item.iconID then add(item.iconID) end
            end
        end
    end
end

local function BuildIcons()
    icons = {}
    local seen = {}
    local function add(v)
        if v and not seen[v] then seen[v] = true icons[#icons + 1] = v end
    end
    add(QUESTION)
    SpellbookIcons(add)
    for _, fname in ipairs({ "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }) do
        local fn = rawget(_G, fname)
        if type(fn) == "function" then
            local t = {}
            local ok, ret = pcall(fn, t)
            if ok and type(ret) == "table" then t = ret end
            for _, v in ipairs(t) do add(v) end
        end
    end
end

local function IconTexture(v)
    if type(v) == "string" and not v:find("\\", 1, true) then return "Interface\\Icons\\" .. v end
    return v
end

-- icons whose spell or item names contain the query, names that start with it first
local function NameHits()
    EnsureIndex()
    local hits = {}
    for icon, e in pairs(nameIndex) do
        local pos = e.key:find(query, 1, true)
        if pos then
            local prefix = e.key:sub(pos - 1, pos - 1) == "\n" and 0 or 1
            hits[#hits + 1] = { icon = icon, rank = prefix, name = e.names[1] or "" }
        end
    end
    table.sort(hits, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    for i, h in ipairs(hits) do hits[i] = h.icon end
    return hits
end

local function CombineView()
    local out, seen = {}, {}
    local function add(v)
        if v and not seen[v] then seen[v] = true out[#out + 1] = v end
    end
    if query ~= "" and not query:match("^%d+$") then
        local filtered = IconFilter.HasSelection()
        for _, icon in ipairs(NameHits()) do
            if not filtered or IconFilter.InCategories(icon, IconFilter.selected) then add(icon) end
        end
    end
    for _, v in ipairs(dataList or {}) do add(v) end
    view = out
end

-- ---------------------------------------------------------------- drawing
local function Status()
    if not bar then return end
    local filtered = IconFilter.HasSelection()
    local n = view and #view or 0
    local text
    if query == "" and not filtered then
        text = L["%d icons"]:format(n)
    elseif not dataDone then
        text = L["%d matches · searching %d%%"]:format(n, math.floor(dataProgress * 100))
    elseif query ~= "" and not indexDone and not query:match("^%d+$") then
        text = L["%d matches · indexing names %d%%"]:format(n, math.floor(math.min(1, indexNext / INDEX_MAX_SPELL) * 100))
    else
        text = n > 0 and L["%d matches"]:format(n) or L["No icon matches."]
    end
    bar.status:SetText(text)
end

local function Render()
    if not grid then return end
    grid:SetShown(active)
    Status()
    if not active then return end
    local list = view or {}
    local maxRow = math.max(0, math.ceil(#list / COLS) - ROWS)
    scroll = math.max(0, math.min(scroll, maxRow))
    for i, c in ipairs(cells) do
        local v = list[scroll * COLS + i]
        c.value = v
        if v then
            c.tex:SetTexture(IconTexture(v))
            c:Show()
        else
            c:Hide()
        end
    end
    if maxRow > 0 then
        local trackH = ROWS * SIZE
        local thumbH = math.max(16, trackH * ROWS / (maxRow + ROWS))
        grid.thumb:ClearAllPoints()
        grid.thumb:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -(trackH - thumbH) * scroll / maxRow)
        grid.thumb:SetHeight(thumbH)
        grid.thumb:Show()
    else
        grid.thumb:Hide()
    end
end

local function SearchKey()
    local keys = {}
    for k in pairs(IconFilter.selected) do keys[#keys + 1] = k end
    table.sort(keys)
    return query .. "\n" .. table.concat(keys, ",")
end

RunSearch = function()
    if not grid then return end
    if not icons then BuildIcons() end
    local filtered = IconFilter.HasSelection()
    if IconFilter.Available() and (filtered or query ~= "") then
        -- the icon data search runs in portions; the view updates as results come in
        local key = SearchKey()
        if key ~= dataKey then
            dataKey, dataList, dataDone, dataProgress = key, {}, false, 0
            IconFilter.Start({
                query = IconFilter.Normalize(query), selected = IconFilter.selected,
                onUpdate = function(list, done, progress)
                    dataList, dataDone, dataProgress = list, done, progress
                    CombineView()
                    Render()
                end,
            })
        end
        CombineView()
        Render()
        return
    end
    IconFilter.Cancel()
    dataKey, dataList, dataDone = nil, nil, true
    if query == "" then
        view = icons
    elseif query:match("^%d+$") then
        view = {}
        for _, v in ipairs(icons) do
            if tostring(v):find(query, 1, true) then view[#view + 1] = v end
        end
    else
        view = NameHits()
    end
    Render()
end

-- ---------------------------------------------------------------- picking
local function Pick(value)
    local cell = popup and EUI.IconPickerCell(popup)
    if not (cell and value) then return end
    cell.value = value
    cell:Click("LeftButton")
end

-- ---------------------------------------------------------------- building (on the first open)
local function Build()
    local level = popup:GetFrameLevel() + 30

    bar = CreateFrame("Frame", nil, popup)
    bar:SetFrameLevel(level)
    bar:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -38)
    bar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -38)
    bar:SetHeight(28)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 1)

    bar.search = UI.Edit(bar, 280, 24, L["Search name or ID ..."])
    bar.search:SetPoint("LEFT", GRID_X - 1, 0)
    bar.search:SetScript("OnTextChanged", function(self)
        self.hint:SetShown((self:GetText() or "") == "")
        query = ns.Fold(ns.Trim(self:GetText()))
        scroll = 0
        RunSearch()
    end)
    bar.search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Search icons"], 1, 1, 1)
        GameTooltip:AddLine(L["Spell and item names, icon file names and file IDs. The question mark in the normal list shows the spell's icon (with #showtooltip)."], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    bar.search:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.filter = UI.Button(bar, 72, 24, L["Filter"], function(self)
        IconFilter.OpenMenu(self, function()
            scroll = 0
            bar.filter:SetActive(IconFilter.HasSelection())
            RunSearch()
        end)
    end)
    bar.filter:SetPoint("RIGHT", -(GRID_X - 1), 0)
    bar.filter.tip = { L["Filter"], L["Inside a group the ticked categories add up, across groups they narrow down. Example: Abilities (General) and Rogue (Classes) show the rogue abilities."] }

    bar.status = UI.Text(bar, 11, UI.DIM)
    bar.status:SetPoint("LEFT", bar.search, "RIGHT", 10, 0)
    bar.status:SetPoint("RIGHT", bar.filter, "LEFT", -8, 0)
    bar.status:SetWordWrap(false)

    grid = CreateFrame("Frame", nil, popup)
    grid:SetFrameLevel(level)
    grid:SetPoint("TOPLEFT", popup, "TOPLEFT", GRID_X, GRID_Y)
    grid:SetSize(COLS * SIZE + 12, ROWS * SIZE)
    grid:EnableMouse(true)
    grid:EnableMouseWheel(true)
    grid.bg = grid:CreateTexture(nil, "BACKGROUND")
    grid.bg:SetAllPoints()
    grid.bg:SetColorTexture(UI.BG[1], UI.BG[2], UI.BG[3], 1)
    grid.thumb = grid:CreateTexture(nil, "OVERLAY")
    grid.thumb:SetWidth(3)
    UI.OnAccent(function(r, g, b) grid.thumb:SetColorTexture(r, g, b, 0.7) end)
    grid:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta
        Render()
    end)

    for i = 1, COLS * ROWS do
        local c = CreateFrame("Button", nil, grid)
        c:SetSize(SIZE - 4, SIZE - 4)
        c:SetPoint("TOPLEFT", ((i - 1) % COLS) * SIZE, -math.floor((i - 1) / COLS) * SIZE)
        c.edge = c:CreateTexture(nil, "BACKGROUND")
        c.edge:SetPoint("TOPLEFT", -1, 1)
        c.edge:SetPoint("BOTTOMRIGHT", 1, -1)
        c.edge:SetColorTexture(1, 1, 1, 0.12)
        c.tex = c:CreateTexture(nil, "ARTWORK")
        c.tex:SetAllPoints()
        c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.2)
        c:RegisterForClicks("LeftButtonUp")
        c:SetScript("OnClick", function(self) Pick(self.value) end)
        c:SetScript("OnEnter", function(self)
            local e = nameIndex and nameIndex[self.value]
            local iconName = IconFilter.NameOf(self.value)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local any = false
            if e then
                for _, n in ipairs(e.names) do GameTooltip:AddLine(n, 1, 1, 1) any = true end
            end
            if iconName then GameTooltip:AddLine(iconName, 0.7, 0.7, 0.7) any = true end
            GameTooltip:AddLine(L["File ID: %s"]:format(tostring(self.value)), 0.5, 0.5, 0.5)
            if any or self.value then GameTooltip:Show() end
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[i] = c
    end
end

-- ---------------------------------------------------------------- open / close
-- the popup grows by the extra columns and rows of our grid; nil = back to its own size
local function SizePopup(grow)
    if not popup then return end
    if not origW then origW, origH = popup:GetWidth(), popup:GetHeight() end
    if grow then
        popup:SetSize(origW + (COLS - EUI_COLS) * SIZE, origH + (ROWS - EUI_ROWS) * SIZE)
    else
        popup:SetSize(origW, origH)
    end
end

local function FitAll()
    UI.FitEdges(bar.search)
    UI.FitEdges(bar.filter)
end

local function OnPickerShow()
    if not active then
        if bar then bar:Hide() grid:Hide() end
        SizePopup(false)
        return
    end
    if not bar then Build() end
    SizePopup(true)
    FitAll()
    icons = nil   -- the spellbook part is read again on every open, as EllesmereUI does
    IconFilter.Load()
    bar.filter:SetShown(IconFilter.Available())
    bar.filter:SetActive(IconFilter.HasSelection())
    bar:Show()
    bar.search:SetText("")
    query, scroll = "", 0
    RunSearch()
end

local function OnPickerHide()
    if not bar then return end
    bar.search:ClearFocus()
    UI.CloseMenu()
    IconFilter.Cancel()
    dataKey, dataDone = nil, true   -- a half-finished search starts over on the next open
end

local function Attach()
    if dimmer then return true end
    local d, p = EUI.IconPicker()
    if not d then return false end
    dimmer, popup = d, p
    dimmer:HookScript("OnShow", OnPickerShow)
    dimmer:HookScript("OnHide", OnPickerHide)
    if dimmer:IsShown() then OnPickerShow() end
    return true
end

-- EllesmereUI builds the popup the first time "Choose Icon" is clicked: look for it
-- twice a second while the switch is on, until it is found (then never again)
local ticker
local function Watch()
    if dimmer or ticker then return end
    ticker = C_Timer.NewTicker(0.5, function()
        if Attach() or not active then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

Search.OnApply(function()
    active = Search.Get("on")
    if active then
        if not Attach() then Watch() end
    elseif bar then
        bar:Hide()
        grid:Hide()
        OnPickerHide()
        SizePopup(false)
    end
end)

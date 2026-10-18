-- ---------------------------------------------------------------------------
-- Extensions > Icon search, data side (ported from EverFrame): icon names and
-- categories from the load-on-demand addon EUITweaks_Icons, a search that runs
-- in portions over several frames, and the two-level category filter menu.
-- Categories are bit fields in the per-icon "tags" list: every icon owns
-- `stride` consecutive 32-bit numbers, category N is bit (N % 32) of number
-- (N // 32) + 1. Inside a menu group ticked categories add up (swords or
-- daggers), across groups they narrow down (abilities and rogue).
-- ---------------------------------------------------------------------------
local _, ns = ...
local L, UI = ns.L, ns.UI

local IconFilter = {}
ns.IconFilter = IconFilter

local DATA_ADDON = "EUITweaks_Icons"
local FIELD_WIDTH = 32
local FILE_ID_LIMIT = 0x04000000   -- bigger IDs are atlases, not texture files
local STEP = 3000                  -- icons checked per frame

local data, count, stride = nil, 0, 1
local loadFailed = false

function IconFilter.Load()
    if data then return true end
    if loadFailed then return false end
    local load = C_AddOns and C_AddOns.LoadAddOn
    if load then pcall(load, DATA_ADDON) end
    local d = rawget(_G, "EUITweaksIconData")
    if type(d) ~= "table" or type(d.id) ~= "table" or type(d.name) ~= "table"
        or type(d.tags) ~= "table" or type(d.categories) ~= "table" then
        loadFailed = true
        return false
    end
    local n = 0
    for _ in pairs(d.categories) do n = n + 1 end
    data, count, stride = d, #d.id, math.max(1, math.ceil(n / FIELD_WIDTH))
    return true
end

function IconFilter.Available() return data ~= nil end

-- index of a file ID in the (sorted) ID list
local function IndexOf(id)
    if type(id) ~= "number" then return nil end
    local ids, lo, hi = data.id, 1, count
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local v = ids[mid]
        if v == id then return mid end
        if v < id then lo = mid + 1 else hi = mid - 1 end
    end
end

function IconFilter.NameOf(id)
    if not data then return nil end
    local i = IndexOf(id)
    return i and data.name[i] or nil
end

IconFilter.groupOf = {}
IconFilter.selected = {}

local function Tests(selected)
    local byGroup, groups = {}, {}
    if data and selected then
        for key in pairs(selected) do
            local cat = data.categories[key]
            if cat then
                local gid = IconFilter.groupOf[key] or key
                local g = byGroup[gid]
                if not g then g = {} byGroup[gid] = g groups[#groups + 1] = g end
                g[#g + 1] = { math.floor(cat / FIELD_WIDTH) + 1, 2 ^ (cat % FIELD_WIDTH) }
            end
        end
    end
    return groups
end

local function Passes(groups, index)
    if #groups == 0 then return true end
    local base = (index - 1) * stride
    local tags = data.tags
    for _, tests in ipairs(groups) do
        local any = false
        for _, t in ipairs(tests) do
            if math.floor((tags[base + t[1]] or 0) / t[2]) % 2 == 1 then any = true break end
        end
        if not any then return false end
    end
    return true
end

-- true/false: does this icon fit the selected categories? nil: unknown icon
function IconFilter.InCategories(id, selected)
    if not data then return nil end
    local i = IndexOf(id)
    if not i then return nil end
    return Passes(Tests(selected), i)
end

-- lowercase, blanks and dashes become "_" (names look like "inv_sword_01")
function IconFilter.Normalize(text)
    return (ns.Fold(ns.Trim(text or "")):gsub("[%s%-]+", "_"))
end

-- ---------------------------------------------------------------- portioned search
-- opts = { query = <normalized>, selected = { key = true }, onUpdate = fn(list, done, progress) }
local runner = CreateFrame("Frame")
runner:Hide()
local job

local function Step()
    local j = job
    local last = math.min(count, j.pos + STEP - 1)
    local ids, names = data.id, data.name
    for i = j.pos, last do
        local id = ids[i]
        if id < FILE_ID_LIMIT and Passes(j.tests, i) then
            if j.query == "" then
                j.rest[#j.rest + 1] = id
            elseif j.digits then
                if tostring(id):find(j.query, 1, true) then j.rest[#j.rest + 1] = id end
            else
                local pos = names[i]:find(j.query, 1, true)
                if pos == 1 then j.first[#j.first + 1] = id
                elseif pos then j.rest[#j.rest + 1] = id end
            end
        end
    end
    j.pos = last + 1
end

runner:SetScript("OnUpdate", function(self)
    if not job then self:Hide() return end
    Step()
    local j = job
    local done = j.pos > count
    local list = {}
    for _, v in ipairs(j.first) do list[#list + 1] = v end
    for _, v in ipairs(j.rest) do list[#list + 1] = v end
    if done then job = nil self:Hide() end
    j.onUpdate(list, done, math.min(1, (j.pos - 1) / count))
end)

function IconFilter.Start(opts)
    if not data then return false end
    job = {
        query = opts.query or "", tests = Tests(opts.selected), onUpdate = opts.onUpdate,
        digits = (opts.query or ""):match("^%d+$") ~= nil, pos = 1, first = {}, rest = {},
    }
    runner:Show()
    return true
end

function IconFilter.Cancel()
    job = nil
    runner:Hide()
end

-- ---------------------------------------------------------------- the filter menu
local GROUPS = {
    { name = L["General"], entries = {
        { "Ability", L["Abilities"] }, { "Achievement", L["Achievements"] }, { "Housing", L["Housing"] },
        { "Item", L["Items"] }, { "Pet", L["Pets"] }, { "Mount", L["Mounts"] },
        { "Alliance", L["Alliance"] }, { "Horde", L["Horde"] }, { "OtherFactions", L["Other factions"] },
    } },
    { name = L["Classes"], entries = {
        { "Warrior", L["Warrior"] }, { "Paladin", L["Paladin"] }, { "Hunter", L["Hunter"] },
        { "Rogue", L["Rogue"] }, { "Priest", L["Priest"] }, { "DeathKnight", L["Death Knight"] },
        { "Shaman", L["Shaman"] }, { "Mage", L["Mage"] }, { "Warlock", L["Warlock"] },
        { "Monk", L["Monk"] }, { "Druid", L["Druid"] }, { "DemonHunter", L["Demon Hunter"] },
        { "Evoker", L["Evoker"] },
    } },
    { name = L["Weapons"], entries = {
        { "Weapon", L["All weapons"] }, { "WeaponTypeSword", L["Swords"] }, { "WeaponTypeAxe", L["Axes"] },
        { "WeaponTypeMace", L["Maces"] }, { "WeaponTypeDagger", L["Daggers"] },
        { "WeaponTypeFists", L["Fist weapons"] }, { "WeaponTypePolearm", L["Polearms"] },
        { "WeaponTypeStaff", L["Staves"] }, { "WeaponTypeWarglaive", L["Warglaives"] },
        { "WeaponTypeBow", L["Bows"] }, { "WeaponTypeCrossbow", L["Crossbows"] }, { "WeaponTypeGun", L["Guns"] },
        { "WeaponTypeWand", L["Wands"] }, { "WeaponTypeThrown", L["Thrown"] }, { "WeaponTypeAmmo", L["Ammunition"] },
    } },
    { name = L["Armor"], entries = {
        { "Armor", L["All armor"] }, { "ClothArmor", L["Cloth"] }, { "LeatherArmor", L["Leather"] },
        { "MailArmor", L["Mail"] }, { "PlateArmor", L["Plate"] }, { "Jewelry", L["Jewelry"] },
        { "InventorySlotShield", L["Shields"] }, { "InventorySlotOffHand", L["Off-hands"] },
        { "InventorySlotTrinket", L["Trinkets"] }, { "InventorySlotRing", L["Rings"] },
        { "InventorySlotNeck", L["Necklaces"] },
    } },
    { name = L["Equipment slots"], entries = {
        { "InventorySlotHead", L["Head"] }, { "InventorySlotShoulders", L["Shoulders"] },
        { "InventorySlotChest", L["Chest"] }, { "InventorySlotBack", L["Back"] },
        { "InventorySlotWrists", L["Wrists"] }, { "InventorySlotHands", L["Hands"] },
        { "InventorySlotWaist", L["Waist"] }, { "InventorySlotLegs", L["Legs"] },
        { "InventorySlotFeet", L["Feet"] }, { "InventorySlotShirt", L["Shirts"] },
        { "InventorySlotTabard", L["Tabards"] },
    } },
    { name = L["Magic"], entries = {
        { "ArcaneMagic", L["Arcane"] }, { "FireMagic", L["Fire"] }, { "FrostMagic", L["Frost"] },
        { "NatureMagic", L["Nature"] }, { "HolyMagic", L["Holy"] }, { "ShadowMagic", L["Shadow"] },
        { "FelMagic", L["Fel"] }, { "VoidMagic", L["Void"] },
    } },
    { name = L["Professions"], entries = {
        { "Professions", L["All professions"] }, { "Alchemy", L["Alchemy"] },
        { "Blacksmithing", L["Blacksmithing"] }, { "Enchanting", L["Enchanting"] },
        { "Engineering", L["Engineering"] }, { "Herbalism", L["Herbalism"] },
        { "Inscription", L["Inscription"] }, { "Jewelcrafting", L["Jewelcrafting"] },
        { "Leatherworking", L["Leatherworking"] }, { "Mining", L["Mining"] },
        { "Skinning", L["Skinning"] }, { "Tailoring", L["Tailoring"] }, { "Cooking", L["Cooking"] },
        { "Fishing", L["Fishing"] }, { "FirstAid", L["First Aid"] }, { "Archaeology", L["Archaeology"] },
    } },
    { name = L["Consumables"], entries = {
        { "Potion", L["Potions"] }, { "Food", L["Food"] }, { "Drink", L["Drinks"] },
        { "TradeGoods", L["Trade goods"] },
    } },
}

for gi, g in ipairs(GROUPS) do
    for _, e in ipairs(g.entries) do IconFilter.groupOf[e[1]] = gi end
end

local function CountIn(group)
    local n = 0
    for _, e in ipairs(group.entries) do
        if IconFilter.selected[e[1]] then n = n + 1 end
    end
    return n
end

function IconFilter.HasSelection() return next(IconFilter.selected) ~= nil end

local OpenGroup
local function OpenTop(anchor, onChange)
    local items = {}
    for _, g in ipairs(GROUPS) do
        local n = CountIn(g)
        items[#items + 1] = { label = g.name, desc = n > 0 and tostring(n) or ">", checked = n > 0,
            fn = function() OpenGroup(anchor, g, onChange) end }
    end
    items[#items + 1] = { label = L["Reset filter"], divider = true,
        fn = function() IconFilter.selected = {} onChange() end }
    UI.OpenMenu(anchor, items, 200)
end

OpenGroup = function(anchor, group, onChange)
    local items = { { label = "< " .. L["Back"], fn = function() OpenTop(anchor, onChange) end } }
    for i, e in ipairs(group.entries) do
        items[#items + 1] = { label = e[2], checked = IconFilter.selected[e[1]], divider = i == 1,
            fn = function()
                IconFilter.selected[e[1]] = (not IconFilter.selected[e[1]]) or nil
                onChange()
                OpenGroup(anchor, group, onChange)
            end }
    end
    UI.OpenMenu(anchor, items, 200)
end

function IconFilter.OpenMenu(anchor, onChange) OpenTop(anchor, onChange) end

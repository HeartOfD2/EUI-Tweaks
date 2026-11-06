-- ---------------------------------------------------------------------------
-- Tweaks > Item count: for stackable items, the top right corner of the tooltip
-- shows how many this character has, all stacks added up, and the split between
-- bags and bank once the bank holds some. EllesmereUI's own "Tooltip Item Counts"
-- does not run on this client. The tooltip hook is set on the first switch-on; it
-- can't be removed again, so it just returns while the switch is off.
-- ---------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local Count = ns.Module("itemcount", { on = false, format = "{count}" })
ns.ItemCount = Count

local active, hooked = false, false

-- the player's text around the count, {count} being the count; without {count} there would be no number to show
function Count.Format()
    local format = ns.Trim(Count.Get("format"))
    return format:find("{count}", 1, true) and format or "{count}"
end

-- the 8th value of GetItemInfo is the stack size; nil while the client has not cached the item
local function Stacks(id)
    local get = C_Item and C_Item.GetItemInfo
    if not get then return false end
    local ok, _, _, _, _, _, _, _, maxStack = pcall(get, id)
    if not ok or ns.IsSecret(maxStack) or type(maxStack) ~= "number" then return false end
    return maxStack > 1
end

-- nil when the client has no answer. A secret count is never used: arithmetic on it would error.
local function Read(id, withBank)
    local get = C_Item and C_Item.GetItemCount
    if not get then return nil end
    local ok, n = pcall(get, id, withBank, false, withBank)
    if not ok or ns.IsSecret(n) or type(n) ~= "number" then return nil end
    return n
end

-- what the tooltip shows, nil for an item that doesn't stack or that the character doesn't have
function Count.Text(id)
    if not Stacks(id) then return nil end
    local bags, all = Read(id, false), Read(id, true)
    if not bags or not all or all <= 0 then return nil end
    local shown = Count.Format():gsub("{count}", tostring(all))
    if all > bags then
        return L["%s (bags %d, bank %d)"]:format(shown, bags, all - bags)
    end
    return shown
end

-- No tooltip:Show() here: it redraws the tooltip during a click on a bag slot and swallows a sale at a vendor.
-- A chat link's tooltip has its close button in that corner, so it gets a line at the bottom, like an
-- item whose title row already carries something on the right.
local function OnItemTooltip(tooltip, data)
    if not active then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip:IsForbidden() then return end
    local id = data and data.id
    if ns.IsSecret(id) or type(id) ~= "number" then return end
    local text = Count.Text(id)
    if not text then return end
    local corner = tooltip == GameTooltip and GameTooltipTextRight1
    if corner and not corner:IsShown() then
        corner:SetText(text)
        corner:SetTextColor(1, 1, 1)
        corner:Show()
    else
        tooltip:AddDoubleLine(L["You have"], text, 1, 0.82, 0, 1, 1, 1)
    end
end

local function Hook()
    if hooked then return end
    local processor = TooltipDataProcessor
    if not (processor and processor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    hooked = true
    processor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

Count.OnApply(function()
    active = Count.Get("on")
    if active then Hook() end
end)

-- English is the key language: a missing key falls back to the English text itself.
local _, ns = ...
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- The language of the texts follows EllesmereUI's language setting (General > Language),
-- else the client. EllesmereUI is a dependency, so its saved variables are readable here.
function ns.Locale()
    local db = rawget(_G, "EllesmereUIDB")
    local override = type(db) == "table" and db.displayLocale or nil
    local locale = (type(override) == "string" and override ~= "auto" and override ~= "") and override or GetLocale()
    if locale == "enGB" then locale = "enUS" end
    return locale
end

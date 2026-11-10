-- English is the key language: a missing key falls back to the English text itself.
-- Every locale file fills its own table in ns.locales; ns.L reads the table of the chosen
-- language at the moment a text is asked for. The choice (General > Language) lives in the
-- saved variables, so it is made in ADDON_LOADED (Core\Init.lua): no file may read a text
-- from ns.L while it loads.
local _, ns = ...

ns.locales = { enUS = {} }
ns.activeLocale = ns.locales.enUS
ns.locale = "enUS"

ns.L = setmetatable({}, {
    __index = function(_, key)
        local text = ns.activeLocale[key]
        if text ~= nil then return text end
        return key
    end,
})

-- "Automatic": EllesmereUI's language setting (General > Language), else the client.
-- EllesmereUI is a dependency, so its saved variables are readable here.
function ns.AutoLocale()
    local db = rawget(_G, "EllesmereUIDB")
    local override = type(db) == "table" and db.displayLocale or nil
    local locale = (type(override) == "string" and override ~= "auto" and override ~= "") and override or GetLocale()
    if type(locale) ~= "string" or locale == "" or locale == "enGB" then locale = "enUS" end
    return locale
end

-- choice: a key of ns.locales, anything else (also "auto") means automatic
function ns.ChooseLocale(choice)
    local locale = (type(choice) == "string" and ns.locales[choice]) and choice or ns.AutoLocale()
    ns.locale = locale
    ns.activeLocale = ns.locales[locale] or ns.locales.enUS
    return locale
end

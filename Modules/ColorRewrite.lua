-- ---------------------------------------------------------------------------
-- ColorRewrite: finds one color everywhere in EllesmereUI's saved settings and
-- replaces it with another. Colors are recognised in five shapes:
--   rgb   { r = , g = , b = [, a = ] }
--   arr   { 0.1, 0.7, 0.6 [, a] }            (three or four numbers 0..1, nothing else)
--   flat  xxxR / xxxG / xxxB next to each other (e.g. borderR, borderG, borderB)
--   hex   "29BDAC", "#29BDAC", "FF29BDAC"    (the whole string)
--   code  "|cFF29BDAC" inside a text
-- A value matches when every channel rounds to the same byte (or lies within
-- the tolerance). Alpha, the spelling of hex strings (case, "#", alpha prefix)
-- and everything else stay as they are. Every replacement is recorded as an
-- undo set (saved), which puts the old values back. EllesmereUI reads its
-- colors when it builds its frames, so changes show after a UI reload.
-- ---------------------------------------------------------------------------
local _, ns = ...
local EUI = ns.EUI

local Rewrite = ns.Module("colorrewrite",
    { source = "29BDAC", target = "29BDAC", scope = "active", tolerance = 0 },
    { tolerance = { 0, 5 } })
ns.ColorRewrite = Rewrite

Rewrite.SCOPES = { active = true, all = true }

-- ---------------------------------------------------------------- color helpers
local function Byte(v) return math.floor(v * 255 + 0.5) end

-- "#29bdac" / "29BDAC" -> "29BDAC"; nil when it is not a color
function Rewrite.NormalizeHex(s)
    s = ns.Trim(s):gsub("^#", ""):upper()
    if s:match("^%x%x%x%x%x%x%x%x$") then s = s:sub(3) end
    return s:match("^%x%x%x%x%x%x$") and s or nil
end

function Rewrite.HexToRGB(hex)
    hex = Rewrite.NormalizeHex(hex)
    if not hex then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function Rewrite.RGBToHex(r, g, b)
    return ("%02X%02X%02X"):format(Byte(r), Byte(g), Byte(b))
end

function Rewrite.Source() return Rewrite.NormalizeHex(Rewrite.Get("source")) or "29BDAC" end
function Rewrite.Target() return Rewrite.NormalizeHex(Rewrite.Get("target")) or "29BDAC" end

function Rewrite.Scope()
    local s = Rewrite.Get("scope")
    return Rewrite.SCOPES[s] and s or "active"
end

-- ---------------------------------------------------------------- matching
local src, tol   -- { r, g, b } as bytes; tolerance in bytes

local function IsByte(v) return type(v) == "number" and v == v and v >= 0 and v <= 1 end

local function Near(r, g, b)
    if not (IsByte(r) and IsByte(g) and IsByte(b)) then return false end
    return math.abs(Byte(r) - src[1]) <= tol and math.abs(Byte(g) - src[2]) <= tol and math.abs(Byte(b) - src[3]) <= tol
end

local function HexNear(hex6)
    local r, g, b = tonumber(hex6:sub(1, 2), 16), tonumber(hex6:sub(3, 4), 16), tonumber(hex6:sub(5, 6), 16)
    return math.abs(r - src[1]) <= tol and math.abs(g - src[2]) <= tol and math.abs(b - src[3]) <= tol
end

-- the six hex digits of a whole-string color, else nil
local function HexOf(s)
    local body = s:match("^#?(%x%x%x%x%x%x)$")
    if body then return body end
    body = s:match("^%x%x(%x%x%x%x%x%x)$")
    return body
end

local function IsArray3(t)
    local n = 0
    for k, v in pairs(t) do
        if type(k) ~= "number" or type(v) ~= "number" then return false end
        n = n + 1
    end
    return (n == 3 or n == 4) and IsByte(t[1]) and IsByte(t[2]) and IsByte(t[3]) and (n == 3 or IsByte(t[4]))
end

-- ---------------------------------------------------------------- scanning
local hits = {}        -- { root, path = { keys }, kind, key (flat prefix / string key), count }
local lastSearch       -- { source, scope, tolerance } of the current hit list

local function CopyPath(path, extra)
    local p = {}
    for i = 1, #path do p[i] = path[i] end
    if extra ~= nil then p[#p + 1] = extra end
    return p
end

local function Scan(root, t, path, seen, skipProfilesBut)
    if seen[t] then return end
    seen[t] = true
    -- the table itself is a color
    if Near(t.r, t.g, t.b) then
        hits[#hits + 1] = { root = root, path = CopyPath(path), kind = "rgb" }
        return
    end
    if IsArray3(t) then
        if Near(t[1], t[2], t[3]) then hits[#hits + 1] = { root = root, path = CopyPath(path), kind = "arr" } end
        return
    end
    -- keys in a fixed order, so the list reads the same every time
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    for _, k in ipairs(keys) do
        local v = t[k]
        if type(k) == "string" then
            -- flat triple: <prefix>R, <prefix>G, <prefix>B
            local prefix = k:match("^(.+)R$")
            if prefix and type(v) == "number" and Near(v, t[prefix .. "G"], t[prefix .. "B"]) then
                hits[#hits + 1] = { root = root, path = CopyPath(path), kind = "flat", key = prefix }
            end
        end
        if type(v) == "string" then
            local hex6 = HexOf(v)
            if hex6 then
                if HexNear(hex6) then hits[#hits + 1] = { root = root, path = CopyPath(path), kind = "hex", key = k } end
            elseif v:find("|c", 1, true) then
                local n = 0
                for code in v:gmatch("|c%x%x(%x%x%x%x%x%x)") do
                    if HexNear(code) then n = n + 1 end
                end
                if n > 0 then hits[#hits + 1] = { root = root, path = CopyPath(path), kind = "code", key = k, count = n } end
            end
        elseif type(v) == "table" then
            if not (skipProfilesBut and #path == 1 and path[1] == "profiles" and k ~= skipProfilesBut) then
                path[#path + 1] = k
                Scan(root, v, path, seen, skipProfilesBut)
                path[#path] = nil
            end
        end
    end
end

-- returns the hit list (also kept for Replace)
function Rewrite.Search()
    local r, g, b = Rewrite.HexToRGB(Rewrite.Source())
    src = { Byte(r), Byte(g), Byte(b) }
    tol = Rewrite.Get("tolerance")
    hits = {}
    local scope = Rewrite.Scope()
    local active = EUI.ActiveProfileName()
    for _, entry in ipairs(EUI.SavedTables()) do
        local name, t = entry[1], entry[2]
        -- the main table: with scope "active" only the active profile of all profiles
        local only = (scope == "active" and EUI.IsMainRoot(name) and active) or nil
        Scan(name, t, {}, {}, only)
    end
    for _, h in ipairs(hits) do h.on = true end
    lastSearch = { source = Rewrite.Source(), scope = scope, tolerance = tol }
    return hits
end

function Rewrite.Hits() return hits end

-- the hit list belongs to the current settings (else it has to be searched again)
function Rewrite.HitsCurrent()
    return lastSearch ~= nil and lastSearch.source == Rewrite.Source() and lastSearch.scope == Rewrite.Scope()
        and lastSearch.tolerance == Rewrite.Get("tolerance")
end

-- ---------------------------------------------------------------- reading and writing a hit
local function Resolve(root, path)
    local t = rawget(_G, root)
    for i = 1, #path do
        if type(t) ~= "table" then return nil end
        t = t[path[i]]
    end
    return type(t) == "table" and t or nil
end

-- a readable place: "Main > unitFrames > player > borderColor"
function Rewrite.Describe(h)
    local parts = {}
    local start = 1
    if EUI.IsMainRoot(h.root) and h.path[1] == "profiles" then
        start = 2
    elseif not EUI.IsMainRoot(h.root) then
        parts[1] = EUI.RootLabel(h.root)
    end
    for i = start, #h.path do parts[#parts + 1] = tostring(h.path[i]) end
    if h.kind == "flat" then parts[#parts + 1] = h.key .. "R/G/B"
    elseif h.kind == "hex" or h.kind == "code" then parts[#parts + 1] = tostring(h.key) end
    return table.concat(parts, " > ")
end

local function KeepCase(old, new)
    return old:match("%l") and new:lower() or new
end

-- writes the target into one hit and returns the undo record (nil when the place is gone)
local function Write(h, tr, tg, tb, thex)
    local t = Resolve(h.root, h.path)
    if not t then return nil end
    local rec = { root = h.root, path = h.path, kind = h.kind, key = h.key }
    if h.kind == "rgb" then
        rec.old = { t.r, t.g, t.b }
        t.r, t.g, t.b = tr, tg, tb
    elseif h.kind == "arr" then
        rec.old = { t[1], t[2], t[3] }
        t[1], t[2], t[3] = tr, tg, tb
    elseif h.kind == "flat" then
        local p = h.key
        rec.old = { t[p .. "R"], t[p .. "G"], t[p .. "B"] }
        t[p .. "R"], t[p .. "G"], t[p .. "B"] = tr, tg, tb
    elseif h.kind == "hex" then
        local v = t[h.key]
        if type(v) ~= "string" then return nil end
        rec.old = v
        local hash, alpha, body = v:match("^(#?)(%x?%x?)(%x%x%x%x%x%x)$")
        if not body then return nil end
        t[h.key] = hash .. alpha .. KeepCase(body, thex)
    elseif h.kind == "code" then
        local v = t[h.key]
        if type(v) ~= "string" then return nil end
        rec.old = v
        t[h.key] = v:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, code)
            if HexNear(code) then return "|c" .. a .. KeepCase(code, thex) end
        end)
    end
    return rec
end

-- replaces every ticked hit; returns the number of places changed
function Rewrite.Replace()
    if InCombatLockdown() then return 0 end
    local thex = Rewrite.Target()
    local tr, tg, tb = Rewrite.HexToRGB(thex)
    local undo = { source = Rewrite.Source(), target = thex, at = time(), records = {} }
    for _, h in ipairs(hits) do
        if h.on then
            local rec = Write(h, tr, tg, tb, thex)
            if rec then undo.records[#undo.records + 1] = rec end
        end
    end
    if #undo.records > 0 then Rewrite.Store().undo = undo end
    hits, lastSearch = {}, nil
    return #undo.records
end

function Rewrite.Undo()
    local undo = Rewrite.Store().undo
    if type(undo) ~= "table" or type(undo.records) ~= "table" or InCombatLockdown() then return 0 end
    local n = 0
    for _, rec in ipairs(undo.records) do
        local t = Resolve(rec.root, rec.path)
        if t then
            local o = rec.old
            if rec.kind == "rgb" and type(o) == "table" then t.r, t.g, t.b = o[1], o[2], o[3] n = n + 1
            elseif rec.kind == "arr" and type(o) == "table" then t[1], t[2], t[3] = o[1], o[2], o[3] n = n + 1
            elseif rec.kind == "flat" and type(o) == "table" then
                local p = rec.key
                t[p .. "R"], t[p .. "G"], t[p .. "B"] = o[1], o[2], o[3]
                n = n + 1
            elseif (rec.kind == "hex" or rec.kind == "code") and type(o) == "string" then
                t[rec.key] = o
                n = n + 1
            end
        end
    end
    Rewrite.Store().undo = nil
    hits, lastSearch = {}, nil
    return n
end

-- { source, target, count } of the saved undo set, or nil
function Rewrite.UndoInfo()
    local undo = Rewrite.Store().undo
    if type(undo) ~= "table" or type(undo.records) ~= "table" or #undo.records == 0 then return nil end
    return { source = undo.source, target = undo.target, count = #undo.records }
end

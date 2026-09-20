-- ===========================================================================
-- PLAYER SETTINGS (2026-09-18, Dragón: "a settings file like a first stage for
-- configurations for players")
-- ===========================================================================
-- One plain Lua file the player can edit, PalBonds_settings.lua. The mod writes
-- it with the defaults and a comment on every value the first time it runs, and
-- reads it once at launch; a change applies on the next launch.
--
-- WHERE IT LIVES: UE4SS's own `Mods/shared/` folder, next to the mod folders
-- rather than inside ours. An update replaces our mod folder (the Workshop even
-- re-copies it when mods are enabled), so a file inside it would be wiped; the
-- shared folder is UE4SS's, ships with every UE4SS install, and nothing of ours
-- ever replaces it. If it is missing for some reason, the file goes in our own
-- mod folder instead -- still editable, just not update-proof. The same
-- technique as DarnMenu and Random Sized Pals, both studied 2026-09-18.
--
-- RULES, so a bad edit can never break the mod:
--   * the file is loaded with an EMPTY environment: it can only return a table
--     of values, never call anything;
--   * a value that is missing, the wrong type, or out of range falls back to its
--     default, and the UE4SS console says which one and why;
--   * a file that does not even parse is left untouched (so the player can fix
--     it) and every default applies;
--   * the mod never rewrites an existing file. Settings added by a later version
--     simply use their default until the player adds the line (or deletes the
--     file to get a fresh one with everything in it).
--
-- Every value is a plain number, Dragón's call: the level and boss multipliers
-- scale the bar, so a percentage would fight them.
local Settings = {}

local FILE_NAME = "PalBonds_settings.lua"

-- The single source of truth: order, default, bounds and the comment written
-- into the file. `section` starts a new block in the written file.
local SCHEMA = {
    { section = "TRUST POINTS",
      note = "Points each interaction adds to a wild Pal's trust bar. The bar is 500 points for a Pal\n" ..
             "near your level; it is larger for Pals above your level and for bosses, smaller for Pals\n" ..
             "below it. 20% = it forgives you, 50% = it follows you, 100% = it joins you." },
    { key = "Pet",  default = 50, min = 0, max = 100000, text = "Petting a wild Pal." },
    { key = "Play", default = 50, min = 0, max = 100000, text = "Playing with a wild Pal (the Play key)." },
    { key = "FeedBase", default = 50, min = 0, max = 100000, text = "Feeding a wild Pal, before the food's rarity bonus below." },
    { key = "FeedBonusCommon",    default = 10, min = 0, max = 100000, text = "Extra for common food." },
    { key = "FeedBonusUncommon",  default = 20, min = 0, max = 100000, text = "Extra for uncommon food." },
    { key = "FeedBonusRare",      default = 30, min = 0, max = 100000, text = "Extra for rare food." },
    { key = "FeedBonusEpic",      default = 40, min = 0, max = 100000, text = "Extra for epic food." },
    { key = "FeedBonusLegendary", default = 50, min = 0, max = 100000, text = "Extra for legendary food." },
    { key = "KinshipPeachLesser", default = 250, min = 0, max = 100000, text = "Feeding a Lesser Kinship Peach (replaces the food amounts above)." },
    { key = "KinshipPeach",       default = 500, min = 0, max = 100000, text = "Feeding a Kinship Peach (replaces the food amounts above)." },
    { key = "PassivePerTick", default = 2, min = 0, max = 100000, text = "Added every 1.5 seconds while a Pal follows you. 0 turns passive gain off." },
    { key = "JoinBonus", default = 50000, min = 0, max = 200000,
      text = "The game's own friendship a Pal receives when it joins you. For scale: rank 5 is 40000,\n" ..
             "rank 6 is 55000, and 200000 is the game's highest friendship rank, so it is also the most\n" ..
             "this accepts. A higher number is ignored and the default is used." },

    { section = "PERSONALITY CHANCES",
      note = "How often each personality is rolled for a wild Pal. These are weights, not percentages:\n" ..
             "each one's chance is its number divided by the total of all seven, so they do not need to\n" ..
             "add up to 100 (the defaults just happen to). Example: Curious 100, Aloof 100 and the other\n" ..
             "five at their defaults (60 together) make a total of 260, so Curious and Aloof each get\n" ..
             "100/260, about 38%. 0 means never; each can go up to 1000. If every one is 0, the defaults\n" ..
             "are used." },
    { key = "ChanceNormal",  default = 35, min = 0, max = 1000, text = "Normal: behaves the way its species normally does." },
    { key = "ChanceCurious", default = 30, min = 0, max = 1000, text = "Curious: stops and looks at you." },
    { key = "ChanceTimid",   default = 10, min = 0, max = 1000, text = "Timid: runs away when you get close." },
    { key = "ChanceAloof",   default = 10, min = 0, max = 1000, text = "Aloof: ignores you almost completely." },
    { key = "ChanceGrumpy",  default = 5,  min = 0, max = 1000, text = "Grumpy: postures, and joins in if its own kind starts a fight." },
    { key = "ChanceHostile", default = 5,  min = 0, max = 1000, text = "Hostile: attacks you on sight." },
    { key = "ChanceFeral",   default = 5,  min = 0, max = 1000, text = "Feral: attacks anything on sight." },

    { section = "LANGUAGE",
      note = "\"auto\" follows the language you picked in Palworld's options. To force one, use:\n" ..
             "en, es, fr, de, it, pl, pt, ru, tr, vi, th, id, ja, ko, zh-hans, zh-hant" },
    { key = "Language", default = "auto", kind = "language", text = "Language of PalBonds' tags and messages." },

    { section = "DISPLAY",
      note = "The personality tag shown over a wild Pal's health bar. The Tags key below turns the tags\n" ..
             "on and off while you play; this is only what they start as when the game launches." },
    { key = "ShowPersonalityTags", default = 1, min = 0, max = 1, text = "1 starts with the personality tags shown, 0 starts with them hidden." },

    { section = "KEYS",
      note = "Key names as UE4SS spells them: F1 to F12, A to Z, ONE to NINE, NUM_ZERO to NUM_NINE,\n" ..
             "and so on. Use a key nothing else of yours is using." },
    { key = "KeyPlay",        default = "F8",  kind = "key", text = "Play with the wild Pal you are looking at." },
    { key = "KeyTags",        default = "F9",  kind = "key", text = "Show or hide the personality tags." },
    { key = "KeyPassiveGain", default = "F10", kind = "key", text = "Pause or resume passive trust gain for followers." },
}

local CHANCE_KEYS = { "ChanceNormal", "ChanceCurious", "ChanceTimid", "ChanceAloof", "ChanceGrumpy", "ChanceHostile", "ChanceFeral" }

local values = {}
local problems = {}
local sourcePath = nil
local status = "defaults"

-- Messages worth a player's attention go to the UE4SS console (and UE4SS.log),
-- which is always on. Not also through Logger: in development it prints to the
-- console too, and the line appeared twice (live run, 2026-09-18).
local function say(msg)
    pcall(function() print("[PalBonds] [SETTINGS] " .. msg .. "\n") end)
end

local function key_exists(name)
    if type(name) ~= "string" or name == "" then return false end
    local ok, v = pcall(function() return Key ~= nil and Key[name] end)
    return ok and v ~= nil
end

-- Kept here rather than read from Locale, so Settings never depends on it.
local LANGUAGE_NAMES = { auto = true, en = true, es = true, fr = true, de = true, it = true, pl = true, pt = true,
    ru = true, tr = true, vi = true, th = true, id = true, ja = true, ko = true, ["zh-hans"] = true, ["zh-hant"] = true }

local function valid_value(entry, v)
    if entry.kind == "language" then
        if type(v) ~= "string" then return nil, "must be a language name in quotes, like \"auto\" or \"es\"" end
        local lower = v:lower()
        if not LANGUAGE_NAMES[lower] then return nil, "\"" .. v .. "\" is not one of the languages listed above it" end
        return lower
    end
    if entry.kind == "key" then
        if type(v) ~= "string" then return nil, "must be a key name in quotes, like \"F8\"" end
        local upper = v:upper()
        if not key_exists(upper) then return nil, "\"" .. v .. "\" is not a key name UE4SS knows" end
        return upper
    end
    if type(v) ~= "number" or v ~= v then return nil, "must be a number" end
    if v ~= math.floor(v) then return nil, "must be a whole number" end
    if v < entry.min or v > entry.max then
        return nil, string.format("must be between %d and %d", entry.min, entry.max)
    end
    return math.floor(v)
end

-- Checks a table as read from the file. Returns the merged values (every key
-- present) and a list of human-readable problems. Pure: no file access.
function Settings.Validate(user)
    local merged, found = {}, {}
    for _, entry in ipairs(SCHEMA) do
        if entry.key then
            merged[entry.key] = entry.default
            local v = type(user) == "table" and user[entry.key] or nil
            if v ~= nil then
                local good, why = valid_value(entry, v)
                if good ~= nil then
                    merged[entry.key] = good
                else
                    found[#found + 1] = entry.key .. " " .. why .. " — using the default (" .. tostring(entry.default) .. ")"
                end
            end
        end
    end

    local total = 0
    for _, k in ipairs(CHANCE_KEYS) do total = total + merged[k] end
    if total <= 0 then
        found[#found + 1] = "every personality chance is 0 — using the default chances"
        for _, entry in ipairs(SCHEMA) do
            if entry.key and entry.key:find("^Chance") then merged[entry.key] = entry.default end
        end
    end

    if type(user) == "table" then
        local known = {}
        for _, entry in ipairs(SCHEMA) do if entry.key then known[entry.key] = true end end
        for k in pairs(user) do
            if not known[k] then found[#found + 1] = "\"" .. tostring(k) .. "\" is not a PalBonds setting (typo?) — ignored" end
        end
    end
    return merged, found
end

-- How one SCHEMA entry is written into the file. Shared by the fresh file and
-- by the settings a later version appends, so a value can never be written two
-- different ways.
local function write_section(entry, out)
    out[#out + 1] = ""
    out[#out + 1] = "    -- ===== " .. entry.section .. " ====="
    for line in (entry.note .. "\n"):gmatch("(.-)\n") do out[#out + 1] = "    -- " .. line end
    out[#out + 1] = ""
end

local function write_entry(entry, out)
    for line in (entry.text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = "    -- " .. line end
    local shown = type(entry.default) == "string" and string.format("%q", entry.default) or tostring(entry.default)
    out[#out + 1] = "    " .. entry.key .. " = " .. shown .. ","
end

-- The text of a fresh settings file, built from SCHEMA so the two can never
-- disagree.
function Settings.DefaultFileText()
    local out = {
        "-- PalBonds settings",
        "--",
        "-- Change a number (or a key name), save, and restart the game: settings are read once",
        "-- when the game starts. A value that is missing or out of range uses its default, and",
        "-- the UE4SS console says so. Delete this file to get a fresh one with every default.",
        "",
        "return {",
    }
    for _, entry in ipairs(SCHEMA) do
        if entry.section then write_section(entry, out) else write_entry(entry, out) end
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

-- ===========================================================================
-- SETTINGS ADDED BY A LATER VERSION (2026-09-20)
-- ===========================================================================
-- Until now an existing file was never touched, so a setting added by a new
-- version only reached players who deleted their file -- and every future
-- setting would ask them to do it again, throwing away their own values each
-- time. niconoko's request (Nexus, 2026-09-19) for the tags to start hidden is
-- the first setting this would have happened to.
--
-- So a missing setting is now added to the file the player already has. The
-- file is never rewritten or reformatted: this is an INSERTION before its last
-- "}", so every value, comment and blank line they wrote stays exactly where it
-- was. And nothing is written until the result has been read back and checked
-- (Settings.AppendedTextIsGood below) -- if the insertion produced anything the
-- mod would not load, the file is left untouched and the console says so.

-- Returns the player's file text with a block for the missing settings added,
-- or nil if there is nothing to add or no "}" to add it before.
function Settings.TextWithMissingKeys(existing, missingKeys)
    if type(existing) ~= "string" or type(missingKeys) ~= "table" or #missingKeys == 0 then return nil end
    local wanted = {}
    for _, k in ipairs(missingKeys) do wanted[k] = true end

    local block = {
        "",
        "    -- ===== ADDED BY A NEWER PALBONDS =====",
        "    -- These settings did not exist when this file was made, so they were added here with",
        "    -- their default values. Nothing else in the file was changed.",
        "",
    }
    local added = 0
    for _, entry in ipairs(SCHEMA) do
        if entry.key and wanted[entry.key] then
            write_entry(entry, block)
            added = added + 1
        end
    end
    if added == 0 then return nil end

    local lastBrace = nil
    for pos in existing:gmatch("()}") do lastBrace = pos end
    if lastBrace == nil then return nil end

    local head, tail = existing:sub(1, lastBrace - 1), existing:sub(lastBrace)
    -- A file whose last value has no comma after it ("return { Pet = 80 }")
    -- needs one before anything can follow it.
    local trimmed = head:gsub("%s*$", "")
    local lastChar = trimmed:sub(-1)
    if lastChar ~= "," and lastChar ~= ";" and lastChar ~= "{" then
        head = trimmed .. ","
    end
    if head:sub(-1) ~= "\n" then head = head .. "\n" end
    return head .. table.concat(block, "\n") .. "\n" .. tail
end

-- Reads the would-be file back the way the mod really reads one (empty
-- environment, must return a table) and checks that every value the player had
-- survived and every added setting arrived at its default.
function Settings.AppendedTextIsGood(newText, user, missingKeys)
    if type(newText) ~= "string" then return false end
    local ok, result = pcall(function()
        local chunk = load(newText, "PalBonds_settings check", "t", {})
        if chunk == nil then return false end
        local ranOk, t = pcall(chunk)
        if not ranOk or type(t) ~= "table" then return false end
        for k, v in pairs(user or {}) do
            if t[k] ~= v then return false end
        end
        for _, k in ipairs(missingKeys or {}) do
            for _, entry in ipairs(SCHEMA) do
                if entry.key == k and t[k] ~= entry.default then return false end
            end
        end
        return true
    end)
    return ok and result == true
end

local function scripts_dir()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if not ok or type(src) ~= "string" then return nil end
    src = src:gsub("^@", "")
    return src:match("^(.*)[/\\][^/\\]+$")
end

-- "C:/x/Mods/PalBonds/Scripts/../../shared/f" -> "C:/x/Mods/shared/f", so the
-- console shows a path a player can actually follow.
local function tidy_path(p)
    p = p:gsub("\\", "/")
    local out = {}
    for part in p:gmatch("[^/]+") do
        if part == ".." and #out > 0 and out[#out] ~= ".." then
            out[#out] = nil
        elseif part ~= "." then
            out[#out + 1] = part
        end
    end
    return (p:sub(1, 1) == "/" and "/" or "") .. table.concat(out, "/")
end

-- Where the file may live, best first: UE4SS's shared folder, then our own mod
-- folder. Both are relative to this script (Mods/PalBonds/Scripts/).
local function candidate_paths()
    local dir = scripts_dir()
    if dir == nil then return {} end
    return {
        tidy_path(dir .. "/../../shared/" .. FILE_NAME),
        tidy_path(dir .. "/../" .. FILE_NAME),
    }
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f == nil then return false end
    f:close()
    return true
end

-- Written to a temporary file first and then renamed, so a crash mid-write can
-- never leave the player with a half-written file.
local function write_text_file(path, text)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if f == nil then return false end
    local ok = f:write(text)
    f:close()
    if not ok then os.remove(tmp) return false end

    -- Windows' os.rename FAILS when the destination already exists, so an
    -- existing file is moved aside first and only deleted once the new one is
    -- safely in place -- and put straight back if anything goes wrong. Found
    -- live (2026-09-20): the first launch of 1.1.6 could create a settings
    -- file but never replace one, which is every launch after the first.
    local bak = nil
    local current = io.open(path, "r")
    if current ~= nil then
        current:close()
        bak = path .. ".bak"
        os.remove(bak)
        if not os.rename(path, bak) then os.remove(tmp) return false end
    end
    if not os.rename(tmp, path) then
        os.remove(tmp)
        if bak ~= nil then os.rename(bak, path) end
        return false
    end
    if bak ~= nil then os.remove(bak) end
    return true
end

local function write_default_file(path)
    return write_text_file(path, Settings.DefaultFileText())
end

-- Adds the settings this version has and the player's file does not.
local function append_missing_settings(path, user, missing)
    local list = table.concat(missing, ", ")
    local existing = nil
    local f = io.open(path, "r")
    if f ~= nil then
        existing = f:read("*a")
        f:close()
    end
    local updated = Settings.TextWithMissingKeys(existing, missing)
    if updated == nil or not Settings.AppendedTextIsGood(updated, user, missing) then
        say("could not add " .. list .. " to your settings file — it was left exactly as it is and " ..
            "those settings use their defaults. Delete the file to get a fresh one with every setting in it.")
        return
    end
    if write_text_file(path, updated) then
        say("added " .. list .. " to " .. path .. " (your own values were kept)")
    else
        say("could not write " .. path .. " — " .. list .. " use their defaults")
    end
end

function Settings.Load()
    values, problems, sourcePath, status = Settings.Validate(nil), {}, nil, "defaults"
    local ok, err = pcall(function()
        local paths = candidate_paths()
        for _, p in ipairs(paths) do
            if file_exists(p) then sourcePath = p break end
        end
        if sourcePath == nil then
            for _, p in ipairs(paths) do
                if write_default_file(p) then
                    sourcePath = p
                    status = "created"
                    say("created " .. p .. " with the default settings")
                    return
                end
            end
            say("could not create a settings file — using the defaults")
            return
        end
        local chunk, loadErr = loadfile(sourcePath, "t", {})
        if chunk == nil then
            status = "unreadable"
            say("could not read " .. sourcePath .. " (" .. tostring(loadErr) .. ") — using every default. The file was left as it is so you can fix it.")
            return
        end
        local okRun, user = pcall(chunk)
        if not okRun or type(user) ~= "table" then
            status = "unreadable"
            say(sourcePath .. " does not return a table of settings — using every default. The file was left as it is.")
            return
        end
        values, problems = Settings.Validate(user)
        status = "loaded"
        say("loaded " .. sourcePath)
        for _, p in ipairs(problems) do say(p) end

        local missing = {}
        for _, entry in ipairs(SCHEMA) do
            if entry.key and user[entry.key] == nil then missing[#missing + 1] = entry.key end
        end
        if #missing > 0 then append_missing_settings(sourcePath, user, missing) end
    end)
    if not ok then
        values = Settings.Validate(nil)
        status = "defaults"
        say("settings could not be loaded (" .. tostring(err) .. ") — using the defaults")
    end
end

function Settings.Get(key)
    local v = values[key]
    if v == nil then
        for _, entry in ipairs(SCHEMA) do
            if entry.key == key then return entry.default end
        end
    end
    return v
end

-- For the log and tests: where the settings came from and what was wrong.
function Settings.Status() return status, sourcePath, problems end

Settings.Load()
return Settings

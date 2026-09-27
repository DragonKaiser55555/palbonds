local Settings = {}

local FILE_NAME = "PalBonds_settings.lua"

local SCHEMA = {
    { section = "LANGUAGE", label = "sec_language",
      note = "\"auto\" follows the language you picked in Palworld's options. To force one, use:\n" ..
             "en, es, fr, de, it, pl, pt, ru, tr, vi, th, id, ja, ko, zh-hans, zh-hant" },
    { key = "Language", default = "auto", kind = "language", label = "set_language", ui = { kind = "choice" }, text = "Language of PalBonds' tags and messages." },

    { section = "TRUST POINTS", label = "sec_trust",
      note = "Points each interaction adds to a wild Pal's trust bar. The bar is 500 points for a Pal\n" ..
             "near your level; it is larger for Pals above your level and for bosses, smaller for Pals\n" ..
             "below it. 20% = it forgives you, 50% = it follows you, 100% = it joins you." },
    { key = "Pet",  default = 50, min = 0, max = 100000, label = "set_pet", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Petting a wild Pal." },
    { key = "Play", default = 50, min = 0, max = 100000, label = "set_play", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Playing with a wild Pal (the Play key)." },
    { key = "FeedBase", default = 50, min = 0, max = 100000, label = "set_feed", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Feeding a wild Pal, before the food's rarity bonus below." },
    { key = "FeedBonusCommon",    default = 10, min = 0, max = 100000, label = "set_feed_common", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Extra for common food." },
    { key = "FeedBonusUncommon",  default = 20, min = 0, max = 100000, label = "set_feed_uncommon", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Extra for uncommon food." },
    { key = "FeedBonusRare",      default = 30, min = 0, max = 100000, label = "set_feed_rare", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Extra for rare food." },
    { key = "FeedBonusEpic",      default = 40, min = 0, max = 100000, label = "set_feed_epic", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Extra for epic food." },
    { key = "FeedBonusLegendary", default = 50, min = 0, max = 100000, label = "set_feed_legendary", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Extra for legendary food." },
    { key = "KinshipPeachLesser", default = 250, min = 0, max = 100000, label = "set_peach_lesser", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Feeding a Lesser Kinship Peach (replaces the food amounts above)." },
    { key = "KinshipPeach",       default = 500, min = 0, max = 100000, label = "set_peach", ui = { kind = "slider", min = 0, max = 1000, step = 10 }, text = "Feeding a Kinship Peach (replaces the food amounts above)." },
    { key = "PassivePerTick", default = 2, min = 0, max = 100000, label = "set_passive", ui = { kind = "slider", min = 0, max = 100, step = 1 }, text = "Added every 1.5 seconds while a Pal follows you. 0 turns passive gain off." },
    { key = "JoinBonus", default = 50000, min = 0, max = 200000, label = "set_join", ui = { kind = "slider", min = 0, max = 200000, step = 5000 },
      text = "The game's own friendship a Pal receives when it joins you. For scale: rank 5 is 40000,\n" ..
             "rank 6 is 55000, and 200000 is the game's highest friendship rank, so it is also the most\n" ..
             "this accepts. A higher number is ignored and the default is used." },

    { section = "PERSONALITY CHANCES", label = "sec_personality",
      note = "Each personality has two settings: how often it is rolled, and whether a Pal with it can bond\n" ..
             "with you at all. Turning one off leaves those Pals in the world, tagged as usual, but they\n" ..
             "never respond to petting, feeding or playing.\n" ..
             "\n" ..
             "The chances are weights, not percentages:\n" ..
             "each one's chance is its number divided by the total of all seven, so they do not need to\n" ..
             "add up to 100 (the defaults just happen to). Example: Curious 100, Aloof 100 and the other\n" ..
             "five at their defaults (60 together) make a total of 260, so Curious and Aloof each get\n" ..
             "100/260, about 38%. 0 means never; each can go up to 1000. If every one is 0, the defaults\n" ..
             "are used." },
    { key = "ChanceNormal",  default = 35, min = 0, max = 1000, label = "tag_normal", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Normal: behaves the way its species normally does." },
    { key = "BondNormal", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_normal",
      ui = { kind = "switch" }, text = "1 lets a Normal Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceCurious", default = 30, min = 0, max = 1000, label = "tag_curious", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Curious: stops and looks at you." },
    { key = "BondCurious", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_curious",
      ui = { kind = "switch" }, text = "1 lets a Curious Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceTimid",   default = 10, min = 0, max = 1000, label = "tag_timid", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Timid: runs away when you get close." },
    { key = "BondTimid", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_timid",
      ui = { kind = "switch" }, text = "1 lets a Timid Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceAloof",   default = 10, min = 0, max = 1000, label = "tag_aloof", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Aloof: ignores you almost completely." },
    { key = "BondAloof", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_aloof",
      ui = { kind = "switch" }, text = "1 lets a Aloof Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceGrumpy",  default = 5,  min = 0, max = 1000, label = "tag_grumpy", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Grumpy: postures, and joins in if its own kind starts a fight." },
    { key = "BondGrumpy", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_grumpy",
      ui = { kind = "switch" }, text = "1 lets a Grumpy Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceHostile", default = 5,  min = 0, max = 1000, label = "tag_hostile", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Hostile: attacks you on sight." },
    { key = "BondHostile", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_hostile",
      ui = { kind = "switch" }, text = "1 lets a Hostile Pal bond with you. 0 means it never can, however much you try." },
    { key = "ChanceFeral",   default = 5,  min = 0, max = 1000, label = "tag_feral", ui = { kind = "slider", min = 0, max = 100, step = 5 }, text = "Feral: attacks anything on sight." },
    { key = "BondFeral", default = 1, min = 0, max = 1, label = "set_bondable", labelPrefix = "tag_feral",
      ui = { kind = "switch" }, text = "1 lets a Feral Pal bond with you. 0 means it never can, however much you try." },

    { section = "MODULES", label = "sec_display",
      note = "The personality tag shown over a wild Pal's health bar. The Tags key below turns the tags\n" ..
             "on and off while you play; this is only what they start as when the game launches." },
    { key = "ShowPersonalityTags", default = 1, min = 0, max = 1, label = "set_tags", ui = { kind = "switch" }, text = "1 starts with the personality tags shown, 0 starts with them hidden." },
    { key = "PassiveGainEnabled", default = 1, min = 0, max = 1, label = "set_passive_enabled", ui = { kind = "switch" },
      text = "1 starts with passive friendship gain on, 0 starts with it off. The key below switches it\n" ..
             "either way while you play; this is only what it starts as." },
    { key = "AbandonmentEnabled", default = 1, min = 0, max = 1, label = "set_abandonment", ui = { kind = "switch" },
      text = "1 means a Pal you leave far behind gives up on you and the bond ends. 0 means it waits for you,\n" ..
             "however far you go." },
    { key = "BetrayalEnabled", default = 1, min = 0, max = 1, label = "set_betrayal", ui = { kind = "switch" },
      text = "1 means hitting a Pal you are bonding with can end the bond for good. 0 means it forgives you,\n" ..
             "however many times." },

    { section = "ACCESSIBILITY", label = "sec_accessibility",
      note = "How the friendship bar and the personality tag are drawn over a wild Pal. Colours are named,\n" ..
             "and the tag size is relative to the Pal\'s own name, so it stays right at any UI scale." },
    { key = "BarColor", default = "gold", kind = "choice",
      values = { "gold", "white", "red", "green", "blue", "purple" },
      label = "set_bar_color", ui = { kind = "choice" }, text = "Colour of the friendship bar." },
    { key = "TagColor", default = "name", kind = "choice",
      values = { "name", "gold", "white", "red", "green", "blue", "purple" },
      label = "set_tag_color", ui = { kind = "choice" },
      text = "Colour of the personality tag. \"name\" copies the Pal\'s own name colour, as it always has." },
    { key = "TagSize", default = "normal", kind = "choice",
      values = { "small", "normal", "large", "huge" },
      label = "set_tag_size", ui = { kind = "choice" }, text = "Size of the personality tag." },

    { section = "KEYS", label = "sec_keys",
      note = "Key names as UE4SS spells them: F1 to F12, A to Z, ONE to NINE, NUM_ZERO to NUM_NINE,\n" ..
             "and so on. Use a key nothing else of yours is using." },
    { key = "KeyPlay",        default = "F8",  kind = "key", label = "set_key_play", ui = { kind = "key" }, text = "Play with the wild Pal you are looking at." },
    { key = "KeyTags",        default = "F9",  kind = "key", label = "set_key_tags", ui = { kind = "key" }, text = "Show or hide the personality tags." },
    { key = "KeyPassiveGain", default = "F10", kind = "key", label = "set_key_passive", ui = { kind = "key" }, text = "Pause or resume passive trust gain for followers." },
}

local CHANCE_KEYS = { "ChanceNormal", "ChanceCurious", "ChanceTimid", "ChanceAloof", "ChanceGrumpy", "ChanceHostile", "ChanceFeral" }

local values = {}
local problems = {}
local sourcePath = nil
local status = "defaults"

local function say(msg)
    pcall(function() print("[PalBonds] [SETTINGS] " .. msg .. "\n") end)
end

local function key_exists(name)
    if type(name) ~= "string" or name == "" then return false end
    local ok, v = pcall(function() return Key ~= nil and Key[name] end)
    return ok and v ~= nil
end

local squashedKeys = nil

local function build_key_lookup()
    squashedKeys = {}
    local names = {}
    pcall(function()
        for name in pairs(Key or {}) do
            if type(name) == "string" then names[#names + 1] = name end
        end
    end)
    for _, name in ipairs(names) do
        local upper = name:upper()
        squashedKeys[(upper:gsub("[^A-Z0-9]", ""))] = upper
    end
end

local function resolve_key_name(v)
    if type(v) ~= "string" or v == "" then return nil end
    local upper = v:upper()
    if key_exists(upper) then return upper end
    if squashedKeys == nil then build_key_lookup() end
    return squashedKeys[(upper:gsub("[^A-Z0-9]", ""))]
end

local LANGUAGE_NAMES = { auto = true, en = true, es = true, fr = true, de = true, it = true, pl = true, pt = true,
    ru = true, tr = true, vi = true, th = true, id = true, ja = true, ko = true, ["zh-hans"] = true, ["zh-hant"] = true }

local function valid_value(entry, v)
    if entry.kind == "language" then
        if type(v) ~= "string" then return nil, "must be a language name in quotes, like \"auto\" or \"es\"" end
        local lower = v:lower()
        if not LANGUAGE_NAMES[lower] then return nil, "\"" .. v .. "\" is not one of the languages listed above it" end
        return lower
    end

    if entry.kind == "choice" then
        local allowed = table.concat(entry.values or {}, ", ")
        if type(v) ~= "string" then return nil, "must be one of: " .. allowed end
        local lower = v:lower()
        for _, name in ipairs(entry.values or {}) do
            if lower == name then return lower end
        end
        return nil, "must be one of: " .. allowed
    end
    if entry.kind == "key" then
        if type(v) ~= "string" then return nil, "must be a key name in quotes, like \"F8\"" end
        local resolved = resolve_key_name(v)
        if resolved == nil then return nil, "\"" .. v .. "\" is not a key name UE4SS knows" end
        return resolved
    end
    if type(v) ~= "number" or v ~= v then return nil, "must be a number" end
    if v ~= math.floor(v) then return nil, "must be a whole number" end
    if v < entry.min or v > entry.max then
        return nil, string.format("must be between %d and %d", entry.min, entry.max)
    end
    return math.floor(v)
end

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

    local trimmed = head:gsub("%s*$", "")
    local lastChar = trimmed:sub(-1)
    if lastChar ~= "," and lastChar ~= ";" and lastChar ~= "{" then
        head = trimmed .. ","
    end
    if head:sub(-1) ~= "\n" then head = head .. "\n" end
    return head .. table.concat(block, "\n") .. "\n" .. tail
end

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

local function write_text_file(path, text)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if f == nil then return false end
    local ok = f:write(text)
    f:close()
    if not ok then os.remove(tmp) return false end

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

function Settings.Status() return status, sourcePath, problems end

local listeners = {}
local dirty = {}

function Settings.OnChange(fn)
    if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function announce(key, value)
    for _, fn in ipairs(listeners) do

        pcall(fn, key, value)
    end
end

function Settings.Entry(key)
    for _, entry in ipairs(SCHEMA) do
        if entry.key == key then return entry end
    end
    return nil
end

function Settings.Schema() return SCHEMA end

local function key_settings()
    local found = {}
    for _, entry in ipairs(SCHEMA) do
        if entry.kind == "key" then found[#found + 1] = entry.key end
    end
    return found
end

local function extra_rule(entry, good)
    if entry.key ~= nil and entry.key:find("^Chance") then
        local total = 0
        for _, k in ipairs(CHANCE_KEYS) do
            total = total + (k == entry.key and good or values[k])
        end
        if total <= 0 then
            return nil, "at least one personality needs a chance above 0"
        end
    end
    if entry.kind == "key" then
        for _, other in ipairs(key_settings()) do
            if other ~= entry.key and values[other] == good then
                return nil, "that key is already used by " .. other
            end
        end
    end
    return good
end

function Settings.Set(key, value)
    local entry = Settings.Entry(key)
    if entry == nil then return nil, "not a PalBonds setting" end
    local good, why = valid_value(entry, value)
    if good == nil then return nil, why end
    good, why = extra_rule(entry, good)
    if good == nil then return nil, why end
    if values[key] == good then return good end
    values[key] = good
    dirty[key] = true
    announce(key, good)
    return good
end

function Settings.Discard()
    dirty = {}
end

function Settings.IsDirty()
    for _ in pairs(dirty) do return true end
    return false
end

local function shown_value(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function end_of_value(text, from)
    local c = text:sub(from, from)
    if c == "" then return nil end
    if c == '"' or c == "'" then
        local i = from + 1
        while i <= #text do
            local ch = text:sub(i, i)
            if ch == "\\" then
                i = i + 2
            elseif ch == c then
                return i + 1
            elseif ch == "\n" then
                return nil
            else
                i = i + 1
            end
        end
        return nil
    end
    local stop = text:find("[^%w%.%-%+]", from)
    if stop == nil then return #text + 1 end
    if stop == from then return nil end
    return stop
end

local function code_mask(text)
    local out, i, n = {}, 1, #text
    local function keep(j) out[#out + 1] = text:sub(j, j) end
    local function blank(j)

        out[#out + 1] = (text:sub(j, j) == "\n") and "\n" or " "
    end
    while i <= n do
        local c = text:sub(i, i)
        if c == "-" and text:sub(i + 1, i + 1) == "-" then
            local openEq = text:match("^%[(=*)%[", i + 2)
            if openEq ~= nil then
                if #openEq > 0 then return nil end
                local closeAt = text:find("]]", i + 4, true)
                local stop = closeAt ~= nil and (closeAt + 1) or n
                for j = i, stop do blank(j) end
                i = stop + 1
            else
                local nl = text:find("\n", i, true) or (n + 1)
                for j = i, nl - 1 do blank(j) end
                i = nl
            end
        elseif c == '"' or c == "'" then
            keep(i)
            local j = i + 1
            while j <= n do
                local ch = text:sub(j, j)
                if ch == "\\" then
                    blank(j)
                    if j + 1 <= n then blank(j + 1) end
                    j = j + 2
                elseif ch == c or ch == "\n" then
                    break
                else
                    blank(j)
                    j = j + 1
                end
            end
            if j > n or text:sub(j, j) ~= c then return nil end
            keep(j)
            i = j + 1
        else
            keep(i)
            i = i + 1
        end
    end
    return table.concat(out)
end

local function value_position(text, key)
    local mask = code_mask(text)
    if mask == nil then return nil end
    local at = 1
    while true do
        local a, b = mask:find(key .. "[ \t]*=[ \t]*", at)
        if a == nil then return nil end

        local before = a > 1 and mask:sub(a - 1, a - 1) or ""
        if not before:match("[%w_%.:]") then return b + 1 end
        at = a + 1
    end
end

function Settings.TextWithValues(existing, changes)
    if type(existing) ~= "string" or type(changes) ~= "table" then return nil end
    local text = existing
    for key, value in pairs(changes) do
        if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") then return nil end
        local valueAt = value_position(text, key)
        if valueAt == nil then return nil end
        local valueEnd = end_of_value(text, valueAt)
        if valueEnd == nil then return nil end
        text = text:sub(1, valueAt - 1) .. shown_value(value) .. text:sub(valueEnd)
    end
    return text
end

function Settings.UpdatedTextIsGood(newText, expected, untouched)
    if type(newText) ~= "string" then return false end
    local ok, result = pcall(function()
        local chunk = load(newText, "PalBonds_settings check", "t", {})
        if chunk == nil then return false end
        local ranOk, t = pcall(chunk)
        if not ranOk or type(t) ~= "table" then return false end
        for k, v in pairs(expected or {}) do
            if t[k] ~= v then return false end
        end
        for k, v in pairs(untouched or {}) do
            if t[k] ~= v then return false end
        end
        return true
    end)
    return ok and result == true
end

function Settings.Flush()
    local changes, any = {}, false
    for k in pairs(dirty) do changes[k] = values[k]; any = true end
    if not any then return true end
    if sourcePath == nil or status == "unreadable" then

        say("your settings file could not be updated, so these changes last until you close the game")
        dirty = {}
        return false
    end
    local f = io.open(sourcePath, "r")
    local existing = nil
    if f ~= nil then
        existing = f:read("*a")
        f:close()
    end
    local updated = Settings.TextWithValues(existing, changes)

    local untouched = {}
    for _, entry in ipairs(SCHEMA) do
        if entry.key and changes[entry.key] == nil then untouched[entry.key] = values[entry.key] end
    end
    if updated == nil or not Settings.UpdatedTextIsGood(updated, changes, untouched) then
        say("could not save your settings into " .. tostring(sourcePath) ..
            " — it was left exactly as it is, and your changes last until you close the game")
        dirty = {}
        return false
    end
    if not write_text_file(sourcePath, updated) then
        say("could not write " .. sourcePath .. " — your changes last until you close the game")
        dirty = {}
        return false
    end
    dirty = {}
    return true
end

Settings.Load()
return Settings

--[[
    PalBonds -- what a guest SEES: trust bars and personality tags drawn from
    the host's numbers (co-op stage 3, 2026-09-21).

    WHY. In a shared world every trust record, every rolled personality and
    every bond lives on the machine that owns the world (Net.lua has the
    history). A guest's copy draws nameplates on its own screen, but it has
    nothing true to draw: co-op run 1 bonded and joined a Cattiva with no bar
    and no tag on the guest's screen at all.

    HOW. Two halves in one file.

      * On the machine that owns the world (a host or a dedicated server):
        every SEND_EVERY_MS, for each player on ANOTHER machine, the Pals this
        machine knows near that player are summarised -- personality, bar,
        bonding, broken bond, and whose bond it is from that player's point of
        view -- and whatever changed since the last message to that player is
        sent in one INFO message over the private line. In singleplayer it
        returns before looking at anything.

      * On a guest: the INFO records are kept by Pal (stable id, the same on
        every machine), and the handful of functions the nameplate code reads
        -- Trust.GetBarRatio / HasBondingState, Personality.GetDisposition /
        IsFemale, Capture.HasPermanentlyFled / GetFledReason,
        Combat.ClaimedByAnotherPlayer -- answer from here instead of from local
        state that a guest never has. Indicator itself is unchanged.

    Nothing here writes to a Pal or to the world. A guest that never receives
    an INFO simply shows what it showed before: no bar, "?" tags.
]]

local Logger = require("Logger")

local HostView = {}

local SEND_EVERY_MS = 2000
local NEAR = 6000               -- a nameplate is only drawn this close anyway
local RECORD_SEP = "\31"        -- between Pal records inside one message
local FIELD_SEP = "\30"         -- between a record's fields

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function valid(o)
    return o ~= nil and safe_call(function() return o:IsValid() end) == true
end

local function session_mode()
    local ok, Session = pcall(require, "Session")
    if not ok or Session == nil or Session.Mode == nil then return nil end
    return safe_call(Session.Mode)
end

local function we_are_a_guest()
    return session_mode() == "client"
end
HostView.IsGuest = we_are_a_guest

-- ===================================================================
-- GUEST SIDE: the cache and the answers
-- ===================================================================
-- palId -> { disp, ratio (0..1), bond, female, fled, rel ("mine"/"other"/"") }
local cache = {}
-- actor address -> palId, so the nameplate tick does not rebuild the id
-- (several reflection calls) for the same actor every two seconds.
local idByAddress = {}

local function id_of(actor)
    if actor == nil then return nil end
    local addr = safe_call(function() return actor:GetAddress() end)
    if addr ~= nil and idByAddress[addr] ~= nil then return idByAddress[addr] end
    local id = safe_call(function() return require("Personality").GetStableId(actor) end)
    if id ~= nil and addr ~= nil then idByAddress[addr] = id end
    return id
end

local function entry_for_actor(actor)
    local id = id_of(actor)
    return id and cache[id] or nil
end

function HostView.Ratio(actor)
    local e = entry_for_actor(actor)
    return e and e.ratio or 0
end

function HostView.HasBond(actor)
    local e = entry_for_actor(actor)
    return e ~= nil and (e.bond == true or (e.ratio or 0) > 0)
end

-- A Pal the host has not described yet, asked for at most every ASK_AGAIN_SECONDS.
local askQueue = {}
local askedAt = {}
local askCount = {}
local ASK_AGAIN_SECONDS = 10
-- Co-op run 3: a few Pals were asked about 11-15 times -- ones the guest can
-- see but the host never describes (too far from the guest for the host to
-- find, or not a wild Pal at all). After ASK_TRIES unanswered asks the same
-- Pal is asked again only every ASK_LATER_SECONDS, in case it comes closer.
local ASK_TRIES = 3
local ASK_LATER_SECONDS = 60

function HostView.Disposition(palId)
    local e = palId and cache[palId] or nil
    if e == nil and palId ~= nil then
        -- A nameplate is showing this Pal with nothing to say about it: ask.
        local now = os.clock()
        local wait = ((askCount[palId] or 0) < ASK_TRIES) and ASK_AGAIN_SECONDS or ASK_LATER_SECONDS
        if askedAt[palId] == nil or (now - askedAt[palId]) >= wait then
            askQueue[palId] = true
        end
    end
    return e and e.disp or nil
end

function HostView.Female(palId)
    local e = palId and cache[palId] or nil
    return e ~= nil and e.female == true
end

function HostView.FledReason(actor)
    local e = entry_for_actor(actor)
    if e == nil or e.fled == nil or e.fled == "" then return nil end
    return e.fled
end

function HostView.ClaimedByOther(actor)
    local e = entry_for_actor(actor)
    return e ~= nil and e.rel == "other"
end

local heardFromHost = false

-- Co-op run 3b (2026-09-21): a guest's dungeon loading screen counts as a new
-- world here (its character is briefly not its own), which empties this cache
-- -- but the host only sends what CHANGED, so everything unchanged would
-- never come back and the drawing would wait for a hello that never repeats.
-- After a reset the guest asks the host to start it over (RESYNC).
local resyncWanted = false

-- True once the host's PalBonds has sent this guest anything at all.
function HostView.HostHasPalBonds()
    return heardFromHost
end

function HostView.Reset()
    cache = {}
    idByAddress = {}
    heardFromHost = false
    askQueue = {}
    askedAt = {}
    askCount = {}
    resyncWanted = true
end

-- The guest's side of starting over: once its character is back, one RESYNC.
-- Exposed for the harness. Returns true when sent.
function HostView.SendResync()
    if not resyncWanted or not we_are_a_guest() then return false end
    local okRef, PlayerRef = pcall(require, "PlayerRef")
    if not (okRef and PlayerRef and PlayerRef.Get and PlayerRef.Get() ~= nil) then return false end
    local okNet, Net = pcall(require, "Net")
    if okNet and Net and Net.SendToServer("RESYNC") == true then
        resyncWanted = false
        return true
    end
    return false
end

-- The guest's side of asking: one ASK with every waiting id (at most 24).
-- Exposed for the harness. Returns how many ids were asked for.
function HostView.SendAsks()
    if not we_are_a_guest() or not heardFromHost then return 0 end
    local ids = {}
    local now = os.clock()
    for palId in pairs(askQueue) do
        if #ids >= 24 then break end
        ids[#ids + 1] = palId
        askedAt[palId] = now
        askCount[palId] = (askCount[palId] or 0) + 1
    end
    for _, palId in ipairs(ids) do askQueue[palId] = nil end
    if #ids == 0 then return 0 end
    local okNet, Net = pcall(require, "Net")
    if okNet and Net then Net.SendToServer("ASK", table.concat(ids, RECORD_SEP)) end
    return #ids
end

-- One INFO message: records separated by RECORD_SEP, fields by FIELD_SEP:
--   palId, disposition, bar percent (0-100), bonding (0/1), female (0/1),
--   fled reason, relation
local function accept_info(text)
    if type(text) ~= "string" or text == "" then return 0 end
    local n = 0
    for rec in (text .. RECORD_SEP):gmatch("(.-)" .. RECORD_SEP) do
        local f = {}
        for field in (rec .. FIELD_SEP):gmatch("(.-)" .. FIELD_SEP) do f[#f + 1] = field end
        local palId = f[1]
        if palId ~= nil and palId ~= "" then
            local pct = tonumber(f[3]) or 0
            if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
            cache[palId] = {
                disp = (f[2] ~= nil and f[2] ~= "") and f[2] or nil,
                ratio = pct / 100,
                bond = f[4] == "1",
                female = f[5] == "1",
                fled = (f[6] ~= nil and f[6] ~= "") and f[6] or nil,
                rel = f[7] or "",
            }
            n = n + 1
        end
    end
    return n
end
HostView.AcceptInfo = accept_info

-- ===================================================================
-- HOST SIDE: summarise and send
-- ===================================================================
-- owner key -> { palId -> the record text last sent to that player }
local sentTo = {}

local function record_for(palId, pawn, state, viewer, viewerKey)
    local Trust = require("Trust")
    local PlayerRef = require("PlayerRef")
    -- The bar's size depends on the player's level: measured for the viewer.
    local ratio = safe_call(function()
        return PlayerRef.WithPlayer(viewer, Trust.GetBarRatio, pawn)
    end) or 0
    local pct = math.floor(ratio * 100 + 0.5)
    local bond = safe_call(function() return Trust.HasBondingState(pawn) end) == true
    local female = state ~= nil and state.female == true
    local fled = ""
    local okCap, Capture = pcall(require, "Capture")
    if okCap and Capture and Capture.HasPermanentlyFled
       and safe_call(function() return Capture.HasPermanentlyFled(pawn) end) then
        fled = tostring(safe_call(function() return Capture.GetFledReason(pawn) end) or "betrayed")
    end
    local rel = ""
    local ownerKey = safe_call(function() return Trust.GetOwnerKey(pawn) end)
    if ownerKey ~= nil then rel = (ownerKey == viewerKey) and "mine" or "other" end
    return table.concat({
        palId, tostring(state and state.disposition or ""), tostring(pct),
        bond and "1" or "0", female and "1" or "0", fled, rel,
    }, FIELD_SEP)
end

local function remote_players()
    local out = {}
    local all = safe_call(function() return FindAllOf("PalPlayerCharacter") end) or {}
    local PlayerRef = require("PlayerRef")
    for _, p in ipairs(all) do
        if valid(p) and PlayerRef.IsRemote(p) then out[#out + 1] = p end
    end
    return out
end

-- One pass. Exposed for the harness. Returns how many records were sent.
function HostView.SendUpdates()
    local mode = session_mode()
    if mode ~= "host" and mode ~= "dedicated" then return 0 end
    local okP, Personality = pcall(require, "Personality")
    if not okP or Personality == nil or Personality.ForEachKnownPal == nil then return 0 end
    local PlayerRef = require("PlayerRef")
    local okNet, Net = pcall(require, "Net")
    if not okNet or Net == nil then return 0 end
    local sentTotal = 0
    for _, viewer in ipairs(remote_players()) do
        local viewerKey = PlayerRef.OwnerKey(viewer)
        local origin = safe_call(function() return viewer:K2_GetActorLocation() end)
        if origin ~= nil then
            local isNewViewer = sentTo[viewerKey] == nil
            sentTo[viewerKey] = sentTo[viewerKey] or {}
            local already = sentTo[viewerKey]
            local batch = {}
            Personality.ForEachKnownPal(function(palId, pawn, state)
                if not valid(pawn) then return end
                local loc = safe_call(function() return pawn:K2_GetActorLocation() end)
                if loc == nil then return end
                local dx, dy, dz = loc.X - origin.X, loc.Y - origin.Y, loc.Z - origin.Z
                if dx * dx + dy * dy + dz * dz > NEAR * NEAR then return end
                local rec = record_for(palId, pawn, state, viewer, viewerKey)
                if already[palId] ~= rec then
                    already[palId] = rec
                    batch[#batch + 1] = rec
                end
            end)
            if #batch > 0 then
                Net.SendToPlayer(viewer, "INFO", table.concat(batch, RECORD_SEP))
                sentTotal = sentTotal + #batch
            elseif isNewViewer then
                -- Nothing to describe yet, but say hello: the guest then knows
                -- this host runs PalBonds and starts drawing and asking.
                Net.SendToPlayer(viewer, "INFO", "")
            end
        end
    end
    return sentTotal
end

-- A player who left: forget what was sent, so a rejoin gets everything again.
-- Called on world reset (both sides).
function HostView.ResetSent()
    sentTo = {}
end

-- The host's side of asking: find those Pals next to that guest, give each a
-- personality if it has none yet (as singleplayer does for a "?" tag), and
-- answer at once. Exposed for the harness.
function HostView.AnswerAsk(viewer, text)
    if type(text) ~= "string" or text == "" or not valid(viewer) then return 0 end
    local wanted, n = {}, 0
    for id in (text .. RECORD_SEP):gmatch("(.-)" .. RECORD_SEP) do
        if id ~= "" and n < 24 then wanted[id] = true; n = n + 1 end
    end
    if n == 0 then return 0 end
    local origin = safe_call(function() return viewer:K2_GetActorLocation() end)
    if origin == nil then return 0 end
    local Personality = require("Personality")
    local PlayerRef = require("PlayerRef")
    local viewerKey = PlayerRef.OwnerKey(viewer)
    sentTo[viewerKey] = sentTo[viewerKey] or {}
    local batch = {}
    local pals = safe_call(function() return FindAllOf("PalCharacter") end) or {}
    for _, pal in ipairs(pals) do
        if valid(pal) then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc ~= nil then
                local dx, dy, dz = loc.X - origin.X, loc.Y - origin.Y, loc.Z - origin.Z
                if dx * dx + dy * dy + dz * dz <= NEAR * NEAR then
                    local palId = safe_call(function() return Personality.GetStableId(pal) end)
                    if palId ~= nil and wanted[palId] then
                        safe_call(function() Personality.GetOrInitState(pal) end)
                        safe_call(function() Personality.RememberPawn(palId, pal) end)
                        local state = safe_call(function() return Personality.GetState(palId) end)
                        local rec = record_for(palId, pal, state, viewer, viewerKey)
                        sentTo[viewerKey][palId] = rec
                        batch[#batch + 1] = rec
                    end
                end
            end
        end
    end
    if #batch > 0 then
        local okNet, Net = pcall(require, "Net")
        if okNet and Net then Net.SendToPlayer(viewer, "INFO", table.concat(batch, RECORD_SEP)) end
    end
    return #batch
end

local started = false
function HostView.Init()
    if started then return end
    started = true
    local okNet, Net = pcall(require, "Net")
    if okNet and Net and Net.OnServer then
        Net.OnServer("ASK", function(ctrl, pawn, fields) HostView.AnswerAsk(pawn, fields[1]) end)
        -- That guest is treated as new: a hello, then everything near them.
        Net.OnServer("RESYNC", function(ctrl, pawn, fields)
            sentTo[require("PlayerRef").OwnerKey(pawn)] = nil
        end)
    end
    if okNet and Net and Net.OnClient then
        Net.OnClient("INFO", function(fields)
            heardFromHost = true
            local n = accept_info(fields[1])
            if n > 0 then
                Logger.log("[PalBonds/HostView] " .. n .. " Pal(s) updated from the host")
            end
        end)
    end
    local function loop()
        pcall(HostView.SendUpdates)
        pcall(HostView.SendResync)
        pcall(HostView.SendAsks)
        pcall(function() ExecuteInGameThreadWithDelay(SEND_EVERY_MS, loop) end)
    end
    pcall(function() ExecuteInGameThreadWithDelay(SEND_EVERY_MS, loop) end)
end

return HostView

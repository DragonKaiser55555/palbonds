local Logger = require("Logger")

local HostView = {}

local SEND_EVERY_MS = 2000
local NEAR = 6000
local RECORD_SEP = "\31"
local FIELD_SEP = "\30"

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

local cache = {}

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

local askQueue = {}
local askedAt = {}
local askCount = {}
local ASK_AGAIN_SECONDS = 10

local ASK_TRIES = 3
local ASK_LATER_SECONDS = 60

function HostView.Disposition(palId)
    local e = palId and cache[palId] or nil
    if e == nil and palId ~= nil then

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

local resyncWanted = false

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

local sentTo = {}

local function record_for(palId, pawn, state, viewer, viewerKey)
    local Trust = require("Trust")
    local PlayerRef = require("PlayerRef")

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

                Net.SendToPlayer(viewer, "INFO", "")
            end
        end
    end
    return sentTotal
end

function HostView.ResetSent()
    sentTo = {}
end

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

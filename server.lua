local QBCore = exports['qb-core']:GetCoreObject()

-- Config (loaded from shared `config.lua`)
local Config = Config or {}
local KILL_THRESHOLD = Config.KILL_THRESHOLD or 10
local WINDOW_SECONDS = Config.WINDOW_SECONDS or 600
local HITMAN_WEAPON = Config.HITMAN_WEAPON or "weapon_assaultrifle"
local HITMAN_DISTANCE = Config.HITMAN_DISTANCE or 50
local HIT_COOLDOWN = Config.HIT_COOLDOWN or 900
local HITMAN_LOCK_TIME = Config.HITMAN_LOCK_TIME or 300000 -- ms to lock global spawn after dispatch

-- Logging / admin notify settings
local ENABLE_LOGGING = Config.ENABLE_LOGGING or true
local ENABLE_ADMIN_NOTIFY = Config.ENABLE_ADMIN_NOTIFY or true
local ADMIN_NOTIFY_RANK = Config.ADMIN_NOTIFY_RANK or 'admin' -- QBCore permission

-- Runtime tables
local pedKills = {} -- [citizenid] = {timestamps = {...}, lastHit = os.time() - large}
local activeHitman = false
local activeTimer = nil

-- Helper: get player object and citizenid
local function getPlayerById(source)
    local Player = QBCore.Functions.GetPlayer(source)
    return Player
end

local function clearActiveHitman()
    activeHitman = false
    if activeTimer then
        CancelEvent(activeTimer)
        activeTimer = nil
    end
end

-- Called by client when a ped is killed
RegisterNetEvent('bldr_hitman:pedKilled', function()
    local src = source
    local player = getPlayerById(src)
    if not player then return end
    local cid = player.PlayerData.citizenid
    if not cid then return end

    pedKills[cid] = pedKills[cid] or {timestamps = {}, lastHit = 0}
    local entry = pedKills[cid]
    table.insert(entry.timestamps, os.time())

    -- prune old timestamps
    local cutoff = os.time() - WINDOW_SECONDS
    local i = 1
    while i <= #entry.timestamps do
        if entry.timestamps[i] < cutoff then
            table.remove(entry.timestamps, i)
        else
            i = i + 1
        end
    end

    -- Check threshold and cooldown
    if #entry.timestamps >= KILL_THRESHOLD and (os.time() - entry.lastHit) >= HIT_COOLDOWN then
        if activeHitman then
            if ENABLE_LOGGING then
                print(('[bldr_hitman] Dispatch suppressed for %s (%s) because a hitman is already active'):format(player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname, cid))
            end
            return
        end

        entry.lastHit = os.time()
        activeHitman = true

        -- clear lock after HITMAN_LOCK_TIME
        CreateThread(function()
            local waitTime = HITMAN_LOCK_TIME
            Wait(waitTime)
            activeHitman = false
        end)

        TriggerClientEvent('bldr_hitman:becomeTarget', src)
        -- Logging
        if ENABLE_LOGGING then
            print(('[bldr_hitman] Player %s (%s) exceeded ped kills (%d) - hitmen dispatched'):format(player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname, cid, #entry.timestamps))
        end
        -- Admin notifications
        if ENABLE_ADMIN_NOTIFY then
            for _, srvPlayer in pairs(QBCore.Functions.GetPlayers()) do
                local tgt = QBCore.Functions.GetPlayer(srvPlayer)
                if tgt and tgt.PlayerData and tgt.PlayerData.job and tgt.PlayerData.job.name == ADMIN_NOTIFY_RANK then
                    TriggerClientEvent('QBCore:Notify', srvPlayer, ('Hitmen dispatched to %s (%s)'):format(player.PlayerData.charinfo.firstname, cid), 'warning', 10000)
                end
            end
        end
    end
end)

-- Client notifies when hitman engagement ends early (cleanup)
RegisterNetEvent('bldr_hitman:hitmanEnded', function()
    activeHitman = false
end)

-- Client notifies when a hitman has been killed by a player; reset that player's ped kill tally
RegisterNetEvent('bldr_hitman:hitmanKilled', function()
    local src = source
    local player = getPlayerById(src)
    if not player then return end
    local cid = player.PlayerData.citizenid
    if not cid then return end
    pedKills[cid] = nil
    if ENABLE_LOGGING then
        print(('[bldr_hitman] Reset ped kill count for %s (%s) after killing hitman'):format(player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname, cid))
    end
end)

-- Admin command to reset a player's count (server console or RCON)
QBCore.Commands.Add('resetpedkills', 'Reset a player ped kill timer (admin)', {{name='id', help='player id'}}, true, function(source, args)
    local target = tonumber(args[1])
    if not target then
        TriggerClientEvent('QBCore:Notify', source, 'Invalid player id', 'error')
        return
    end
    local player = getPlayerById(target)
    if not player then
        TriggerClientEvent('QBCore:Notify', source, 'Player not found', 'error')
        return
    end
    local cid = player.PlayerData.citizenid
    pedKills[cid] = nil
    TriggerClientEvent('QBCore:Notify', source, 'Ped kills reset for '..player.PlayerData.charinfo.firstname, 'success')
end, 'admin')

-- Command: let player query their ped kill count
QBCore.Commands.Add('pedkills', 'Show your ped kill count', {}, false, function(source, args)
    local player = getPlayerById(source)
    if not player then return end
    local cid = player.PlayerData.citizenid
    local count = 0
    -- use internal table to calculate
    local e = pedKills[cid]
    if e then
        local cutoff = os.time() - WINDOW_SECONDS
        for _, t in ipairs(e.timestamps) do
            if t >= cutoff then count = count + 1 end
        end
    end
    TriggerClientEvent('QBCore:Notify', source, ('You have killed %d ped(s) in the last %d seconds'):format(count, WINDOW_SECONDS), 'primary', 5000)
end)



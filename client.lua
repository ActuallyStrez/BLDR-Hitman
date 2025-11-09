local QBCore = exports['qb-core']:GetCoreObject()

-- Client config from shared `config.lua`
local HITMAN_REL_NAME = 'HITMAN_REL'
local Config = Config or {}
local HITMAN_DISTANCE = Config.HITMAN_DISTANCE or 150
-- models loaded from `config.lua` with sensible fallback
local HITMAN_MODELS = Config.HITMAN_MODELS or {
    's_m_m_highsec_01',
    's_m_m_highsec_02',
    's_m_m_highsec_03',
    's_m_m_highsec_04',
    's_m_m_highsec_05'
}

-- utility
local function isPed(entity)
    return entity and DoesEntityExist(entity) and IsEntityAPed(entity) and not IsPedAPlayer(entity)
end

-- track local ped kills to inform server
local trackedPeds = {}
Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()

        local playerPos = GetEntityCoords(playerPed)
        local handle, ped = FindFirstPed()
        local success
        repeat
            local pedPos = GetEntityCoords(ped)
            if #(pedPos - playerPos) < 50.0 then
                if isPed(ped) then
                    if IsEntityDead(ped) and not trackedPeds[ped] then
                        local lastDamager = GetPedSourceOfDeath(ped)
                        local owner = NetworkGetEntityOwner(ped)
                        if owner == PlayerId() or lastDamager == playerPed then
                            trackedPeds[ped] = true
                            TriggerServerEvent('bldr_hitman:pedKilled')
                        end
                    end
                end
            end
            success, ped = FindNextPed(handle)
        until not success
        EndFindPed(handle)
        for k,_ in pairs(trackedPeds) do
            if not DoesEntityExist(k) then trackedPeds[k] = nil end
        end
        Wait(3000)
    end
end)

-- helpers for spawn
local function getRandomOffset(pos, distance)
    local angle = math.rad(math.random() * 360)
    local r = distance * (0.8 + math.random() * 0.4)
    return vector3(pos.x + math.cos(angle) * r, pos.y + math.sin(angle) * r, pos.z)
end

local function getGroundZ(coords)
    local z = coords.z
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, 0)
    if found then return groundZ end
    return z
end

local function isNearRoad(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    return streetHash ~= 0
end

local vehicleList = Config.VEHICLE_LIST or { 'fbi', 'fbi2', 'fbi3' }

-- Utility: check if a model is a motorcycle and avoid spawning bikes for hitmen
local function isMotorcycleModel(modelHash)
    if not modelHash then return false end
    return IsThisModelABike(modelHash) or IsThisModelABoat(modelHash) -- precautionary, prefer vehicles
end

-- spawn vehicle for ped
local function spawnVehicle(modelHash, coords, heading)
    RequestModel(modelHash)
    local tries = 0
    while not HasModelLoaded(modelHash) and tries < 100 do Wait(50); tries = tries + 1 end
    if not HasModelLoaded(modelHash) then return nil end
    local veh = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    -- upgrade vehicle for hitman: max performance, brakes, armor, double health
    SetVehicleModKit(veh, 0)
    -- try enabling turbo and high performance engine
    SetVehicleMod(veh, 11, 3, false) -- engine
    SetVehicleMod(veh, 13, 2, false) -- transmission
    SetVehicleMod(veh, 12, 2, false) -- brakes
    SetVehicleMod(veh, 18, 1, false) -- turbo if available
    -- performance multipliers and handling tweaks
    SetVehicleEnginePowerMultiplier(veh, 250.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia', 6.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', 5.0)
    -- bump vehicle health/body
    local curEngineHealth = GetVehicleEngineHealth(veh)
    local curBodyHealth = GetVehicleBodyHealth(veh)
    SetVehicleEngineHealth(veh, math.max(curEngineHealth * 2.0, 2000.0))
    SetVehicleBodyHealth(veh, math.max(curBodyHealth * 2.0, 2000.0))
    -- make tyres bulletproof (prevent bursting)
    SetVehicleTyresCanBurst(veh, false)
    -- apply configuration: set colors and plate
    local primary = Config.VEHICLE_COLOR_PRIMARY or 0
    local secondary = Config.VEHICLE_COLOR_SECONDARY or primary
    -- Try to set custom primary/secondary colors (using native color indexes)
    SetVehicleColours(veh, primary, secondary)
    -- Set plate text
    if Config.HITMAN_VEHICLE_PLATE then
        SetVehicleNumberPlateText(veh, tostring(Config.HITMAN_VEHICLE_PLATE))
    end
    -- Performance, armor, brakes, and extra durability tuning
    SetModelAsNoLongerNeeded(modelHash)
    -- ensure mod kit is set so we can apply mods
    SetVehicleModKit(veh, 0)
    -- set heavy armor (mod slot 16) if available
    local armorLevel = 4
    if GetNumVehicleMods(veh, 16) and GetNumVehicleMods(veh, 16) >= armorLevel then
        SetVehicleMod(veh, 16, armorLevel, false)
    end
    -- boost engine power and torque
    SetVehicleEnginePowerMultiplier(veh, 250.0)
    -- increase braking
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', 5.0)
    -- increase drive inertia/torque handling for better acceleration
    pcall(function() SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia', 5.0) end)
    -- set engine health (double standard) and fix vehicle
    SetVehicleEngineHealth(veh, 2000.0)
    SetVehicleFixed(veh)
    -- make tyres robust
    SetVehicleTyreFixed(veh, 0)
    SetVehicleTyreFixed(veh, 1)
    SetVehicleTyreFixed(veh, 2)
    SetVehicleTyreFixed(veh, 3)
    return veh
end

-- spawn a single hitman (foot or vehicle)
local function spawnHitman(modelHash, spawnPos, weaponHash, inVehicle, vehModel, spawnHeading)
    local hitPed
    if inVehicle and vehModel then
        local veh = spawnVehicle(vehModel, spawnPos, spawnHeading or (math.random() * 360))
        if veh and DoesEntityExist(veh) then
            local seat = -1
            hitPed = CreatePedInsideVehicle(veh, 4, modelHash, seat, true, false)
            -- make vehicle tyres bulletproof so the hitman keeps mobility
            SetVehicleTyresCanBurst(veh, false)
        else
            -- fallback to foot spawn
            hitPed = CreatePed(4, modelHash, spawnPos.x, spawnPos.y, spawnPos.z + 1.0, 0.0, true, false)
        end
    else
        hitPed = CreatePed(4, modelHash, spawnPos.x, spawnPos.y, spawnPos.z + 1.0, 0.0, true, false)
    end

    if not hitPed or not DoesEntityExist(hitPed) then return nil end

    -- Strength and combat tuning
    local maxHealth = (Config.HITMAN_HEALTH or 200) * 2
    SetEntityMaxHealth(hitPed, maxHealth)
    SetEntityHealth(hitPed, maxHealth)
    SetPedArmour(hitPed, Config.HITMAN_ARMOR or 100)
    SetPedCanSwitchWeapon(hitPed, true)
    SetPedCombatAttributes(hitPed, 46, true)
    SetPedCombatRange(hitPed, 2)
    SetPedFleeAttributes(hitPed, 0, 0)
    SetPedRelationshipGroupHash(hitPed, GetHashKey(HITMAN_REL_NAME))
    TaskSetBlockingOfNonTemporaryEvents(hitPed, true)
    SetPedCombatAbility(hitPed, 2) -- higher combat ability
    SetPedCombatMovement(hitPed, 2) -- aggressive movement
    SetPedAccuracy(hitPed, math.random(Config.HITMAN_ACCURACY_MIN or 65, Config.HITMAN_ACCURACY_MAX or 95))
    SetPedShootRate(hitPed, Config.HITMAN_SHOOT_RATE or 100)
    SetEntityAsMissionEntity(hitPed, true, true)
    return hitPed
end

-- create and remove blip
local function createTempBlip(coords)
    if not Config.SHOW_BLIP then return nil end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.BLIP_SPRITE or 280)
    SetBlipColour(blip, Config.BLIP_COLOR or 1)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Threat')
    EndTextCommandSetBlipName(blip)
    return blip
end

-- helper: find a road node close to candidate point and return ground position and heading
local function getRoadNearby(candidate)
    -- try the closest vehicle node with heading first
    local success, outPos = GetClosestVehicleNodeWithHeading(candidate.x, candidate.y, candidate.z, 1, 3.0, 0)
    if success and outPos then
        local x,y,z,h = outPos.x, outPos.y, outPos.z, outPos.w
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 5.0, 0)
        if found and groundZ < 100.0 then -- avoid rooftops
            return vector3(x, y, groundZ), h or 0.0
        end
    end

    -- fallback: probe multiple nearby points around candidate to find a solid vehicle node
    local probeDistances = {5.0, 10.0, 20.0, 30.0}
    for _, d in ipairs(probeDistances) do
        for angleDeg = 0, 330, 30 do
            local ang = math.rad(angleDeg)
            local probe = vector3(candidate.x + math.cos(ang) * d, candidate.y + math.sin(ang) * d, candidate.z)
            local s2, out2 = GetClosestVehicleNodeWithHeading(probe.x, probe.y, probe.z, 1, 3.0, 0)
            if s2 and out2 then
                local x2,y2,z2,h2 = out2.x, out2.y, out2.z, out2.w
                local found2, groundZ2 = GetGroundZFor_3dCoord(x2, y2, z2 + 5.0, 0)
                if found2 and groundZ2 < 100.0 then
                    -- ensure there's enough clear space (no vehicles/peds nearby)
                    local nearbyVeh = GetClosestVehicle(x2, y2, groundZ2, 6.0, 0, 70)
                    local handle, ped = FindFirstPed()
                    local blocked = false
                    if nearbyVeh ~= 0 then blocked = true end
                    -- simple check for peds near node
                    local hFound, nped = FindFirstPed()
                    if hFound then
                        repeat
                            local pCoords = GetEntityCoords(nped)
                            if #(pCoords - vector3(x2,y2,groundZ2)) < 4.0 then blocked = true; break end
                            local ok, nextPed = FindNextPed(hFound)
                            nped = nextPed
                        until not ok
                        EndFindPed(hFound)
                    end
                    if not blocked then
                        return vector3(x2, y2, groundZ2), h2 or 0.0
                    end
                end
            end
        end
    end

    return nil, nil
end

-- main: become target event
RegisterNetEvent('bldr_hitman:becomeTarget', function()
    local playerPed = PlayerPedId()

    local playerCoords = GetEntityCoords(playerPed)

    -- notify player that a hitman is targeting them
    QBCore.Functions.Notify("You think you can get away with killing locals?", "error", 5000)

    -- relationship group
    AddRelationshipGroup(HITMAN_REL_NAME)
    SetRelationshipBetweenGroups(5, GetHashKey(HITMAN_REL_NAME), GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), GetHashKey(HITMAN_REL_NAME))

    -- pick a random high-security model
    local modelName = HITMAN_MODELS[math.random(#HITMAN_MODELS)]
    local modelHash = GetHashKey(modelName)
    RequestModel(modelHash)
    local tries = 0
    while not HasModelLoaded(modelHash) and tries < 100 do Wait(50); tries = tries + 1 end
    if not HasModelLoaded(modelHash) then return end

    local spawned = {}
    local blips = {}
    local weaponsGiven = {} -- track if we've armed a hitman after exiting vehicles

    do
        local attempt = 0
        local spawnPos
        while attempt < (Config.MAX_SPAWN_ATTEMPTS or 30) do
            local candidate = getRandomOffset(playerCoords, HITMAN_DISTANCE)
            -- prefer road nodes nearby
            local roadPos, roadHeading = getRoadNearby(candidate)
            if roadPos then
                -- place spawn on the road node and capture heading so vehicles spawn correctly
                local nodeHeading = roadHeading or 0.0
                -- position slightly to the side of the road so vehicle has room to spawn
                local sideOffset = 3.0
                local nx = roadPos.x + math.cos(nodeHeading) * sideOffset
                local ny = roadPos.y + math.sin(nodeHeading) * sideOffset
                local offset = vector3(nx + (math.random()-0.5)*1.0, ny + (math.random()-0.5)*1.0, roadPos.z)
                offset = vector3(offset.x, offset.y, getGroundZ(offset))
                spawnPos = offset
                spawnHeading = nodeHeading
                break
            else
                -- fallback to candidate if near road and ground
                candidate = vector3(candidate.x, candidate.y, getGroundZ(candidate))
                if isNearRoad(candidate) then
                    spawnPos = candidate
                    break
                end
            end
            attempt = attempt + 1
            Wait(10)
        end
        if not spawnPos then
            -- final fallback: close to player on ground
            spawnPos = getRandomOffset(playerCoords, math.min(HITMAN_DISTANCE, 30))
            spawnPos = vector3(spawnPos.x, spawnPos.y, getGroundZ(spawnPos))
        end

        -- always spawn hitmen with a vehicle
        local inVehicle = true

        -- if player is far at spawn time, force vehicle spawn so hitman can pursue by car
        local playerDistAtSpawn = #(playerCoords - spawnPos)
        if playerDistAtSpawn > (Config.HITMAN_DISTANCE or HITMAN_DISTANCE) then
            inVehicle = true
        end

        local vehModelHash = nil
        if inVehicle then
            -- choose a vehicle model that is not a motorcycle (try a few times)
            local attempts = 0
            local chosen = nil
            while attempts < 10 do
                chosen = vehicleList[math.random(#vehicleList)]
                vehModelHash = GetHashKey(chosen)
                RequestModel(vehModelHash)
                local t = 0
                while not HasModelLoaded(vehModelHash) and t < 100 do Wait(50); t = t + 1 end
                if HasModelLoaded(vehModelHash) and not isMotorcycleModel(vehModelHash) then
                    break
                end
                -- cleanup and retry
                if HasModelLoaded(vehModelHash) then SetModelAsNoLongerNeeded(vehModelHash) end
                vehModelHash = nil
                attempts = attempts + 1
            end
            if not vehModelHash then
                -- failed to find a suitable non-bike vehicle
                vehModelHash = nil
            end
        end

        local willSpawnInVehicle = inVehicle and vehModelHash ~= nil

        local hitPed = spawnHitman(modelHash, spawnPos, nil, willSpawnInVehicle, vehModelHash, spawnHeading)
        if hitPed then
            table.insert(spawned, hitPed)

            -- If the player was out of HITMAN_DISTANCE at the moment of spawn and the ped is on foot,
            -- spawn a vehicle for them and force immediate entry so they can pursue by vehicle.
            local playerDistAtSpawn = #(playerCoords - spawnPos)
            if playerDistAtSpawn > (Config.HITMAN_DISTANCE or HITMAN_DISTANCE) and not IsPedInAnyVehicle(hitPed, false) then
                -- try to pick a non-motorcycle vehicle from the vehicle list
                local chosenHash = nil
                for i=1,10 do
                    local choice = vehicleList[math.random(#vehicleList)]
                    local h = GetHashKey(choice)
                    RequestModel(h)
                    local t = 0
                    while not HasModelLoaded(h) and t < 100 do Wait(50); t = t + 1 end
                    if HasModelLoaded(h) and not isMotorcycleModel(h) then
                        chosenHash = h
                        break
                    end
                    if HasModelLoaded(h) then SetModelAsNoLongerNeeded(h) end
                end
                    if chosenHash then
                        local veh = spawnVehicle(chosenHash, spawnPos, math.random() * 360)
                        if veh and DoesEntityExist(veh) then
                            -- reliably place the ped into the vehicle: attempt warp then enter with retries
                            TaskWarpPedIntoVehicle(hitPed, veh, -1)

                            local entered = IsPedInAnyVehicle(hitPed, false)
                            local attempts = 0
                            while not entered and attempts < 10 do
                                Wait(100)
                                entered = IsPedInAnyVehicle(hitPed, false)
                                if entered then break end
                                -- try controlled enter if warp failed
                                TaskEnterVehicle(hitPed, veh, 1000, -1, 1.5, 1, 0)
                                Wait(150)
                                entered = IsPedInAnyVehicle(hitPed, false)
                                attempts = attempts + 1
                            end
                            -- final fallback: warp again
                            if not entered then
                                TaskWarpPedIntoVehicle(hitPed, veh, -1)

                            end
                        end
                    end
            end

            -- decide weapon based on actual spawn state (in vehicle = do NOT arm, on foot = equip)
            local actuallyInVehicle = IsPedInAnyVehicle(hitPed, false)
            if actuallyInVehicle then
                -- ensure the hitman does not shoot from the vehicle: remove firearms and disable switching
                RemoveAllPedWeapons(hitPed, true)
                SetCurrentPedWeapon(hitPed, GetHashKey('WEAPON_UNARMED'), true)
                SetPedCanSwitchWeapon(hitPed, false)
                weaponsGiven[hitPed] = false
                -- they will use vehicle pursuit AI below
            else
                -- choose random weapon from config melee list for on-foot combat
                local melees = Config.WEAPON_MELEES or { Config.WEAPON_MELEE }
                local weaponChoice = melees[math.random(#melees)]
                local weaponHash = GetHashKey(weaponChoice)
                -- ensure ped can switch when giving weapon
                SetPedCanSwitchWeapon(hitPed, true)
                -- give weapon for on-foot engagement
                GiveWeaponToPed(hitPed, weaponHash, 250, false, true)
                SetCurrentPedWeapon(hitPed, weaponHash, true)
                weaponsGiven[hitPed] = true
                -- aggressive on-foot combat
                TaskCombatPed(hitPed, playerPed, 0, 16)
                SetPedAccuracy(hitPed, 60 + math.random(0,30))
            end
            -- create blip attached to the ped so it follows them
            local b = nil
            if Config.SHOW_BLIP then
                b = AddBlipForEntity(hitPed)
                SetBlipSprite(b, Config.BLIP_SPRITE or 280)
                SetBlipColour(b, Config.BLIP_COLOR or 1)
                SetBlipScale(b, 1.0)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString('Threat')
                EndTextCommandSetBlipName(b)
                -- fallback timeout to remove stale blip if something goes wrong
                Citizen.SetTimeout(Config.BLIP_TIMEOUT or 120000, function()
                    if DoesBlipExist(b) then RemoveBlip(b) end
                end)
            end
            if b then blips[hitPed] = b end
        end
        -- only one hitman configured; do not spawn more
        Wait(200)
    end

    -- monitor spawned hitmen and ensure they keep attacking until death or timeout
    Citizen.CreateThread(function()
        local vehicles = {} -- map ped -> vehicle entity if spawned with vehicle
        -- capture vehicles for any ped currently in vehicle
        for _, ped in ipairs(spawned) do
            if DoesEntityExist(ped) then
                local v = GetVehiclePedIsIn(ped, false)
                if v and DoesEntityExist(v) then vehicles[ped] = v end
            end
        end
        while #spawned > 0 do
            local alive = {}
            local playerPos = GetEntityCoords(playerPed)
            for _, ped in ipairs(spawned) do
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local pedPos = GetEntityCoords(ped)
                    local dist = #(playerPos - pedPos)
                    -- if player is far away, try to return to vehicle and chase
                    local veh = vehicles[ped]
                    if dist > (Config.HITMAN_RETURN_DISTANCE or 150.0) then
                        -- ensure we have a valid vehicle for this ped; spawn one if missing
                        if not veh or not DoesEntityExist(veh) then
                            -- attempt to spawn a nearby vehicle for the ped to use
                            local pedPos = GetEntityCoords(ped)
                            local chosenHash = nil
                            for i=1,6 do
                                local choice = vehicleList[math.random(#vehicleList)]
                                local h = GetHashKey(choice)
                                RequestModel(h)
                                local t = 0
                                while not HasModelLoaded(h) and t < 100 do Wait(10); t = t + 1 end
                                if HasModelLoaded(h) and not isMotorcycleModel(h) then
                                    chosenHash = h
                                    break
                                end
                                if HasModelLoaded(h) then SetModelAsNoLongerNeeded(h) end
                            end
                            if chosenHash then
                                local spawnCoords = vector3(pedPos.x + math.random(-6,6), pedPos.y + math.random(-6,6), getGroundZ(pedPos))
                                local spawnedVeh = spawnVehicle(chosenHash, spawnCoords, math.random() * 360)
                                if spawnedVeh and DoesEntityExist(spawnedVeh) then
                                    vehicles[ped] = spawnedVeh
                                    veh = spawnedVeh
                                end
                            end
                        end

                        if veh and DoesEntityExist(veh) then
                            -- if ped is not in vehicle, tell them to enter it
                            if not IsPedInAnyVehicle(ped, false) then
                                -- reliably force entry with retries: warp -> enter -> warp
                                TaskWarpPedIntoVehicle(ped, veh, -1)

                                local entered = IsPedInAnyVehicle(ped, false)
                                local tries = 0
                                while not entered and tries < 10 do
                                    Wait(100)
                                    entered = IsPedInAnyVehicle(ped, false)
                                    if entered then break end
                                    TaskEnterVehicle(ped, veh, 1000, -1, 1.5, 1, 0)
                                    Wait(150)
                                    entered = IsPedInAnyVehicle(ped, false)
                                    tries = tries + 1
                                end
                                if not entered then
                                    TaskWarpPedIntoVehicle(ped, veh, -1)

                                end
                            end
                            -- make the ped chase using vehicle AI
                            if IsPedInAnyVehicle(ped, false) then
                                -- buff driving skills for better pursuit
                                -- elite driving setup
                                SetDriverAbility(ped, 1.0)
                                SetDriverAggressiveness(ped, 1.0)
                                SetPedKeepTask(ped, true)
                                -- expert speeds
                                local driveSpeed = (Config.HITMAN_DRIVE_SPEED or 60.0)
                                SetDriveTaskCruiseSpeed(ped, driveSpeed)
                                SetDriveTaskMaxCruiseSpeed(ped, driveSpeed)
                                -- force safer road-following driving style
                                SetDriveTaskDrivingStyle(ped, 786603)
                                -- maximize vehicle power and handling for effective pursuit
                                local vehEntity = GetVehiclePedIsIn(ped, false)
                                if vehEntity and DoesEntityExist(vehEntity) then
                                    SetVehicleEnginePowerMultiplier(vehEntity, 150.0)
                                    SetVehicleHandlingFloat(vehEntity, 'CHandlingData', 'fDriveInertia', 5.0)
                                end
                                -- persistent long-range pursuit at high speed
                                TaskVehicleDriveToCoordLongrange(ped, veh, playerPos.x, playerPos.y, playerPos.z, driveSpeed, 1073741824, 786603, 5.0)
                            else
                                -- if still not in vehicle, attempt melee chase temporarily
                                TaskGoToEntity(ped, playerPed, -1, 5.0, 2.0, 1073741824.0, 0)
                            end
                        else
                            -- no vehicle available: fallback to on-foot chase
                            TaskGoToEntity(ped, playerPed, -1, 5.0, 2.0, 1073741824.0, 0)
                        end
                    else
                        -- normal behavior: if in vehicle, chase; if on foot, equip and combat
                        if IsPedInAnyVehicle(ped, false) then
                            -- if very close to player, force immediate exit so hitman engages quicker
                            local exitDist = Config.HITMAN_EXIT_DISTANCE or 20.0
                            local vehNow = GetVehiclePedIsIn(ped, false)
                            if dist < exitDist and vehNow and DoesEntityExist(vehNow) then
                                -- make sure ped exits vehicle promptly
                                TaskLeaveVehicle(ped, vehNow, 0)
                                -- give a short grace to ensure ped is out next tick
                                SetPedKeepTask(ped, true)
                            else
                                -- ensure they do NOT shoot from vehicle: remove weapons and disable switching while inside
                                RemoveAllPedWeapons(ped, true)
                                SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
                                SetPedCanSwitchWeapon(ped, false)
                                weaponsGiven[ped] = false
                                local v = GetVehiclePedIsIn(ped, false)
                                -- elite driving setup while pursuing
                                SetDriverAbility(ped, 1.0)
                                SetDriverAggressiveness(ped, 1.0)
                                SetPedKeepTask(ped, true)
                                local driveSpeed = (Config.HITMAN_DRIVE_SPEED or 60.0)
                                SetDriveTaskCruiseSpeed(ped, driveSpeed)
                                SetDriveTaskMaxCruiseSpeed(ped, driveSpeed)
                                SetDriveTaskDrivingStyle(ped, 786603)
                                local vehEntity = GetVehiclePedIsIn(ped, false)
                                if vehEntity and DoesEntityExist(vehEntity) then
                                    SetVehicleEnginePowerMultiplier(vehEntity, 150.0)
                                    SetVehicleHandlingFloat(vehEntity, 'CHandlingData', 'fDriveInertia', 5.0)
                                end
                                TaskVehicleChase(ped, playerPed)
                            end
                        else
                            -- if they've just exited a vehicle, arm them now and begin combat
                            if not weaponsGiven[ped] then
                                local melees = Config.WEAPON_MELEES or { Config.WEAPON_MELEE }
                                local weaponChoice = melees[math.random(#melees)]
                                local weaponHash = GetHashKey(weaponChoice)
                                GiveWeaponToPed(ped, weaponHash, 250, false, true)
                                SetCurrentPedWeapon(ped, weaponHash, true)
                                weaponsGiven[ped] = true
                            end
                            TaskCombatPed(ped, playerPed, 0, 16)
                        end
                    end
                    table.insert(alive, ped)
                else
                    -- if the ped died, check if the player killed the hitman and notify server to reset counts
                    local lastDamager = nil
                    if DoesEntityExist(ped) then
                        lastDamager = GetPedSourceOfDeath(ped)
                    end
                    if lastDamager and lastDamager == playerPed then
                        -- inform server that this player killed the hitman so their ped kill tally can be cleared
                        QBCore.Functions.Notify('Hitman Killed', 'success', 5000)
                        TriggerServerEvent('bldr_hitman:hitmanKilled')
                    end
                    -- remove associated blip when ped died
                    local b = blips[ped]
                    if b and DoesBlipExist(b) then RemoveBlip(b) end
                    blips[ped] = nil
                    -- cleanup vehicle mapping
                    vehicles[ped] = nil
                end
            end
            -- if player died, remove all blips and break
            if IsEntityDead(playerPed) then
                for k,b in pairs(blips) do
                    if b and DoesBlipExist(b) then RemoveBlip(b) end
                end
                blips = {}
                spawned = {}
                break
            end
            spawned = alive
            Wait(1500)
        end
        -- cleanup
        for _, ped in ipairs(spawned) do
            if DoesEntityExist(ped) then
                SetEntityAsNoLongerNeeded(ped)
                DeleteEntity(ped)
            end
        end
        for _, b in ipairs(blips) do
            if DoesBlipExist(b) then RemoveBlip(b) end
        end
        -- notify server that hitman engagement ended so global lock can be cleared
        TriggerServerEvent('bldr_hitman:hitmanEnded')
    end)

    SetModelAsNoLongerNeeded(modelHash)
end)

AddEventHandler('onClientResourceStop', function(name)
    if GetCurrentResourceName() ~= name then return end
end)

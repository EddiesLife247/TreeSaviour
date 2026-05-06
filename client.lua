local despawnCoords = vector3(-585.17, 5468.99, 59.22)
local despawnRadius = 200.0

-- Cached peds for performance
local cachedPeds = {}

-- Cache nearby peds every 3 seconds
CreateThread(function()
    while true do
        cachedPeds = GetGamePool("CPed")
        Wait(3000)
    end
end)

-- Clean up mountain lions every 5 seconds
CreateThread(function()
    while true do
        Wait(5000)

        local playerCoords = GetEntityCoords(PlayerPedId())

        for _, ped in ipairs(cachedPeds) do
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                local model = GetEntityModel(ped)
                if model == `A_C_MtLion` then
                    local pedCoords = GetEntityCoords(ped)
                    local distance = #(pedCoords - despawnCoords)

                    if distance <= despawnRadius then
                        -- Soft delete to avoid crashes
                        SetEntityCoords(ped, 0.0, 0.0, -500.0, false, false, false, false)
                        SetEntityAsNoLongerNeeded(ped)
                    end
                end
            end
        end
    end
end)
local protectedJobs = {
    ["fire"] = true,
    ["ambulance"] = true,
    ["firearms"] = true,
    ["police"] = true,
    ["response"] = true,
    ["roadspolicing"] = true,
    ["cid"] = true,
    ["staff"] = true,
    ["highways"] = true
}

local isProtected = false

local function checkIfProtected()
    local Player = exports['qbx_core']:GetPlayerData()
    if Player and Player.job then
        isProtected = protectedJobs[Player.job.name] or false
    else
        isProtected = false
    end
end

-- Initial check
CreateThread(function()
    Wait(1500) -- Give some time for player to load
    checkIfProtected()
    if isProtected then
        SetPedRelationshipGroupHash(PlayerPedId(), `CIVMALE`)
    end
end)

-- Optionally listen for job update events
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    isProtected = protectedJobs[job.name] or false
    if isProtected then
        SetPedRelationshipGroupHash(PlayerPedId(), `CIVMALE`)
    end
end)

-- Set initial group relations
CreateThread(function()
    Wait(2000)
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())

    local relationshipGroups = {
        `AMBIENT_GANG_LOST`,
        `AMBIENT_GANG_BALLAS`,
        `AMBIENT_GANG_FAMILY`,
        `CIVMALE`,
        `CIVFEMALE`,
        `SECURITY_GUARD`
    }

    for _, group in ipairs(relationshipGroups) do
        SetRelationshipBetweenGroups(0, group, playerGroup)
    end
end)

-- Aggro prevention loop
CreateThread(function()
    while true do
        Wait(2000)

        if not isProtected then goto continue end

        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local playerGroup = GetPedRelationshipGroupHash(playerPed)

        local peds = GetGamePool("CPed")

        for _, ped in ipairs(peds) do
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and IsPedHuman(ped) then
                local pedCoords = GetEntityCoords(ped)
                local dist = #(pedCoords - playerCoords)

                if dist < 100.0 then
                    SetPedCanBeTargetted(ped, false)
                    SetPedAsEnemy(ped, false)
                    SetRelationshipBetweenGroups(0, GetPedRelationshipGroupHash(ped), playerGroup)
                    SetRelationshipBetweenGroups(0, playerGroup, GetPedRelationshipGroupHash(ped))

                    if IsPedInCombat(ped, playerPed) or IsPedFleeing(ped) or IsPedShooting(ped) or IsPedRunning(ped) then
                        ClearPedTasksImmediately(ped)
                        TaskWanderStandard(ped, 10.0, 10)
                    end

                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetPedFleeAttributes(ped, 0, false)
                    SetPedCombatAttributes(ped, 0, false)
                    SetPedCombatAttributes(ped, 1, false)
                    SetPedCombatAttributes(ped, 2, false)
                    SetPedCombatAttributes(ped, 5, false)
                    SetPedCombatAttributes(ped, 20, false)
                    SetPedCombatAttributes(ped, 46, false)
                    SetPedCombatAbility(ped, 0)
                    SetPedCombatRange(ped, 0)
                    SetPedSeeingRange(ped, 0.0)
                    SetPedHearingRange(ped, 0.0)
                    SetPedAlertness(ped, 0)
                    SetPedEnableWeaponBlocking(ped, false)
                end
            end
        end

        ::continue::
    end
end)



-- Suppress AI reactions to stun-compatible weapons
local ignoreWeapons = {
    [`WEAPON_UNARMED`] = true,
    [`WEAPON_HANDCUFFS`] = true,
    [`WEAPON_GARBAGEBAG`] = true,
    [`WEAPON_FOAMBRANCH`] = true,
    [`WEAPON_REELBRANCH`] = true,
    [`WEAPON_FERTILIZERCAN`] = true,
    [`WEAPON_FIREEXTINGUISHER`] = true,
    [`WEAPON_STUNGUN`] = true,
    [`WEAPON_VINTAGEPISTOL`] = true,
    [`WEAPON_HOSE`] = true
}

CreateThread(function()
    while true do
        Wait(1500)

        local playerPed = PlayerPedId()
        local weapon = GetSelectedPedWeapon(playerPed)

        if ignoreWeapons[weapon] and (IsPedShooting(playerPed) or IsPlayerFreeAiming(PlayerId())) then
            local playerCoords = GetEntityCoords(playerPed)
            local count = 0

            for _, ped in ipairs(cachedPeds) do
                if count >= 5 then break end -- limit to 5 NPCs per check

                if ped ~= playerPed and not IsPedAPlayer(ped) and IsPedHuman(ped) then
                    local pedCoords = GetEntityCoords(ped)
                    local dist = #(playerCoords - pedCoords)

                    if dist < 75.0 then
                        ClearPedTasks(ped)
                        ClearPedSecondaryTask(ped)
                        TaskStandStill(ped, 1000)
                        SetPedFleeAttributes(ped, 0, false)
                        SetPedCombatAttributes(ped, 46, true)
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedCanRagdollFromPlayerImpact(ped, false)
count = count + 1
                    end
                end
            end
        end
    end
end)

-- Prevent stun gun deaths on NPCs
local revivedPeds = {}

CreateThread(function()
    while true do
        Wait(2000) -- Reduce frequency

        for _, ped in ipairs(cachedPeds) do
            if not IsPedAPlayer(ped) and IsPedHuman(ped) then
                if HasEntityBeenDamagedByWeapon(ped, `WEAPON_STUNGUN`, 0) then
                    ClearEntityLastDamageEntity(ped)

                    local health = GetEntityHealth(ped)
                    if IsEntityDead(ped) or health <= 0 then
                        if not revivedPeds[ped] then
                            ResurrectPed(ped)
                            ClearPedTasksImmediately(ped)
                            SetEntityHealth(ped, 150)
                            SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
                            revivedPeds[ped] = true
                        end
                    elseif health <= 100 then
                        SetEntityHealth(ped, 125)
                        SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
                    else
                        SetPedToRagdoll(ped, 2000, 2000, 0, false, false, false)
                    end
                end
            end
        end
    end
end)

-- Intercept stun gun damage from network
AddEventHandler('gameEventTriggered', function(eventName, args)
    if eventName == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        local attacker = args[2]
        local weaponHash = args[7]

        if weaponHash == `WEAPON_STUNGUN` and DoesEntityExist(victim) then
            if not IsPedAPlayer(victim) and IsPedHuman(victim) then
                local health = GetEntityHealth(victim)
                if health <= 101 then
                    SetEntityHealth(victim, 150)
                end

                if not IsPedRagdoll(victim) then
                    ClearPedTasksImmediately(victim)
                    SetPedToRagdoll(victim, 2000, 2000, 0, false, false, false)
                end

                CancelEvent()
            end
        end
    end
end)

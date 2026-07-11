local Blips, activeBlips = {}, {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function logging(code, ...)
    if not Config.Debug then return end
    MSK.Logging(code, ...)
end

local function mySource()
    return GetPlayerServerId(PlayerId())
end

-- Blip sprite for a movement category (configurable, with fallback).
local function getSprite(category)
    local sprites = Config.GPS.sprites
    return (sprites and sprites[category]) or Config.GPS.blip.id or 1
end

-- Clientside vehicle category, used for live tracking when the ped is nearby.
local function getVehicleCategory(ped)
    local veh = ped and GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return 'foot' end

    local vtype = GetVehicleType(veh)

    if vtype == 'bike' then
        return 'bike'
    elseif vtype == 'boat' or vtype == 'submarine' then
        return 'boat'
    elseif vtype == 'heli' then
        return 'heli'
    elseif vtype == 'plane' then
        return 'plane'
    end

    return 'car'
end

local function inOneSync(netId)
    local playerPed = NetworkDoesNetworkIdExist(netId) and NetworkGetEntityFromNetworkId(netId)

    if playerPed and DoesEntityExist(playerPed) then return {ped = playerPed} end
    return false
end

local function styleBlip(blip, xPlayer, heading, category)
    SetBlipSprite(blip, getSprite(category or 'foot'))
    SetBlipRotation(blip, heading or 0)
    SetBlipScale(blip, Config.GPS.blip.scale)
    SetBlipColour(blip, Config.GPS.blip.color)
    SetBlipDisplay(blip, 2)
    SetBlipAsShortRange(blip, true)

    AddTextEntry("BLIP_OTHPLYR", Config.GPS.blip.prefix)
    SetBlipCategory(blip, 7)
    ShowOutlineIndicatorOnBlip(blip, true)
    SetBlipSecondaryColour(blip, 255, 0, 0)
    ShowHeadingIndicatorOnBlip(blip, true)

    AddTextEntry("NAME_" .. xPlayer.name, "~a~")
    BeginTextCommandSetBlipName("NAME_" .. xPlayer.name)
    AddTextComponentString(xPlayer.name)
    EndTextCommandSetBlipName(blip)
end

local function createBlip(xPlayer, heading, category)
    local blip = AddBlipForCoord(xPlayer.coords.x, xPlayer.coords.y, xPlayer.coords.z)
    styleBlip(blip, xPlayer, heading, category)

    Blips[#Blips + 1] = blip
    activeBlips[tonumber(xPlayer.source)] = {isActive = false, blip = blip}
    return blip
end

--------------------------------------------------------------------------------
-- Blip handling
--------------------------------------------------------------------------------

local function addBlips(GPS)
    for _, v in pairs(GPS) do
        -- v = xPlayer, netId, coords, heading, veh
        local xPlayer = v.xPlayer
        local pid = tonumber(xPlayer.source)
        logging('debug', pid, v)

        if pid ~= mySource() and not activeBlips[pid] then
            createBlip(xPlayer, v.heading, v.veh)
        end
    end
end
RegisterNetEvent('msk_jobGPS:activateGPS', addBlips)

local function refreshBlips(GPS)
    logging('debug', 'refreshBlips')

    for _, v in pairs(GPS) do
        -- v = xPlayer, netId, coords, heading, veh
        local xPlayer = v.xPlayer
        local pid = tonumber(xPlayer.source)

        if pid ~= mySource() then
            if not activeBlips[pid] then createBlip(xPlayer, v.heading, v.veh) end

            local blip = activeBlips[pid].blip
            SetBlipSprite(blip, getSprite(v.veh))

            local OneSync = inOneSync(v.netId)

            if OneSync and not activeBlips[pid].isActive then
                logging('debug', 'inOneSync')

                CreateThread(function()
                    activeBlips[pid].isActive = true

                    while activeBlips[pid] and activeBlips[pid].isActive and DoesEntityExist(OneSync.ped) do
                        local ped = OneSync.ped
                        local liveBlip = activeBlips[pid] and activeBlips[pid].blip
                        if not liveBlip then break end

                        local coords = GetEntityCoords(ped)
                        local heading = math.ceil(GetEntityHeading(ped))

                        SetBlipCoords(liveBlip, coords.x, coords.y, coords.z)
                        SetBlipRotation(liveBlip, heading)
                        SetBlipSprite(liveBlip, getSprite(getVehicleCategory(ped)))

                        Wait(250)
                    end
                end)
            elseif not OneSync then
                logging('debug', 'not inOneSync')
                activeBlips[pid].isActive = false

                SetBlipCoords(blip, v.coords.x, v.coords.y, v.coords.z)
                SetBlipRotation(blip, v.heading)
            end
        end
    end
end
RegisterNetEvent('msk_jobGPS:refreshBlips', refreshBlips)

local function removeBlips()
    logging('debug', 'removeBlips')

    for k, blip in pairs(Blips) do
        RemoveBlip(blip)
    end

    Blips = {}
    activeBlips = {}
end
RegisterNetEvent('msk_jobGPS:deactivateGPS', removeBlips)

local function removeBlipById(playerId, reason)
    if not activeBlips[playerId] then return end

    if Config.StayActivated.enable then
        activeBlips[playerId].isActive = false

        if Config.StayActivated[reason] then
            SetBlipColour(activeBlips[playerId].blip, 40)
            Wait(Config.StayActivated.seconds * 1000)

            -- During the wait removeBlips() (deactivateGPS) may have run
            -- and cleared activeBlips -> re-check, otherwise nil access.
            if not activeBlips[playerId] then return end
        end
    end
    logging('debug', 'Deactivating Blip by ID for ID: ' .. playerId)

    for k, blip in pairs(Blips) do
        if activeBlips[playerId].blip == blip then
            Blips[k] = nil
            break
        end
    end

    RemoveBlip(activeBlips[playerId].blip)
    activeBlips[playerId] = nil
end
RegisterNetEvent('msk_jobGPS:deactivateGPSById', removeBlipById)

--------------------------------------------------------------------------------
-- Panicbutton
--------------------------------------------------------------------------------

if Config.Panicbutton.enable and Config.Commands.panicbutton.enable then
    RegisterCommand(Config.Commands.panicbutton.command, function()
        -- The server validates job, GPS state, item and cooldown.
        TriggerServerEvent('msk_jobGPS:togglePanicbutton')
    end)

    if Config.Panicbutton.hotkey.enable then
        RegisterKeyMapping(Config.Commands.panicbutton.command, 'Panicbutton', 'keyboard', Config.Panicbutton.hotkey.key)
    end
end

RegisterNetEvent('msk_jobGPS:activatePanicbutton', function(data)
    local playerId = tonumber(data.source)

    if activeBlips[playerId] then SetBlipColour(activeBlips[playerId].blip, Config.Panicbutton.blipColor) end
    SetNewWaypoint(data.coords.x, data.coords.y)
end)

--------------------------------------------------------------------------------
-- Death (framework-agnostic via msk_core)
--------------------------------------------------------------------------------

AddEventHandler('msk_core:onPlayerDeath', function(data)
    TriggerServerEvent('msk_jobGPS:setDeath')
end)

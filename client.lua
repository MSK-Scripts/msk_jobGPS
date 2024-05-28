local isActivated = false
local Blips, activeBlips = {}, {}

AddEventHandler('esx:onPlayerDeath', function()
    TriggerServerEvent('msk_jobGPS:setDeath')
end)

AddEventHandler('msk_jobGPS:activateGPS', function(GPS)
    isActivated = true
end)

AddEventHandler('msk_jobGPS:deactivateGPS', function()
    isActivated = false
end)

if Config.Panicbutton.enable and Config.Commands.panicbutton.enable then
	RegisterCommand(Config.Commands.panicbutton.command, function()
        if not Config.allowedJobs[ESX.PlayerData.job.name] then return end
        if not Config.allowedJobs[ESX.PlayerData.job.name].panicbutton then return end

		TriggerServerEvent('msk_jobGPS:togglePanicbutton')

        if Config.Panicbutton.notifyNearestPlayers then
            local players = ESX.Game.GetPlayersInArea(GetEntityCoords(PlayerPedId()), 8.0)
            
            for k, player in pairs(players) do
                TriggerServerEvent('msk_jobGPS:notifyNearestPlayers', GetPlayerServerId(player))
            end
        end
	end)

    if Config.Panicbutton.hotkey.enable then
        RegisterKeyMapping(Config.Commands.panicbutton.command, 'Panicbutton', 'keyboard', Config.Panicbutton.hotkey.key)
    end
end

RegisterNetEvent('msk_jobGPS:activatePanicbutton')
AddEventHandler('msk_jobGPS:activatePanicbutton', function(xPlayer)
    local playerId = tonumber(xPlayer.source)

    if activeBlips[playerId] then SetBlipColour(activeBlips[playerId].blip, Config.Panicbutton.blipColor) end
    SetNewWaypoint(xPlayer.coords.x, xPlayer.coords.y)
end)

addBlips = function(GPS)
    for playerId, v in pairs(GPS) do
        logging('debug', playerId, v)
        -- v = xPlayer, netId, coords, heading
        local xPlayer = v.xPlayer

        if ESX.PlayerData.identifier ~= xPlayer.identifier then
            local blip = AddBlipForCoord(xPlayer.coords.x, xPlayer.coords.y, xPlayer.coords.z)

            SetBlipRotation(blip, v.heading)

            SetBlipSprite(blip, Config.GPS.blip.id)
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

            Blips[#Blips + 1] = blip
            activeBlips[playerId] = {isActive = false, blip = blip}
        end
    end
end
RegisterNetEvent('msk_jobGPS:activateGPS', addBlips)

addBlip = function(GPS, xPlayer, heading)
    logging('debug', 'Add Blip for ' .. xPlayer.source)
    local blip = AddBlipForCoord(xPlayer.coords.x, xPlayer.coords.y, xPlayer.coords.z)

    SetBlipRotation(blip, heading)

    SetBlipSprite(blip, Config.GPS.blip.id)
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

    Blips[#Blips + 1] = blip
    activeBlips[tonumber(xPlayer.source)] = {isActive = false, blip = blip}
end

refreshBlips = function(GPS)
    logging('debug', 'refreshBlips')

    for playerId, v in pairs(GPS) do
        -- v = xPlayer, netId, coords, heading
        local xPlayer = v.xPlayer
        
        if ESX.PlayerData.identifier ~= xPlayer.identifier then
            if not activeBlips[playerId] then addBlip(GPS, xPlayer, v.heading) end

            logging('debug', 'Blip is active')
            local OneSync = inOneSync(v.netId)
                
            if OneSync and not activeBlips[playerId].isActive then
                logging('debug', 'inOneSync')
                
                CreateThread(function()
                    activeBlips[playerId].isActive = true

                    while activeBlips[playerId] and activeBlips[playerId].isActive and DoesEntityExist(OneSync.ped) do
                        local coords = GetEntityCoords(OneSync.ped)
                        local heading = math.ceil(GetEntityHeading(OneSync.ped))

                        SetBlipCoords(activeBlips[playerId].blip, coords.x, coords.y, coords.z)
                        SetBlipRotation(activeBlips[playerId].blip, heading)

                        Wait(0)
                    end
                end)
            elseif not OneSync then
                logging('debug', 'not inOneSync')
                activeBlips[playerId].isActive = false

                SetBlipCoords(activeBlips[playerId].blip, v.coords.x, v.coords.y, v.coords.z)
                SetBlipRotation(activeBlips[playerId].blip, v.heading)
            end
        end
    end
end
RegisterNetEvent('msk_jobGPS:refreshBlips', refreshBlips)

removeBlips = function()
    logging('debug', 'removeBlips')

    for k, blip in pairs(Blips) do
        RemoveBlip(blip)
    end

    Blips = {}
    activeBlips = {}
end
RegisterNetEvent('msk_jobGPS:deactivateGPS', removeBlips)

removeBlipById = function(playerId, reason)
    if not activeBlips[playerId] then return end

    if Config.StayActivated.enable then
        activeBlips[playerId].isActive = false

        if Config.StayActivated[reason] then
            SetBlipColour(activeBlips[playerId].blip, 40)
            Wait(Config.StayActivated.seconds * 1000)
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

inOneSync = function(netId)
    local playerPed = NetworkDoesNetworkIdExist(netId) and NetworkGetEntityFromNetworkId(netId)

    if DoesEntityExist(playerPed) then return {ped = playerPed} end
    return false
end

logging = function(code, ...)
    if not Config.Debug then return end
    MSK.Logging(code, ...)
end
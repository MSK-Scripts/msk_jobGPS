local GPS = {}

AddEventHandler('onResourceStart', function(resource)
	if GetCurrentResourceName() == resource then
		for job, v in pairs(Config.allowedJobs) do
			GPS[job] = {}
		end
	end
end)

if Config.Commands.gps.enable then
	RegisterCommand(Config.Commands.gps.command, function(source, args, rawCommand)
		ESX.UseItem(source, Config.GPS.item)
	end)
end

if Config.Panicbutton.item.enable then
	ESX.RegisterUsableItem(Config.Panicbutton.item.item, function(source)
		togglePanicbutton(source)
	end)
end

RegisterNetEvent('msk_jobGPS:togglePanicbutton')
AddEventHandler('msk_jobGPS:togglePanicbutton', function()
	local src = source
	togglePanicbutton(src)
end)

RegisterNetEvent('msk_jobGPS:notifyNearestPlayers')
AddEventHandler('msk_jobGPS:notifyNearestPlayers', function(playerId)
	Config.Notification(playerId, 'The Player has activated the Panicbutton')
end)

togglePanicbutton = function(source)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local canUseItem = false

	if not isAllowed(xPlayer, 'panic') then return end
	if Config.Panicbutton.item.enable then
		local hasItem = xPlayer.getInventoryItem(Config.Panicbutton.item.item)

		if hasItem and hasItem.count > 0 then canUseItem = true end
	else
		canUseItem = true
	end

	if not GPS[xPlayer.job.name][xPlayer.source] then canUseItem = false end
	if not canUseItem then return Config.Notification(src, 'Panicbutton does not work now') end

	local xPlayers = ESX.GetExtendedPlayers('job', xPlayer.job.name)
	for k, xTarget in pairs(xPlayers) do
		if GPS[xTarget.job.name][xTarget.source] and xTarget.source ~= xPlayer.source then
			xTarget.triggerEvent('msk_jobGPS:activatePanicbutton', xPlayer)
			Config.Notification(xTarget.source, xPlayer.name .. ' activated the Panicbutton')
		end
	end
end

ESX.RegisterUsableItem(Config.GPS.item, function(source)
	local src = source
   	local xPlayer = ESX.GetPlayerFromId(src)

	if not isAllowed(xPlayer, 'gps') then return end

	if GPS[xPlayer.job.name][xPlayer.source] then
		Config.Notification(src, 'GPS deactivated')
		xPlayer.triggerEvent('msk_jobGPS:deactivateGPS')
		removeBlipById(xPlayer)
	else
		local playerPed = GetPlayerPed(xPlayer.source)

		GPS[xPlayer.job.name][xPlayer.source] = {
			xPlayer = xPlayer,
			playerPed = playerPed,
			netId = NetworkGetNetworkIdFromEntity(playerPed),
			heading = math.ceil(GetEntityHeading(playerPed))
		}

		Config.Notification(src, 'GPS activated')
   		xPlayer.triggerEvent('msk_jobGPS:activateGPS', GPS)
	end
end)

RegisterNetEvent('esx:playerLogout', function(source)
    local src = source
	local xPlayer = ESX.GetPlayerFromId(src)

	removeBlipById(xPlayer)
end)

RegisterNetEvent('esx:playerDropped', function(playerId, reason)
	local src = playerId
	local xPlayer = ESX.GetPlayerFromId(src)

	removeBlipById(xPlayer)
end)

RegisterNetEvent('msk_jobGPS:setDeath')
AddEventHandler('msk_jobGPS:setDeath', function()
	local src = source
   	local xPlayer = ESX.GetPlayerFromId(src)

	xPlayer.triggerEvent('msk_jobGPS:deactivateGPS')
	removeBlipById(xPlayer)
end)

AddEventHandler('esx:onRemoveInventoryItem', function(source, item, count)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)

	if item == Config.GPS.item then
		xPlayer.triggerEvent('msk_jobGPS:deactivateGPS')
		removeBlipById(xPlayer)
	end
end)

CreateThread(function()
    while true do
        local sleep = Config.GPS.refresh * 1000

		local xPlayers = ESX.GetExtendedPlayers()
		for k, xPlayer in pairs(xPlayers) do
			if GPS[xPlayer.job.name][xPlayer.source] then
				GPS[xPlayer.job.name][xPlayer.source].coords = xPlayer.getCoords(true)
				GPS[xPlayer.job.name][xPlayer.source].heading = math.ceil(GetEntityHeading(GetPlayerPed(xPlayer.source)))

				xPlayer.triggerEvent('msk_jobGPS:refreshBlips', GPS)
			end
		end

        Wait(sleep)
    end
end)

removeBlipById = function(xPlayer)
	local source, job = xPlayer.source, xPlayer.job.name

	if GPS[job][source] then 
		GPS[job][source] = nil

		for playerId, v in pairs(GPS[job]) do
			TriggerClientEvent('msk_jobGPS:deactivateGPSById', playerId, source)
		end
	end
end

isAllowed = function(xPlayer, action)
	for job, v in pairs(Config.allowedJobs) do
		if xPlayer.job.name == job then
			if action == 'gps' and v.gps then
				return true
			elseif action == 'panic' and v.panicbutton then
				return true
			end
		end
	end

	return false
end

logging = function(code, ...)
    if Config.Debug then
        local script = "[^2"..GetCurrentResourceName().."^0]"
        MSK.logging(script, code, ...)
    end
end
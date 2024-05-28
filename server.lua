local GPS = {}
local playerJobs = {}

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

if Config.Panicbutton.enable and Config.Panicbutton.item.enable then
	ESX.RegisterUsableItem(Config.Panicbutton.item.item, function(source)
		togglePanicbutton(source)
	end)
end

RegisterNetEvent('msk_jobGPS:togglePanicbutton', function()
	local src = source
	togglePanicbutton(src)
end)

RegisterNetEvent('msk_jobGPS:notifyNearestPlayers', function(targetId)
	Config.Notification(targetId, Translation[Config.Locale]['panic_activated']:format(Translation[Config.Locale]['someone']), 'warning')
end)

togglePanicbutton = function(source)
	if not Config.Panicbutton.enable then return end
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	local canUseItem = true

	if not Config.allowedJobs[xPlayer.job.name] then return end
	if not Config.allowedJobs[xPlayer.job.name].panicbutton then return end

	if Config.Panicbutton.item.enable then
		local hasItem = xPlayer.hasItem(Config.Panicbutton.item.item)

		if not hasItem or hasItem and hasItem.count == 0 then 
			canUseItem = false 
		end
	end

	if not GPS[xPlayer.job.name][tonumber(src)] then canUseItem = false end
	if not canUseItem then return Config.Notification(src, Translation[Config.Locale]['panic_activate_GPS'], 'error') end
	Config.Notification(src, Translation[Config.Locale]['panic_pressed'], 'info')

	for playerId, info in pairs(GPS[xPlayer.job.name]) do
		if tonumber(playerId) ~= tonumber(src) then
			TriggerClientEvent('msk_jobGPS:activatePanicbutton', playerId, xPlayer)
			Config.Notification(playerId, Translation[Config.Locale]['panic_activated']:format(xPlayer.name), 'warning')
		end
	end
end

ESX.RegisterUsableItem(Config.GPS.item, function(source)
	local src = source
   	local xPlayer = ESX.GetPlayerFromId(src)

	if not Config.allowedJobs[xPlayer.job.name] then return end
	if not Config.allowedJobs[xPlayer.job.name].gps then return end

	if GPS[xPlayer.job.name][tonumber(src)] then
		Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
		TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
		removeBlipById(xPlayer, 'stayOnDeactivate')
	else
		local playerPed, playerJob = GetPlayerPed(src), xPlayer.job.name
		playerJobs[tonumber(src)] = playerJob

		for playerId, v in pairs(GPS[playerJob]) do
			Config.Notification(playerId, Translation[Config.Locale]['gps_activated_all']:format(xPlayer.name), 'info')
		end

		GPS[playerJob][tonumber(src)] = {
			xPlayer = xPlayer,
			netId = NetworkGetNetworkIdFromEntity(playerPed),
			coords = GetEntityCoords(playerPed),
			heading = math.ceil(GetEntityHeading(playerPed))
		}

		Config.Notification(src, Translation[Config.Locale]['gps_activated'], 'info')
		TriggerClientEvent('msk_jobGPS:activateGPS', src, GPS[playerJob])
	end
end)

RegisterNetEvent('esx:playerLogout', function(source)
    local src = source
	local xPlayer = ESX.GetPlayerFromId(src)

	removeBlipById(xPlayer, 'stayOnLeaveServer')
end)

RegisterNetEvent('esx:playerDropped', function(playerId, reason)
	local src = playerId
	local xPlayer = ESX.GetPlayerFromId(src)

	removeBlipById(xPlayer, 'stayOnLeaveServer')
end)

RegisterNetEvent("esx:setJob", function(playerId, newJob, oldJob)
	if newJob.name == oldJob.name then return end
	local src = playerId
	local xPlayer = ESX.GetPlayerFromId(src)
	if not GPS[oldJob.name] then return end
	if not not GPS[oldJob.name][tonumber(src)] then return end

	Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(xPlayer, 'stayOnJobChange')
end)

RegisterNetEvent('msk_jobGPS:setDeath', function()
	local src = source
   	local xPlayer = ESX.GetPlayerFromId(src)
	if not GPS[xPlayer.job.name] then return end
	if not GPS[xPlayer.job.name][tonumber(xPlayer.source)] then return end

	Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(xPlayer, 'stayOnDeath')
end)

AddEventHandler('esx:onRemoveInventoryItem', function(source, item, count)
	local src = source
	local xPlayer = ESX.GetPlayerFromId(src)
	
	if item == Config.GPS.item and count == 0 then
		if not GPS[xPlayer.job.name] then return end
		if not GPS[xPlayer.job.name][tonumber(xPlayer.source)] then return end

		TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
		removeBlipById(xPlayer, 'stayOnRemoveItem')

		for playerId, v in pairs(GPS[xPlayer.job.name]) do
			Config.Notification(playerId, Translation[Config.Locale]['gps_removed_inventory']:format(xPlayer.name), 'warning')
		end
	end
end)

CreateThread(function()
    while true do
        local sleep = Config.GPS.refresh * 1000

		for job, players in pairs(GPS) do
			for playerId, info in pairs(players) do
                -- info = xPlayer, netId, coords, heading
				local playerPed = GetPlayerPed(playerId)

				GPS[job][playerId].coords = GetEntityCoords(playerPed)
				GPS[job][playerId].heading = math.ceil(GetEntityHeading(playerPed))
			end
		end

		for k, playerId in pairs(GetPlayers()) do
			playerId = tonumber(playerId)
			local playerJob = getPlayerJob(playerId)

			if GPS[playerJob] and GPS[playerJob][playerId] then
				TriggerClientEvent('msk_jobGPS:refreshBlips', playerId, GPS[playerJob])
			end
		end

        Wait(sleep)
    end
end)

getPlayerJob = function(playerId)
	playerId = tonumber(playerId)

	if not playerJobs[playerId] then 
		local xPlayer = ESX.GetPlayerFromId(playerId)

		if xPlayer then
			playerJobs[playerId] = xPlayer.job.name
		end
	end

	return playerJobs[playerId] or 'unemployed'
end

removeBlipById = function(xPlayer, reason)
	local source, job = xPlayer.source, xPlayer.job.name

	if GPS[job] and GPS[job][tonumber(source)] then 
		GPS[job][tonumber(source)] = nil

		for playerId, v in pairs(GPS[job]) do
			Config.Notification(playerId, Translation[Config.Locale]['gps_deactivated_all']:format(xPlayer.name), 'info')
			TriggerClientEvent('msk_jobGPS:deactivateGPSById', playerId, tonumber(source), reason)
		end
	end
end

logging = function(code, ...)
    if not Config.Debug then return end
    MSK.Logging(code, ...)
end

GithubUpdater = function()
    local GetCurrentVersion = function()
	    return GetResourceMetadata( GetCurrentResourceName(), "version" )
    end
    
    local CurrentVersion = GetCurrentVersion()
    local resourceName = "[^2"..GetCurrentResourceName().."^0]"

    if Config.VersionChecker then
        PerformHttpRequest('https://raw.githubusercontent.com/MSK-Scripts/msk_jobGPS/main/VERSION', function(Error, NewestVersion, Header)
            print("###############################")
            if CurrentVersion == NewestVersion then
                print(resourceName .. '^2 ✓ Resource is Up to Date^0 - ^5Current Version: ^2' .. CurrentVersion .. '^0')
            elseif CurrentVersion ~= NewestVersion then
                print(resourceName .. '^1 ✗ Resource Outdated. Please Update!^0 - ^5Current Version: ^1' .. CurrentVersion .. '^0')
                print('^5Newest Version: ^2' .. NewestVersion .. '^0 - ^6Download here:^9 https://github.com/MSK-Scripts/msk_jobGPS/releases/tag/v'.. NewestVersion .. '^0')
            end
            print("###############################")
        end)
    else
        print(resourceName .. '^2 ✓ Resource loaded^0')
    end
end
GithubUpdater()
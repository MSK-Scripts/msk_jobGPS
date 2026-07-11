local GPS = {}
local playerJobs = {}
local panicCooldowns = {}

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

	-- Serverside rate limit against spam.
	local cooldown = (Config.Panicbutton.cooldown or 0) * 1000
	if cooldown > 0 then
		local now = GetGameTimer()
		if panicCooldowns[src] and now - panicCooldowns[src] < cooldown then return end
		panicCooldowns[src] = now
	end

	Config.Notification(src, Translation[Config.Locale]['panic_pressed'], 'info')

	local job = xPlayer.job.name
	-- Only send source + coords, not the whole ESX object.
	local panicData = { source = tonumber(src), coords = GetEntityCoords(GetPlayerPed(src)) }

	for playerId, info in pairs(GPS[job]) do
		if tonumber(playerId) ~= tonumber(src) then
			TriggerClientEvent('msk_jobGPS:activatePanicbutton', playerId, panicData)
			Config.Notification(playerId, Translation[Config.Locale]['panic_activated']:format(xPlayer.name), 'warning')
		end
	end

	if Config.Panicbutton.notifyNearestPlayers then
		notifyNearestPlayers(src, job)
	end
end

-- Serverside neighbour notification. Distance is checked here, not on the client,
-- so no arbitrary target IDs can be passed in from outside.
notifyNearestPlayers = function(src, job)
	local presserCoords = GetEntityCoords(GetPlayerPed(src))
	local radius = Config.Panicbutton.radius or 8.0

	for _, playerId in ipairs(GetPlayers()) do
		playerId = tonumber(playerId)

		-- Job colleagues with active GPS were already notified -> don't notify twice
		if playerId ~= tonumber(src) and not (GPS[job] and GPS[job][playerId]) then
			local targetPed = GetPlayerPed(playerId)

			if targetPed and targetPed ~= 0 and #(presserCoords - GetEntityCoords(targetPed)) <= radius then
				Config.Notification(playerId, Translation[Config.Locale]['panic_activated']:format(Translation[Config.Locale]['someone']), 'warning')
			end
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
		removeBlipById(src, xPlayer.job.name, 'stayOnDeactivate')
	else
		local playerPed, playerJob = GetPlayerPed(src), xPlayer.job.name
		playerJobs[tonumber(src)] = playerJob

		for playerId, v in pairs(GPS[playerJob]) do
			Config.Notification(playerId, Translation[Config.Locale]['gps_activated_all']:format(xPlayer.name), 'info')
		end

		GPS[playerJob][tonumber(src)] = {
			-- Only the fields the client actually needs. NOT the whole
			-- ESX object (which holds accounts, inventory, license, ssn, ...).
			xPlayer = {
				source = tonumber(src),
				name = xPlayer.name,
				identifier = xPlayer.identifier,
				coords = GetEntityCoords(playerPed),
			},
			netId = NetworkGetNetworkIdFromEntity(playerPed),
			coords = GetEntityCoords(playerPed),
			heading = math.ceil(GetEntityHeading(playerPed))
		}

		Config.Notification(src, Translation[Config.Locale]['gps_activated'], 'info')
		TriggerClientEvent('msk_jobGPS:activateGPS', src, GPS[playerJob])
	end
end)

-- Serverside-only ESX events -> AddEventHandler so clients cannot fake them.
AddEventHandler('esx:playerLogout', function(source)
	removeBlipByAnyJob(source, 'stayOnLeaveServer')
end)

AddEventHandler('esx:playerDropped', function(playerId, reason)
	local src = tonumber(playerId)

	removeBlipByAnyJob(src, 'stayOnLeaveServer')
	playerJobs[src] = nil
	panicCooldowns[src] = nil
end)

AddEventHandler("esx:setJob", function(playerId, newJob, oldJob)
	if newJob.name == oldJob.name then return end
	local src = tonumber(playerId)
	if not GPS[oldJob.name] then return end
	if not GPS[oldJob.name][src] then return end

	Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(src, oldJob.name, 'stayOnJobChange')
end)

RegisterNetEvent('msk_jobGPS:setDeath', function()
	local src = source
   	local xPlayer = ESX.GetPlayerFromId(src)
	if not xPlayer then return end
	if not GPS[xPlayer.job.name] then return end
	if not GPS[xPlayer.job.name][tonumber(src)] then return end

	Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(src, xPlayer.job.name, 'stayOnDeath')
end)

-- Deactivates a player's GPS when he lost the tracker item.
-- Called both by the ESX event (default inventory) and by the ownership poll
-- in the refresh loop (ox_inventory and others).
handleGpsItemRemoved = function(src, job)
	src = tonumber(src)
	local entry = GPS[job] and GPS[job][src]
	if not entry then return end

	local name = entry.xPlayer and entry.xPlayer.name or 'Unknown'

	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(src, job, 'stayOnRemoveItem')

	for playerId, v in pairs(GPS[job]) do
		Config.Notification(playerId, Translation[Config.Locale]['gps_removed_inventory']:format(name), 'warning')
	end
end

-- ESX default inventory: fires immediately on removal. ox_inventory does NOT
-- fire this event, so the ownership poll in the refresh loop covers it instead.
AddEventHandler('esx:onRemoveInventoryItem', function(source, item, count)
	if item ~= Config.GPS.item or count ~= 0 then return end
	handleGpsItemRemoved(source, getPlayerJob(source))
end)

-- Inventory-agnostic check whether the player still owns the GPS tracker item.
playerHasGpsItem = function(playerId)
	local item = MSK.HasItem(playerId, Config.GPS.item)

	if type(item) == 'table' then
		return (item.count or 0) > 0
	end

	return (tonumber(item) or 0) > 0
end

CreateThread(function()
    while true do
        local sleep = Config.GPS.refresh * 1000

		for job, players in pairs(GPS) do
			local lostItem = {}

			for playerId, info in pairs(players) do
                -- info = xPlayer, netId, coords, heading
				local playerPed = GetPlayerPed(playerId)

				GPS[job][playerId].coords = GetEntityCoords(playerPed)
				GPS[job][playerId].heading = math.ceil(GetEntityHeading(playerPed))

				-- ox_inventory and others don't fire esx:onRemoveInventoryItem -> check ownership here.
				-- Only check with a loaded ped so a still-loading player is not deactivated by mistake.
				if playerPed ~= 0 and not playerHasGpsItem(playerId) then
					lostItem[#lostItem + 1] = playerId
				end
			end

			-- Deactivate only after iterating, so we don't delete from players during pairs().
			for _, playerId in ipairs(lostItem) do
				handleGpsItemRemoved(playerId, job)
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

removeBlipById = function(source, jobName, reason)
	source = tonumber(source)
	local entry = GPS[jobName] and GPS[jobName][source]
	if not entry then return end

	-- Read the name from the stored entry so it still works
	-- when the ESX object was already removed on disconnect.
	local name = entry.xPlayer and entry.xPlayer.name or 'Unknown'
	GPS[jobName][source] = nil

	for playerId, v in pairs(GPS[jobName]) do
		Config.Notification(playerId, Translation[Config.Locale]['gps_deactivated_all']:format(name), 'info')
		TriggerClientEvent('msk_jobGPS:deactivateGPSById', playerId, source, reason)
	end
end

-- Removes a player from the job table he is actually registered in.
-- For cases (disconnect) where the current job can no longer be reliably determined.
removeBlipByAnyJob = function(source, reason)
	source = tonumber(source)

	for job, players in pairs(GPS) do
		if players[source] then
			removeBlipById(source, job, reason)
			return
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
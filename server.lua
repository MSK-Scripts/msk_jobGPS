-- Notifications, TextUI and progress bars use the table forms of msk_core 4.1.0.
-- An older msk_core shows broken notifications, so say it loudly on start.
MSK.Check.Dependency('msk_core', '4.1.0', true)

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

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

logging = function(code, ...)
	if not Config.Debug then return end
	MSK.Logging(code, ...)
end

-- Maps a ped's current vehicle to a coarse blip category.
-- Serverside natives (OneSync): GetVehiclePedIsIn + GetVehicleType.
getVehicleCategory = function(ped)
	local veh = ped and GetVehiclePedIsIn(ped, false)
	if not veh or veh == 0 then return 'foot' end

	local vtype = GetVehicleType(veh)

	if vtype == 'bike' then
		return 'bike' -- bicycle & motorcycle
	elseif vtype == 'boat' or vtype == 'submarine' then
		return 'boat'
	elseif vtype == 'heli' then
		return 'heli'
	elseif vtype == 'plane' then
		return 'plane'
	end

	return 'car'
end

-- Inventory-agnostic check whether the player still owns the GPS tracker item.
playerHasGpsItem = function(playerId)
	local item = MSK.HasItem(playerId, Config.GPS.item)

	if type(item) == 'table' then
		return (item.count or 0) > 0
	end

	return (tonumber(item) or 0) > 0
end

getPlayerJob = function(playerId)
	playerId = tonumber(playerId)

	if not playerJobs[playerId] then
		local xPlayer = MSK.GetPlayerFromId(playerId)
		if xPlayer and xPlayer.job then playerJobs[playerId] = xPlayer.job.name end
	end

	return playerJobs[playerId] or 'unemployed'
end

removeBlipById = function(source, jobName, reason)
	source = tonumber(source)
	local entry = GPS[jobName] and GPS[jobName][source]
	if not entry then return end

	-- Read the name from the stored entry so it still works
	-- when the framework player object was already removed on disconnect.
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

cleanupPlayer = function(src)
	src = tonumber(src)
	if not src then return end

	removeBlipByAnyJob(src, 'stayOnLeaveServer')
	playerJobs[src] = nil
	panicCooldowns[src] = nil
end

--------------------------------------------------------------------------------
-- GPS toggle (item use or command)
--------------------------------------------------------------------------------

toggleGps = function(src)
	src = tonumber(src)
	local xPlayer = MSK.GetPlayerFromId(src)
	if not xPlayer or not xPlayer.job then return end

	local job = xPlayer.job.name
	if not (Config.allowedJobs[job] and Config.allowedJobs[job].gps) then return end
	if not GPS[job] then GPS[job] = {} end

	playerJobs[src] = job

	if GPS[job][src] then
		Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
		TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
		removeBlipById(src, job, 'stayOnDeactivate')
	else
		local playerPed = GetPlayerPed(src)

		for playerId, v in pairs(GPS[job]) do
			Config.Notification(playerId, Translation[Config.Locale]['gps_activated_all']:format(xPlayer.name), 'info')
		end

		GPS[job][src] = {
			-- Only the fields the client actually needs. NOT the whole framework
			-- object (which holds accounts, inventory, license, ...).
			xPlayer = {
				source = src,
				name = xPlayer.name,
				identifier = xPlayer.identifier,
				coords = GetEntityCoords(playerPed),
			},
			netId = NetworkGetNetworkIdFromEntity(playerPed),
			coords = GetEntityCoords(playerPed),
			heading = math.ceil(GetEntityHeading(playerPed)),
			veh = getVehicleCategory(playerPed),
		}

		Config.Notification(src, Translation[Config.Locale]['gps_activated'], 'info')
		TriggerClientEvent('msk_jobGPS:activateGPS', src, GPS[job])
	end
end

-- Registers the usable item for ESX and QBCore (via msk_core).
MSK.RegisterItem(Config.GPS.item, function(source)
	toggleGps(source)
end)

if Config.Commands.gps.enable then
	RegisterCommand(Config.Commands.gps.command, function(source)
		if not source or source == 0 then return end
		-- The command requires the tracker item, just like using it from the inventory.
		if not playerHasGpsItem(source) then return end
		toggleGps(source)
	end)
end

--------------------------------------------------------------------------------
-- Panicbutton
--------------------------------------------------------------------------------

togglePanicbutton = function(src)
	if not Config.Panicbutton.enable then return end
	src = tonumber(src)
	local xPlayer = MSK.GetPlayerFromId(src)
	if not xPlayer or not xPlayer.job then return end

	local job = xPlayer.job.name
	if not (Config.allowedJobs[job] and Config.allowedJobs[job].panicbutton) then return end

	local canUse = true

	if Config.Panicbutton.item.enable then
		local hasItem = MSK.HasItem(src, Config.Panicbutton.item.item)

		if not hasItem or (type(hasItem) == 'table' and (hasItem.count or 0) == 0) then
			canUse = false
		end
	end

	if not (GPS[job] and GPS[job][src]) then canUse = false end
	if not canUse then return Config.Notification(src, Translation[Config.Locale]['panic_activate_GPS'], 'error') end

	-- Serverside rate limit against spam.
	local cooldown = (Config.Panicbutton.cooldown or 0) * 1000
	if cooldown > 0 then
		local now = GetGameTimer()
		if panicCooldowns[src] and now - panicCooldowns[src] < cooldown then return end
		panicCooldowns[src] = now
	end

	Config.Notification(src, Translation[Config.Locale]['panic_pressed'], 'info')

	-- Only send source + coords, not a full player object.
	local panicData = { source = src, coords = GetEntityCoords(GetPlayerPed(src)) }

	for playerId, info in pairs(GPS[job]) do
		if tonumber(playerId) ~= src then
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
		if playerId ~= src and not (GPS[job] and GPS[job][playerId]) then
			local targetPed = GetPlayerPed(playerId)

			if targetPed and targetPed ~= 0 and #(presserCoords - GetEntityCoords(targetPed)) <= radius then
				Config.Notification(playerId, Translation[Config.Locale]['panic_activated']:format(Translation[Config.Locale]['someone']), 'warning')
			end
		end
	end
end

RegisterNetEvent('msk_jobGPS:togglePanicbutton', function()
	togglePanicbutton(source)
end)

if Config.Panicbutton.enable and Config.Panicbutton.item.enable then
	MSK.RegisterItem(Config.Panicbutton.item.item, function(source)
		togglePanicbutton(source)
	end)
end

--------------------------------------------------------------------------------
-- Deactivation triggers (item lost, death, job change, disconnect)
--------------------------------------------------------------------------------

-- Deactivates a player's GPS when he lost the tracker item.
-- Called both by the ESX event (default inventory) and by the ownership poll
-- in the refresh loop (QBCore, ox_inventory and others).
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

-- ESX default inventory: fires immediately on removal. Other inventories don't
-- fire this, so the ownership poll in the refresh loop covers them.
AddEventHandler('esx:onRemoveInventoryItem', function(source, item, count)
	if item ~= Config.GPS.item or count ~= 0 then return end
	handleGpsItemRemoved(source, getPlayerJob(source))
end)

-- Deactivate on job change. Works without knowing the old job by finding the
-- table the player is registered in.
onJobChange = function(src, newJobName)
	src = tonumber(src)

	for job, players in pairs(GPS) do
		if players[src] then
			if job == newJobName then return end -- same job (e.g. grade change) -> keep
			Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
			TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
			removeBlipById(src, job, 'stayOnJobChange')
			return
		end
	end
end

-- Registered for both frameworks; each event only fires on its own framework.
AddEventHandler('esx:setJob', function(playerId, newJob, oldJob)
	if newJob and newJob.name then onJobChange(playerId, newJob.name) end
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(playerId, newJob)
	if newJob and newJob.name then onJobChange(playerId, newJob.name) end
end)

-- Death (the client reports it framework-agnostic via msk_core:onPlayerDeath).
RegisterNetEvent('msk_jobGPS:setDeath', function()
	local src = source
	local job = getPlayerJob(src)
	if not (GPS[job] and GPS[job][tonumber(src)]) then return end

	Config.Notification(src, Translation[Config.Locale]['gps_deactivated'], 'info')
	TriggerClientEvent('msk_jobGPS:deactivateGPS', src)
	removeBlipById(src, job, 'stayOnDeath')
end)

-- Disconnect / logout. playerDropped is framework-agnostic; the framework logout
-- events additionally cover character switches without a full disconnect.
AddEventHandler('playerDropped', function(reason)
	cleanupPlayer(source)
end)

AddEventHandler('esx:playerLogout', function(playerId)
	cleanupPlayer(playerId)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId)
	cleanupPlayer(playerId)
end)

--------------------------------------------------------------------------------
-- Refresh loop
--------------------------------------------------------------------------------

CreateThread(function()
	while true do
		local sleep = Config.GPS.refresh * 1000

		for job, players in pairs(GPS) do
			local lostItem = {}

			for playerId, info in pairs(players) do
				-- info = xPlayer, netId, coords, heading, veh
				local playerPed = GetPlayerPed(playerId)

				GPS[job][playerId].coords = GetEntityCoords(playerPed)
				GPS[job][playerId].heading = math.ceil(GetEntityHeading(playerPed))
				GPS[job][playerId].veh = getVehicleCategory(playerPed)

				-- Non-ESX inventories don't fire esx:onRemoveInventoryItem -> check ownership here.
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

		for _, playerId in ipairs(GetPlayers()) do
			playerId = tonumber(playerId)
			local playerJob = getPlayerJob(playerId)

			if GPS[playerJob] and GPS[playerJob][playerId] then
				TriggerClientEvent('msk_jobGPS:refreshBlips', playerId, GPS[playerJob])
			end
		end

		Wait(sleep)
	end
end)

--------------------------------------------------------------------------------
-- Version check
--------------------------------------------------------------------------------

GithubUpdater = function()
    local GetCurrentVersion = function()
	    return GetResourceMetadata( GetCurrentResourceName(), "version" )
    end

    local CurrentVersion = GetCurrentVersion()
    local resourceName = "[^2"..GetCurrentResourceName().."^0]"

    if Config.VersionChecker then
        PerformHttpRequest('https://raw.githubusercontent.com/MSK-Scripts/msk_jobGPS/main/VERSION', function(Error, NewestVersion, Header)
            if CurrentVersion == NewestVersion then
                print(resourceName .. '^2 ✓ Resource is Up to Date^0 - ^5Current Version: ^2' .. CurrentVersion .. '^0')
            elseif CurrentVersion ~= NewestVersion then
                print(resourceName .. '^1 ✗ Resource Outdated. Please Update!^0 - ^5Current Version: ^1' .. CurrentVersion .. '^0')
                print('^5Newest Version: ^2' .. NewestVersion .. '^0 - ^6Download here:^9 https://github.com/MSK-Scripts/msk_jobGPS/releases/tag/v'.. NewestVersion .. '^0')
            end
        end)
    else
        print(resourceName .. '^2 ✓ Resource loaded^0')
    end
end
GithubUpdater()

Config = {}
----------------------------------------------------------------
Config.Locale = 'de'
Config.Debug = false
Config.VersionChecker = true
----------------------------------------------------------------
-- !!! This function is clientside AND serverside !!!
Config.Notification = function(source, message, info)
    if IsDuplicityVersion() then -- serverside
        MSK.Notification(source, 'MSK JobGPS', message, info)
    else -- clientside
        MSK.Notification('MSK JobGPS', message, info)
    end
end
----------------------------------------------------------------
Config.StayActivated = {
    -- If set to true and someone deactivate the GPS then the Blip will be removed after X seconds.
    -- If set to false and someone deactivated the GPS then the Blip will be removed immediately.
    enable = true, -- Set to false to deactivated this feature completely
    seconds = 60,

    ['stayOnDeactivate'] = false,
    ['stayOnLeaveServer'] = true,
    ['stayOnDeath'] = true,
    ['stayOnRemoveItem'] = true,
}

Config.GPS = {
    item = 'tracker',
    blip = {id = 1, color = 2, scale = 0.7, prefix = 'GPS'},
    refresh = 2.5 -- in seconds // Refreshtime if player is not in OneSync distance
}

Config.Panicbutton = {
    enable = true, -- Set false to deactivated this feature completely
    item = {enable = false, item = 'panicbutton'}, -- You need that item in your inventory if set to true
    hotkey = {enable = true, key = 'f9'}, -- Command has to be activated // RegisterKeyMapping (https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/)
    blipColor = 1, -- This will change the Blipcolor of GPS Blip
    notifyNearestPlayers = true,
}
----------------------------------------------------------------
Config.Commands = {
    gps = {enable = true, command = 'toggleGPS'},
    panicbutton = {enable = true, command = 'togglePanic'} -- If you set to false then the hotkey doesn't work
}
----------------------------------------------------------------
Config.allowedJobs = {
    ['police'] = {gps = true, panicbutton = true},
    ['ambulance'] = {gps = true, panicbutton = true},
    ['justice'] = {gps = true, panicbutton = true},
    ['doj'] = {gps = true, panicbutton = true},

    ['bloods'] = {gps = true, panicbutton = false},
    ['grove'] = {gps = true, panicbutton = false},
    ['vagos'] = {gps = true, panicbutton = false},
    ['crips'] = {gps = true, panicbutton = false},
    ['ballas'] = {gps = true, panicbutton = false},
    ['mg13'] = {gps = true, panicbutton = false},
    ['lm'] = {gps = true, panicbutton = false},
}
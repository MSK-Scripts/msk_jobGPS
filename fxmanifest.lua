fx_version 'adamant'
games { 'gta5' }

author 'Musiker15 - MSK Scripts'
name 'msk_jobGPS'
description 'Creates Blips for all players at the same job if they activate their gps. Supports ESX & QBCore via msk_core.'
version '1.5.1'

lua54 'yes'

shared_script {
    '@msk_core/import.lua',
    'config.lua',
    'translations.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

dependencies {
    'msk_core'
}
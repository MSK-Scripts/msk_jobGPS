fx_version 'adamant'
games { 'gta5' }

author 'Musiker15 - MSK Scripts'
name 'msk_jobGPS'
description 'Creates Blips for all players at the same job if they activate there gps'
version '1.4.0'

lua54 'yes'

shared_script {
    '@es_extended/imports.lua',
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
    'es_extended',
    'msk_core'
}
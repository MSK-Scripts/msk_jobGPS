# msk_jobGPS
Player, Job, Blip & Panicbutton for ESX and QBCore

### [Forum Post](https://forum.cfx.re/t/msk-jobgps/5109080)

## Description
* Works on both ESX and QBCore (framework is auto detected through msk_core)
* Use an Item or Command to activate/deactivate your GPS signal and see the blips of other players with the same job
* The blip icon shows how a player is travelling: on foot, bike (bicycle & motorcycle), car, boat, helicopter or plane
* If the player is in OneSync distance the blip is updated in real time, otherwise it is updated every X seconds
* If you die, change your job, drop the tracker item or leave the server the blip is removed
* You can configure which jobs may use the GPS or the panicbutton
* If you use the panicbutton the blip color changes and all players with the same job get a notification
* The nearest players also get a notification when the panicbutton is used

## Requirements
* [msk_core](https://github.com/MSK-Scripts/msk_core)
* A framework: [ESX Legacy](https://github.com/esx-framework/esx_core) or [QBCore](https://github.com/qbcore-framework/qb-core)

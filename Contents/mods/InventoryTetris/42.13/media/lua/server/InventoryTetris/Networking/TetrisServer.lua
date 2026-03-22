-- Keep command names synced with TetrisClient.lua
local MODULE = "InventoryTetris"

local TETRIS_UUID = "TetrisUUID"

local WORLD_ITEM_DATA    = "INVENTORYTETRIS_WorldItemData"
local VEHICLE_ITEM_DATA  = "INVENTORYTETRIS_VehicleItemData"

local CMD_WORLD_PARTIAL   = "WorldItemPartial"
local CMD_VEHICLE_PARTIAL = "VehicleItemPartial"
local CMD_REQUEST_WORLD   = "RequestWorldData"
local CMD_REQUEST_VEHICLE = "RequestVehicleData"
local CMD_WORLD_UPDATE    = "WorldItemUpdate"
local CMD_VEHICLE_UPDATE  = "VehicleItemUpdate"
local CMD_WORLD_FULL      = "WorldItemFull"
local CMD_VEHICLE_FULL    = "VehicleItemFull"

local TetrisServer = {}

function TetrisServer.getOrCreateUuid(tableObj)
    local uuid = tableObj[TETRIS_UUID]
    if not uuid then
        uuid = getRandomUUID()
        tableObj[TETRIS_UUID] = uuid
    end
    return uuid
end

local function validateTimestamps(existingData, incomingData)
    if not existingData.lastServerTime then
        return true
    end

    if not incomingData.lastServerTime then
        return false
    end

    return incomingData.lastServerTime == existingData.lastServerTime
end

local function handlePartialData(fullKey, broadcastCommand, player, incomingData)
    local uuid = TetrisServer.getOrCreateUuid(incomingData)
    local fullData = ModData.getOrCreate(fullKey)
    local existingData = fullData[uuid]

    if not existingData or validateTimestamps(existingData, incomingData) then
        incomingData.lastServerTime = getTimestampMs()
        fullData[uuid] = incomingData
        -- Broadcast the accepted update to all clients
        sendServerCommand(nil, MODULE, broadcastCommand, incomingData)
    else
        -- Reject stale data: send the authoritative version back to just this client
        sendServerCommand(player, MODULE, broadcastCommand, existingData)
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if not isServer() or module ~= MODULE then return end

    if command == CMD_WORLD_PARTIAL then
        handlePartialData(WORLD_ITEM_DATA, CMD_WORLD_UPDATE, player, args)

    elseif command == CMD_VEHICLE_PARTIAL then
        handlePartialData(VEHICLE_ITEM_DATA, CMD_VEHICLE_UPDATE, player, args)

    elseif command == CMD_REQUEST_WORLD then
        local fullData = ModData.getOrCreate(WORLD_ITEM_DATA)
        sendServerCommand(player, MODULE, CMD_WORLD_FULL, fullData)

    elseif command == CMD_REQUEST_VEHICLE then
        local fullData = ModData.getOrCreate(VEHICLE_ITEM_DATA)
        sendServerCommand(player, MODULE, CMD_VEHICLE_FULL, fullData)
    end
end)

return TetrisServer

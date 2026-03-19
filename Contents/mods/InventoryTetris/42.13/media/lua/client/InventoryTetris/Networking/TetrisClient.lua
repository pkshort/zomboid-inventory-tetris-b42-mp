-- Handles syncing of grid data between client and server for world items and vehicles,
-- which do not support the normal modData syncing methods.

-- Keep command names synced with TetrisServer.lua
local MODULE = "InventoryTetris"

local TETRIS_UUID = "TetrisUUID"

local WORLD_ITEM_DATA = "INVENTORYTETRIS_WorldItemData"
local VEHICLE_ITEM_DATA = "INVENTORYTETRIS_VehicleItemData"

local CMD_WORLD_PARTIAL  = "WorldItemPartial"
local CMD_VEHICLE_PARTIAL = "VehicleItemPartial"
local CMD_REQUEST_WORLD   = "RequestWorldData"
local CMD_REQUEST_VEHICLE = "RequestVehicleData"
local CMD_WORLD_UPDATE    = "WorldItemUpdate"
local CMD_VEHICLE_UPDATE  = "VehicleItemUpdate"
local CMD_WORLD_FULL      = "WorldItemFull"
local CMD_VEHICLE_FULL    = "VehicleItemFull"

TetrisClient = {}
TetrisClient._modDataSyncQueue = {}

function TetrisClient.queueModDataSync(obj)
    TetrisClient._modDataSyncQueue[obj] = true
end


function TetrisClient.getMostRecentModData(isoModData, isoKey, worldModData, worldKey)
    local worldData = worldModData[worldKey]
    if not worldData then
        return isoModData
    end

    local isoData = isoModData[isoKey]
    if not isoData then
        isoModData[isoKey] = worldData
    else
        local isoTime = isoData.lastServerTime or 0
        local worldTime = worldData.lastServerTime or 0
        if worldTime > isoTime then
            isoModData[isoKey] = worldData
        end
    end

    return isoModData
end

function TetrisClient.getInventoryContainerModData(item)
    return TetrisClient.getMostRecentModData(item:getModData(), "gridContainers", ModData.getOrCreate(WORLD_ITEM_DATA), item:getID()), item:getWorldItem()
end

function TetrisClient.getVehicleModData(vehicle)
    return TetrisClient.getMostRecentModData(vehicle:getModData(), "gridContainers", ModData.getOrCreate(VEHICLE_ITEM_DATA), vehicle:getKeyId()), vehicle
end


local function cacheGridData(dataKey, gridData)
    ModData.getOrCreate(dataKey)[gridData[TETRIS_UUID]] = gridData
end

function TetrisClient.transmitWorldInventoryObjectData(worldInvObject)
    local item = worldInvObject:getItem()
    local gridData = item and item:getModData().gridContainers
    if not gridData then return end

    gridData[TETRIS_UUID] = item:getID()
    cacheGridData(WORLD_ITEM_DATA, gridData)
    sendClientCommand(MODULE, CMD_WORLD_PARTIAL, gridData)
end

function TetrisClient.transmitVehicleInventoryData(vehicleObj)
    local gridData = vehicleObj:getModData().gridContainers
    if not gridData then return end

    gridData[TETRIS_UUID] = vehicleObj:getKeyId()
    cacheGridData(VEHICLE_ITEM_DATA, gridData)
    sendClientCommand(MODULE, CMD_VEHICLE_PARTIAL, gridData)
end

if isClient() then
    Events.OnTick.Add(function()
        for obj,_ in pairs(TetrisClient._modDataSyncQueue) do
            if instanceof(obj, "IsoWorldInventoryObject") then
                TetrisClient.transmitWorldInventoryObjectData(obj)

            elseif instanceof(obj, "BaseVehicle") then
                TetrisClient.transmitVehicleInventoryData(obj)

            elseif obj.transmitModData then
                obj:transmitModData()
            end
        end
        table.wipe(TetrisClient._modDataSyncQueue)
    end)

    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE then return end

        if command == CMD_WORLD_UPDATE then
            -- A world item was updated by another client (or corrected by server)
            if args and args[TETRIS_UUID] then
                cacheGridData(WORLD_ITEM_DATA, args)
            end

        elseif command == CMD_VEHICLE_UPDATE then
            -- A vehicle was updated by another client (or corrected by server)
            if args and args[TETRIS_UUID] then
                cacheGridData(VEHICLE_ITEM_DATA, args)
            end

        elseif command == CMD_WORLD_FULL then
            -- Full world item dataset received on initial load
            ModData.add(WORLD_ITEM_DATA, args)

        elseif command == CMD_VEHICLE_FULL then
            -- Full vehicle dataset received on initial load
            ModData.add(VEHICLE_ITEM_DATA, args)
        end
    end)
end

Events.OnLoad.Add(function()
    if isClient() then
        sendClientCommand(MODULE, CMD_REQUEST_WORLD, {})
        sendClientCommand(MODULE, CMD_REQUEST_VEHICLE, {})
    end
end)

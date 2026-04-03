local Version = require("Notloc/Versioning/Version")

---@class InventoryTetris
---@field public version ModVersion
local InventoryTetris = {
    version = Version:new(6, 12, 0, "beta"),
}

print("InventoryTetris version: " .. Version.format(InventoryTetris.version))
_G.InventoryTetris = InventoryTetris

return InventoryTetris

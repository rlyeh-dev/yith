---@diagnostic disable
local res = interplanetary_weather({ cherry = "GIVE ME CHERRIES DAMN IT" })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))

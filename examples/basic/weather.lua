---@diagnostic disable: lowercase-global, missing-return

---@class WeatherParams
---@field location "mercury"|"venus"|"earth"|"mars"|"jupiter"|"saturn"|"uranus"|"neptune"|"pluto"|"ceres"|"eris"|"makemake"|"asteroid_belt"|"luna"|"phobos"|"deimos"|"io"|"europa"|"ganymede"|"titan"|"enceladus" Location you'd like your weather for

---@class WeatherReport
---@field kelvin number Temperature for Scientists!
---@field fahrenheit number Temperature for Americans!
---@field celsius number Temperature for Everyone Else!
---@field conditions string Friendly overview of weather conditions
---@field advisory string Warnings for travelers and local residents

---Up-to-date weather information across the solar system
---@param params WeatherParams
---@return WeatherReport
function interplanetary_weather(params)
  -- implemented in native code
end

-- EXAMPLE:
local res = interplanetary_weather({ location = "luna" })
print(string.format("io temps: %.3f k, %.3f f, %.3f c", res.kelvin, res.fahrenheit, res.celsius))
print(string.format("io conditions: %s", res.conditions))
print(string.format("io advisory: %s", res.advisory))

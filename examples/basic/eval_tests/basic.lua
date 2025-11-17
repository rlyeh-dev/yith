---@diagnostic disable: undefined-global
local res

res = simple_food_service({ food = "orange", count = 2 })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))

res = interplanetary_weather({ location = "io" })
print(string.format("io temps: %.3f k, %.3f f, %.3f c", res.kelvin, res.fahrenheit, res.celsius))
print(string.format("io conditions: %s", res.conditions))
print(string.format("io advisory: %s", res.advisory))

res = hello_goodbye_a({ hello = "hey", goodbye = "cya" })
print("hi:", res.hi)
print("bye:", res.bye)

res = hello_goodbye_b({ hello = "sup", goodbye = "later tater" })
print("hi:", res.hi)
print("bye:", res.bye)

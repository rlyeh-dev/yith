---@diagnostic disable: undefined-global
local res

print()
print("FOOD: ")
res = simple_food_service({ food = "orange", count = 2 })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))
print()

print("WEATHER: ")
res = interplanetary_weather({ location = "io" })
print(string.format("io temps: %.0f°k, %.0f°f, %.0f°c", res.kelvin, res.fahrenheit, res.celsius))
print(string.format("io conditions: %s", res.conditions))
print(string.format("io advisory: %s", res.advisory))
print()

print("HIHI BYEBYE #1: ")
res = hello_goodbye_marshaled({ hello = "hey", goodbye = "cya" })
print("hi:", res.hi)
print("bye:", res.bye)
print()

print("HIHI BYEBYE #2: ")
res = hello_goodbye_raw_lua({ hello = "haha sup", goodbye = "later tater rofl" })
print("hi:", res.hi)
print("bye:", res.bye)
print()


print("HIHI BYEBYE #3: ")
res = hello_goodbye_auto({ hello = "hi", goodbye = "bye" })
print("hi:", res.hi)
print("bye:", res.bye)
print()

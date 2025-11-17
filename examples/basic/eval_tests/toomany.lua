local res = simple_food_service({ food = "banana", count = 500 })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))

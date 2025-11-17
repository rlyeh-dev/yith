local res = simple_food_service({ food = "cherry", count = 8 })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))

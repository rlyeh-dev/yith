---@diagnostic disable: lowercase-global, missing-return

---@class FoodInput
---@field food string what kind of food item you want, e.g. "potato", "cherry", "pizza", "the soul of an orphan child"
---@field count integer how many of them food item you want to eat (maximum 10)

---@class FoodOutput
---@field food string your delivered food! enjoy and remember to tip your mcp!
---@field cost number how much you owe us

---Simple Food Delivery Service, Delivering Food to You and Your Friends to Eat! YUM!
---@param params FoodInput
---@return FoodOutput
function simple_food_service(params)
  -- implemented in native code
end

-- example call:
local res = simple_food_service({ food = "pizza", count = 8 })
print(res.food .. " just cost me $" .. string.format("%.2f", res.cost))

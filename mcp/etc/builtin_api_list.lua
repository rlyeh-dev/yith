---@diagnostic disable: lowercase-global, missing-return

---@class ApiListParams
---@field page integer Page number (starting from 1)
---@field per_page integer Number of results per page (max 50)

---@class ApiListResultItem
---@field name string API Function Name
---@field description string Short description of the api function
---@field docs string Long-form docs, be careful using this field as it can balloon your context especially with a lot of docs

---@class ApiListResults
---@field apis ApiListResultItem[] List of API functions matching the search criteria
---@field more boolean Whether or not there are more pages
---@field next_page integer Next page number if more results are available, 0 when more = false

---Search API functions available in this lua environment
---@param params ApiListParams
---@return ApiListResults
function api_list(params)
  -- implemented in native code
end

-- example
local next_page = 1
while next_page do
  print("Page:", next_page)
  local first_page = next_page == 1
  local results = api_list({ per_page = 5, page = next_page })
  next_page = results.next_page

  for index, value in ipairs(results.apis) do
    print('*', value.name, value.description)
    local first_result = index == 1
    if first_result and first_page then
      print(">>>", "DOCS:")
      print(value.docs)
      print("<<<")
    end
  end
end

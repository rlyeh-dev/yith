---@diagnostic disable: lowercase-global, missing-return

---@class ApiSearchParams
---@field query string Search Terms
---@field count? integer Number of results. Default: 3. Max: 10

---@class ApiSearchResult
---@field name string API Function Name
---@field description string Short description of the api function
---@field docs string Long-form docs, be careful using this field as it can balloon your context especially with a lot of docs
---@field score number the TF-IDF relevance score for this search

---Search API functions available in this lua environment
---@param params ApiSearchParams
---@return ApiSearchResult[]
function api_search(params)
  -- implemented in native code
end

-- example
local results = api_search({ query = "help search exact", count = 2 })
for index, value in ipairs(results) do
  print(value.score, value.name, value.description)
  print("DOCS:")
  print(value.docs)
end

print("---- Builtins: \n")
print("-- api_help():\n")
api_help()
print()

print("-- api_search():\n")
local results = api_search({ query = "help search exact", count = 2 })
for index, value in ipairs(results) do
  print(value.score, value.name, value.description)
  print("DOCS:")
  print(value.docs)
end
print()

print("-- api_docs():\n")
api_docs({ name = "api_docs" })
print()

print("-- api_list():\n")
local next_page = 1
local more = true
while more do
  print("Page:", next_page)
  local first = next_page == 1
  results = api_list({ per_page = 5, page = next_page })
  more = results.more
  next_page = results.next_page

  for index, value in ipairs(results.apis) do
    print('*', value.name, value.description)
    if index == 1 and first then
      print(">>>", "DOCS:")
      print(value.docs)
      print("<<<")
    end
  end
end

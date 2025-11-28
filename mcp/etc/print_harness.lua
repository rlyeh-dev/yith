MCP_PRINT_HARNESS_OUTPUT = {}

local function dump(t, depth)
  depth = depth or 0
  if depth > 3 then return "..." end -- Prevent infinite recursion

  if type(t) ~= "table" then
    return tostring(t)
  end

  local parts = {}
  for k, v in pairs(t) do
    local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
    local val = type(v) == "table" and dump(v, depth + 1) or tostring(v)
    parts[#parts + 1] = key .. "=" .. val
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

print = function(...)
  local args = { ... }
  local str = ""
  for i, v in ipairs(args) do
    if i > 1 then str = str .. "\t" end
    str = str .. dump(v)
  end
  table.insert(MCP_PRINT_HARNESS_OUTPUT, str)
end

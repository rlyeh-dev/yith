package miskatonic_mcp

import "base:runtime"
import "core:math"
import "core:fmt"
import "core:strings"
import lua "vendor:lua/5.4"

add_builtin_apis :: proc(server: ^Server) {
	register_api_docs(
		server,
		"api_help",
		"print help documentation, the same as the help tool",
		#load("etc/builtin_api_help.lua"),
	)
	register_api_docs(
		server,
		"api_search",
		"search apis and docs (tf-idf based)",
		#load("etc/builtin_api_search.lua"),
	)
	register_api_docs(
    server,
    "api_docs",
    "print api documentation for a given function name",
    #load("etc/builtin_api_docs.lua"),
  )
  register_api_docs(
    server,
    "api_list",
    "list all available APIs with pagination",
    #load("etc/builtin_api_list.lua"),
  )

	register_sandbox_setup(server, proc(sandbox: Sandbox) {
		register_sandbox_function(sandbox, Empty, Empty, "api_help", builtin_api_help)
		register_sandbox_function(sandbox, Api_Doc_Params, Empty, "api_docs", builtin_api_docs)
		lua.register(sandbox.lua_state, "api_search", builtin_api_search)
		lua.register(sandbox.lua_state, "api_list", builtin_api_list)
	})
}


@(private = "package")
Empty :: struct {}

@(private = "package")
Api_Doc_Params :: struct {
	name: string,
}

@(private = "package")
builtin_api_docs :: proc(params: Api_Doc_Params, sandbox: Sandbox) -> (res: Empty, error: string) {
	output, ok := docs_tool(server_from_sandbox(sandbox), params.name)
	if ok do sandbox_print(sandbox, output)
	else do error = "Couldn't print output"
	return
}

@(private = "package")
builtin_api_help :: proc(params: Empty, sandbox: Sandbox) -> (res: Empty, error: string) {
	output, ok := help_tool(server_from_sandbox(sandbox))

	if ok do sandbox_print(sandbox, output)
	else do error = "Couldn't print output"

	return
}


@(private = "package")
Api_List_Params :: struct {
  page: i64,
  per_page: i64,
}

@(private = "package")
builtin_api_list :: proc "c" (state: ^lua.State) -> i32 {
  sandbox := Sandbox{state}
	context = context_with_arena_from_sandbox(state)
	server := server_from_sandbox(state)

	ok: bool
	params: Api_List_Params
	params, ok = unmarshal_lua_table(state, -1, Api_List_Params)
	if !ok {
		lua.pushstring(state, "could not unmarshal input")
		lua.error(state)
	}

	page := int(params.page == 0 ? LIST_TOOL_DEFAULT_PAGE : math.max(params.page, 1))
  per_page := int(params.per_page == 0 ? LIST_TOOL_DEFAULT_PER_PAGE : math.clamp(params.per_page, 1, 50))

  api_count := len(server.api_docs)
	api_max_idx := api_count - 1
	first := (page - 1) * per_page
	if first > api_max_idx {
  	err := fmt.aprintfln("no results for page %d", page)
		return 0
	}

	last := math.min(first + per_page - 1, api_max_idx)
	lua.createtable(state, 0, 2)
	lua.createtable(state, i32(last - first + 1), 0)
	for idx in first ..= last {
		api := server.api_docs[idx]

		lua.createtable(state, 0, 3)

		lua.pushstring(state, strings.clone_to_cstring(api.name))
		lua.setfield(state, -2, "name")

		lua.pushstring(state, strings.clone_to_cstring(api.description))
		lua.setfield(state, -2, "description")

		lua.pushstring(state, strings.clone_to_cstring(api.docs))
		lua.setfield(state, -2, "docs")

		lua.seti(state, -2, lua.Integer(idx - first + 1))
	}
	lua.setfield(state, -2, "apis")
	if last < api_max_idx {
	  lua.pushinteger(state, lua.Integer(page + 1))
  } else {
    lua.pushnil(state)
	}
	lua.setfield(state, -2, "next_page")
  return 1
}

@(private = "package")
Api_Search_Params :: struct {
	query: string,
	count: i64,
}

@(private = "package")
builtin_api_search :: proc "c" (state: ^lua.State) -> i32 {
	sandbox := Sandbox{state}
	context = context_with_arena_from_sandbox(state)
	server := server_from_sandbox(state)

	ok: bool
	params: Api_Search_Params
	params, ok = unmarshal_lua_table(state, -1, Api_Search_Params)
	if !ok {
		lua.pushstring(state, "could not unmarshal input")
		lua.error(state)
	}

	count := int(params.count == 0 ? SEARCH_TOOL_DEFAULT_COUNT : math.clamp(params.count, 1, 10))
	results := api_search(server, params.query, count)
	defer destroy_api_search_results(&results)

	lua.createtable(state, i32(len(results)), 0)
	for result, idx in results {
		desc := server.api_docs[result.index].description
		docs := server.api_docs[result.index].docs

		lua.createtable(state, 0, 4)

		lua.pushstring(state, strings.clone_to_cstring(result.name))
		lua.setfield(state, -2, "name")

		lua.pushstring(state, strings.clone_to_cstring(desc))
		lua.setfield(state, -2, "description")

		lua.pushstring(state, strings.clone_to_cstring(docs))
		lua.setfield(state, -2, "docs")

		lua.pushnumber(state, lua.Number(result.score))
		lua.setfield(state, -2, "score")

		lua.seti(state, -2, lua.Integer(idx + 1))
	}

	return 1
}

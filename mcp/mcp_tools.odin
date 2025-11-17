package miskatonic_mcp

import "core:fmt"
import "core:mem"
import "core:strings"

evaluate_tool :: proc(server: ^Server, code: string) -> (output: string, ok: bool) {
	return lua_evaluate(&server.sandbox, server.apis[:], server.setups[:], code)
}

search_tool :: proc(server: ^Server, query: string, count: int = 5) -> (output: string, ok: bool) {
	ct := count > 10 ? 10 : count // you cant have more than 10
	results := api_search(server, query, ct)
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)

	fmt.sbprintfln(&ob, "Found %d results: ", len(results))
	for result in results {
		desc := server.apis[result.index].description
		fmt.sbprintfln(&ob, " * `%s`: %s (score: %.3f)", result.name, desc, result.score)
	}
	output = strings.clone(strings.to_string(ob))
	ok = true
	return
}

docs_tool :: proc(server: ^Server, func_name: string) -> (output: string, ok: bool) {
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)
	for api in server.apis {
		if api.name == func_name {
			fmt.sbprintfln(
				&ob,
				"API docs for `%s`:\nDescription: %s\n",
				func_name,
				api.description,
			)
			fmt.sbprintfln(&ob, "```lua\n%s\n```\n", api.docs)
			output = strings.clone(strings.to_string(ob))
			ok = true
			return
		}
	}
	fmt.sbprintfln(&ob, "No Lua API named `%s` could be found")
	output = strings.clone(strings.to_string(ob))
	ok = false
	return
}

list_tool :: proc(server: ^Server) -> (output: string, ok: bool) {
	//@TODO (but later, not important rn) add pagination/cursor support, do like 25 per page idk
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)
	fmt.sbprintfln(&ob, "# Available Lua API Calls: ")
	for api in server.apis {
		fmt.sbprintfln(&ob, " * `%s`: %s", api.name, api.description)
	}
	output = strings.clone(strings.to_string(ob))
	ok = true
	return
}

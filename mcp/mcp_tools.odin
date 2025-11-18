package miskatonic_mcp

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

evaluate_tool :: proc(server: ^Server, code: string) -> (output: string, ok: bool) {
	return lua_evaluate(&server.sandbox, server.apis[:], server.setups[:], code)
}

search_tool :: proc(
	server: ^Server,
	query: string,
	descs := true,
	count: int = 3,
) -> (
	output: string,
	ok: bool,
) {
	count := math.clamp(count, 1, 10)
	results := api_search(server, query, count)
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)

	fmt.sbprintfln(&ob, "Found %d results: ", len(results))
	for result in results {
		if descs {
			desc := server.apis[result.index].description
			fmt.sbprintfln(&ob, " * `%s`: %s (score: %.3f)", result.name, desc, result.score)
		} else {
			fmt.sbprintfln(&ob, " * `%s`: %s (score: %.3f)", result.name, result.score)
		}
	}
	output = strings.clone(strings.to_string(ob))
	ok = true
	return
}

docs_tool :: proc(server: ^Server, func_name: string) -> (output: string, ok: bool) {
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)
	if api_idx, found := server.api_names[func_name]; found {
		api := server.apis[api_idx]
		fmt.sbprintfln(&ob, "API docs for `%s`:\nDescription: %s\n", func_name, api.description)
		fmt.sbprintfln(&ob, "```lua\n%s\n```\n", api.docs)
		output = strings.clone(strings.to_string(ob))
		ok = true
		return
	}
	fmt.sbprintfln(&ob, "No Lua API named `%s` could be found")
	output = strings.clone(strings.to_string(ob))
	ok = false
	return
}

list_tool :: proc(
	server: ^Server,
	descs := false,
	page := 1,
	per_page := 25,
) -> (
	output: string,
	ok: bool,
) {
	per_page := math.clamp(per_page, 1, 50)
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)

	api_count := len(server.apis)
	api_max_idx := api_count - 1
	first := (page - 1) * per_page
	if first > api_max_idx {
		output = fmt.aprintfln("no results for page %d", page)
		ok = false
		return
	}

	last := math.min(first + per_page - 1, api_max_idx)

	fmt.sbprintfln(
		&ob,
		"# Available Lua API Calls: (page %d: functions %d-%d of %d)",
		page,
		first + 1,
		last + 1,
		api_count,
	)
	for idx in first ..= last {
		api := server.apis[idx]
		if descs {
			fmt.sbprintfln(&ob, " * `%s`: %s", api.name, api.description)
		} else {
			fmt.sbprintfln(&ob, " * `%s`", api.name)
		}
	}

	if last < api_max_idx {
		fmt.sbprintfln(&ob, "# More pages available, request again with page=%d", page + 1)
	} else {
		fmt.sbprintfln(&ob, "# No more pages available")
	}

	output = strings.clone(strings.to_string(ob))
	ok = true
	return
}

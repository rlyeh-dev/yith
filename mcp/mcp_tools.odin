package miskatonic_mcp

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

evaluate_tool :: proc(server: ^Server, code: string) -> (output: string, ok: bool = true) {
	return lua_evaluate(server.apis[:], server.setups[:], code)
}

HELP_TEXT :: #load("etc/help.md")

help_tool :: proc(server: ^Server) -> (output: string, ok: bool = true) {
	output = strings.clone(transmute(string)HELP_TEXT)
	return
}

SEARCH_TOOL_DEFAULT_COUNT :: 3
SEARCH_TOOL_DEFAULT_DESCS :: false

search_tool :: proc(
	server: ^Server,
	query: string,
	count: int = SEARCH_TOOL_DEFAULT_COUNT,
	descs: bool = SEARCH_TOOL_DEFAULT_DESCS,
) -> (
	output: string,
	ok: bool = true,
) {
	count := count == 0 ? SEARCH_TOOL_DEFAULT_COUNT : math.clamp(count, 1, 10)
	results := api_search(server, query, count)
	defer destroy_api_search_results(&results)
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)

	fmt.sbprintfln(&ob, "Found %d results: ", len(results))
	for result in results {
		if descs {
			desc := server.apis[result.index].description
			fmt.sbprintfln(&ob, " * `%s` relevance %.3f: %s ", result.name, result.score, desc)
		} else {
			fmt.sbprintfln(&ob, " * `%s` relevance %.3f", result.name, result.score)
		}
	}
	output = strings.clone(strings.to_string(ob))
	return
}

docs_tool :: proc(server: ^Server, func_name: string) -> (output: string, ok: bool = true) {
	ob := strings.builder_make()
	defer strings.builder_destroy(&ob)
	if api_idx, found := server.api_names[func_name]; found {
		api := server.apis[api_idx]
		fmt.sbprintfln(&ob, "API docs for `%s`:\nDescription: %s\n", func_name, api.description)
		fmt.sbprintfln(&ob, "```lua\n%s\n```\n", api.docs)
		output = strings.clone(strings.to_string(ob))
		return
	}
	fmt.sbprintfln(&ob, "No Lua API named `%s` could be found")
	output = strings.clone(strings.to_string(ob))
	ok = false
	return
}

LIST_TOOL_DEFAULT_PAGE :: 1
LIST_TOOL_DEFAULT_PER_PAGE :: 25
LIST_TOOL_DEFAULT_DESCS :: false

list_tool :: proc(
	server: ^Server,
	descs: bool = LIST_TOOL_DEFAULT_DESCS,
	page: int = LIST_TOOL_DEFAULT_PAGE,
	per_page: int = LIST_TOOL_DEFAULT_PER_PAGE,
) -> (
	output: string,
	ok: bool = true,
) {
	per_page := per_page == 0 ? LIST_TOOL_DEFAULT_PER_PAGE : math.clamp(per_page, 1, 50)
	page := page == 0 ? LIST_TOOL_DEFAULT_PAGE : math.clamp(page, 1, 1000)
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
	lst_hdr :: "# Available Lua API Calls: (page %d: functions %d-%d of %d)"
	fmt.sbprintfln(&ob, lst_hdr, page, first + 1, last + 1, api_count)

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
	return
}

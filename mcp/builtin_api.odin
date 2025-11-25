package yith

import "core:fmt"
import "core:math"

add_builtin_apis :: proc(server: ^Server) {
	HELP, HELP_SIG, HELP_DESC :: "api_help", `api_help() -- no args`, "print help documentation for this mcp"
	DOCS, DOCS_SIG, DOCS_DESC :: "api_docs", `api_docs({name="func_name"})`, "print api documentation for any lua call"
	SRCH, SRCH_SIG, SRCH_DESC :: "api_search", `api_search({query="q", count=4})`, "search apis and docs (tf-idf based)"
	LIST, LIST_SIG, LIST_DESC :: "api_list", `api_list({page=1, per_page=25})`, "list all available APIs with pagination"

	add_documentation(server, HELP, HELP_SIG, HELP_DESC, #load("etc/builtin_api_help.lua"))
	add_documentation(server, DOCS, DOCS_SIG, DOCS_DESC, #load("etc/builtin_api_docs.lua"))
	add_documentation(server, SRCH, SRCH_SIG, SRCH_DESC, #load("etc/builtin_api_search.lua"))
	add_documentation(server, LIST, LIST_SIG, LIST_DESC, #load("etc/builtin_api_list.lua"))

	setup(server, proc(sandbox: Sandbox_Init) {
		add_function(sandbox, HELP, builtin_api_help)
		add_function(sandbox, DOCS, builtin_api_docs)
		add_function(sandbox, SRCH, builtin_api_search)
		add_function(sandbox, LIST, builtin_api_list)
	})
}


@(private = "package")
Empty :: struct {}

@(private = "package")
Api_Doc_Params :: struct {
	name: string,
}

@(private = "package")
builtin_api_docs :: proc(params: Api_Doc_Params, sandbox: Sandbox) -> (res: Empty) {
	output, ok := docs_tool(server_from_sandbox(sandbox), params.name)
	if ok do sandbox_print(sandbox, output)
	else do sandbox_error(sandbox, "Couldn't print output")
	return
}

@(private = "package")
builtin_api_help :: proc(params: Empty, sandbox: Sandbox) -> (res: Empty) {
	output, ok := help_tool(server_from_sandbox(sandbox))

	if ok do sandbox_print(sandbox, output)
	else do sandbox_error(sandbox, "Couldn't print output")

	return
}


@(private = "package")
Api_List_Params :: struct {
	page:     int,
	per_page: int,
}

Api_List_Result :: struct {
	name:        string,
	signature:   string,
	description: string,
	docs:        string,
}
Api_List_Results :: struct {
	apis:      []Api_List_Result,
	more:      bool,
	next_page: int,
}

@(private = "package")
builtin_api_list :: proc(params: Api_List_Params, sandbox: Sandbox) -> (res: Api_List_Results) {
	if params.page <= 0 {
		sandbox_error(sandbox, "page must be >= 0")
		return
	}
	res.more = false
	server := server_from_sandbox(sandbox)
	page := params.page
	per_page := params.per_page == 0 ? LIST_TOOL_DEFAULT_PER_PAGE : math.clamp(params.per_page, 1, 50)

	api_count := len(server.api_docs)
	api_max_idx := api_count - 1
	first := (page - 1) * per_page
	if first > api_max_idx {
		err := fmt.aprintfln("no results for page %d", page)
		return
	}

	last := math.min(first + per_page - 1, api_max_idx)
	apis := make([dynamic]Api_List_Result)
	for idx in first ..= last {
		api := server.api_docs[idx]
		append(
			&apis,
			Api_List_Result{name = api.name, signature = api.signature, description = api.description, docs = api.docs},
		)
	}
	res.apis = apis[:]
	if last < api_max_idx {
		res.next_page = page + 1
		res.more = true
	}
	fmt.eprintfln("results apis:%d more:%w next:%d", len(res.apis), res.more, res.next_page)
	return
}

@(private = "package")
Api_Search_Params :: struct {
	query: string,
	count: int,
}

Api_Search_Result :: struct {
	name:        string,
	description: string,
	docs:        string,
	score:       f32,
}

@(private = "package")
builtin_api_search :: proc(params: Api_Search_Params, sandbox: Sandbox) -> (res: []Api_Search_Result) {
	server := server_from_sandbox(sandbox)
	if params.query == "" {
		sandbox->error("error: empty query. did you mean api_list()?")
		return
	}
	query := params.query
	count := params.count == 0 ? SEARCH_TOOL_DEFAULT_COUNT : math.clamp(params.count, 1, 10)
	results := api_search(server, params.query, count)

	defer destroy_api_tfidf_search_results(&results)

	dynres := make([dynamic]Api_Search_Result)
	for result, idx in results {
		desc := server.api_docs[result.index].description
		docs := server.api_docs[result.index].docs
		append(&dynres, Api_Search_Result{name = result.name, description = desc, docs = docs, score = result.score})
	}
	res = dynres[:]
	return
}

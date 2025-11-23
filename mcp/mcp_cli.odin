package yith

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

// Cli access to evaluate tool. Mostly for human debugging
// without needing to plug an LLM into the pipeline
cli_eval :: proc(server: ^Server, args: []string) -> bool {
	complete_setup(server)
	non_flags := slice.filter(args, proc(s: string) -> bool {
		return s == "-" || !strings.starts_with(s, "-")
	})
	first := non_flags[0]

	if first == "-" {
		fmt.printf("stdin support not implemented yet")
		return true
	} else {
		output, ok := evaluate_tool(server, first)
		defer delete(output)
		fmt.print(output)
		if !ok {
			fmt.eprintfln("\nsandbox exited with fatal error")
		}
		return ok
	}

	return true
}

// Cli access to api_docs tool. Mostly for human debugging
// without needing to plug an LLM into the pipeline
cli_docs :: proc(server: ^Server, args: []string) -> bool {
	complete_setup(server)
	first := args[0]
	output, ok := docs_tool(server, first)
	defer delete(output)
	fmt.print(output)
	if !ok { fmt.eprintln("\ndocs fetch failed") }
	return ok
}

// Cli access to api_help tool. Mostly for human debugging
// without needing to plug an LLM into the pipeline
cli_help :: proc(server: ^Server) -> bool {
	complete_setup(server)
	output, ok := help_tool(server)
	defer delete(output)
	fmt.print(output)
	if !ok { fmt.eprintln("\nhelp failed") }
	return ok
}

// Cli access to api_list tool. Mostly for human debugging
// without needing to plug an LLM into the pipeline
cli_list :: proc(server: ^Server) -> bool {
	complete_setup(server)
	lst := slice.clone(server.api_docs[:])
	defer delete(lst)
	slice.sort_by(lst, proc(i, j: Api_Docs) -> bool { return i.name < j.name })
	longest_name: int = 0
	for api in lst {
		longest_name = math.max(len(api.name), longest_name)
	}
	lenstr := fmt.aprintf("%d", longest_name)
	defer delete(lenstr)
	fmtstr := strings.concatenate({"%-", lenstr, "s | %s"})
	defer delete(fmtstr)
	fmt.printfln("Available APIs: ")
	for api in lst {
		fmt.printfln(fmtstr, api.name, api.description)
	}
	return true
}

// Cli access to api_search tool. Mostly for human debugging
// without needing to plug an LLM into the pipeline
cli_search :: proc(server: ^Server, args: []string) -> bool {
	complete_setup(server)
	query := strings.join(args, " ")
	defer delete(query)
	if len(query) == 0 {
		fmt.printfln("this command requires a search query")
		return false
	}
	results := api_search(server, query, 20)
	defer destroy_api_tfidf_search_results(&results)
	longest_name: int = 0
	ct := 0
	for r in results {
		if r.score < 0.001 { break }
		ct += 1
		api := server.api_docs[r.index]
		longest_name = math.max(len(api.name), longest_name)
	}
	if ct == 0 {
		fmt.printfln("No results found for query: `%s`", query)
		return false
	}

	lenstr := fmt.aprintf("%d", longest_name)
	defer delete(lenstr)
	fmtstr := strings.concatenate({"%-", lenstr, "s | %.3f | %s"})
	defer delete(fmtstr)
	fmthdr := strings.concatenate({"%-", lenstr, "s | %5s | %s"})
	defer delete(fmthdr)
	fmt.printfln(fmthdr, "name", "score", "description")
	for r in results {
		if r.score < 0.001 { break }
		api := server.api_docs[r.index]
		fmt.printfln(fmtstr, api.name, r.score, api.description)
	}
	return true
}

cli_tool_access :: proc(server: ^Server, prefix: string, args: []string) -> (ok: bool) {
	usage :: proc(prefix: string) {
		fmt.eprintfln("Usage: %s [command]", prefix)
		fmt.eprintln("\nCommands:")
		fmt.eprintln("\teval       | run code within the lua sandbox")
		fmt.eprintln("\tapi-docs   | print docs for any function available in the lua sandbox")
		fmt.eprintln("\tapi-help   | print the help text for llms")
		fmt.eprintln("\tapi-list   | print all available lua functions")
		fmt.eprintln("\tapi-search | search for lua functions by their documentation contents")
	}
	if len(args) == 0 {
		usage(prefix)
		return false
	}
	first, rest := slice.split_first(args)

	switch first {
	case "eval": ok = cli_eval(server, rest)
	case "api-docs": ok = cli_docs(server, rest)
	case "api-help": ok = cli_help(server)
	case "api-list": ok = cli_list(server)
	case "api-search": ok = cli_search(server, rest)
	case:
		usage(prefix)
		ok = false
	}
	return
}

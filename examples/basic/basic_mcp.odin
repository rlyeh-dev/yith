package basic_mcp

import mcp "../../mcp"
import "core:fmt"
import "core:mem"
import "core:slice"

check_eval :: proc(server: ^mcp.Server, title, code: string) {
	fmt.eprintln("----------------------------")
	fmt.eprintfln("EVAL TEST: %s", title)
	fmt.eprintln("code to evaluate: ")
	fmt.eprint(code)
	fmt.eprintln()
	out, ok := mcp.tool_evaluate(server, code)
	fmt.eprintfln("STATUS OF %s: %s", title, ok ? "success" : "failure")
	fmt.eprintln("result output:")
	fmt.eprint(out)
	fmt.eprintln()
}

print_extra_debug_info :: proc(server: ^mcp.Server) {
	check_eval(server, "basic (should succeed)", #load("eval_tests/basic.lua"))
	check_eval(server, "cherry (should fail)", #load("eval_tests/cherry.lua"))
	check_eval(server, "badarg (should fail)", #load("eval_tests/badarg.lua"))
	check_eval(server, "toomany (should fail)", #load("eval_tests/toomany.lua"))

	fmt.eprintln("---------------------------- TF-IDF DEBUG:\n\n")
	for doc, idx in &server.api_index.docs {
		fmt.eprintln("----------------------------")
		fmt.eprintfln("-> api function: %s", server.apis[idx].name)
		fmt.eprintfln("-> api desc: %s", server.apis[idx].description)
		fmt.eprintfln("-> api docs:\n%s", server.apis[idx].docs)
		fmt.eprintfln("-> scanned api: %w\n\n", doc)
	}
	for word, idx in &server.api_index.vocab.words {
		fmt.eprintf("%s (%d): ", word, idx)
		found := 0
		for doc, i in &server.api_index.docs {
			val := doc.vec[idx]
			if val == 0 {continue}
			if found > 0 {fmt.eprintf(", ")}
			found += 1
			fmt.eprintf("%s->%.3f", doc.name, doc.vec[idx])
		}
		fmt.eprintf("\n")
	}
	fmt.eprintln()

	srch_qry := "weather fahrenheit hello report kelvin cherry orphan mercury mars balloon"
	srch_res := mcp.api_search(server, srch_qry, 8)
	defer mcp.destroy_api_search_results(&srch_res)

	fmt.eprintfln("api search query: %w", srch_qry)
	for sres, i in srch_res {
		fmt.eprintfln("search result #%d: %w", i + 1, sres)
	}

}

when ODIN_DEBUG {
	tracking_alloc_report_and_cleanup :: proc(track: ^mem.Tracking_Allocator) {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			total: int
			for _, entry in track.allocation_map {
				total += entry.size
				when #config(tracking_details, true) {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			fmt.eprintf("-> %v bytes total\n", total)
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				when #config(tracking_details, true) {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
		}
		mem.tracking_allocator_destroy(track)
	}
}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
		context.allocator = mem.tracking_allocator(&track)
		defer tracking_alloc_report_and_cleanup(&track)
	}

	server := mcp.make_server("Basic MCP", "im a basic example", "2.1.4")

	setup_food_service(&server)
	setup_interplanetary_weather(&server)
	setup_manual_apis(&server)

	mcp.build_api_index(&server)

	when ODIN_DEBUG {
		print_extra_debug_info(&server)
	}

	mcp.destroy_server(&server)
}

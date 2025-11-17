package basic_mcp

import mcp "../../mcp"
import "core:fmt"
import "core:slice"

check_eval :: proc(server: ^mcp.Mcp_Server, title, code: string) {
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

print_extra_debug_info :: proc(server: ^mcp.Mcp_Server) {
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
}

main :: proc() {
	server := mcp.make_mcp_server("Basic MCP", "im a basic example", "2.1.4")

	setup_food_service(&server)
	setup_interplanetary_weather(&server)
	setup_manual_apis(&server)

	when ODIN_DEBUG {
		print_extra_debug_info(&server)
	}

}

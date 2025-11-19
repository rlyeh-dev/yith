package basic_mcp

import mcp "../../mcp"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:terminal/ansi"

get_columns :: proc() -> int {
	cols: int = 80
	c, ok := os.lookup_env("COLUMNS")
	defer delete(c)
	if !ok {return cols}
	n, nok := strconv.parse_int(c)
	return nok ? cols : n
}

debug_hdr :: proc(text: string) {
	START :: ansi.CSI + ansi.BOLD + ";" + ansi.FG_CYAN + ansi.SGR
	END :: ansi.CSI + ansi.RESET + ansi.SGR
	longline := strings.repeat("#", get_columns())
	defer delete(longline)
	fmt_str := START + "\n%s\n##### %s\n\n" + END
	fmt.eprintf(fmt_str, longline, text)
}

debug_subhdr :: proc(text: string) {
	START :: ansi.CSI + ansi.BOLD + ";" + ansi.FG_CYAN + ansi.SGR
	END :: ansi.CSI + ansi.RESET + ansi.SGR
	fmt.eprintfln(START + "-> %s" + END, text)
}

debug_subhdrf :: proc(fmt_str: string, args: ..any) {
	debug_subhdr(fmt.tprintf(fmt_str, ..args))
}

debug_dim :: proc(text: string) {
	START :: ansi.CSI + ansi.FAINT + ansi.SGR
	END :: ansi.CSI + ansi.RESET + ansi.SGR
	fmt.eprintfln(START + "%s" + END, text)
}

debug_dimf :: proc(fmt_str: string, args: ..any) {
	debug_dim(fmt.tprintf(fmt_str, ..args))
}

debug_sucfail :: proc(ok: bool, text: string) {
	start := strings.concatenate(
		{ansi.CSI + ansi.BOLD + ";", ok ? ansi.FG_GREEN : ansi.FG_RED, ansi.SGR},
	)
	defer delete(start)
	END :: ansi.CSI + ansi.RESET + ansi.SGR
	fmt.eprintfln("%s-> %s" + END, start, text)
}

debug_sucfailf :: proc(ok: bool, fmt_str: string, args: ..any) {
	debug_sucfail(ok, fmt.tprintf(fmt_str, ..args))
}

check_eval :: proc(server: ^mcp.Server, title, code: string) {
	debug_subhdrf("code for %s", title)
	debug_dim(code)
	out, ok := mcp.evaluate_tool(server, code)
	defer delete(out)
	debug_sucfailf(ok, "results of %s:", title)
	fmt.eprintln(out)
}

print_extra_debug_info :: proc(server: ^mcp.Server) {
	when INSPECT_EVAL {
		debug_hdr("EVAL")
		check_eval(server, "basic (should succeed)", #load("eval_tests/basic.lua"))
		check_eval(server, "cherry (should fail)", #load("eval_tests/cherry.lua"))
		check_eval(server, "badarg (should fail)", #load("eval_tests/badarg.lua"))
		check_eval(server, "toomany (should fail)", #load("eval_tests/toomany.lua"))
	}


	when INSPECT_TFIDF {
		debug_hdr("TF-IDF")
		for doc, idx in &server.api_index.docs {
			debug_subhdrf("doc #%d", idx + 1)
			debug_subhdrf("api function: %s", server.api_docs[idx].name)
			debug_subhdrf("api desc: %s", server.api_docs[idx].description)
			debug_subhdr("api docs:")
			debug_dim(server.api_docs[idx].docs)
			debug_subhdr("scanned api:")
			debug_dimf("%w\n", doc)
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
	}

	when INSPECT_SEARCH {
		debug_hdr("TOOL: SEARCH")
		srch_qry :: "weather fahrenheit hello report kelvin cherry orphan mercury mars balloon"
		srch_res, srch_ok := mcp.search_tool(server, srch_qry, 2, descs = false)
		defer delete(srch_res)
		debug_sucfailf(srch_ok, "Search tool: %s (no descriptions)", srch_qry)
		fmt.eprintln(srch_res)

		srch_qry_2 :: "weather mercury kelvin celsius fahrenheit conditions"
		srch_res_2, srch_ok_2 := mcp.search_tool(server, srch_qry_2, count = 3, descs = true)
		defer delete(srch_res_2)
		debug_sucfailf(srch_ok_2, "Search tool: %s (with descriptions)", srch_qry_2)
		fmt.eprintln(srch_res_2)
	}

	when INSPECT_LIST {
		debug_hdr("TOOL: LIST")
		p := 0
		for {
			p += 1
			list_res, list_ok := mcp.list_tool(server, descs = p == 1, page = p, per_page = 3)
			defer delete(list_res)
			debug_sucfailf(list_ok, "page %d", p)
			fmt.eprintln(list_res)
			if !list_ok {break}
		}
	}

	when INSPECT_DOCS {
		debug_hdr("TOOL: DOCS")
		names := [?]string{"interplanetary_weather", "simple_food_service", "nonexistent"}
		for name in names {
			docs_res, docs_ok := mcp.docs_tool(server, name)
			defer delete(docs_res)
			debug_sucfailf(docs_ok, "Docs: %s", name)
			debug_dim(docs_res)
			fmt.eprintln()
		}
	}

	when INSPECT_HELP {
		debug_hdr("TOOL: HELP")
		help, help_ok := mcp.help_tool(server)
		defer delete(help)
		debug_sucfail(help_ok, "results")
		debug_dim(help)
		fmt.eprintln()
	}


	when #config(proto_debug, true) {
		debug_hdr("PROTOCOL")
		messages := [?]string {
			`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"roots":{"listChanged":true},"sampling":{},"elicitation":{}},"clientInfo":{"name":"ExampleClient","title":"Example Client Display Name","version":"1.0.0"}}}`,
			`{"jsonrpc":"2.0","method":"notifications/initialized"}`,
			`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"cursor":"optional-cursor-value"}}`,
			`{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"query":"weather pluto kelvin"}}}`,
			`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list"}}`,
			`{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"evaluate", "arguments":{"code":"print(\"lol\")"}}}`,
			`{"jsonrpc":"2.0","id":5,"method":"dance","params":{}}`,
			`{"jsonrpc":"2.0","id":6,"method":"initialize","params":{"protocolVersion":1}}`,
		}
		for m in messages {
			bytes, send, ok := mcp.handle_mcp_message(server, transmute([]u8)m)
			defer delete(bytes)
			debug_subhdrf("SENT: %s", m)
			debug_sucfailf(ok, "RECEIVED (send:%w)", send)
			debug_dim(transmute(string)bytes)
			fmt.eprintln()
		}
	}
}

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

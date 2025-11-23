package basic_mcp

import mcp "../../mcp"
import back "../../vendor/back"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	when ODIN_DEBUG {
		when USE_BACK {
			track: back.Tracking_Allocator
			back.tracking_allocator_init(&track, context.allocator)
			defer back.tracking_allocator_destroy(&track)

			context.allocator = back.tracking_allocator(&track)
			defer back.tracking_allocator_print_results(&track)

			context.assertion_failure_proc = back.assertion_failure_proc
			back.register_segfault_handler()
		} else {
			track: mem.Tracking_Allocator
			mem.tracking_allocator_init(&track, context.allocator)
			track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
			context.allocator = mem.tracking_allocator(&track)
			defer tracking_alloc_report_and_cleanup(&track)
		}
	}

	server := mcp.make_server("Basic MCP", "im a basic example", "2.1.4")

	setup_food_service(&server)
	setup_interplanetary_weather(&server)
	setup_manual_apis(&server)

	mcp.add_help(&server, #load("help_text.md"))

	when INSPECT_ANY {
		// complete_setup is normally run by server start, but need it for our inspects
		mcp.complete_setup(&server)
		print_extra_debug_info(&server)
	}

	if len(os.args) > 1 {
		post_cmd_args := len(os.args) > 2 ? os.args[2:] : {}
		ok: bool = true
		switch os.args[1] {
		case "stdio": mcp.start_stdio(&server)
		case "eval": ok = mcp.cli_eval(&server, post_cmd_args)
		case "api-docs": ok = mcp.cli_docs(&server, post_cmd_args)
		case "api-help": ok = mcp.cli_help(&server)
		case "api-list": ok = mcp.cli_list(&server)
		case "api-search": ok = mcp.cli_search(&server, post_cmd_args)
		case "cli":
			basename := filepath.base(os.args[0])
			prefix := strings.join({basename, "cli"}, " ")
			defer delete(prefix)
			ok = mcp.cli_aggregated(&server, prefix, post_cmd_args)
		case: cli_help()
		}
		if !ok { os.exit(1) }
	} else {
		cli_help()
	}

	cli_help :: proc() {
		basename := filepath.base(os.args[0])
		fmt.eprintfln("Usage: %s [command]", basename)
		fmt.eprintln("\nCommands:")
		fmt.eprintln("\tstdio      | start mcp stdio server")
		fmt.eprintln("\tcli        | cli sub-command. it contains all of the commands shown below this one")
		fmt.eprintln("\teval       | run code within the lua sandbox")
		fmt.eprintln("\tapi-docs   | print docs for any function available in the lua sandbox")
		fmt.eprintln("\tapi-help   | print the help text for llms")
		fmt.eprintln("\tapi-list   | print all available lua functions")
		fmt.eprintln("\tapi-search | search for lua functions by their documentation contents")
	}

	mcp.destroy_server(&server)
}

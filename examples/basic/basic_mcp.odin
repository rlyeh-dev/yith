package basic_mcp

import mcp "../../mcp"
import back "../../vendor/back"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"

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

	if len(os.args) > 1 && os.args[1] == "stdio" {
		mcp.start_stdio(&server)
	} else {
		basename := filepath.base(os.args[0])
		fmt.eprintfln("run `%s stdio` to start the stdio server", basename)
	}

	mcp.destroy_server(&server)
}

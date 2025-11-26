package basic_mcp

import mcp "../../mcp"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import lua "vendor:lua/5.4"

setup_manual_apis :: proc(server: ^mcp.Server) {
	// the same api function, 3 different ways:
	// 1. (`t_*`) automatic lua wrapper, which uses arena allocator and automatic input/output (un)marshaling
	// 2. (`m_*`) manual lua wrapper, but using the arena allocator and automatic input/output (un)marshaling
	// 3. (`r_*`) manual lua wrapper, manual memory management, manually convert between input/output <-> lua stack
	//
	// the handler from #1 (`hello_goodbye`) is used by the other two
	// #2 does the exact same thing that the add_function does
	//
	// note that because we're doing raw lua stuff, we have to import vendor:lua/5.4 directly, matching what
	// yith uses internally. the other handlers in this basic example don't touch the lua instance
	// directly

	t_name :: "hello_goodbye_auto"
	t_sig :: `hello_goodybye_auto({hello="hey", goodbye="cya"})`
	t_desc :: "Hello/Goodbye with typed lua registry helper"
	t_docs := build_hg_docs(t_name)
	defer delete(t_docs)

	m_name :: "hello_goodbye_marshaled"
	m_sig :: `hello_goodbye_marshaled({hello="hey", goodbye="cya"})`
	m_desc :: "Hello/Goodbye with marshaling helpers"
	m_docs := build_hg_docs(m_name)
	defer delete(m_docs)

	r_name :: "hello_goodbye_raw_lua"
	r_sig :: `hello_goodbye_raw_lua({hello="hey", goodbye="cya"})`
	r_desc :: "Hello/Goodbye with manual lua stack tomfoolery"
	r_docs := build_hg_docs(r_name)
	defer delete(r_docs)

	mcp.add_documentation(server, t_name, t_sig, t_desc, t_docs)
	mcp.add_documentation(server, m_name, m_sig, m_desc, m_docs)
	mcp.add_documentation(server, r_name, r_sig, r_desc, r_docs)

	mcp.setup(server, proc(state: ^lua.State) {
		mcp.add_function(state, t_name, hello_goodbye)
		lua.register(state, m_name, hello_goodbye_marshaled)
		lua.register(state, r_name, hello_goodbye_raw_lua)
	})
}

Hi_Bye_In :: struct {
	hello:   string,
	goodbye: string,
}

Hi_Bye_Out :: struct {
	hi:  string,
	bye: string,
}

hello_goodbye :: proc(input: Hi_Bye_In, state: ^lua.State) -> (output: Hi_Bye_Out) {
	if input.hello == "NO" || input.goodbye == "NO" {
		NO_NO :: "THIS IS AN ERROR STATE, NO IS NEITHER A VALID GREETING NOR A VALID .. um.. ANTI-GREETING"
		mcp.error(state, NO_NO)
		return
	}
	output.hi = strings.concatenate({input.hello, " lol"})
	output.bye = strings.concatenate({"lmao ", input.goodbye})
	return
}

hello_goodbye_marshaled :: proc "c" (state: ^lua.State) -> i32 {
	context = runtime.default_context()
	context.allocator = mcp.arena_allocator(state)

	params: Hi_Bye_In
	um_err := mcp.unmarshal_lua_value(state, -1, &params)
	if um_err != .None {
		lua.pushstring(state, "could not unmarshal input")
		lua.error(state)
	}

	result: Hi_Bye_Out
	if params.hello == "NO" || params.goodbye == "NO" {
		NO_NO :: "THIS IS AN ERROR STATE, NO IS NEITHER A VALID GREETING NOR A VALID .. um.. ANTI-GREETING"
		mcp.error(state, NO_NO)
		return 0
	}
	result.hi = strings.concatenate({params.hello, " lol"})
	result.bye = strings.concatenate({"lmao ", params.goodbye})

	// mcp.error() sets this, this var is what triggers the `isError` flag in the mcp response to the LLM
	lua.getglobal(state, "MCP_IS_ERROR")
	is_err := lua.toboolean(state, -1)
	if is_err {
		return 0
	}

	m_err := mcp.marshal_lua_value(state, result)
	if m_err != nil {
		when ODIN_DEBUG {
			fmt.eprintfln("could not marshal output: %w", result)
		}
		lua.pushstring(state, "error marshaling hello_goodbye output")
		lua.error(state)
	}

	return 1
}

hello_goodbye_raw_lua :: proc "c" (state: ^lua.State) -> i32 {
	// dont use our arena allocator! make sure to clean up after yourself!
	// in fact we'll use a tracking allocator here in this example just
	// for "fun" and definitely not because i had to fix a bug here 👀

	context = runtime.default_context()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	params: Hi_Bye_In
	lua.L_checktype(state, 1, i32(lua.TTABLE))

	lua.getfield(state, -1, "hello")
	hello := strings.clone_from_cstring(lua.tostring(state, -1))
	defer delete(hello)
	params.hello = hello
	lua.pop(state, 1)

	lua.getfield(state, -1, "goodbye")
	goodbye := strings.clone_from_cstring(lua.tostring(state, -1))
	defer delete(goodbye)
	params.goodbye = goodbye
	lua.pop(state, 1)

	result: Hi_Bye_Out
	is_error: bool
	if params.hello == "NO" || params.goodbye == "NO" {
		NO_NO: cstring : "THIS IS AN ERROR STATE, NO IS NEITHER A VALID GREETING NOR A VALID .. um.. ANTI-GREETING"
		// without using mcp.error, but doing what it does internally:
		//
		// first, add the string to the MCP_ERROR_OUTPUT global
		// (MCP_PRINT_HARNESS_OUTPUT) is what the print() and printf() print to
		lua.getglobal(state, "MCP_ERROR_OUTPUT")
		lua.pushstring(state, NO_NO)
		nextidx := lua.rawlen(state, -2) + 1
		lua.seti(state, -2, lua.Integer(nextidx))

		// now flag this as an error
		lua.pushboolean(state, b32(true))
		lua.setglobal(state, "MCP_IS_ERROR")

		// you could also just do:
		// lua.pushstring(state, NO_NO)
		// lua.error(state)
		// though the output would be slightly different
		return 0
	}
	result.hi = strings.concatenate({params.hello, " lol"})
	result.bye = strings.concatenate({"lmao ", params.goodbye})
	defer delete(result.hi)
	defer delete(result.bye)

	lua.createtable(state, 0, 2)

	lua.pushstring(state, cstring(raw_data(result.hi)))
	lua.setfield(state, -2, "hi")

	lua.pushstring(state, cstring(raw_data(result.bye)))
	lua.setfield(state, -2, "bye")

	return 1
}


build_hg_docs :: proc(name: string) -> string {
	// ignore the `allocated`. it will always allocate in this case, because we know our
	// constant string "HELLO_GOODBYE" appears in the also constant HELLO_GOODBYE_DOCS
	val, _ := strings.replace_all(HELLO_GOODBYE_DOCS, "HELLO_GOODBYE", name)
	return val
}

HELLO_GOODBYE_DOCS :: `
---@class Input
---@field hello string
---@field goodbye string

---@class Output
---@field hi string
---@field bye string

---helps you say hello and goodbye to me and me say hi and bye to you
---@param params Input
---@return Output
function HELLO_GOODBYE(params) end

-- example:
local res = HELLO_GOODBYE({ hello = "hello my good friend", goodbye = "farewell babe" })
print("hi:", res.hi)
print("bye:", res.bye)
`

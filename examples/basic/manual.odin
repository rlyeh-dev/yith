package basic_mcp

import mcp "../../mcp"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import lua "vendor:lua/5.4"

MyInput :: struct {
	hello:   string,
	goodbye: string,
}

MyOutput :: struct {
	hi:  string,
	bye: string,
}


setup_manual_apis :: proc(server: ^mcp.Server) {
	MANUAL_DOCS_MARSHALED :: `
---@class Input
---@field hello string
---@field goodbye string

---@class Output
---@field hi string
---@field bye string

---helps you say hello and goodbye to me and me say hi and bye to you
---@param params Input
---@return Output
function %s(params) end

-- example:
local res = hello_goodbye_marshaled({ hello = "hello my good friend", goodbye = "farewell babe" })
print("hi:", res.hi)
print("bye:", res.bye)
`


	MANUAL_DOCS_RAW_LUA :: `
---@class Input
---@field hello string
---@field goodbye string

---@class Output
---@field hi string
---@field bye string

---helps you say hello and goodbye to me and me say hi and bye to you
---@param params Input
---@return Output
function %s(params) end

-- example:
local res = hello_goodbye_raw_lua({ hello = "hey good luck with that lua stack", goodbye = "so long hope you didnt mess up your memory" })
print("hi:", res.hi)
print("bye:", res.bye)
`


	TOOL_MARSHALED :: "hello_goodbye_marshaled"

	mcp.register_api(
		server,
		TOOL_MARSHALED,
		"Hello/Goodbye with marshaling helpers",
		MANUAL_DOCS_MARSHALED,
		proc(state: ^lua.State) {
			lua.register(state, TOOL_MARSHALED, hello_goodbye_with_marshaling)
		},
	)

	TOOL_RAW_LUA :: "hello_goodbye_raw_lua"

	mcp.register_api(
		server,
		TOOL_RAW_LUA,
		"Hello/Goodbye with manual lua stack tomfoolery",
		MANUAL_DOCS_RAW_LUA,
		proc(state: ^lua.State) {
			lua.register(state, TOOL_RAW_LUA, hello_goodbye_totally_manual)
		},
	)
}

my_call :: proc(input: MyInput) -> (output: MyOutput, error: string) {
	if input.hello == "NO" || input.goodbye == "NO" {
		error = "THIS IS AN ERROR STATE, NO IS NEITHER A VALID GREETING NOR A VALID .. um.. ANTI-GREETING"
		return
	}
	output.hi = strings.concatenate({input.hello, " lol"})
	output.bye = strings.concatenate({"lmao ", input.goodbye})
	return
}

hello_goodbye_with_marshaling :: proc "c" (state: ^lua.State) -> i32 {
	// get our arena allocator out of lua
	context = mcp.context_with_arena_from_lua(state)
	// can also do this:
	// context = runtime.default_context()
	// context.allocator = mcp.arena_from_lua(state)

	ok: bool
	my_in: MyInput

	my_in, ok = mcp.unmarshal_lua_table(state, -1, MyInput)
	if !ok {
		lua.pushstring(state, "could not unmarshal input")
		lua.error(state)
	}

	my_out, err := my_call(my_in)

	if err != "" {
		lua.pushstring(state, strings.clone_to_cstring(err))
		lua.error(state)
	}

	ok = mcp.marshal_lua_table(state, MyOutput, &my_out)
	if !ok {
		when ODIN_DEBUG {
			fmt.eprintfln("could not marshal output: %w", my_out)
		}
		lua.pushstring(state, "error marshaling my_call output")
		lua.error(state)
	}

	return 1
}

hello_goodbye_totally_manual :: proc "c" (state: ^lua.State) -> i32 {
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

	my_in: MyInput
	lua.L_checktype(state, 1, i32(lua.TTABLE))

	lua.getfield(state, -1, "hello")
	my_in.hello = strings.clone_from_cstring(lua.tostring(state, -1))
	lua.pop(state, 1)

	lua.getfield(state, -1, "goodbye")
	my_in.goodbye = strings.clone_from_cstring(lua.tostring(state, -1))
	lua.pop(state, 1)

	my_out, err := my_call(my_in)
	delete(my_in.hello)
	delete(my_in.goodbye)

	if err != "" {
		lua.pushstring(state, cstring(raw_data(err)))
		if my_out.hi != "" do delete(my_out.hi)
		if my_out.bye != "" do delete(my_out.bye)
		lua.error(state) // lua.error longjumps so we cant rely on defer
	}

	lua.createtable(state, 0, 2)

	lua.pushstring(state, cstring(raw_data(my_out.hi)))
	lua.setfield(state, -2, "hi")

	lua.pushstring(state, cstring(raw_data(my_out.bye)))
	lua.setfield(state, -2, "bye")

	delete(my_out.hi)
	delete(my_out.bye)

	return 1
}

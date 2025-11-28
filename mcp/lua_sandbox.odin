package yith

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import lua "vendor:lua/5.4"

// mcp.setup(server, setup_proc) the type of this setup_proc is this
Sandbox_Setup :: #type proc(_: ^lua.State)

@(private)
// The primary lua evaluate. The evaluate tool call and everything else that
// does a sandbox lua eval runs through this eventually. creates a fresh lua
// state and dynamic arena, and blows them both away at the end of execution
lua_evaluate :: proc(server: ^Server, setup_procs: []Sandbox_Setup, lua_code: string) -> (output: string, ok: bool) {
	parent_allocator := context.allocator
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, alignment = 64)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	state := lua.L_newstate()
	defer lua.close(state)

	lua.pushlightuserdata(state, &arena)
	lua.setfield(state, lua.REGISTRYINDEX, "arena")

	lua.pushlightuserdata(state, server)
	lua.setfield(state, lua.REGISTRYINDEX, "server")

	lua.pushboolean(state, b32(false))
	lua.setfield(state, lua.REGISTRYINDEX, "is_error")

	lua.open_base(state)
	lua.L_requiref(state, "string", lua.open_string, 1)
	lua.L_requiref(state, "math", lua.open_math, 1)
	lua.L_requiref(state, "utf8", lua.open_utf8, 1)
	lua.L_requiref(state, "table", lua.open_table, 1)
	lua.settop(state, 0)

	for setup_proc in setup_procs {
		setup_proc(state)
	}

	lua.L_dostring(state, #load("etc/print_harness.lua"))

	code_cstr := strings.clone_to_cstring(lua_code)
	defer delete(code_cstr)
	err_str: string
	is_error := false

	ok = lua.L_dostring(state, code_cstr) == 0
	if !ok {
		err_str = strings.clone_from_cstring(lua.tostring(state, -1))
		lua.pop(state, 1)
		is_error = true
	} else {
		lua.getfield(state, lua.REGISTRYINDEX, "is_error")
		is_error = bool(lua.toboolean(state, -1))
		lua.pop(state, 1)
		err_str = strings.clone("fatal error")
	}

	output_builder := strings.builder_make()

	lua.getglobal(state, "MCP_PRINT_HARNESS_OUTPUT")
	lua.L_checktype(state, -1, i32(lua.TTABLE))

	output_len := lua.rawlen(state, -1)
	defer strings.builder_destroy(&output_builder)

	for idx in 1 ..= output_len {
		lua.geti(state, -1, lua.Integer(idx))
		cstr := lua.tostring(state, -1)
		strings.write_string(&output_builder, strings.clone_from_cstring(cstr))
		strings.write_string(&output_builder, "\n")
		lua.pop(state, 1)
	}

	if err_str != "" {
		fmt.sbprintfln(&output_builder, "Lua fatal error: %s", err_str)
	}

	output = strings.clone(strings.to_string(output_builder), parent_allocator)

	return
}

// a fancier version of `lua.register()`. It will create a lua_wrapper for you,
// set it up with the sandbox's dynamic arena allocator, (un)marshal your input/output
// params to/from lua stack, and call your typed lua handler for you
add_function :: proc(state: ^lua.State, name: string, handler: proc(_: $In, _: ^lua.State) -> $Out) {
	Wrapper :: struct {
		name:    string,
		handler: proc(_: In, state: ^lua.State) -> Out,
	}

	wrapper_ptr := (^Wrapper)(lua.newuserdata(state, size_of(Wrapper)))
	wrapper_ptr^ = Wrapper {
		name    = strings.clone(name),
		handler = handler,
	}

	lua_wrapper :: proc "c" (state: ^lua.State) -> i32 {
		context = runtime.default_context()
		context.allocator = arena_allocator(state)

		wrapper := (^Wrapper)(lua.touserdata(state, lua.REGISTRYINDEX - 1))

		ok: bool
		params: In
		um_err := unmarshal_lua_value(state, -1, &params)
		if um_err != .None {
			fmt.eprintln("unmarshal error", um_err)
			lua_eprintfln(
				state,
				"BAD ARGUMENT ERROR (%s): Your input could not be parsed. please check docs and try again",
				wrapper.name,
			)
			return 0
		}
		result := wrapper.handler(params, state)

		lua.getfield(state, lua.REGISTRYINDEX, "is_error")
		is_error := lua.toboolean(state, -1)
		lua.pop(state, 1)

		if is_error {
			cstr := fmt.caprintfln("%s returned a fatal error", wrapper.name)
			lua.pushstring(state, cstr)
			lua.error(state)
		}

		m_err := marshal_lua_value(state, result)
		if m_err != .None {
			when ODIN_DEBUG {
				fmt.eprintfln("could not marshal output from function %s: %w (%w)", wrapper.name, result, m_err)
			}
			lua_eprintfln(state, "could not marshal return value of function %s to lua stack (%w)", wrapper.name, m_err)
			lua_abort(state)
			return 0
		}

		return 1
	}

	lua.pushcclosure(state, lua_wrapper, 1)
	name_cstr := strings.clone_to_cstring(name)
	defer delete(name_cstr)
	lua.setglobal(state, name_cstr)
}

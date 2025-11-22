package yith

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import lua "vendor:lua/5.4"

Sandbox :: struct {
	lua_state: ^lua.State,
}
Sandbox_Setup :: #type proc(sandbox: Sandbox)

@(private)
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

	lua.open_base(state)
	lua.L_requiref(state, "string", lua.open_string, 1)
	lua.L_requiref(state, "math", lua.open_math, 1)
	lua.L_requiref(state, "utf8", lua.open_utf8, 1)
	lua.L_requiref(state, "table", lua.open_table, 1)
	lua.settop(state, 0)

	for setup_proc in setup_procs {
		setup_proc(Sandbox{state})
	}

	lua.L_dostring(state, #load("etc/print_harness.lua"))

	code_cstr := strings.clone_to_cstring(lua_code)
	defer delete(code_cstr)
	err_str: string

	ok = lua.L_dostring(state, code_cstr) == 0
	if !ok {
		err_str = strings.clone_from_cstring(lua.tostring(state, -1))
		lua.pop(state, 1)
	}

	output_builder := strings.builder_make()

	lua.getglobal(state, "MCP_IS_ERROR")
	is_error := lua.toboolean(state, -1)
	lua.pop(state, 1)

	lua.getglobal(state, "MCP_ERROR_OUTPUT")
	lua.L_checktype(state, -1, i32(lua.TTABLE))

	error_len := lua.rawlen(state, -1)
	if error_len > 0 || is_error {
		strings.write_string(&output_builder, "\nLUA EVAL FATAL ERROR\n\n")
		for idx in 1 ..= error_len {
			lua.geti(state, -1, lua.Integer(idx))
			cstr := lua.tostring(state, -1)
			strings.write_string(&output_builder, strings.clone_from_cstring(cstr))
			strings.write_string(&output_builder, "\n")
			lua.pop(state, 1)
		}
		ok = false
	} else {
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
	}

	output = strings.clone(strings.to_string(output_builder), parent_allocator)

	return
}


@(private = "package")
server_from_sandbox :: proc {
	server_from_sandbox_box,
	server_from_sandbox_lua,
}
@(private = "package")
server_from_sandbox_box :: proc(sandbox: Sandbox) -> (server: ^Server) {
	return server_from_sandbox_lua(sandbox.lua_state)
}
@(private = "package")
server_from_sandbox_lua :: proc(state: ^lua.State) -> (server: ^Server) {
	lua.getfield(state, lua.REGISTRYINDEX, "server")
	server = (^Server)(lua.touserdata(state, -1))
	lua.pop(state, 1)
	return
}

arena_from_sandbox :: proc {
	arena_from_sandbox_box,
	arena_from_sandbox_lua,
}
arena_from_sandbox_box :: proc(sandbox: Sandbox) -> (allocator: mem.Allocator) {
	return arena_from_sandbox_lua(sandbox.lua_state)
}
arena_from_sandbox_lua :: proc(state: ^lua.State) -> (allocator: mem.Allocator) {
	lua.getfield(state, lua.REGISTRYINDEX, "arena")
	arena := (^mem.Dynamic_Arena)(lua.touserdata(state, -1))
	allocator = mem.dynamic_arena_allocator(arena)
	lua.pop(state, 1)
	return
}

context_with_arena_from_sandbox :: proc {
	context_with_arena_from_sandbox_box,
	context_with_arena_from_sandbox_lua,
}
context_with_arena_from_sandbox_box :: proc(sandbox: Sandbox) -> (ctx: runtime.Context) {
	return context_with_arena_from_sandbox_lua(sandbox.lua_state)
}
context_with_arena_from_sandbox_lua :: proc(state: ^lua.State) -> (ctx: runtime.Context) {
	ctx = runtime.default_context()
	ctx.allocator = arena_from_sandbox(state)
	return
}

custom_data_from_sandbox :: proc {
	custom_data_from_sandbox_box,
	custom_data_from_sandbox_lua,
}
custom_data_from_sandbox_box :: proc(sandbox: Sandbox, key: string) -> (data: rawptr, ok: bool) {
	return custom_data_from_sandbox_lua(sandbox.lua_state, key)
}
custom_data_from_sandbox_lua :: proc(state: ^lua.State, key: string) -> (data: rawptr, ok: bool) {
	server := server_from_sandbox_lua(state)
	return server.custom_data[key]
}

sandbox_error :: proc {
	sandbox_error_box,
	sandbox_error_lua,
}

sandbox_error_box :: proc(sandbox: Sandbox, texts: ..string) {
	sandbox_error_lua(sandbox.lua_state, ..texts)
}

sandbox_error_lua :: proc(state: ^lua.State, texts: ..string) {
	lua.getglobal(state, "MCP_ERROR_OUTPUT")

	for text in texts {
		nextidx := lua.rawlen(state, -1) + 1
		ctext := strings.clone_to_cstring(text)
		defer delete(ctext)
		lua.pushstring(state, ctext)
		lua.seti(state, -2, lua.Integer(nextidx))
	}
	lua.pop(state, 1)
	lua.pushboolean(state, b32(true))
	lua.setglobal(state, "MCP_IS_ERROR")
}

sandbox_errorf :: proc {
	sandbox_errorf_box,
	sandbox_errorf_lua,
}

sandbox_errorf_box :: proc(sandbox: Sandbox, fmt_str: string, args: ..any) {
	sandbox_errorf_lua(sandbox.lua_state, fmt_str, ..args)
}

sandbox_errorf_lua :: proc(state: ^lua.State, fmt_str: string, args: ..any) {
	str := fmt.aprintf(fmt_str, ..args)
	defer delete(str)
	sandbox_error_lua(state, str)
}

sandbox_print :: proc {
	sandbox_print_box,
	sandbox_print_lua,
}

sandbox_print_lua :: proc(state: ^lua.State, texts: ..string) {
	lua.getglobal(state, "MCP_PRINT_HARNESS_OUTPUT")

	for text in texts {
		nextidx := lua.rawlen(state, -1) + 1
		ctext := strings.clone_to_cstring(text)
		defer delete(ctext)
		lua.pushstring(state, ctext)
		lua.seti(state, -2, lua.Integer(nextidx))
	}
	lua.pop(state, 1)
}

sandbox_print_box :: proc(sandbox: Sandbox, texts: ..string) {
	sandbox_print_lua(sandbox.lua_state, ..texts)
}

sandbox_printf :: proc {
	sandbox_printf_box,
	sandbox_printf_lua,
}

sandbox_printf_lua :: proc(state: ^lua.State, fmt_str: string, args: ..any) {
	str := fmt.aprintf(fmt_str, ..args)
	defer delete(str)
	sandbox_print_lua(state, str)
}

sandbox_printf_box :: proc(sandbox: Sandbox, fmt_str: string, args: ..any) {
	sandbox_printf_lua(sandbox.lua_state, fmt_str, ..args)
}

register_sandbox_function :: proc(
	sandbox: Sandbox,
	$In, $Out: typeid,
	name: string,
	handler: proc(_: In, sandbox: Sandbox) -> Out,
) {
	Wrapper :: struct {
		name:    string,
		handler: proc(_: In, sandbox: Sandbox) -> Out,
	}

	wrapper_ptr := (^Wrapper)(lua.newuserdata(sandbox.lua_state, size_of(Wrapper)))
	wrapper_ptr^ = Wrapper {
		name    = strings.clone(name),
		handler = handler,
	}

	lua_wrapper :: proc "c" (state: ^lua.State) -> i32 {
		context = context_with_arena_from_sandbox(state)

		wrapper := (^Wrapper)(lua.touserdata(state, lua.REGISTRYINDEX - 1))

		ok: bool
		params: In
		um_err := unmarshal_lua_value(state, -1, &params)
		if um_err != .None {
			fmt.eprintln("unmarshal error", um_err)
			sandbox_errorf(
				state,
				"BAD ARGUMENT ERROR (%s): Your input could not be parsed. please check docs and try again",
				wrapper.name,
			)
			return 0
		}
		result := wrapper.handler(params, Sandbox{state})

		lua.getglobal(state, cstring("MCP_IS_ERROR"))
		is_error := lua.toboolean(state, -1)
		lua.pop(state, 1)

		if is_error {
			return 0
		}

		m_err := marshal_lua_value(state, result)
		if m_err != .None {
			when ODIN_DEBUG {
				fmt.eprintfln("could not marshal output from function %s: %w (%w)", wrapper.name, result, m_err)
			}
			sandbox_errorf(state, "could not marshal return value of function %s to lua stack (%w)", wrapper.name, m_err)
			return 0
		}

		return 1
	}

	lua.pushcclosure(sandbox.lua_state, lua_wrapper, 1)
	name_cstr := strings.clone_to_cstring(name)
	defer delete(name_cstr)
	lua.setglobal(sandbox.lua_state, name_cstr)
}

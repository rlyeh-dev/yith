package yith

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import lua "vendor:lua/5.4"

// this is passed to functions registered with add_function(). The upside is,
// if you do not need to use the lua api, you do not need to `import lua "vendor:lua/5.4"`
// to register, and also allows sandbox->print() etc. not involved when you use `lua.register()`
Sandbox :: struct {
	lua_state: ^lua.State,
	printf:    proc(sandbox: Sandbox, fmt_str: string, args: ..any),
	print:     proc(sandbox: Sandbox, texts: ..string),
	errorf:    proc(sandbox: Sandbox, fmt_str: string, args: ..any),
	error:     proc(sandbox: Sandbox, texts: ..string),
}

// init type sandbox. It's used for your mcp.setup(server, setup_proc) calls
Sandbox_Init :: struct {
	lua_state: ^lua.State,
}

// mcp.setup(server, setup_proc) the type of this setup_proc is this
Sandbox_Setup :: #type proc(sandbox: Sandbox_Init)

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

	lua.open_base(state)
	lua.L_requiref(state, "string", lua.open_string, 1)
	lua.L_requiref(state, "math", lua.open_math, 1)
	lua.L_requiref(state, "utf8", lua.open_utf8, 1)
	lua.L_requiref(state, "table", lua.open_table, 1)
	lua.settop(state, 0)

	for setup_proc in setup_procs {
		setup_proc(Sandbox_Init{state})
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
	}

	if err_str != "" {
		fmt.sbprintfln(&output_builder, "Lua fatal error: %s", err_str)
	}

	output = strings.clone(strings.to_string(output_builder), parent_allocator)

	return
}


// fetches a pointer to the running mcp server instance
server_from_sandbox :: proc {
	server_from_sandbox_box,
	server_from_sandbox_lua,
}

// fetches a pointer to the running mcp server instance
server_from_sandbox_box :: proc(sandbox: Sandbox) -> (server: ^Server) {
	return server_from_sandbox_lua(sandbox.lua_state)
}

// fetches a pointer to the running mcp server instance
server_from_sandbox_lua :: proc(state: ^lua.State) -> (server: ^Server) {
	lua.getfield(state, lua.REGISTRYINDEX, "server")
	server = (^Server)(lua.touserdata(state, -1))
	lua.pop(state, 1)
	return
}

// fetch the dynamic arena allocator that we stuff into the lua context for you
// if you use add_function() this is already in your context, but you can call it
// from functions made with `lua.register()`
arena_from_sandbox :: proc {
	arena_from_sandbox_box,
	arena_from_sandbox_lua,
}

// fetch the dynamic arena allocator that we stuff into the lua context for you
// if you use add_function() this is already in your context, but you can call it
// from functions made with `lua.register()`
arena_from_sandbox_box :: proc(sandbox: Sandbox) -> (allocator: mem.Allocator) {
	return arena_from_sandbox_lua(sandbox.lua_state)
}

// fetch the dynamic arena allocator that we stuff into the lua context for you
// if you use add_function() this is already in your context, but you can call it
// from functions made with `lua.register()`
arena_from_sandbox_lua :: proc(state: ^lua.State) -> (allocator: mem.Allocator) {
	lua.getfield(state, lua.REGISTRYINDEX, "arena")
	arena := (^mem.Dynamic_Arena)(lua.touserdata(state, -1))
	allocator = mem.dynamic_arena_allocator(arena)
	lua.pop(state, 1)
	return
}

// like arena_from_sandbox but also gives you the context so that you can just
// context := context_with_arena_from_sandbox() from your `proc "c" ()` function
// if you're too lazy to context := runtime.default_context(); context.allocator = arena_from_context()
context_with_arena_from_sandbox :: proc {
	context_with_arena_from_sandbox_box,
	context_with_arena_from_sandbox_lua,
}

// like arena_from_sandbox but also gives you the context so that you can just
// context := context_with_arena_from_sandbox() from your `proc "c" ()` function
// if you're too lazy to context := runtime.default_context(); context.allocator = arena_from_context()
// this may be superfluous as if you're in a proc "c" you probably have a ^lua.State that is not wrapped
// within a Sandbox{}, in which case you likely already have this arena
context_with_arena_from_sandbox_box :: proc(sandbox: Sandbox) -> (ctx: runtime.Context) {
	return context_with_arena_from_sandbox_lua(sandbox.lua_state)
}

// like arena_from_sandbox but also gives you the context so that you can just
// context := context_with_arena_from_sandbox() from your `proc "c" ()` function
// if you're too lazy to context := runtime.default_context(); context.allocator = arena_from_context()
context_with_arena_from_sandbox_lua :: proc(state: ^lua.State) -> (ctx: runtime.Context) {
	ctx = runtime.default_context()
	ctx.allocator = arena_from_sandbox(state)
	return
}

// use add_custom_data(&server, key, rawptr(somethin)) then in odin functions registered with
// lua.register or add_function() pull it back out with this function
custom_data_from_sandbox :: proc {
	custom_data_from_sandbox_box,
	custom_data_from_sandbox_lua,
}
// use add_custom_data(&server, key, rawptr(somethin)) then in odin functions registered with
// add_function() pull it back out with this function
custom_data_from_sandbox_box :: proc(sandbox: Sandbox, key: string) -> (data: rawptr, ok: bool) {
	return custom_data_from_sandbox_lua(sandbox.lua_state, key)
}
// use add_custom_data(&server, key, rawptr(somethin)) then in odin functions registered with
// lua.register pull it back out with this function
custom_data_from_sandbox_lua :: proc(state: ^lua.State, key: string) -> (data: rawptr, ok: bool) {
	server := server_from_sandbox_lua(state)
	return server.custom_data[key]
}

// shortcut for pushing a string and calling lua.error(state). this causes lua to longjmp
// and get away from your code immediately so it can leak data if you're not using the arena
// allocator that we provide
sandbox_abort :: proc {
	sandbox_abort_box,
	sandbox_abort_lua,
}

// shortcut for pushing a string and calling lua.error(state). this causes lua to longjmp
// and get away from your code immediately so it can leak data if you're not using the arena
// allocator that we provide
sandbox_abort_box :: proc(sandbox: Sandbox, msg: string) {
	sandbox_abort_lua(sandbox.lua_state, msg)
}

// shortcut for pushing a string and calling lua.error(state). this causes lua to longjmp
// and get away from your code immediately so it can leak data if you're not using the arena
// allocator that we provide
sandbox_abort_lua :: proc(state: ^lua.State, msg: string) {
	cmsg := strings.clone_to_cstring(msg)
	defer delete(cmsg)
	lua.pushstring(state, cmsg)
	lua.error(state)
}

// writes to the sandbox auto-output that will get sent back to the llm, and set an internal flag
// which causes this evaluate call to be treated as an error when it eventually completes.
sandbox_error :: proc {
	sandbox_error_box,
	sandbox_error_lua,
}

// writes to the sandbox auto-output that will get sent back to the llm, and set an internal flag
// which causes this evaluate call to be treated as an error when it eventually completes.
sandbox_error_box :: proc(sandbox: Sandbox, texts: ..string) {
	sandbox_error_lua(sandbox.lua_state, ..texts)
}

// writes to the sandbox auto-output that will get sent back to the llm, and set an internal flag
// which causes this evaluate call to be treated as an error when it eventually completes.
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

// sandbox_error() but printf style
sandbox_errorf :: proc {
	sandbox_errorf_box,
	sandbox_errorf_lua,
}

// sandbox_error_box() but printf style
sandbox_errorf_box :: proc(sandbox: Sandbox, fmt_str: string, args: ..any) {
	sandbox_errorf_lua(sandbox.lua_state, fmt_str, ..args)
}

// sandbox_error_lua() but printf style
sandbox_errorf_lua :: proc(state: ^lua.State, fmt_str: string, args: ..any) {
	str := fmt.aprintf(fmt_str, ..args)
	defer delete(str)
	sandbox_error_lua(state, str)
}

// the same as our custom lua `print()`. this output will be sent to the LLM
sandbox_print :: proc {
	sandbox_print_box,
	sandbox_print_lua,
}

// the same as our custom lua `print()`. this output will be sent to the LLM
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

// the same as our custom lua `print()`. this output will be sent to the LLM
sandbox_print_box :: proc(sandbox: Sandbox, texts: ..string) {
	sandbox_print_lua(sandbox.lua_state, ..texts)
}

// sandbox_print but printf style
sandbox_printf :: proc {
	sandbox_printf_box,
	sandbox_printf_lua,
}

// sandbox_print_lua but printf style
sandbox_printf_lua :: proc(state: ^lua.State, fmt_str: string, args: ..any) {
	str := fmt.aprintf(fmt_str, ..args)
	defer delete(str)
	sandbox_print_lua(state, str)
}

// sandbox_print_box but printf style
sandbox_printf_box :: proc(sandbox: Sandbox, fmt_str: string, args: ..any) {
	sandbox_printf_lua(sandbox.lua_state, fmt_str, ..args)
}

// turns a lua.State into a Sandbox object. mostly used internally but if you
// find a reason to care to use it, knock yourself out.
get_sandbox :: proc(state: ^lua.State) -> Sandbox {
	return Sandbox {
		lua_state = state,
		printf = sandbox_printf_box,
		print = sandbox_print_box,
		errorf = sandbox_errorf_box,
		error = sandbox_error_box,
	}
}

// a fancier version of `lua.register()`. It will create a lua_wrapper for you,
// set it up with the sandbox's dynamic arena allocator, (un)marshal your input/output
// params to/from lua stack, and call your typed lua handler for you
add_function :: proc(sandbox: Sandbox_Init, name: string, handler: proc(_: $In, _: Sandbox) -> $Out) {
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
		result := wrapper.handler(params, get_sandbox(state))

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

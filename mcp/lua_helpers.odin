package yith
import "core:fmt"
import "core:mem"
import "core:strings"
import lua "vendor:lua/5.4"

// shortcut for pushing a string and calling lua.error(state). this causes lua to longjmp
// and get away from your code immediately so it can leak data if you're not using the arena
// allocator that we provide.
lua_abort :: proc(state: ^lua.State, msg: string = "Lua handler error") {
	set_sandbox_error_state(state)
	cmsg := strings.clone_to_cstring(msg)
	defer delete(cmsg)
	lua.pushstring(state, cmsg)
	lua.error(state)
}

append_sandbox_output :: proc(state: ^lua.State, str: cstring) {
	lua.getglobal(state, "MCP_PRINT_HARNESS_OUTPUT")
	nextidx := lua.rawlen(state, -1) + 1
	lua.pushstring(state, str)
	lua.seti(state, -2, lua.Integer(nextidx))
	lua.pop(state, 1)
}

set_sandbox_error_state :: proc(state: ^lua.State) {
	lua.pushboolean(state, b32(true))
	lua.setfield(state, lua.REGISTRYINDEX, "is_error")
}

lua_eprint :: proc(state: ^lua.State, args: ..any, sep := " ", allocator := context.allocator) {
	str := fmt.caprint(..args, sep = sep, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
	set_sandbox_error_state(state)
}

lua_eprintln :: proc(state: ^lua.State, args: ..any, sep := " ", allocator := context.allocator) {
	str := fmt.aprintln(..args, sep = sep, allocator = allocator)
	defer delete(str)
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	append_sandbox_output(state, cstr)
	set_sandbox_error_state(state)
}

//
lua_eprintf :: proc(state: ^lua.State, fmt_str: string, args: ..any, allocator := context.allocator) {
	str := fmt.caprintf(fmt_str, ..args, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
	set_sandbox_error_state(state)
}

lua_eprintfln :: proc(state: ^lua.State, fmt_str: string, args: ..any, allocator := context.allocator) {
	str := fmt.caprintfln(fmt_str, ..args, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
	set_sandbox_error_state(state)
}


// the same as our custom lua `print()` except the lua one appends a newline and we have print() and println(). this output will be sent to the LLM
lua_print :: proc(state: ^lua.State, args: ..any, sep := " ", allocator := context.allocator) {
	str := fmt.caprint(..args, sep = sep, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
}

lua_println :: proc(state: ^lua.State, args: ..any, sep := " ", allocator := context.allocator) {
	str := fmt.aprintln(..args, sep = sep, allocator = allocator)
	defer delete(str)
	cstr := strings.clone_to_cstring(str)
	defer delete(cstr)
	append_sandbox_output(state, cstr)
}

// printf() but will be sent as output to the LLM, like our internal lua print() but w/ fmt.aprintf backing it
lua_printf :: proc(state: ^lua.State, fmt_str: string, args: ..any, allocator := context.allocator) {
	str := fmt.caprintf(fmt_str, ..args, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
}

// printfln() but will be sent as output to the LLM, like our internal lua print() but w/ fmt.aprintfln backing it
lua_printfln :: proc(state: ^lua.State, fmt_str: string, args: ..any, allocator := context.allocator) {
	str := fmt.caprintfln(fmt_str, ..args, allocator = allocator)
	defer delete(str)
	append_sandbox_output(state, str)
}

// fetches a pointer to the running mcp server instance
mcp_server_instance :: proc(state: ^lua.State) -> (server: ^Server) {
	lua.getfield(state, lua.REGISTRYINDEX, "server")
	server = (^Server)(lua.touserdata(state, -1))
	lua.pop(state, 1)
	return
}

// fetch the dynamic arena allocator that we stuff into the lua context for you
// if you use add_function() this is already in your context, but you can call it
// from functions made with `lua.register()`
arena_allocator :: proc(state: ^lua.State) -> (allocator: mem.Allocator) {
	lua.getfield(state, lua.REGISTRYINDEX, "arena")
	arena := (^mem.Dynamic_Arena)(lua.touserdata(state, -1))
	allocator = mem.dynamic_arena_allocator(arena)
	lua.pop(state, 1)
	return
}

// use add_custom_data(&server, key, rawptr(somethin)) then in odin functions registered with
// lua.register pull it back out with this function
get_custom_data :: proc(state: ^lua.State, key: string) -> (data: rawptr, ok: bool) {
	server := mcp_server_instance(state)
	return server.custom_data[key]
}

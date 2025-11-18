package miskatonic_mcp

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import lua "vendor:lua/5.4"

Lua_Setup :: #type proc(state: ^lua.State)

@(private)
lua_evaluate :: proc(
	apis: []Api,
	setup_procs: []Lua_Setup,
	lua_code: string,
) -> (
	output: string,
	ok: bool,
) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	state := lua.L_newstate()
	defer lua.close(state)

	lua.pushlightuserdata(state, &arena)
	lua.setfield(state, lua.REGISTRYINDEX, "arena")

	lua.open_base(state)
	lua.L_requiref(state, "string", lua.open_string, 1)
	lua.L_requiref(state, "math", lua.open_math, 1)
	lua.L_requiref(state, "utf8", lua.open_utf8, 1)
	lua.L_requiref(state, "table", lua.open_table, 1)
	lua.settop(state, 0)

	for setup_proc in setup_procs {
		setup_proc(state)
	}

	for api in apis {
		api.setup(state)
	}

	lua.L_dostring(state, #load("etc/print_harness.lua"))

	code_cstr := strings.clone_to_cstring(lua_code)
	defer delete(code_cstr)
	err_str: string

	ok = lua.L_dostring(state, code_cstr) == 0
	if !ok {
		// will be appended to the code below
		err_str = strings.clone_from_cstring(lua.tostring(state, -1))
		lua.pop(state, 1)
	}

	lua.getglobal(state, "MCP_PRINT_HARNESS_OUTPUT")

	// the LLM eval'd code would have to overwrite this to error in this state, which is highly unlikely, but lets check and bail anyway
	lua.L_checktype(state, -1, i32(lua.TTABLE))

	output_len := lua.rawlen(state, -1)
	output_builder := strings.builder_make()
	defer strings.builder_destroy(&output_builder)

	for idx in 1 ..= output_len {
		lua.geti(state, -1, lua.Integer(idx))
		cstr := lua.tostring(state, -1)
		strings.write_string(&output_builder, strings.clone_from_cstring(cstr))
		strings.write_string(&output_builder, "\n")
		lua.pop(state, 1)
	}

	if !ok {
		strings.write_string(&output_builder, "LUA EVAL ERROR: ")
		strings.write_string(&output_builder, err_str)
		strings.write_string(&output_builder, "\n")
	}

	output = strings.to_string(output_builder)


	return
}

marshal_lua_table :: proc(
	state: ^lua.State,
	$T: typeid,
	val: ^T,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	context.allocator = allocator
	ti := type_info_of(T)
	tib := reflect.type_info_base(ti)

	#partial switch info in tib.variant {
	case runtime.Type_Info_Struct:
		lua.createtable(state, 0, info.field_count)
		for i in 0 ..< info.field_count {
			fld := info.names[i]
			off := info.offsets[i]
			ptr := rawptr(uintptr(val) + off)
			typ := info.types[i]
			key := strings.clone_to_cstring(fld)
			defer delete(key)

			switch typ.id {
			case string:
				str := strings.clone_to_cstring((^string)(ptr)^)
				defer delete(str)
				lua.pushstring(state, str)
			case i64:
				lua.pushinteger(state, lua.Integer((^i64)(ptr)^))
			case f64:
				lua.pushnumber(state, lua.Number((^f64)(ptr)^))
			case bool:
				lua.pushboolean(state, b32((^bool)(ptr)^))
			case:
				// so we don't setfield when we havent pushed a val, e.g. unsupported type.
				// we could also return an error but meh for now
				continue
			}
			lua.setfield(state, -2, key)
		}
	case:
		// we need to create an empty table anyway b/c this func is expected to push onto lua stack
		lua.createtable(state, 0, 0)
		return false
	}

	return true
}

unmarshal_lua_table :: proc(
	state: ^lua.State,
	idx: i32,
	$T: typeid,
	allocator := context.allocator,
) -> (
	result: T,
	ok: bool,
) {
	context.allocator = allocator
	ti := type_info_of(T)
	tib := reflect.type_info_base(ti)

	#partial switch info in tib.variant {
	case runtime.Type_Info_Struct:
		for i in 0 ..< info.field_count {
			fld := info.names[i]
			off := info.offsets[i]
			ptr := rawptr(uintptr(&result) + off)
			typ := info.types[i]
			key := strings.clone_to_cstring(fld)
			defer delete(key)

			lua.getfield(state, idx, key)
			switch typ.id {
			case string:
				str := strings.clone_from_cstring(lua.tostring(state, -1))
				(^string)(ptr)^ = str
			case i64:
				(^i64)(ptr)^ = i64(lua.tointeger(state, -1))
			case f64:
				(^f64)(ptr)^ = f64(lua.tonumber(state, -1))
			case bool:
				(^bool)(ptr)^ = bool(lua.toboolean(state, -1))
			case:
				// we should also probably error here too but im not here for errors rn
				// but we still want to do the following pop so we also dont need a continue
				// but if we did error we would need to pop first, so eff it we'll do it anyway
				lua.pop(state, 1)
				continue // err here when we are here for errors instead of ok and tbh for now this is still ok
			}
			lua.pop(state, 1)
		}

		ok = true
	case:
		ok = false
	}
	return
}

arena_from_lua :: proc(state: ^lua.State) -> (allocator: mem.Allocator) {
	lua.getfield(state, lua.REGISTRYINDEX, "arena")
	arena := (^mem.Dynamic_Arena)(lua.touserdata(state, -1))
	allocator = mem.dynamic_arena_allocator(arena)
	lua.pop(state, 1)
	return
}

context_with_arena_from_lua :: proc(state: ^lua.State) -> (ctx: runtime.Context) {
	ctx = runtime.default_context()
	ctx.allocator = arena_from_lua(state)
	return
}

register_typed_lua_handler :: proc(
	state: ^lua.State,
	$In, $Out: typeid,
	name: string,
	handler: proc(_: In) -> (Out, string),
) {
	Wrapper :: struct {
		name:    string,
		handler: proc(_: In) -> (Out, string),
	}

	wrapper_ptr := (^Wrapper)(lua.newuserdata(state, size_of(Wrapper)))
	wrapper_ptr^ = Wrapper {
		name    = strings.clone(name),
		handler = handler,
	}

	lua_wrapper :: proc "c" (state: ^lua.State) -> i32 {
		context = context_with_arena_from_lua(state)

		wrapper := (^Wrapper)(lua.touserdata(state, lua.REGISTRYINDEX - 1))

		ok: bool
		params: In
		params, ok = unmarshal_lua_table(state, -1, In)
		if !ok {
			lua_err_cstr := fmt.caprintfln(
				"could not unmarshal input params for function %s from lua stack",
				wrapper.name,
			)
			defer delete(lua_err_cstr)
			lua.pushstring(state, lua_err_cstr)
			lua.error(state)
		}

		result, err := wrapper.handler(params)
		if err != "" {
			err_cstr := strings.clone_to_cstring(err)
			defer delete(err_cstr)
			lua.pushstring(state, err_cstr)
			lua.error(state)
		}

		ok = marshal_lua_table(state, Out, &result)
		if !ok {
			when ODIN_DEBUG {
				// this could be sensitive info, stderr is fine when in dev but don't send it
				fmt.eprintfln(
					"could not marshal output from function %s: %w",
					wrapper.name,
					result,
				)
			}
			lua_err_cstr := fmt.caprintfln(
				"could not marshal return value of function %s to lua stack",
				wrapper.name,
			)
			defer delete(lua_err_cstr)
			lua.pushstring(state, lua_err_cstr)
			lua.error(state)
		}

		return 1
	}

	lua.pushcclosure(state, lua_wrapper, 1)
	name_cstr := strings.clone_to_cstring(name)
	defer delete(name_cstr)
	lua.setglobal(state, name_cstr)
}

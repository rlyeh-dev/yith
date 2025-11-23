package yith

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import lua "vendor:lua/5.4"

Marshal_Error :: enum {
	None,
	Unsupported_Type,
}

// Turns an Odin data type into lua state. supports a lot of the same things that json.marshal does,
// should handle primitives and structs and slices/arrays/etc. unions are NOT supported currently
marshal_lua_value :: proc(state: ^lua.State, val: any, allocator := context.allocator) -> (error: Marshal_Error) {
	return marshal_value(state, val, allocator)
}

@(private)
marshal_value :: proc(state: ^lua.State, val: any, allocator := context.allocator) -> (error: Marshal_Error) {
	context.allocator = allocator

	ti := runtime.type_info_base(type_info_of(val.id))
	a := any{val.data, ti.id}
	top := lua.gettop(state)

	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		str := strings.clone_to_cstring((^string)(val.data)^)
		defer delete(str)
		lua.pushstring(state, str)

	case runtime.Type_Info_Integer:
		to: lua.Integer
		switch typ in a {
		case i128: to = lua.Integer((^i128)(val.data)^)
		case i64: to = lua.Integer((^i64)(val.data)^)
		case i32: to = lua.Integer((^i32)(val.data)^)
		case i16: to = lua.Integer((^i16)(val.data)^)
		case i8: to = lua.Integer((^i8)(val.data)^)
		case u128: to = lua.Integer((^u128)(val.data)^)
		case u64: to = lua.Integer((^u64)(val.data)^)
		case u32: to = lua.Integer((^u32)(val.data)^)
		case u16: to = lua.Integer((^u16)(val.data)^)
		case u8: to = lua.Integer((^u8)(val.data)^)
		case int: to = lua.Integer((^int)(val.data)^)
		case uint: to = lua.Integer((^uint)(val.data)^)
		case:
			lua.settop(state, top)
			return .Unsupported_Type
		}
		lua.pushinteger(state, to)

	case runtime.Type_Info_Float:
		to: lua.Number
		switch typ in a {
		case f64: to = lua.Number((^f64)(val.data)^)
		case f32: to = lua.Number((^f32)(val.data)^)
		case f16: to = lua.Number((^f16)(val.data)^)
		case:
			lua.settop(state, top)
			return .Unsupported_Type
		}
		lua.pushnumber(state, to)

	case runtime.Type_Info_Boolean: lua.pushboolean(state, b32((^bool)(val.data)^))

	case runtime.Type_Info_Enum:
		name, found := reflect.enum_name_from_value_any(val)
		if found {
			cname := strings.clone_to_cstring(name)
			defer delete(cname)
			lua.pushstring(state, cname)
		} else {
			err := marshal_value(state, any{rawptr(val.data), info.base.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
		}

	case runtime.Type_Info_Struct:
		lua.createtable(state, 0, info.field_count)
		for i in 0 ..< info.field_count {
			fld := info.names[i]
			off := info.offsets[i]
			ptr := rawptr(uintptr(val.data) + off)
			typ := info.types[i]
			key := strings.clone_to_cstring(fld)
			defer delete(key)
			err := marshal_value(state, any{ptr, typ.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
			lua.setfield(state, -2, key)
		}

	case runtime.Type_Info_Slice:
		slice := cast(^mem.Raw_Slice)val.data
		lua.createtable(state, i32(slice.len), 0)
		for i in 0 ..< slice.len {
			data := uintptr(slice.data) + uintptr(i * info.elem_size)
			err := marshal_value(state, any{rawptr(data), info.elem.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
			lua.seti(state, -2, lua.Integer(i + 1))
		}

	case runtime.Type_Info_Dynamic_Array:
		array := cast(^mem.Raw_Dynamic_Array)val.data
		lua.createtable(state, i32(array.len), 0)
		for i in 0 ..< array.len {
			data := uintptr(array.data) + uintptr(i * info.elem_size)
			err := marshal_value(state, any{rawptr(data), info.elem.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
			lua.seti(state, -2, lua.Integer(i + 1))
		}
	case runtime.Type_Info_Array:
		lua.createtable(state, i32(info.count), 0)
		for i in 0 ..< info.count {
			data := uintptr(val.data) + uintptr(i * info.elem_size)
			err := marshal_value(state, any{rawptr(data), info.elem.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
			lua.seti(state, -2, lua.Integer(i + 1))
		}
	case runtime.Type_Info_Enumerated_Array:
		index_type := reflect.type_info_base(info.index)
		enum_type := index_type.variant.(reflect.Type_Info_Enum)
		lua.createtable(state, 0, i32(info.count))
		for i in 0 ..< info.count {
			value := cast(runtime.Type_Info_Enum_Value)i
			index, found := slice.linear_search(enum_type.values, value)
			if !found { continue }
			key := strings.clone_to_cstring(enum_type.names[index])
			defer delete(key)
			data := uintptr(val.data) + uintptr(i * info.elem_size)
			err := marshal_value(state, any{rawptr(data), info.elem.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return err
			}
			lua.setfield(state, -2, key)
		}


	case runtime.Type_Info_Map:
		m := (^mem.Raw_Map)(val.data)

		if m == nil {
			break
		}

		if info.map_info == nil {
			return .Unsupported_Type
		}

		map_cap := uintptr(runtime.map_cap(m^))
		ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(m^, info.map_info)

		lua.createtable(state, 0, i32(map_cap))
		i := 0
		key_loop: for bucket_index in 0 ..< map_cap {
			runtime.map_hash_is_valid(hs[bucket_index]) or_continue
			i += 1

			key := rawptr(runtime.map_cell_index_dynamic(ks, info.map_info.ks, bucket_index))
			value := rawptr(runtime.map_cell_index_dynamic(vs, info.map_info.vs, bucket_index))

			lua_key: cstring
			{
				kv := any{key, info.key.id}
				kti := runtime.type_info_base(type_info_of(kv.id))
				ka := any{kv.data, kti.id}
				name: string

				mapinfo := info

				#partial switch info in kti.variant {
				case runtime.Type_Info_String:
					switch s in ka {
					case string: name = s
					case cstring: name = string(s)
					}
					lua_key = strings.clone_to_cstring(name)
				case runtime.Type_Info_Integer:
					buf: [40]byte
					u := cast_any_int_to_u128(ka)
					name = strconv.write_bits_128(buf[:], u, 10, info.signed, 8 * kti.size, "0123456789", nil)
					lua_key = strings.clone_to_cstring(name)
				case runtime.Type_Info_Enum:
					name, found := reflect.enum_name_from_value_any(ka)
					if found {
						lua_key = strings.clone_to_cstring(name)
					} else {
						lua.settop(state, top)
						return .Unsupported_Type
					}

				case:
					lua.settop(state, top)
					return .Unsupported_Type
				}
			}
			defer delete(lua_key)
			err := marshal_value(state, any{value, info.value.id}, allocator)
			if err != nil {
				lua.settop(state, top)
				return .Unsupported_Type
			}
			lua.setfield(state, -2, lua_key)
		}
	case:
		lua.settop(state, top)
		return .Unsupported_Type
	}

	return
}

Unmarshal_Error :: enum {
	None,
	Top_Level_Pointer_Required,
	Type_Mismatch,
	Unsupported_Type,
	Invalid_Allocator,
	Out_Of_Memory,
}

// Turns an item on the lua stack into into an Odin datatype. supports a lot of the same things that json.marshal does,
// should handle primitives and structs and slices/arrays/etc. unions are NOT supported currently
unmarshal_lua_value :: proc(
	state: ^lua.State,
	idx: i32,
	val: any,
	allocator := context.allocator,
) -> (
	error: Unmarshal_Error,
) {
	context.allocator = allocator
	ti := runtime.type_info_base(type_info_of(val.id))

	#partial switch info in ti.variant {
	case runtime.Type_Info_Pointer:
		pointed_val := any{(^rawptr)(val.data)^, ti.variant.(runtime.Type_Info_Pointer).elem.id}
		return unmarshal_value(state, idx, pointed_val, allocator)
	}

	return .Top_Level_Pointer_Required
}


@(private = "package")
unmarshal_value :: proc(
	state: ^lua.State,
	idx: i32,
	val: any,
	allocator := context.allocator,
) -> (
	error: Unmarshal_Error,
) {
	context.allocator = allocator

	ti := runtime.type_info_base(type_info_of(val.id))
	top := lua.gettop(state)
	absidx := idx < 0 ? top + idx + 1 : idx
	ltyp := lua.type(state, idx)
	a := any{val.data, ti.id}
	defer lua.pop(state, 1)

	#partial switch info in ti.variant {
	case runtime.Type_Info_String:
		if ltyp != .STRING {
			return .Type_Mismatch
		}

		str := strings.clone_from_cstring(lua.tostring(state, -1))
		(^string)(val.data)^ = str

	case runtime.Type_Info_Integer:
		if ltyp != .NUMBER {
			return .Type_Mismatch
		}
		integer := lua.tointeger(state, -1)
		switch typ in a {
		case i128: (^i128)(val.data)^ = cast(i128)integer
		case i64: (^i64)(val.data)^ = cast(i64)integer
		case i32: (^i32)(val.data)^ = cast(i32)integer
		case i16: (^i16)(val.data)^ = cast(i16)integer
		case i8: (^i8)(val.data)^ = cast(i8)integer
		case u128: (^u128)(val.data)^ = cast(u128)integer
		case u64: (^u64)(val.data)^ = cast(u64)integer
		case u32: (^u32)(val.data)^ = cast(u32)integer
		case u16: (^u16)(val.data)^ = cast(u16)integer
		case u8: (^u8)(val.data)^ = cast(u8)integer
		case int: (^int)(val.data)^ = cast(int)integer
		case uint: (^uint)(val.data)^ = cast(uint)integer
		}

	case runtime.Type_Info_Float:
		if ltyp != .NUMBER {
			return .Type_Mismatch
		}
		flt := lua.tonumber(state, -1)
		switch typ in a {
		case f64: (^f64)(val.data)^ = cast(f64)flt
		case f32: (^f32)(val.data)^ = cast(f32)flt
		case f16: (^f16)(val.data)^ = cast(f16)flt
		}

	case runtime.Type_Info_Boolean:
		if ltyp != .BOOLEAN {
			return
		}
		b := lua.toboolean(state, -1)
		(^bool)(val.data)^ = bool(b)

	case runtime.Type_Info_Enum: if ltyp == .STRING {
				str := strings.clone_from_cstring(lua.tostring(state, -1))
				defer delete(str)
				for name, i in info.names {
					if name == str {
						v := info.values[i]
						assign_int(val, info.values[i])
					}
				}
			} else if ltyp == .NUMBER {
				assign_int(val, lua.tointeger(state, -1))
			}

	case runtime.Type_Info_Struct:
		if ltyp != .TABLE {
			return
		}
		for i in 0 ..< info.field_count {
			fld := info.names[i]
			off := info.offsets[i]
			ptr := rawptr(uintptr(val.data) + off)
			typ := info.types[i]
			key := strings.clone_to_cstring(fld)
			defer delete(key)
			lua.getfield(state, idx, key)
			err := unmarshal_value(state, -1, any{ptr, typ.id}, allocator)
			if err != nil {
				return err
			}
		}

	case reflect.Type_Info_Slice:
		if ltyp != .TABLE {
			return
		}
		length := lua.rawlen(state, -1)
		raw := (^mem.Raw_Slice)(val.data)
		data, err := bytes_make(info.elem.size * int(length), info.elem.align, allocator)
		if err != .None {
			lua.pop(state, 1)
			return
		}
		raw.data = raw_data(data)
		raw.len = int(length)

		for i in 0 ..< length {
			lua.geti(state, -1, lua.Integer(i + 1))
			elem_ptr := rawptr(uintptr(raw.data) + uintptr(i) * uintptr(info.elem.size))
			elem := any{elem_ptr, info.elem.id}
			err := unmarshal_value(state, -1, elem, allocator)
			if err != nil {
				return err
			}
		}

	case runtime.Type_Info_Dynamic_Array:
		if ltyp != .TABLE {
			return
		}
		length := lua.rawlen(state, -1)
		raw := (^mem.Raw_Dynamic_Array)(val.data)
		data, err := bytes_make(info.elem.size * int(length), info.elem.align, allocator)
		if err != .None {
			return
		}
		raw.data = raw_data(data)
		raw.len = int(length)
		raw.cap = int(length)
		raw.allocator = allocator

		for i in 0 ..< length {
			lua.geti(state, -1, lua.Integer(i + 1))
			elem_ptr := rawptr(uintptr(raw.data) + uintptr(i) * uintptr(info.elem.size))
			elem := any{elem_ptr, info.elem.id}
			err := unmarshal_value(state, -1, elem, allocator)
			if err != nil {
				return err
			}
		}

	case runtime.Type_Info_Array:
		if ltyp != .TABLE {
			return
		}
		length := lua.rawlen(state, -1)
		for i in 0 ..< length {
			if int(i) >= info.count {
				// just.. silently ignore this
				break
			}
			lua.geti(state, -1, lua.Integer(i + 1))
			elem_ptr := rawptr(uintptr(val.data) + uintptr(i) * uintptr(info.elem.size))
			elem := any{elem_ptr, info.elem.id}
			err := unmarshal_value(state, -1, elem, allocator)
			if err != nil {
				return err
			}
		}

	case runtime.Type_Info_Enumerated_Array:
		if ltyp != .TABLE {
			return
		}
		length := info.count
		index_type := reflect.type_info_base(info.index)
		enum_type := index_type.variant.(reflect.Type_Info_Enum)
		for i in 0 ..< length {
			value := cast(runtime.Type_Info_Enum_Value)i
			index, found := slice.linear_search(enum_type.values, value)
			if !found {
				continue
			}
			key := strings.clone_to_cstring(enum_type.names[index])
			defer delete(key)
			lua.getfield(state, -1, key)
			elem_ptr := rawptr(uintptr(val.data) + uintptr(i) * uintptr(info.elem.size))
			elem := any{elem_ptr, info.elem.id}
			err := unmarshal_value(state, -1, elem, allocator)
			if err != nil {
				return err
			}
		}

	case reflect.Type_Info_Map:
		if ltyp != .TABLE {
			return
		}
		if !reflect.is_string(info.key) && !reflect.is_integer(info.key) && !reflect.is_enum(info.key) {
			return .Unsupported_Type
		}
		raw_map := (^mem.Raw_Map)(val.data)
		if raw_map.allocator.procedure == nil {
			raw_map.allocator = allocator
		}

		elem_backing := bytes_make(info.value.size, info.value.align, allocator) or_return
		defer delete(elem_backing, allocator)

		map_backing_value := any{raw_data(elem_backing), info.value.id}

		lua.pushnil(state)
		for lua.next(state, absidx) != 0 {
			top := lua.gettop(state)
			kidx, vidx := i32(top - 1), i32(top)
			lua_kt := lua.type(state, kidx)
			err := unmarshal_value(state, vidx, map_backing_value, allocator)
			if err != .None {
				lua.pop(state, 1)
				continue
			}

			odin_kt := info.key

			#partial switch kt in odin_kt.variant {
			// usually this should only affect when odin_kt is an enum, but in case theres a distinct string or distinct int passed
			case runtime.Type_Info_Named: odin_kt = reflect.type_info_base(kt.base)
			}
			#partial switch kt in odin_kt.variant {
			case runtime.Type_Info_String:
				if lua_kt != .STRING {
					lua.pop(state, 1)
					continue
				}
				key := strings.clone_from_cstring(lua.tostring(state, kidx))
				set_ptr := runtime.__dynamic_map_set_without_hash(raw_map, info.map_info, rawptr(&key), map_backing_value.data)
				if set_ptr == nil {
					delete(key, allocator)
				}

			case runtime.Type_Info_Enum:
				if lua_kt != .STRING {
					lua.pop(state, 1)
					continue
				}
				key := strings.clone_from_cstring(lua.tostring(state, kidx))
				found := false
				for name, i in kt.names {
					if name == key {
						v := kt.values[i]

						set_ptr := runtime.__dynamic_map_set_without_hash(
							raw_map,
							info.map_info,
							rawptr(&v),
							map_backing_value.data,
						)
						if set_ptr == nil {
							delete(key, allocator)
						}
						found = true
					}
				}
				if !found {
					delete(key, allocator)
				}

			case runtime.Type_Info_Integer:
				if lua_kt != .STRING {
					continue
				}
				lua_int_as_str := strings.clone_from_cstring(lua.tostring(state, kidx))
				i, ok := strconv.parse_u128(lua_int_as_str)
				if !ok {
					continue
				}
				set_ptr := runtime.__dynamic_map_set_without_hash(raw_map, info.map_info, rawptr(&i), map_backing_value.data)
			}


		}

	case: return .Unsupported_Type
	}


	return
}


// unmarshal_lua_value :: proc(
// 	state: ^lua.State,
// 	idx: i32,
// 	$T: typeid,
// 	allocator := context.allocator,
// ) -> (
// 	result: T,
// 	ok: bool,
// ) {
// 	context.allocator = allocator
// 	ti := type_info_of(T)
// 	tib := reflect.type_info_base(ti)

// 	#partial switch info in tib.variant {
// 	case runtime.Type_Info_Struct:
// 		for i in 0 ..< info.field_count {
// 			fld := info.names[i]
// 			off := info.offsets[i]
// 			ptr := rawptr(uintptr(&result) + off)
// 			typ := info.types[i]
// 			key := strings.clone_to_cstring(fld)
// 			defer delete(key)

// 			lua.getfield(state, idx, key)
// 			switch typ.id {
// 			case string:
// 				str := strings.clone_from_cstring(lua.tostring(state, -1))
// 				(^string)(ptr)^ = str
// 			case i64:
// 				(^i64)(ptr)^ = i64(lua.tointeger(state, -1))
// 			case f64:
// 				(^f64)(ptr)^ = f64(lua.tonumber(state, -1))
// 			case bool:
// 				(^bool)(ptr)^ = bool(lua.toboolean(state, -1))
// 			case:
// 				// we should also probably error here too but im not here for errors rn
// 				// but we still want to do the following pop so we also dont need a continue
// 				// but if we did error we would need to pop first, so eff it we'll do it anyway
// 				lua.pop(state, 1)
// 				continue // err here when we are here for errors instead of ok and tbh for now this is still ok
// 			}
// 			lua.pop(state, 1)
// 		}

// 		ok = true
// 	case:
// 		ok = false
// 	}
// 	return
// }

// taken from odin json marshal stuff
@(private)
cast_any_int_to_u128 :: proc(any_int_value: any) -> u128 {
	u: u128 = 0
	switch i in any_int_value {
	case i8: u = u128(i)
	case i16: u = u128(i)
	case i32: u = u128(i)
	case i64: u = u128(i)
	case i128: u = u128(i)
	case int: u = u128(i)
	case u8: u = u128(i)
	case u16: u = u128(i)
	case u32: u = u128(i)
	case u64: u = u128(i)
	case u128: u = u128(i)
	case uint: u = u128(i)
	case uintptr: u = u128(i)
	case i16le: u = u128(i)
	case i32le: u = u128(i)
	case i64le: u = u128(i)
	case u16le: u = u128(i)
	case u32le: u = u128(i)
	case u64le: u = u128(i)
	case u128le: u = u128(i)
	case i16be: u = u128(i)
	case i32be: u = u128(i)
	case i64be: u = u128(i)
	case u16be: u = u128(i)
	case u32be: u = u128(i)
	case u64be: u = u128(i)
	case u128be: u = u128(i)
	}

	return u
}

// also copied from json
@(private)
assign_int :: proc(val: any, i: $T) -> bool {
	v := reflect.any_core(val)
	switch &dst in v {
	case i8: dst = i8(i)
	case i16: dst = i16(i)
	case i16le: dst = i16le(i)
	case i16be: dst = i16be(i)
	case i32: dst = i32(i)
	case i32le: dst = i32le(i)
	case i32be: dst = i32be(i)
	case i64: dst = i64(i)
	case i64le: dst = i64le(i)
	case i64be: dst = i64be(i)
	case i128: dst = i128(i)
	case i128le: dst = i128le(i)
	case i128be: dst = i128be(i)
	case u8: dst = u8(i)
	case u16: dst = u16(i)
	case u16le: dst = u16le(i)
	case u16be: dst = u16be(i)
	case u32: dst = u32(i)
	case u32le: dst = u32le(i)
	case u32be: dst = u32be(i)
	case u64: dst = u64(i)
	case u64le: dst = u64le(i)
	case u64be: dst = u64be(i)
	case u128: dst = u128(i)
	case u128le: dst = u128le(i)
	case u128be: dst = u128be(i)
	case int: dst = int(i)
	case uint: dst = uint(i)
	case uintptr: dst = uintptr(i)
	case:
		is_bit_set_different_endian_to_platform :: proc(ti: ^runtime.Type_Info) -> bool {
			if ti == nil {
				return false
			}
			t := runtime.type_info_base(ti)
			#partial switch info in t.variant {
			case runtime.Type_Info_Integer: switch info.endianness {
					case .Platform: return false
					case .Little: return ODIN_ENDIAN != .Little
					case .Big: return ODIN_ENDIAN != .Big
					}
			}
			return false
		}

		ti := type_info_of(v.id)
		if info, ok := ti.variant.(runtime.Type_Info_Bit_Set); ok {
			do_byte_swap := is_bit_set_different_endian_to_platform(info.underlying)
			switch ti.size * 8 {
			case 0: // no-op.
			case 8:
				x := (^u8)(v.data)
				x^ = u8(i)
			case 16:
				x := (^u16)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u16(i)) : u16(i)
			case 32:
				x := (^u32)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u32(i)) : u32(i)
			case 64:
				x := (^u64)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u64(i)) : u64(i)
			case: panic("unknown bit_size size")
			}
			return true
		}
		return false
	}
	return true
}

// i sure am stealing a lot of stuff from json 🤷‍♀️
@(private)
bytes_make :: proc(
	size, alignment: int,
	allocator: mem.Allocator,
	loc := #caller_location,
) -> (
	bytes: []byte,
	err: Unmarshal_Error,
) {
	b, berr := mem.alloc_bytes(size, alignment, allocator, loc)
	if berr != nil {
		if berr == .Out_Of_Memory {
			err = .Out_Of_Memory
		} else {
			err = .Invalid_Allocator
		}
	}
	bytes = b
	return
}

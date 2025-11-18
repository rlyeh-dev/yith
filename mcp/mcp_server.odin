package miskatonic_mcp

import "core:mem"
import "core:slice"
import "core:strings"
import lua "vendor:lua/5.4"


Api :: struct {
	name:        string,
	description: string,
	docs:        string,
	setup:       Lua_Setup,
}

destroy_api :: proc(api: ^Api) {
	delete(api.name)
	delete(api.description)
	delete(api.docs)
}

Server :: struct {
	name:        string,
	description: string,
	version:     string,
	sandbox:     Sandbox,
	apis:        [dynamic]Api,
	api_names:   map[string]int,
	setups:      [dynamic]Lua_Setup,
	api_index:   Tfidf,
}

destroy_server :: proc(server: ^Server) {
	delete(server.name)
	delete(server.description)
	delete(server.version)
	for &api in server.apis {
		destroy_api(&api)
	}
	for name, _ in server.api_names {
		delete(name)
	}
	delete(server.api_names)
	delete(server.apis)
	delete(server.setups)
	destroy_tfidf(&server.api_index)
	destroy_sandbox(&server.sandbox)
}

register_api :: proc(server: ^Server, name, description, docs: string, setup: Lua_Setup) {
	append(
		&server.apis,
		Api {
			name = strings.clone(name),
			description = strings.clone(description),
			docs = strings.clone(docs),
			setup = setup,
		},
	)
	server.api_names[strings.clone(name)] = len(server.apis) - 1
	add_api_to_index(&server.api_index, name, description, docs)
}

register_global_lua_setup_handler :: proc(server: ^Server, setup_handler: Lua_Setup) {
	append(&server.setups, setup_handler)
}

init_server :: proc(
	server: ^Server,
	name, description: string,
	version := "1.0.0",
	api_search_arena_size: int = DEFAULT_API_SEARCH_ARENA_SIZE,
	sandbox_arena_size: int = DEFAULT_SANDBOX_ARENA_SIZE,
) {
	server.name = strings.clone(name)
	server.description = strings.clone(description)
	server.version = strings.clone(version)
	server.apis = make([dynamic]Api)
	server.api_names = make(map[string]int)

	init_tfidf(&server.api_index, api_search_arena_size)
	init_sandbox(&server.sandbox, sandbox_arena_size)
}

make_server :: proc(
	name, description: string,
	version := "1.0.0",
	api_search_arena_size: int = DEFAULT_API_SEARCH_ARENA_SIZE,
	sandbox_arena_size: int = DEFAULT_SANDBOX_ARENA_SIZE,
) -> (
	server: Server,
) {
	init_server(&server, name, description, version, api_search_arena_size, sandbox_arena_size)
	return
}

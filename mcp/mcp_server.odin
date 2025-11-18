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
	name:            string,
	description:     string,
	version:         string,
	apis:            [dynamic]Api,
	api_names:       map[string]int,
	setups:          [dynamic]Lua_Setup,
	api_index:       Tfidf,
	setup_completed: bool,
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

init_server :: proc(server: ^Server, name, description: string, version := "1.0.0") {
	server.name = strings.clone(name)
	server.description = strings.clone(description)
	server.version = strings.clone(version)
	server.apis = make([dynamic]Api)
	server.api_names = make(map[string]int)
}

make_server :: proc(name, description: string, version := "1.0.0") -> (server: Server) {
	init_server(&server, name, description, version)
	return
}

complete_setup :: proc(server: ^Server) {
	if !server.setup_completed {
		build_api_index(server)
	}
	server.setup_completed = true
}

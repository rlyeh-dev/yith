package necronomicon_mcp

import "core:slice"
import "core:strings"
import lua "vendor:lua/5.4"

Mcp_Api :: struct {
	name:        string,
	description: string,
	docs:        string,
	setup:       Lua_Setup,
}

destroy_mcp_api :: proc(api: ^Mcp_Api) {
	delete(api.name)
	delete(api.description)
	delete(api.docs)
}

Mcp_Server :: struct {
	name:        string,
	description: string,
	version:     string,
	apis:        [dynamic]Mcp_Api,
	setups:      [dynamic]Lua_Setup,
	api_index:   Tfidf,
}

destroy_mcp_server :: proc(server: ^Mcp_Server) {
	delete(server.name)
	delete(server.description)
	delete(server.version)
	for &api in server.apis {
		destroy_mcp_api(&api)
	}
	delete(server.apis)
	delete(server.setups)
}

register_mcp_api :: proc(server: ^Mcp_Server, name, description, docs: string, setup: Lua_Setup) {
	append(
		&server.apis,
		Mcp_Api {
			name = strings.clone(name),
			description = strings.clone(description),
			docs = strings.clone(docs),
			setup = setup,
		},
	)

	// index the documentation right away
	tokens := tokenize_luadoc(docs, description)
	defer delete(tokens)
	append(
		&server.api_index.docs,
		Document {
			id = len(server.apis),
			name = strings.clone(name),
			tokens = slice.clone(tokens[:]),
		},
	)
}

register_global_lua_setup_handler :: proc(server: ^Mcp_Server, setup_handler: Lua_Setup) {
	append(&server.setups, setup_handler)
}

init_mcp_server :: proc(server: ^Mcp_Server, name, description: string, version := "1.0.0") {
	server.name = strings.clone(name)
	server.description = strings.clone(description)
	server.version = strings.clone(version)
}

make_mcp_server :: proc(name, description: string, version := "1.0.0") -> (server: Mcp_Server) {
	init_mcp_server(&server, name, description, version)
	return
}

package miskatonic_mcp

import "core:strings"

Api_Docs :: struct {
	name:        string,
	description: string,
	docs:        string,
}

destroy_api :: proc(api: ^Api_Docs) {
	delete(api.name)
	delete(api.description)
	delete(api.docs)
}

Server :: struct {
	name:            string,
	description:     string,
	version:         string,
	api_names:       map[string]int,
	api_docs:        [dynamic]Api_Docs,
	setups:          [dynamic]Sandbox_Setup,
	api_index:       Tfidf,
	setup_completed: bool,
}

destroy_server :: proc(server: ^Server) {
	delete(server.name)
	delete(server.description)
	delete(server.version)
	for &api in server.api_docs {
		destroy_api(&api)
	}
	for name, _ in server.api_names {
		delete(name)
	}
	delete(server.api_names)
	delete(server.api_docs)
	delete(server.setups)
	destroy_tfidf(&server.api_index)
}

register_api_docs :: proc(server: ^Server, name, description, docs: string) {
	rec := Api_Docs {
		name        = strings.clone(name),
		description = strings.clone(description),
		docs        = strings.clone(docs),
	}
	append(&server.api_docs, rec)
	server.api_names[strings.clone(name)] = len(server.api_docs) - 1
	add_api_to_index(&server.api_index, name, description, docs)
}

register_sandbox_setup :: proc(server: ^Server, setup_handler: Sandbox_Setup) {
	append(&server.setups, setup_handler)
}

init_server :: proc(server: ^Server, name, description: string, version := "1.0.0") {
	server.name = strings.clone(name)
	server.description = strings.clone(description)
	server.version = strings.clone(version)
	server.api_docs = make([dynamic]Api_Docs)
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

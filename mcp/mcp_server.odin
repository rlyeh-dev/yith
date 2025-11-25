package yith

import "core:strings"

Api_Docs :: struct {
	name:        string,
	description: string,
	signature:   string,
	docs:        string,
}

destroy_api :: proc(api: ^Api_Docs) {
	delete(api.name)
	delete(api.signature)
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
	help_docs:       [dynamic]string,
	custom_data:     map[string]rawptr,
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
	for help in server.help_docs {
		delete(help)
	}
	delete(server.help_docs)
	destroy_tfidf(&server.api_index)
	for key, ptr in server.custom_data {
		delete(key)
	}
	delete(server.custom_data)
}

// append to the markdown-formatted `help` tool and `api_help()` lua call.
// this is the documentation for the LLM as a whole and already has content
// related to how to use the lua subsytem. Document your most important calls
// with this
add_help :: proc(server: ^Server, help: string) {
	append(&server.help_docs, strings.clone(help))
}

// give us a pointer to anything you want. it will be placed within the lua state,
// and you can retrieve it with the `custom_data_from_sandbox` procedure group.
add_custom_data :: proc(server: ^Server, key: string, data: rawptr) {
	server.custom_data[strings.clone(key)] = data
}

// register api docs for the LLMs to know how to use your registered lua functions.
// it is up to you to keep the `name` here in sync with the one you register the
// function with. I suggest storing the name in a constant. docs should be full luadoc
// api docs, and signature should be 1-line documentation like
// `my_func({arg1="foo", arg2="blah"})`, description should similarly be a 1-line
// textual description of its purpose
add_documentation :: proc(server: ^Server, name, signature, description, docs: string) {
	rec := Api_Docs {
		name        = strings.clone(name),
		description = strings.clone(description),
		signature   = strings.clone(signature),
		docs        = strings.clone(docs),
	}
	append(&server.api_docs, rec)
	server.api_names[strings.clone(name)] = len(server.api_docs) - 1
	add_api_to_index(&server.api_index, name = name, description = description, docs = docs)
}

// The proc that you pass to this function will be called at the beginning of every
// lua evaluation. Use this to register your functions or do anything else you want
// to the lua environment (using the .lua_state inside Sandbox_Setup{})
setup :: proc(server: ^Server, setup_handler: Sandbox_Setup) {
	append(&server.setups, setup_handler)
}

init_server :: proc(server: ^Server, name, description: string, version := "1.0.0") {
	server.name = strings.clone(name)
	server.description = strings.clone(description)
	server.version = strings.clone(version)
	server.api_docs = make([dynamic]Api_Docs)
	server.api_names = make(map[string]int)
	add_builtin_apis(server)
}

make_server :: proc(name, description: string, version := "1.0.0") -> (server: Server) {
	init_server(&server, name, description, version)
	return
}

// This will be called upon server start, but it can also be used to force
// your api docs index to be to be built before the server starts. Currently
// this is a no-op after the first call, so make sure all api docs are registered
// before calling it.
complete_setup :: proc(server: ^Server) {
	if !server.setup_completed {
		build_api_index(server)
	}
	server.setup_completed = true
}

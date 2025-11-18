package miskatonic_mcp

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

Request_Id :: union {
	string,
	i64,
}

@(private = "package")
destroy_request_id :: proc(id: ^Request_Id) {
	#partial switch tid in id {
	case string:
		delete(tid)
	}
}

@(private = "package")
Request :: struct($Params: typeid) {
	jsonrpc: string,
	id:      Request_Id,
	method:  string,
	params:  Params,
}

@(private = "package")
destroy_request :: proc(req: ^Request($Params)) {
	delete(req.jsonrpc)
	destroy_request_id(&req.id)
	delete(req.method)
}

@(private = "package")
Unknown_Request :: Request(json.Object)

@(private = "package")
destroy_unknown_request :: proc(req: ^Unknown_Request) {
	json.destroy_value(req.params)
	destroy_request(req)
}


@(private = "package")
Tool_Call_Params :: struct($Args: typeid) {
	name:      string,
	arguments: Args,
}
@(private = "package")
destroy_tool_call_params :: proc(params: ^Tool_Call_Params($Args)) {
	delete(params.name)
}

@(private = "package")
Evaluate_Tool_Args :: struct {
	code: string,
}
@(private = "package")
destroy_evaluate_tool_args :: proc(args: ^Evaluate_Tool_Args) {
	delete(args.code)
}

@(private = "package")
Evaluate_Tool_Call_Request :: Request(Tool_Call_Params(Evaluate_Tool_Args))
@(private = "package")
destroy_evaluate_tool_call_request :: proc(req: ^Evaluate_Tool_Call_Request) {
	destroy_evaluate_tool_args(&req.params.arguments)
	destroy_tool_call_params(&req.params)
	destroy_request(req)
}

@(private = "package")
Search_Tool_Args :: struct {
	query:        string,
	descriptions: Maybe(bool),
	count:        Maybe(int),
}
@(private = "package")
destroy_search_tool_args :: proc(args: ^Search_Tool_Args) {
	delete(args.query)
}

@(private = "package")
Search_Tool_Call_Request :: Request(Tool_Call_Params(Search_Tool_Args))
@(private = "package")
destroy_search_tool_request :: proc(req: ^Search_Tool_Call_Request) {
	destroy_search_tool_args(&req.params.arguments)
	destroy_tool_call_params(&req.params)
	destroy_request(req)
}

@(private = "package")
List_Tool_Args :: struct {
	page:         Maybe(int),
	per_page:     Maybe(int),
	descriptions: Maybe(bool),
}
@(private = "package")
destroy_list_tool_args :: proc(args: ^List_Tool_Args) {
	// nothing to kill
}

@(private = "package")
List_Tool_Call_Request :: Request(Tool_Call_Params(List_Tool_Args))
@(private = "package")
destroy_list_tool_request :: proc(req: ^List_Tool_Call_Request) {
	destroy_list_tool_args(&req.params.arguments)
	destroy_tool_call_params(&req.params)
	destroy_request(req)
}

@(private = "package")
Docs_Tool_Args :: struct {
	name: string,
}
@(private = "package")
destroy_docs_tool_args :: proc(args: ^Docs_Tool_Args) {
	delete(args.name)
}

@(private = "package")
Docs_Tool_Call_Request :: Request(Tool_Call_Params(Docs_Tool_Args))
@(private = "package")
destroy_docs_tool_request :: proc(req: ^Docs_Tool_Call_Request) {
	destroy_docs_tool_args(&req.params.arguments)
	destroy_tool_call_params(&req.params)
	destroy_request(req)
}

@(private = "package")
Init_Request :: Request(
	struct {
		protocol_version: string `json:"protocolVersion"`,
		// we don't care what you support we don't use it, we're not
		// even going to unmarshal it that's how much we do not care
		// capabilities:     json.Object,
		client_info:      struct {
			name:    string,
			title:   string,
			version: string,
		} `json:"clientInfo"`,
	},
)

@(private = "package")
destroy_init_request :: proc(req: ^Init_Request) {
	delete(req.params.protocol_version)
	// json.destroy_value(req.params.capabilities)
	delete(req.params.client_info.name)
	delete(req.params.client_info.title)
	delete(req.params.client_info.version)
	destroy_request(req)
}

@(private = "package")
Error_Response :: struct {
	jsonrpc: string,
	id:      Request_Id,
	error:   struct {
		code:    int,
		message: string,
	},
}

@(private = "package")
destroy_error_response :: proc(res: ^Error_Response) {
	destroy_request_id(&res.id)
}

@(private = "package")
Response :: struct($Result: typeid) {
	jsonrpc: string,
	id:      Request_Id,
	result:  Result,
}

@(private = "package")
Init_Response :: Response(
	struct {
		protocol_version: string `json:"protocolVersion"`,
		capabilities:     struct {
			// only tools for now
			tools: struct {
				subscribe:   bool,
				listChanged: bool,
			},
			// we may add prompts later. maybe
		},
		server_info:      struct {
			name:    string,
			title:   string,
			version: string,
		} `json:"serverInfo"`,
		instructions:     string,
	},
)

// our tools only return text, and exactly one result with the error bool
@(private = "package")
Tool_Call_Response :: struct {
	content:  []struct {
		type: string,
		text: string,
	},
	is_error: bool `json:"isError"`,
}

@(private = "package")
Tool_List_Response :: struct {
	tools: []struct {
		name:         string,
		title:        string,
		description:  string,
		input_schema: json.Object,
	},
}


// we have a hard-coded list of tools
@(private = "package")
TOOLS_LIST_RAW :: #load("./etc/tools_list.json")

@(private = "package")
request_id_to_json_value :: proc(id: Request_Id) -> (result: json.Value) {
	switch typed_id in id {
	case i64:
		result = json.Integer(typed_id)
	case string:
		result = json.String(typed_id)
	}
	return
}

@(private = "package")
tools_list_response :: proc(id: Request_Id) -> (result: []byte) {
	jval: json.Object
	defer json.destroy_value(jval)
	um_err := json.unmarshal(TOOLS_LIST_RAW, &jval)
	if um_err != nil {
		result = handle_error_response("invalid input", id, 65537)
		return
	}

	jval["id"] = request_id_to_json_value(id)
	bytes, m_err := json.marshal(jval)
	if m_err != nil {
		result = handle_error_response("invalid output", id, 65532)
		return
	}
	defer delete(bytes)
	result = slice.clone(bytes)
	return
}

@(private = "package")
server_init_response :: proc(
	id: Request_Id,
	protocol_version, name, title, version: string,
) -> (
	res_bytes: []byte,
) {
	result := Init_Response {
		jsonrpc = "2.0",
		id = id,
		result = {
			protocol_version = protocol_version,
			capabilities = {tools = {subscribe = false, listChanged = false}},
			server_info = {name = name, title = title, version = version},
			instructions = "this is a lua code evaluation mcp. call the help tool for more info",
		},
	}

	m_err: json.Marshal_Error
	res_bytes, m_err = json.marshal(result, {})
	if m_err != nil {
		fmt.eprintln("Server Init: Marshal Error: %w", m_err)
		res_bytes = handle_error_response("error during initialization response", id, 5551212)
	}
	return
}

@(private = "package")
handle_unknown_tool_call :: proc(
	server: ^Server,
	req_bytes: []byte,
	id: Request_Id,
) -> (
	res_bytes: []byte,
) {
	return render_tool_call_response("unknown", id, "unknown tool call", true)
}

@(private = "package")
render_tool_call_response :: proc(
	tool: string,
	id: Request_Id,
	text_content: string,
	is_error: bool,
) -> (
	res_bytes: []u8,
) {
	result := Response(Tool_Call_Response) {
		jsonrpc = "2.0",
		id = id,
		result = Tool_Call_Response {
			content = {{type = "text", text = text_content}},
			is_error = is_error,
		},
	}

	m_err: json.Marshal_Error
	res_bytes, m_err = json.marshal(result, {})
	if m_err != nil {
		fmt.eprintln("%s Tool: Marshal Error: %w", tool, m_err)
		res_bytes = handle_error_response("i couldnt render json at you, but i can now", id, -37)
	}
	return
}

@(private = "package")
render_tool_call_failed :: proc(tool: string, id: Request_Id) -> (res_bytes: []u8) {
	msg :: "Tool failed for an unknown reason :("
	return handle_error_response(msg, id, 314159)
}

@(private = "package")
render_tool_call_bad_params :: proc(tool: string, id: Request_Id) -> (res_bytes: []u8) {
	msg :: "Tool call failed due to invalid arguments"
	return handle_error_response(msg, id, 42)
}

@(private = "package")
handle_tool_call :: proc(
	server: ^Server,
	req_bytes: []byte,
	name: string,
	id: Request_Id,
) -> (
	res_bytes: []byte,
) {
	res: string
	ok: bool
	switch name {
	case "help":
		res, ok := help_tool(server)
		defer delete(res)
		res_bytes = render_tool_call_response("Help", id, res, !ok)

	case "evaluate":
		msg: Evaluate_Tool_Call_Request
		defer destroy_evaluate_tool_call_request(&msg)
		um_ok := json.unmarshal(req_bytes, &msg)
		if um_ok != nil {
			fmt.eprintln("evaluate unmarshal error", um_ok)
			res_bytes = render_tool_call_bad_params("Evaluate", id)
			return
		}
		a := msg.params.arguments
		res, ok := evaluate_tool(server, a.code)
		defer delete(res)
		res_bytes = render_tool_call_response("Evaluate", id, res, !ok)

	case "docs":
		msg: Docs_Tool_Call_Request
		defer destroy_docs_tool_request(&msg)
		um_ok := json.unmarshal(req_bytes, &msg)
		if um_ok != nil {
			fmt.eprintln("docs unmarshal error", um_ok)
			res_bytes = render_tool_call_bad_params("Docs", id)
			return
		}
		a := msg.params.arguments
		res, ok := docs_tool(server, a.name)
		defer delete(res)
		res_bytes = render_tool_call_response("Docs", id, res, !ok)

	case "list":
		msg: List_Tool_Call_Request
		defer destroy_list_tool_request(&msg)
		um_ok := json.unmarshal(req_bytes, &msg)
		if um_ok != nil {
			fmt.eprintln("list unmarshal error", um_ok)
			res_bytes = render_tool_call_bad_params("List", id)
			return
		}
		a := msg.params.arguments
		page := a.page.? or_else LIST_TOOL_DEFAULT_PAGE
		per_page := a.per_page.? or_else LIST_TOOL_DEFAULT_PER_PAGE
		descs := a.descriptions.? or_else LIST_TOOL_DEFAULT_DESCS
		res, ok := list_tool(server, descs = descs, page = page, per_page = per_page)
		defer delete(res)
		res_bytes = render_tool_call_response("List", id, res, !ok)

	case "search":
		msg: Search_Tool_Call_Request
		defer destroy_search_tool_request(&msg)
		um_ok := json.unmarshal(req_bytes, &msg)
		if um_ok != nil {
			fmt.eprintln("search unmarshal error", um_ok)
			res_bytes = render_tool_call_bad_params("Search", id)
			return
		}
		a := msg.params.arguments
		count := a.count.? or_else SEARCH_TOOL_DEFAULT_COUNT
		descs := a.descriptions.? or_else SEARCH_TOOL_DEFAULT_DESCS
		res, ok := search_tool(server, a.query, descs = descs, count = count)
		defer delete(res)
		res_bytes = render_tool_call_response("Search", id, res, !ok)

	case:
		handle_unknown_tool_call(server, req_bytes, id)
	}
	return
}

@(private = "package")
handle_init_req :: proc(
	server: ^Server,
	req_bytes: []byte,
	id: Request_Id,
) -> (
	res_bytes: []byte,
) {
	msg: Init_Request
	defer destroy_init_request(&msg)
	um_ok := json.unmarshal(req_bytes, &msg)
	if um_ok != nil {
		fmt.eprintln("init unmarshal error", um_ok)
		// 101 because they fucked up on the very first msg so they need to take an introductory course
		res_bytes = handle_error_response("you sent a terrible init message", id, 101)
		return
	}

	res_bytes = server_init_response(
		id,
		// yeah we totally support whatever version you said, i ABSOLUTELY
		// looked at this value and didnt just echo it back to you. promise.
		protocol_version = msg.params.protocol_version,
		name = server.name,
		title = server.description,
		version = server.version,
	)

	return
}

handle_error_response :: proc(
	message: string,
	id: Request_Id,
	code: int = 1,
) -> (
	res_bytes: []byte,
) {
	result := Error_Response {
		jsonrpc = "2.0",
		id = id,
		error = {code = code, message = message},
	}
	defer destroy_error_response(&result)

	m_err: json.Marshal_Error
	res_bytes, m_err = json.marshal(result, {})
	if m_err != nil {
		fmt.eprintln("Error Response: Marshal Error: %w", m_err)
		panic("serious bug here")
	}
	return
}

handle_mcp_message :: proc(
	server: ^Server,
	req_bytes: []byte,
) -> (
	res_bytes: []byte,
	send: bool = true,
	ok: bool = true,
) {
	tmp: Unknown_Request
	defer destroy_unknown_request(&tmp)
	um_err := json.unmarshal(req_bytes, &tmp)
	if um_err != nil {
		ok = false
		return
	}
	if strings.starts_with(tmp.method, "notifications/") {
		// lol im not even gonna read your notification, take that
		send = false
		return
	}
	if tmp.method == "initialize" {
		res_bytes = handle_init_req(server, req_bytes, tmp.id)
		return
	}
	if tmp.method == "tools/list" {
		res_bytes = tools_list_response(tmp.id)
		return
	}
	if tmp.method == "tools/call" {
		#partial switch name_str in tmp.params["name"] {
		case string:
			res_bytes = handle_tool_call(server, req_bytes, name_str, tmp.id)
			return
		}
		res_bytes = handle_unknown_tool_call(server, req_bytes, tmp.id)
		return
	}

	// 8 sounds like a good error code for this
	res_bytes = handle_error_response("unsupported method", tmp.id, 8)

	return
}

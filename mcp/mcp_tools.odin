package necronomicon_mcp

tool_evaluate :: proc(server: ^Mcp_Server, code: string) -> (output: string, ok: bool) {
	return lua_evaluate(server.apis[:], server.setups[:], code)
}

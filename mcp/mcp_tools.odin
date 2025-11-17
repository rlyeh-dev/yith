package miskatonic_mcp

tool_evaluate :: proc(server: ^Server, code: string) -> (output: string, ok: bool) {
	return lua_evaluate(&server.sandbox, server.apis[:], server.setups[:], code)
}

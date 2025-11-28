### Yith: Code-Exec MCP Server SDK

This is an Odin Server-Only MCP SDK that behaves differently from the traditional/official MCP-SDK's listed in [MCP's official documentation](https://modelcontextprotocol.io/docs/sdk), in favor of the Sandboxed Code-Exec style dicussed by [Anthropic](https://www.anthropic.com/engineering/code-execution-with-mcp) and [Cloudflare](https://blog.cloudflare.com/code-mode/) in late 2025.

Unlike the above-mentioned blog posts, which advocate for LLMs running TypeScript code in a Docker or cloud container sandbox, this project opts for a more streamlined approach using an in-process lua sandbox. Your api is documented with luadoc comments and implemented in Odin procs (see [weather.lua](examples/basic/weather.lua) and [weather.odin](examples/basic/weather.odin) from the [basic example server](examples/basic))

Only four tools are provided to LLMs:

- **evaluate**: LLM provides a block of lua code to execute in the lua sandbox
- **help**: Lists a prose help overview on how to use the system.
- **search**: A tf-idf powered search of all lua api functions available within the sandbox based on the content of the luadoc api docs
- **list**: Lists only the name and description of each function available
- **docs**: look up the luadoc documenation for a single api function

In addition, the `help`, `search`, `list`, and `docs` tools have in-lua equivalents as `api_help()`, `api_search()`, `api_list()`, and `api_docs()` respectively. `api_docs()` and `api_help()` return no results but print to the lua sandbox console, which is captured and returned to the LLM as part of the tool response. `api_search()` and `api_list()` return structured results.

The only other MCP-SDK features that support is planned for are user-initiated prompts (slash commands), though client support for these is incredibly limited currently, so it is not a priority. 

### Usage 

```odin

import mcp "path/to/yith/mcp"
import lua "vendor:lua/5.4"

main :: proc() {
  server := mcp.make_server("CodeExecMCP", "Code Execution MCP utilizing Yith MCP Framework", "1.2.3")
  // Register the api docs for the function. 
  // do not need to store these in constants, but it's wise to do 
  // so for the name since it's replicated in both places. The 
  // api docs registry happens outside of the sandbox, before lua
  // is ever booted up, while function registration happens within 
  // the sandbox
  mcp.add_documentation(server, NAME, SIG, DESC, DOCS) 

  // Register the sandbox setup to add the function to each sandbox, 
  // as the lua environment is recreated on every evaluate call
  mcp.setup(server, proc(state: ^lua.State) {
    mcp.add_function(state, NAME, do_something)
  })
  
  // Start the MCP stdio server. no http server is provided at this time.
  mcp.start_stdio(server)
}

NAME :: "do_something"
// the signature is VERY helpful to llms to get a basic idea of the api 
// without needing to pull full docs
SIG :: `do_something({ str = "string to do something with" })`
DESC :: "it does... something"
Input :: struct { str: string }
Output :: struct { str: string }
// it is possible to write your own lua wrapper `proc "c" ()` style handlers, 
// and register them with `lua.register()`, but for simple calls and printing
// output, this style is easiest and most ergonomic.
do_something :: proc(params: Input, state: ^lua.State) -> (result: Output) {
  // this gets printed as output in the tool call response to the LLM
  mcp.lua_print(state, "do_something was called with input:", params.str)
  // printf style works too, supports all 4 of print/printf/println/printfln
  mcp.lua_printf(state, "do_something likes your input: %s,", params.str)
  
  if params.str == "BAD_INPUT" {
    // this treats the result as a fatal error, and this call will be
    // reported back as an error to the LLM. as with lua_print* the 
    // lua_eprint also supports all 4 variants
    mcp.lua_eprintln(state, "do not send me bad input :(")
    // immediately after return, before marshaling output params, the 
    // wrapper function will know that we errored because we used a
    // `mcp.lua_eprint*` call, and it will trigger a lua.error()
    return
  }
  
  if params.str == "OTHER_BAD_INPUT" {
    // can also do this, which is the same as doing
    // `lua.pushstring(state, "msg"); lua.error(state)` except in one call
    // since we're calling abort() directly, its best to return our own
    // lua function name here (normally when we use the `mcp.lua_eprint*` procs, 
    // the lua_wrapper that mcp.add_function() wraps us in will handle this,
    // but the lua.error() longjmp will bypass that, so this will let the llm 
    // know what function call errored)
    mcp.lua_abort(state, "[do_something()] your input sucks")
    // technically not needed b/c lua.error() will longjmp us out of the 
    // entire lua.L_dostring() call, but its nice to put for readability
    return 
  }
  
  // by default this proc is run within a dynamic arena allocator, so allocate 
  // whatever you want and it'll get cleaned up automatically at the end of the 
  // `evaluate` tool call, after your output has been marshaled into a lua table.
  // see examples/basic/manual.odin for a comparison of both memory management 
  // strategies as well as the Input/Output auto-marshaling to/from lua tables.
  result.str = strings.concatenate({"You said: ", params.str})
  return
}

// docs in luadoc format
DOCS: string: `
---@class DoSomethingParams
---@field str string The input string to process

---@class DoSomethingResult
---@field str string The processed output string

---Returns AND prints its input
---@param params DoSomethingParams
---@return DoSomethingResult
function do_something(params) 
  -- implemented in native code
end 
`

```

### Miskatonic MCP

This is an Odin MCP SDK that behaves differently from the traditional/official MCP-SDK's listed at model context protocol, in favor of the Sandboxed Code-Exec style dicussed by [Anthropic](https://www.anthropic.com/engineering/code-execution-with-mcp) and [Cloudflare](https://blog.cloudflare.com/code-mode/).

Unlike the above-mentioned blog posts, which advocate for LLMs running Typescript code in a Docker or Cloud container sandbox, this project opts for a more streamlined approach using an in-process lua sandbox, and instead of tools you expose api functions to the lua sandbox, where the LLM writes lua to interact with your mcp server, and prints out the data it wants rather than large blocks of context-hungry json data. Your api is documented with luadoc comments and implemented in Odin procs (see [weather.lua](examples/basic/weather.lua) and [weather.odin](examples/basic/weather.odin) from the [basic example server](examples/basic))

Only four tools are provided to LLMs:

- **evaluate**: LLM provides a block of lua code to execute in the lua sandbox
- **search**: A tf-idf powered search of all lua api functions available within the sandbox based on the content of the luadoc api docs
- **list**: Lists only the name and description of each function available
- **docs**: look up the luadoc documenation for a single api function

The only other MCP-SDK features that support is planned for are user-initiated prompts (slash commands), though client support for these is incredibly limited currently, so it is not a priority.

Currently still a work in progress. Haven't bothered actually implementing the mcp protocol or transport layers yet, those are the boring parts. :> Sandbox evaluate and basic api search backend support are working.

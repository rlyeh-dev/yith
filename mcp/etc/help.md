## Overview of Lua Evaluation Environment

This MCP provides a code evaluation environment using lua. Rather than traditional MCP tools, the core tool provided to you is called `evaluate`, where you may call lua api functions, and print() out the results you wish to process, keeping your token context usage low and getting the exact specific information you need.

You may also use the `list` (show all lua api functions available to you), `search` (search api calls & documentation to find the api call you need), and `docs` (returns the luadoc api docs for a particular api function). 

Your lua environment always has access to the `strings`, `tables`, and `math` lua libs. 

Anything your lua code prints with `print()` will be included in the results of the API call.

Some api functions themselves may `print()` output. Their api documentation should mention this.

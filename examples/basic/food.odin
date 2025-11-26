package basic_mcp

import mcp "../../mcp"
import "core:fmt"
import "core:math/rand"
import "core:strings"
import lua "vendor:lua/5.4"

Food_Service_Input :: struct {
	food:  string,
	count: i64,
}

Food_Service_Output :: struct {
	food: string,
	cost: f64,
}

setup_food_service :: proc(server: ^mcp.Server) {
	name, sig, desc ::
		"simple_food_service", `simple_food_service({food:"strawberry", count:7})`, "Gives you some of your favorite food"
	docs: string : #load("food.lua")

	mcp.add_documentation(server, name, sig, desc, docs)
	mcp.setup(server, proc(state: ^lua.State) {
		mcp.add_function(state, name, food_service_tool)
	})
}

food_service_tool :: proc(input: Food_Service_Input, state: ^lua.State) -> (output: Food_Service_Output) {
	// mcp provides print / printf / error / errorf procs that print to the output LLM receives from tool call
	mcp.print(state, "lol im printing for you")
	if input.food == "cherry" {
		// mcp.error(state, )
		mcp.abort(state, "You can't have ANY OF my cherries THEY ARE MINE")
		return
	}

	if input.count > 10 {
		// this syntax is also supported for error/errorf/print/printf
		mcp.error(state, "You can't have more than 10 of any one food")
		return
	}

	// no delete needed, all tools are in an arena allocator
	out := make([dynamic]string)

	for i in 0 ..< input.count {
		append(&out, input.food)
	}

	output.food = strings.join(out[:], ", ")
	output.cost = rand.float64() * 50

	fmt.eprintln("UH-OH: ", output)

	return
}

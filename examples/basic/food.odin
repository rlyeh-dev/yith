package basic_mcp

import mcp "../../mcp"
import "core:math/rand"
import "core:strings"

Food_Service_Input :: struct {
	food:  string,
	count: i64,
}

Food_Service_Output :: struct {
	food: string,
	cost: f64,
}

setup_food_service :: proc(server: ^mcp.Server) {
	name :: "simple_food_service"
	sig :: `simple_food_service({food:"strawberry", count:7})`
	description :: "Gives you some of your favorite food"
	docs: string : #load("food.lua")
	In :: Food_Service_Input
	Out :: Food_Service_Output

	mcp.add_documentation(server, name, sig, description, docs)

	mcp.setup(server, proc(sandbox: mcp.Sandbox_Init) {
		mcp.add_function(sandbox, name, food_service_tool)
	})
}

food_service_tool :: proc(input: Food_Service_Input, sandbox: mcp.Sandbox) -> (output: Food_Service_Output) {
	// mcp provides sandbox_print / sandbox_printf / sandbox_error / sandbox_errorf procs
	mcp.sandbox_print(sandbox, "lol im printing for you")
	if input.food == "cherry" {
		mcp.sandbox_error(sandbox, "You can't have ANY OF my cherries THEY ARE MINE")
		return
	}

	if input.count > 10 {
		// this syntax is also supported for error/errorf/print/printf
		sandbox->error("You can't have more than 10 of any one food")
		return
	}

	// no delete needed, all tools are in an arena allocator
	out := make([dynamic]string)

	for i in 0 ..< input.count {
		append(&out, input.food)
	}

	output.food = strings.join(out[:], ", ")
	output.cost = rand.float64() * 50

	return
}

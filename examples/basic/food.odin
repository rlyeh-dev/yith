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
	description :: "Gives you some of your favorite food"
	docs: string : #load("food.lua")
	In :: Food_Service_Input
	Out :: Food_Service_Output

	mcp.register_api_docs(server, name, description, docs)

	mcp.register_sandbox_setup(server, proc(sandbox: mcp.Sandbox) {
		mcp.register_sandbox_function(sandbox, In, Out, name, food_service_tool)
	})
}

food_service_tool :: proc(
	input: Food_Service_Input,
) -> (
	output: Food_Service_Output,
	error: string,
) {
	if input.food == "cherry" {
		error = "You can't have ANY OF my cherries THEY ARE MINE"
		return
	}

	if input.count > 10 {
		error = "You can't have more than 10 of any one food"
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

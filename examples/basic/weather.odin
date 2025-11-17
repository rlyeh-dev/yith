package basic_mcp

import mcp "../../mcp"
import "core:fmt"
import lua "vendor:lua/5.4"

Weather_Params :: struct {
	location: string,
}

Weather_Error :: enum {
	None,
	Location_Unknown,
}

Weather_Report_Extended :: struct {
	kelvin:     f64,
	celsius:    f64,
	fahrenheit: f64,
	conditions: string,
	advisory:   string,
}

Weather_Report :: struct {
	location:    string,
	temperature: f64,
	conditions:  string,
	advisory:    string,
}


interplanetary_weather :: proc(
	params: Weather_Params,
) -> (
	report: Weather_Report_Extended,
	error: string,
) {

	err: Weather_Error
	if report, err = weather_lookup(params.location); err != .None {
		error = fmt.aprintf("Weather Lookup Error: %w", err)
	}

	return
}

weather_lookup :: proc(loc: string) -> (weather: Weather_Report_Extended, error: Weather_Error) {
	for entry in weather_db {
		if loc == entry.location {
			weather = Weather_Report_Extended {
				kelvin     = entry.temperature,
				celsius    = to_c(entry.temperature),
				fahrenheit = to_f(entry.temperature),
				conditions = entry.conditions,
				advisory   = entry.advisory,
			}
			return
		}
	}
	error = .Location_Unknown
	return
}

setup_interplanetary_weather :: proc(server: ^mcp.Mcp_Server) {
	WEATHER_TOOL :: "interplanetary_weather"
	setup :: proc(state: ^lua.State) {
		mcp.register_typed_lua_handler(
			state,
			Weather_Params,
			Weather_Report_Extended,
			WEATHER_TOOL,
			interplanetary_weather,
		)
	}
	mcp.register_mcp_api(
		server,
		name = WEATHER_TOOL,
		description = "whether you're on mars, io, or surfing the asteroid belt, we've got your weather conditions covered",
		docs = #load("weather.lua"),
		setup = setup,
	)
}

to_c :: proc(k: f64) -> f64 {
	return k - 273.15
}

to_f :: proc(k: f64) -> f64 {
	return to_c(k) * 9 / 5 + 32
}

weather_db: [21]Weather_Report : {
	// Planets
	{
		location = "mercury",
		temperature = 440,
		conditions = "Extreme heat, no atmosphere",
		advisory = "Stay on the terminator line",
	},
	{
		location = "venus",
		temperature = 737,
		conditions = "Sulfuric acid clouds, crushing pressure",
		advisory = "Bring more than an umbrella",
	},
	{
		location = "earth",
		temperature = 288,
		conditions = "Partly cloudy",
		advisory = "Honestly pretty nice today",
	},
	{
		location = "mars",
		temperature = 210,
		conditions = "Dust storm season, low pressure",
		advisory = "Visibility near zero. Reschedule EVA",
	},
	{
		location = "jupiter",
		temperature = 165,
		conditions = "Perpetual superstorm activity",
		advisory = "Great Red Spot still going strong after 300+ years",
	},
	{
		location = "saturn",
		temperature = 134,
		conditions = "Hexagonal polar vortex, high winds",
		advisory = "North pole storm remains inexplicably geometric",
	},
	{
		location = "uranus",
		temperature = 76,
		conditions = "Featureless haze, sideways rotation",
		advisory = "Exceptionally boring. Check back in 42 years",
	},
	{
		location = "neptune",
		temperature = 72,
		conditions = "Supersonic winds, dark spot activity",
		advisory = "Fastest winds in solar system detected",
	},
	// Dwarf Planets
	{
		location = "pluto",
		temperature = 44,
		conditions = "Frozen nitrogen ice, thin atmosphere",
		advisory = "Heart-shaped glacier says hello",
	},
	{
		location = "ceres",
		temperature = 168,
		conditions = "Stable, icy surface patches",
		advisory = "Suspiciously bright spots remain unexplained",
	},
	{
		location = "eris",
		temperature = 30,
		conditions = "Distant, frozen, methane frost",
		advisory = "It's very far away. Like, really far",
	},
	{
		location = "makemake",
		temperature = 30,
		conditions = "Reddish surface, no atmosphere detected",
		advisory = "Named after Easter Island deity. Still no bunnies",
	},
	// Asteroid Belt
	{
		location = "asteroid_belt",
		temperature = 200,
		conditions = "Sparse, rocky, mostly empty space",
		advisory = "Despite what movies show, collision risk is basically zero",
	},
	// Moons
	{
		location = "luna",
		temperature = 250,
		conditions = "No atmosphere, temperature swings ±280K",
		advisory = "Dress in layers. Many, many layers",
	},
	{
		location = "phobos",
		temperature = 233,
		conditions = "Airless, cratered surface",
		advisory = "Orbital decay detected. Will crash into Mars eventually",
	},
	{
		location = "deimos",
		temperature = 233,
		conditions = "Small, irregular, low gravity",
		advisory = "You could probably jump into orbit from here",
	},
	{
		location = "io",
		temperature = 130,
		conditions = "Active volcanism, sulfur dioxide atmosphere",
		advisory = "400+ active volcanoes. Not a typo",
	},
	{
		location = "europa",
		temperature = 102,
		conditions = "Ice sheet surface, subsurface ocean suspected",
		advisory = "DO NOT land here. Seriously. Prime Directive stuff",
	},
	{
		location = "ganymede",
		temperature = 110,
		conditions = "Magnetic field active, thin oxygen atmosphere",
		advisory = "Only moon with its own magnetosphere. Overachiever",
	},
	{
		location = "titan",
		temperature = 94,
		conditions = "Thick nitrogen atmosphere, methane lakes",
		advisory = "Smells like a gas station, looks like orange smog",
	},
	{
		location = "enceladus",
		temperature = 75,
		conditions = "Ice geysers, subsurface ocean activity",
		advisory = "Cryovolcanoes shooting water into space right now",
	},
}

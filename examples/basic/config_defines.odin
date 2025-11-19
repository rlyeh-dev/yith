package basic_mcp

// use backtrace (only applies when ODIN_DEBUG)
USE_BACK :: #config(back, false)

// these show some outputs of stuff that should be covered by tests
// but its nice to just look at them for debugging sometimes
INSPECT_ALL :: #config(inspect, false)
INSPECT_EVAL :: #config(inspect_eval, false) || INSPECT_ALL
INSPECT_TFIDF :: #config(inspect_tfidf, false) || INSPECT_ALL
INSPECT_SEARCH :: #config(inspect_search, false) || INSPECT_ALL
INSPECT_LIST :: #config(inspect_list, false) || INSPECT_ALL
INSPECT_DOCS :: #config(inspect_docs, false) || INSPECT_ALL
INSPECT_HELP :: #config(inspect_help, false) || INSPECT_ALL
INSPECT_PROTO :: #config(inspect_proto, false) || INSPECT_ALL
INSPECT_ANY ::
	INSPECT_ALL ||
	INSPECT_EVAL ||
	INSPECT_TFIDF ||
	INSPECT_SEARCH ||
	INSPECT_LIST ||
	INSPECT_DOCS ||
	INSPECT_HELP ||
	INSPECT_PROTO

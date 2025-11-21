package yith

import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:text/regex"

// ezpz regexes for this

// scope is only used by fields but its ugly so separate it, and also we just ignore privacy, not interesting to index
SCOPE :: `(?:(?:private|public|package|protected) )?`

// field and param share these patterns
NAME_TYPE :: `(\w+)\?? (\S+)` // name + type are required
DESC :: `\s*(.+)?$` // description is optional, swallow the space ahead of it

// class name, ignore hierarchy that's more complex than anything will have
CLASS :: `^---@class (\w+)`

// boring once scope/name_type/desc are separate regex chunks
FIELD :: `^---@field ` + SCOPE + NAME_TYPE + DESC
PARAM :: `^---@param ` + NAME_TYPE + DESC

// function def we want to treat as identifier
// for all identifiers: decamel/desnake and use for example "foo_bar_baz" as ["foo_bar_baz", "foo", "bar", "baz"]
FN_DEF :: `^\s*function\s+(\w+)\(.*$` // function identifier should be treated specially
FN_EXP :: `^(local )?(\w+)\s*=\s*function.*$` // blah_blah = function style

// three annoying to parse forms of return
RETURN_A :: `^---@return (\w+)\s*$` // type only
RETURN_B :: `^---@return (\w+)\s+(?:(\w+)\s+)?#\s*(.*)$` // optional name with #comment
RETURN_C :: `^---@return (\w+)\s+(\w+)\s*(.*)$` // required name with optional comment

// enum values, could split on | and strip quotes but tokenize as prose is same
ENUM :: `^(?:\S+\|)+\S+$`

// ignore these they're boring
BORING_TYPES: [11]string : {
	`nil`,
	`boolean`,
	`number`,
	`integer`,
	`string`,
	`table`,
	`function`,
	`thread`,
	`any`,
	`unknown`,
	`userdata`,
}

tokenize_luadoc :: proc(
	results: ^[dynamic]string,
	documentation: string,
	description: string = "",
) {
	rgx_class, rgx_field, rgx_param, rgx_func_def, rgx_func_exp, rgx_return_a, rgx_return_b, rgx_return_c: regex.Regular_Expression
	err: regex.Error
	if rgx_class, err = regex.create(CLASS); err != nil {
		log.panicf("fix your regex (class): %w", err)
	}
	defer regex.destroy(rgx_class)
	if rgx_field, err = regex.create(FIELD); err != nil {
		log.panicf("fix your regex (field): %w", err)
	}
	defer regex.destroy(rgx_field)
	if rgx_param, err = regex.create(PARAM); err != nil {
		log.panicf("fix your regex (param): %w", err)
	}
	defer regex.destroy(rgx_param)
	if rgx_func_def, err = regex.create(FN_DEF); err != nil {
		log.panicf("fix your regex (func def): %w", err)
	}
	defer regex.destroy(rgx_func_def)
	if rgx_func_exp, err = regex.create(FN_EXP); err != nil {
		log.panicf("fix your regex (func expr): %w", err)
	}
	defer regex.destroy(rgx_func_exp)
	if rgx_return_a, err = regex.create(RETURN_A); err != nil {
		log.panicf("fix your regex (return a): %w", err)
	}
	defer regex.destroy(rgx_return_a)
	if rgx_return_b, err = regex.create(RETURN_B); err != nil {
		log.panicf("fix your regex (return b): %w", err)
	}
	defer regex.destroy(rgx_return_b)
	if rgx_return_c, err = regex.create(RETURN_C); err != nil {
		log.panicf("fix your regex (return c): %w", err)
	}
	defer regex.destroy(rgx_return_c)

	cap := regex.preallocate_capture()
	defer regex.destroy(cap)

	tokenize_prose(results, description)

	lines := strings.split_lines(documentation)
	defer delete(lines)

	matched: bool
	for line in lines {
		if len(line) == 0 {
			// skip empty lines early
			continue
		}

		if strings.starts_with(line, "---@diagnostic") {
			// disagnostic lines dont need indexing
			continue
		}

		if _, matched = regex.match(rgx_class, line, &cap); matched {
			tokenize_identifier(results, cap.groups[1])
			continue
		}

		if _, matched = regex.match(rgx_func_def, line, &cap); matched {
			tokenize_identifier(results, cap.groups[1])
			continue
		}

		if _, matched = regex.match(rgx_func_exp, line, &cap); matched {
			tokenize_identifier(results, cap.groups[1])
			continue
		}

		if _, matched = regex.match(rgx_return_a, line, &cap); matched {
			tokenize_type(results, cap.groups[1])
			continue
		}

		if _, matched = regex.match(rgx_return_b, line, &cap); matched {
			tokenize_type(results, cap.groups[1])
			tokenize_identifier(results, cap.groups[2])
			tokenize_prose(results, cap.groups[3])
			continue
		}

		if _, matched = regex.match(rgx_return_c, line, &cap); matched {
			tokenize_type(results, cap.groups[1])
			tokenize_identifier(results, cap.groups[2])
			tokenize_prose(results, cap.groups[3])
			continue
		}

		if _, matched = regex.match(rgx_field, line, &cap); matched {
			tokenize_identifier(results, cap.groups[1])
			tokenize_type(results, cap.groups[2])
			tokenize_prose(results, cap.groups[3])
			continue
		}

		if _, matched = regex.match(rgx_param, line, &cap); matched {
			tokenize_identifier(results, cap.groups[1])
			tokenize_type(results, cap.groups[2])
			tokenize_prose(results, cap.groups[3])
			continue
		}

		if strings.starts_with(line, "---@") {
			continue
		}

		// anything else is probably prose
		tokenize_prose(results, line)
	}

	return
}

tokenize_prose :: proc(results: ^[dynamic]string, str: string) {
	if len(str) == 0 {return}
	lstr := strings.to_lower(str)
	defer delete(lstr)

	from := -1 // we do -1 and from + 1 to avoid from == len(lstr) causing oob
	max := len(lstr) - 1
	for ch, i in lstr {
		is_sep := strings.is_separator(ch)
		is_max := i == max
		to := i
		if is_max && !is_sep {
			to = i + 1
		}
		substr := lstr[from + 1:to]

		if is_max || is_sep {
			if len(substr) > 2 {
				append(results, strings.clone(substr))
			}
			from = i
		}
	}
}

tokenize_identifier :: proc(results: ^[dynamic]string, str: string) {
	snaked := strings.to_snake_case(str)
	defer delete(snaked)
	append(results, strings.clone(snaked))
	if strings.contains(snaked, "_") {
		segments := strings.split(snaked, "_")
		defer delete(segments)
		for s in segments {
			append(results, strings.clone(s))
		}
	}
}

tokenize_type :: proc(results: ^[dynamic]string, str: string) {
	cap := regex.preallocate_capture()
	defer regex.destroy(cap)
	rgx_enum: regex.Regular_Expression
	err: regex.Error
	if rgx_enum, err = regex.create(ENUM); err != nil {
		log.panicf("fix your regex (enum): %w", err)
	}
	defer regex.destroy(rgx_enum)
	matched: bool

	for v in BORING_TYPES {
		if str == v {return}
	}

	if _, matched = regex.match(rgx_enum, str, &cap); matched {
		tokenize_prose(results, str) // prose basically does what we need here anyway
		return
	}

	tokenize_identifier(results, str)
}

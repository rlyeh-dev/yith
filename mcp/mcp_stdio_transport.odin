package yith

import "core:bufio"
import "core:os"
import "core:strings"

start_stdio :: proc(server: ^Server) {
	complete_setup(server)

	buf := [16384]u8{}
	lf := []u8{10}
	r: bufio.Reader
	bufio.reader_init_with_buf(&r, os.stream_from_handle(os.stdin), buf[:])
	defer bufio.reader_destroy(&r)

	for {
		line, err := bufio.reader_read_string(&r, '\n')
		if err != nil do break
		defer delete(line)

		line = strings.trim_right(line, "\r")
		if len(line) == 0 do continue

		resp, send, ok := handle_mcp_message(server, transmute([]u8)line)
		if !ok || !send do continue

		os.write(os.stdout, resp)
		os.write(os.stdout, lf)
	}
}

package olox

import "core:fmt"
import "core:mem"

compile :: proc(source: string) {
	init_scanner(source)
	line := -1
	for {
		token := scan_token()
		if token.line != line {
			fmt.printf("%4d ", token.line)
			line = token.line
		} else {
			fmt.printf("	|")
		}
		str := string(mem.ptr_to_bytes(token.start, token.length))
		fmt.printf("{} '{}'\n", token.type, str)

		if token.type == .EOF do break
	}
}

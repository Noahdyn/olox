package olox

import "core:fmt"
import "core:mem"

compile :: proc(source: string, chunk: ^Chunk) -> {
	init_scanner(source)
	advance()
	expression() 
	consume(.EOF, "Expect end of expression.")

}

advance :: proc() {
parser.previous = parser.current 

	for {
parser.current = scan_token()
		if parser.current.type != .ERROR do break 

		error_at_current(parser.current.start)
	}
}

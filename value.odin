package olox

import "core:fmt"

Value :: distinct f64

print_value :: proc(value: Value) {
	fmt.printf("%g", value)
}

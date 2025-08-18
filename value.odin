package olox

import "core:fmt"

ValueType :: enum {
	BOOL,
	NIL,
	NUMBER,
}

Value :: struct {
	type:    ValueType,
	variant: union {
		bool,
		f64,
	},
}

print_value :: proc(value: Value) {
	switch value.type {
	case .NUMBER:
		fmt.printf("%g", as_number(value))
	case .BOOL:
		fmt.printf(as_bool(value) ? "true" : "false")
	case .NIL:
		fmt.printf("nil")
	}
}

bool_val :: #force_inline proc(val: bool) -> Value {
	return Value{.BOOL, val}
}

number_val :: #force_inline proc(val: f64) -> Value {
	return Value{.NUMBER, val}
}

nil_val :: #force_inline proc() -> Value {
	return Value{.NIL, 0}
}

as_bool :: #force_inline proc(val: Value) -> bool {
	return val.variant.(bool)
}

as_number :: #force_inline proc(val: Value) -> f64 {
	return val.variant.(f64)
}

is_bool :: #force_inline proc(val: Value) -> bool {
	return val.type == .BOOL
}

is_number :: #force_inline proc(val: Value) -> bool {
	return val.type == .NUMBER
}

is_nil :: #force_inline proc(val: Value) -> bool {
	return val.type == .NIL
}

package olox

import "core:fmt"

ValueType :: enum {
	BOOL,
	NIL,
	NUMBER,
	OBJ,
}

Value :: struct {
	type:    ValueType,
	variant: union {
		bool,
		f64,
		^Obj,
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
	case .OBJ:
		print_object(value)
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


obj_val :: #force_inline proc(object: ^Obj) -> Value {
	return Value{.OBJ, object}
}

as_bool :: #force_inline proc(val: Value) -> bool {
	return val.variant.(bool)
}

as_number :: #force_inline proc(val: Value) -> f64 {
	return val.variant.(f64)
}

as_obj :: #force_inline proc(val: Value) -> ^Obj {
	return val.variant.(^Obj)
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

is_obj :: #force_inline proc(val: Value) -> bool {
	return val.type == .OBJ
}

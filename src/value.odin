package olox

import "core:fmt"

when NAN_BOXING {
	Value :: distinct u64

	SIGN_BIT: u64 : 0x8000000000000000
	QNAN: u64 : 0x7ffc000000000000

	TAG_NIL :: 1
	TAG_FALSE :: 2
	TAG_TRUE :: 3

	FALSE_VAL: u64 : QNAN | TAG_FALSE
	TRUE_VAL: u64 : QNAN | TAG_TRUE

	number_val :: #force_inline proc(num: f64) -> Value {
		return transmute(Value)transmute(u64)num
	}
	nil_val :: #force_inline proc() -> Value {
		return transmute(Value)(QNAN | TAG_NIL)
	}
	bool_val :: #force_inline proc(b: bool) -> Value {
		return Value(b ? TRUE_VAL : FALSE_VAL)
	}
	obj_val :: #force_inline proc(obj: ^Obj) -> Value {
		val := SIGN_BIT | QNAN | cast(u64)uintptr(obj)
		return Value(val)
	}

	is_number :: #force_inline proc(val: Value) -> bool {return (u64(val) & QNAN) != QNAN}
	is_nil :: #force_inline proc(val: Value) -> bool {
		return u64(val) == (QNAN | TAG_NIL)
	}
	is_bool :: #force_inline proc(val: Value) -> bool {
		return (u64(val) | 1) == TRUE_VAL
	}

	is_obj :: #force_inline proc(val: Value) -> bool {return(
			(u64(val) & (QNAN | SIGN_BIT)) ==
			(QNAN | SIGN_BIT) \
		)}

	as_bool :: #force_inline proc(val: Value) -> bool {
		return u64(val) == TRUE_VAL
	}
	as_obj :: #force_inline proc(val: Value) -> ^Obj {
		return cast(^Obj)uintptr(u64(val) & ~(SIGN_BIT | QNAN))
	}

	as_number :: #force_inline proc(val: Value) -> f64 {
		return transmute(f64)val
	}

	print_value :: proc(val: Value) {
		if (is_bool(val)) {
			fmt.printf("true" if as_bool(val) else "false")
		} else if (is_nil(val)) {
			fmt.printf("nil")
		} else if (is_number(val)) {
			fmt.printf("%v", as_number(val))
		} else if (is_obj(val)) {
			print_object(val)
		}
	}

	values_equal :: proc(a, b: Value) -> bool {
		if (is_number(a) && is_number(b)) {
			return as_number(a) == as_number(b)
		}
		return u64(a) == u64(b)
	}

} else {
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

	number_val :: #force_inline proc(val: f64) -> Value {
		return Value{.NUMBER, val}
	}
	nil_val :: #force_inline proc() -> Value {
		return Value{.NIL, 0}
	}
	bool_val :: #force_inline proc(val: bool) -> Value {
		return Value{.BOOL, val}
	}
	obj_val :: #force_inline proc(object: ^Obj) -> Value {
		return Value{.OBJ, object}
	}

	is_number :: #force_inline proc(val: Value) -> bool {
		return val.type == .NUMBER
	}
	is_nil :: #force_inline proc(val: Value) -> bool {
		return val.type == .NIL
	}
	is_bool :: #force_inline proc(val: Value) -> bool {
		return val.type == .BOOL
	}
	is_obj :: #force_inline proc(val: Value) -> bool {
		return val.type == .OBJ
	}

	as_bool :: #force_inline proc(val: Value) -> bool {
		return val.variant.(bool)
	}
	as_obj :: #force_inline proc(val: Value) -> ^Obj {
		return val.variant.(^Obj)
	}
	as_number :: #force_inline proc(val: Value) -> f64 {
		return val.variant.(f64)
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

	values_equal :: proc(a, b: Value) -> bool {
		if a.type != b.type do return false
		#partial switch a.type {
		case .BOOL:
			return as_bool(a) == as_bool(b)
		case .NIL:
			return true
		case .NUMBER:
			return as_number(a) == as_number(b)
		case .OBJ:
			return as_obj(a) == as_obj(b)
		case:
			return false // Unreachable.
		}
	}
}

package olox

import "core:fmt"

when NAN_BOXING {
	Value :: distinct u64

	SIGN_BIT: u64 : 0x8000000000000000
	QNAN: u64 : 0x7ffc000000000000
	FINAL_BIT: u64 : 0x0002000000000000

	TAG_NIL :: 1
	TAG_FALSE :: 2
	TAG_TRUE :: 3

	FALSE_VAL: u64 : QNAN | TAG_FALSE
	TRUE_VAL: u64 : QNAN | TAG_TRUE

	number_val :: #force_inline proc(num: f64, final: bool = false) -> Value {
		val := transmute(u64)num
		if final {
			if val & SIGN_BIT == 0 {
				val |= FINAL_BIT
			}
		}
		return transmute(Value)val
	}
	nil_val :: #force_inline proc(final: bool = false) -> Value {
		val := QNAN | TAG_NIL
		if final do val |= FINAL_BIT
		return transmute(Value)val
	}
	bool_val :: #force_inline proc(b: bool, final: bool = false) -> Value {
		val := b ? TRUE_VAL : FALSE_VAL
		if final do val |= FINAL_BIT
		return Value(val)
	}
	obj_val :: #force_inline proc(obj: ^Obj, final: bool = false) -> Value {
		val := SIGN_BIT | QNAN | cast(u64)uintptr(obj)
		if final do val |= FINAL_BIT
		return Value(val)
	}

	is_number :: #force_inline proc(val: Value) -> bool {return (u64(val) & QNAN) != QNAN}
	is_nil :: #force_inline proc(val: Value) -> bool {
		return (u64(val) & ~FINAL_BIT) == (QNAN | TAG_NIL)
	}
	is_bool :: #force_inline proc(val: Value) -> bool {
		return ((u64(val) & ~FINAL_BIT) | 1) == TRUE_VAL
	}

	is_obj :: #force_inline proc(val: Value) -> bool {return(
			(u64(val) & (QNAN | SIGN_BIT)) ==
			(QNAN | SIGN_BIT) \
		)}
	is_final :: #force_inline proc(val: Value) -> bool {
		if is_number(val) {
			raw := u64(val)
			if raw & FINAL_BIT != 0 {
				original := raw & ~FINAL_BIT
				return (transmute(f64)original >= 0) || (raw & SIGN_BIT == 0)
			}
			return false
		} else {
			return (u64(val) & FINAL_BIT) != 0
		}
	}

	as_bool :: #force_inline proc(val: Value) -> bool {
		return (u64(val) & ~FINAL_BIT) == TRUE_VAL
	}
	as_obj :: #force_inline proc(val: Value) -> ^Obj {
		return cast(^Obj)uintptr(u64(val) & ~(SIGN_BIT | QNAN | FINAL_BIT))
	}

	as_number :: #force_inline proc(val: Value) -> f64 {
		raw := u64(val)
		if raw & FINAL_BIT != 0 {
			raw &= ~FINAL_BIT
		}
		return transmute(f64)raw
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

		if is_final(val) {
			fmt.printf(" (final)")
		}
	}

	values_equal :: proc(a, b: Value) -> bool {
		if (is_number(a) && is_number(b)) {
			return as_number(a) == as_number(b)
		}
		return (u64(a) & ~FINAL_BIT) == (u64(b) & ~FINAL_BIT)
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
		final:   bool,
		variant: union {
			bool,
			f64,
			^Obj,
		},
	}

	number_val :: #force_inline proc(val: f64, final: bool = false) -> Value {
		return Value{.NUMBER, final, val}}
	nil_val :: #force_inline proc(final: bool = false) -> Value {
		return Value{.NIL, final, 0}
	}
	bool_val :: #force_inline proc(val: bool, final: bool = false) -> Value {
		return Value{.BOOL, final, val}
	}
	obj_val :: #force_inline proc(object: ^Obj, final: bool = false) -> Value {
		return Value{.OBJ, final, object}
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
	is_final :: #force_inline proc(val: Value) -> bool {
		return val.final
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

make_final :: proc(val: Value) -> Value {
	if is_final(val) do return val

	when NAN_BOXING {
		if is_number(val) {
			return number_val(as_number(val), final = true)
		} else if is_bool(val) {
			return bool_val(as_bool(val), final = true)
		} else if is_nil(val) {
			return nil_val(final = true)
		} else if is_obj(val) {
			return obj_val(as_obj(val), final = true)
		}
	} else {
		result := val
		result.final = true
		return result
	}

	return val // Fallback, shouldn't happen
}

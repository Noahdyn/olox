package olox

import "core:fmt"
import "core:strings"

NativeFn :: proc(arg_count: int, args: []Value) -> Value

ObjType :: enum {
	String,
	Function,
	Native,
}

Obj :: struct {
	type: ObjType,
	next: ^Obj,
}

ObjString :: struct {
	using obj: Obj,
	str:       string,
	hash:      u32,
}

ObjFunction :: struct {
	using obj: Obj,
	arity:     int,
	chunk:     Chunk,
	name:      ^ObjString,
}

ObjNative :: struct {
	using obj: Obj,
	function:  NativeFn,
}


new_function :: proc() -> ^ObjFunction {
	function := allocate_obj(ObjFunction, .Function)
	return function
}

new_native :: proc(function: NativeFn) -> ^ObjNative {
	native := allocate_obj(ObjNative, .Native)
	native.function = function
	return native
}


is_string :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .String)
}

is_obj_type :: #force_inline proc(val: Value, type: ObjType) -> bool {
	return is_obj(val) && as_obj(val).type == type
}

is_function :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Function)
}

is_native :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Native)
}

as_function :: #force_inline proc(val: Value) -> ^ObjFunction {
	return cast(^ObjFunction)(as_obj(val))
}

as_native :: #force_inline proc(val: Value) -> NativeFn {
	return (cast(^ObjNative)(as_obj(val))).function
}

copy_string :: proc(str: string) -> ^ObjString {
	s := strings.clone(str)
	hash := hash_string(s)
	interned := table_find_string(&vm.strings, s, hash)
	if interned != nil {
		return interned
	}
	return allocate_string(s, hash)
}

print_function :: proc(function: ^ObjFunction) {
	if function.name == nil {
		fmt.printf("<script>")
		return
	}
	fmt.printf("<fn %s>", function.name.str)
}

allocate_string :: proc(str: string, hash: u32) -> ^ObjString {
	s := allocate_obj(ObjString, .String)
	s.str = str
	s.hash = hash
	table_set(&vm.strings, obj_val(s), nil_val())
	return s
}

hash_string :: proc(str: string) -> u32 {
	hash: u32 = 2166136261
	for i := 0; i < len(str); i += 1 {
		hash ~= u32(str[i])
		hash *= 16777619
	}
	return hash
}

allocate_obj :: proc($T: typeid, type: ObjType) -> ^T {
	object := new(T)
	object.type = type
	object.next = vm.objects
	vm.objects = object
	return object
}

print_object :: proc(val: Value) {
	switch as_obj(val).type {
	case .String:
		str_obj := cast(^ObjString)as_obj(val)
		fmt.printf("%s", str_obj.str)
	case .Function:
		print_function(as_function(val))
	case .Native:
		fmt.print("<native fn>")
	}
}

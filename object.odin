package olox

import "core:fmt"
import "core:strings"

ObjType :: enum {
	String,
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

is_string :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .String)
}

is_obj_type :: #force_inline proc(val: Value, type: ObjType) -> bool {
	return is_obj(val) && as_obj(val).type == type
}

copy_string :: proc(str: string) -> ^ObjString {
	s := strings.clone(str)
	hash := hash_string(s)
	interned := table_find_string(&vm.strings, s, hash)
	if interned != nil do return interned
	return allocate_string(s, hash)
}

allocate_string :: proc(str: string, hash: u32) -> ^ObjString {
	s := allocate_obj(ObjString, .String)
	s.str = str
	s.hash = hash
	table_set(&vm.strings, s, nil_val())
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
	}
}

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
}

is_string :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .String)
}

is_obj_type :: #force_inline proc(val: Value, type: ObjType) -> bool {
	return is_obj(val) && as_obj(val).type == type
}

copy_string :: proc(str: string) -> ^ObjString {
	s := strings.clone(str)
	return allocate_string(s)
}

allocate_string :: proc(str: string) -> ^ObjString {
	s := allocate_obj(ObjString, .String)
	s.str = str
	return s
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

package olox

import "core:fmt"
import "core:strings"

NativeFn :: proc(arg_count: int, args: []Value) -> Value

ObjType :: enum {
	String,
	Function,
	Closure,
	Upvalue,
	Native,
	Class,
	Bound_Method,
	Instance,
}

Obj :: struct {
	type:      ObjType,
	next:      ^Obj,
	is_marked: bool,
}

ObjString :: struct {
	using obj: Obj,
	str:       string,
	hash:      u32,
}

ObjFunction :: struct {
	using obj:     Obj,
	upvalue_count: int,
	arity:         int,
	chunk:         Chunk,
	name:          ^ObjString,
}

ObjClosure :: struct {
	using obj: Obj,
	function:  ^ObjFunction,
	upvalues:  [dynamic]^ObjUpvalue,
}

ObjClass :: struct {
	using obj: Obj,
	name:      ^ObjString,
	methods:   Table,
}

ObjInstance :: struct {
	using obj: Obj,
	class:     ^ObjClass,
	fields:    Table,
}

ObjBoundMethod :: struct {
	using obj: Obj,
	receiver:  Value,
	method:    ^ObjClosure,
}

ObjUpvalue :: struct {
	using obj:    Obj,
	location:     ^Value,
	closed:       Value,
	next_upvalue: ^ObjUpvalue,
}

ObjNative :: struct {
	using obj: Obj,
	function:  NativeFn,
}


new_function :: proc() -> ^ObjFunction {
	function := allocate_obj(ObjFunction, .Function)
	return function
}

new_closure :: proc(function: ^ObjFunction) -> ^ObjClosure {
	upvalues := make([dynamic]^ObjUpvalue, function.upvalue_count)
	closure := allocate_obj(ObjClosure, .Closure)
	closure.upvalues = upvalues
	closure.function = function
	return closure
}

new_upvalue :: proc(slot: ^Value) -> ^ObjUpvalue {
	upvalue := allocate_obj(ObjUpvalue, .Upvalue)
	upvalue.closed = nil_val()
	upvalue.location = slot
	return upvalue
}

new_native :: proc(function: NativeFn) -> ^ObjNative {
	native := allocate_obj(ObjNative, .Native)
	native.function = function
	return native
}

new_class :: proc(name: ^ObjString) -> ^ObjClass {
	class := allocate_obj(ObjClass, .Class)
	class.name = name
	return class
}

new_instance :: proc(class: ^ObjClass) -> ^ObjInstance {
	instance := allocate_obj(ObjInstance, .Instance)
	instance.class = class
	return instance
}

new_bound_method :: proc(receiver: Value, method: ^ObjClosure) -> ^ObjBoundMethod {
	bound := allocate_obj(ObjBoundMethod, .Bound_Method)
	bound.receiver = receiver
	bound.method = method
	return bound
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

is_closure :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Closure)
}

is_class :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Class)
}

is_instance :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Instance)
}

is_bound_method :: #force_inline proc(val: Value) -> bool {
	return is_obj_type(val, .Bound_Method)
}

as_function :: #force_inline proc(val: Value) -> ^ObjFunction {
	return cast(^ObjFunction)(as_obj(val))
}

as_closure :: #force_inline proc(val: Value) -> ^ObjClosure {
	return cast(^ObjClosure)(as_obj(val))
}

as_class :: #force_inline proc(val: Value) -> ^ObjClass {
	return cast(^ObjClass)(as_obj(val))
}

as_instance :: #force_inline proc(val: Value) -> ^ObjInstance {
	return cast(^ObjInstance)(as_obj(val))
}

as_bound_method :: #force_inline proc(val: Value) -> ^ObjBoundMethod {
	return cast(^ObjBoundMethod)(as_obj(val))
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
	push_stack(obj_val(s))
	table_set(&vm.strings, obj_val(s), nil_val())
	pop_stack()
	return s
}

hash_string :: proc(str: string) -> u32 {
	hash: u32 = 2166136261
	for i in 0 ..< len(str) {
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
	vm.bytes_allocated += size_of(T)

	if (vm.bytes_allocated > vm.next_gc) {
		collect_garbage()
	}

	if DEBUG_LOG_GC {
		fmt.println("%p allocate %v for %v", object, size_of(T), type)
	}
	return object
}

print_object :: proc(val: Value) {
	switch as_obj(val).type {
	case .String:
		str_obj := cast(^ObjString)as_obj(val)
		fmt.printf("%v", str_obj.str)
	case .Function:
		print_function(as_function(val))
	case .Native:
		fmt.print("<native fn>")
	case .Upvalue:
		fmt.printf("upvalue")
	case .Closure:
		print_function(as_closure(val).function)
	case .Class:
		fmt.printf("%v", as_class(val).name.str)
	case .Instance:
		fmt.printf("%v instance", as_instance(val).class.name.str)
	case .Bound_Method:
		print_function(as_bound_method(val).method.function)
	}
}

package olox

import "core:fmt"
import "core:mem"
import "core:strings"


VM :: struct {
	chunk:          ^Chunk,
	//instruction pointer
	ip:             ^u8,
	stack_capacity: int,
	stack:          [dynamic]Value,
	globals:        Table,
	strings:        Table,
	objects:        ^Obj,
}

InterpretResult :: enum {
	OK,
	COMPILE_ERROR,
	RUNTIME_ERROR,
}

vm: VM
DEBUG_TRACE_EXECUTION := false

init_VM :: proc() {
	reset_stack()
}

reset_stack :: proc() {
	clear(&vm.stack)
}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintf(format, ..args)
	fmt.eprintln()
	instruction := uintptr(vm.ip) - uintptr(raw_data(vm.chunk.code)) - 1
	line := get_line(vm.chunk, int(instruction))
	fmt.eprintf("[line %d] in script\n", line)
	reset_stack()
}

free_VM :: proc() {
	free_table(&vm.strings)
	free_table(&vm.globals)
	delete(vm.stack)
	free_objects()
}

free_objects :: proc() {
	object := vm.objects
	for object != nil {
		next := object.next
		free_object(object)
		object = next
	}
}

free_object :: proc(object: ^Obj) {
	switch object.type {
	case .String:
		o := cast(^ObjString)object
		delete(o.str)
		free(o)
	}
}

interpret :: proc(source: string) -> InterpretResult {
	chunk: Chunk
	defer free_chunk(&chunk)

	if !compile(source, &chunk) {
		return .COMPILE_ERROR
	}
	vm.chunk = &chunk
	vm.ip = raw_data(vm.chunk.code)
	res := run()

	return res
}

push_stack :: proc(val: Value) {
	append(&vm.stack, val)
}

pop_stack :: proc() -> Value {
	return pop(&vm.stack)
}

run :: proc() -> InterpretResult {
	for {
		if DEBUG_TRACE_EXECUTION {
			disassemble_instruction(
				vm.chunk,
				int(uintptr(vm.ip) - uintptr(raw_data(vm.chunk.code))),
			)
			fmt.printf("          ")
			for val in vm.stack {
				fmt.printf("[ ")
				print_value(val)
				fmt.printf(" ]")
			}
			fmt.printf("\n")
		}
		instruction := read_byte()
		switch (instruction) {
		case u8(OpCode.RETURN):
			return InterpretResult.OK
		case u8(OpCode.CONSTANT):
			constant := read_constant()
			push_stack(constant)
		case u8(OpCode.CONSTANT_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			constant_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			constant := vm.chunk.constants[constant_index]
			push_stack(constant)
		case u8(OpCode.NEGATE):
			last_elem := &vm.stack[len(vm.stack) - 1]
			if !is_number(last_elem^) {
				runtime_error("Operand must be a number.")
				return .RUNTIME_ERROR
			}
			last_elem^ = number_val(-as_number(last_elem^))
		case u8(OpCode.ADD):
			if is_string(peek_vm(0)) && is_string(peek_vm(1)) {
				concatenate()
			} else if is_number(peek_vm(0)) || is_number(peek_vm(1)) {
				b := as_number(pop_stack())
				a := as_number(pop_stack())
				push_stack(number_val(a + b))

			} else {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
		case u8(OpCode.SUBTRACT):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a - b))
		case u8(OpCode.MULTIPLY):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a * b))
		case u8(OpCode.DIVIDE):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a / b))
		case u8(OpCode.NIL):
			push_stack(nil_val())
		case u8(OpCode.TRUE):
			push_stack(bool_val(true))
		case u8(OpCode.FALSE):
			push_stack(bool_val(false))
		case u8(OpCode.NOT):
			last_elem := &vm.stack[len(vm.stack) - 1]
			if !is_bool(last_elem^) {
				runtime_error("Operand must be boolean.")
				return .RUNTIME_ERROR
			}
			last_elem^ = bool_val(is_falsey(last_elem^))
		case u8(OpCode.EQUAL):
			b := pop_stack()
			a := pop_stack()
			push_stack(bool_val(values_equal(a, b)))
		case u8(OpCode.GREATER):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(bool_val(a > b))
		case u8(OpCode.LESS):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(bool_val(a < b))
		case u8(OpCode.PRINT):
			print_value(pop_stack())
			fmt.println()
		case u8(OpCode.POP):
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL):
			name := read_constant()
			table_set(&vm.globals, name, peek_vm(0))
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_FINAL):
			name := read_constant()
			val := peek_vm(0)
			val.final = true
			table_set(&vm.globals, name, val)
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			name_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			name := vm.chunk.constants[name_index]
			table_set(&vm.globals, name, peek_vm(0))
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_FINAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			name_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			name := vm.chunk.constants[name_index]
			val := peek_vm(0)
			val.final = true
			table_set(&vm.globals, name, val)
			pop_stack()
		case u8(OpCode.GET_GLOBAL):
			key := read_constant()
			value, ok := table_get(&vm.globals, key)
			if !ok {
				runtime_error("Undefined variable '%s'", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			push_stack(value)
		case u8(OpCode.GET_GLOBAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			key_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			key := vm.chunk.constants[key_index]
			value, ok := table_get(&vm.globals, key)
			if !ok {
				runtime_error("Undefined variable '%s'", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			push_stack(value)
		case u8(OpCode.SET_GLOBAL):
			key := read_constant()
			val, found := table_get(&vm.globals, key)
			if !found {
				runtime_error("Undefined variable '%s'.", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			if val.final {
				runtime_error(
					"Cannot assign to final variable '%s'.",
					(cast(^ObjString)as_obj(key)).str,
				)
				return .RUNTIME_ERROR
			}
			table_set(&vm.globals, key, peek_vm(0))
		case u8(OpCode.SET_GLOBAL_LONG):
			//TODO: byte1-3 lesen zu einer procedure machen
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			key_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			key := vm.chunk.constants[key_index]
			val, found := table_get(&vm.globals, key)
			if !found {
				runtime_error("Undefined variable '%s'.", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			if val.final {
				runtime_error(
					"Cannot assign to final variable '%s'.",
					(cast(^ObjString)as_obj(key)).str,
				)
				return .RUNTIME_ERROR
			}
			table_set(&vm.globals, key, peek_vm(0))
		case u8(OpCode.JUMP_IF_FALSE):
			offset := read_short()
			if is_falsey(peek_vm(0)) do vm.ip = mem.ptr_offset(vm.ip, offset)
		case u8(OpCode.JUMP):
			offset := read_short()
			vm.ip = mem.ptr_offset(vm.ip, offset)
		case u8(OpCode.GET_LOCAL):
			slot := read_byte()
			push_stack(vm.stack[slot])
		case u8(OpCode.SET_LOCAL):
			slot := read_byte()
			vm.stack[slot] = peek_vm(0)
		case u8(OpCode.LOOP):
			offset := read_short()
			vm.ip = mem.ptr_offset(vm.ip, -offset)
		case u8(OpCode.DUPLICATE):
			val := peek_vm(0)
			push_stack(val)
		}
	}
}

concatenate :: proc() {
	b := cast(^ObjString)as_obj(pop_stack())
	a := cast(^ObjString)as_obj(pop_stack())
	new_string := strings.concatenate({a.str, b.str})
	hash := hash_string(new_string)
	result := allocate_string(new_string, hash)
	push_stack(obj_val(result))
}

read_byte :: #force_inline proc() -> u8 {
	byte := vm.ip^
	vm.ip = mem.ptr_offset(vm.ip, 1)
	return byte
}

read_constant :: #force_inline proc() -> Value {
	return vm.chunk.constants[read_byte()]
}

read_string :: #force_inline proc() -> ^ObjString {
	return cast(^ObjString)as_obj(read_constant())
}

read_short :: #force_inline proc() -> u16 {
	vm.ip = mem.ptr_offset(vm.ip, 2)
	return u16((mem.ptr_offset(vm.ip, -2))^) << 8 | u16((mem.ptr_offset(vm.ip, -1))^)

}

peek_vm :: proc(distance: int) -> Value {
	return vm.stack[len(vm.stack) - 1 - distance]
}

is_falsey :: proc(val: Value) -> bool {
	return is_nil(val) || (is_bool(val) && !as_bool(val))
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

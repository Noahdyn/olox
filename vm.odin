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
			print_value(pop_stack())
			fmt.printf("\n")
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

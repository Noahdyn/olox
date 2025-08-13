package olox

import "core:fmt"
import "core:mem"

STACK_MAX :: 512

VM :: struct {
	chunk:          ^Chunk,
	//instruction pointer
	ip:             ^u8,
	stack_capacity: int,
	stack:          [STACK_MAX]Value,
	stack_top:      ^Value,
}

InterpretResult :: enum {
	OK,
	COMPILE_ERROR,
	RUNTIME_ERROR,
}

vm: VM
DEBUG_TRACE_EXECUTION := true

init_VM :: proc() {
	reset_stack()
}

reset_stack :: proc() {
	vm.stack_top = &vm.stack[0]
}

free_VM :: proc() {}

interpret :: proc(chunk: ^Chunk) -> InterpretResult {
	vm.chunk = chunk
	vm.ip = raw_data(vm.chunk.code)
	return run()
}

push :: proc(val: Value) {
	vm.stack_top^ = val
	vm.stack_top = mem.ptr_offset(vm.stack_top, 1)
}

pop :: proc() -> Value {
	vm.stack_top = mem.ptr_offset(vm.stack_top, -1)
	return vm.stack_top^
}

run :: proc() -> InterpretResult {
	for {
		if DEBUG_TRACE_EXECUTION {
			disassemble_instruction(
				vm.chunk,
				int(uintptr(vm.ip) - uintptr(raw_data(vm.chunk.code))),
			)
			fmt.printf("          ")
			for ptr := &vm.stack[0]; ptr < vm.stack_top; ptr = mem.ptr_offset(ptr, 1) {
				fmt.printf("[ ")
				print_value(ptr^)
				fmt.printf(" ]")
			}


			fmt.printf("\n")
		}
		instruction := read_byte()
		switch (instruction) {
		case u8(OpCode.RETURN):
			print_value(pop())
			fmt.printf("/n")
			return InterpretResult.OK
		case u8(OpCode.CONSTANT):
			constant := read_constant()
			push(constant)
			print_value(constant)
			fmt.printf("\n")
			break
		case u8(OpCode.CONSTANT_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			constant_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			constant := vm.chunk.constants[constant_index]
			push(constant)
			print_value(constant)
			fmt.printf("\n")
			break
		case u8(OpCode.NEGATE):
			last_elem := mem.ptr_offset(vm.stack_top, -1)
			last_elem^ = -last_elem^
			break
		case u8(OpCode.ADD):
			b := f64(pop())
			a := f64(pop())
			push(Value(a + b))
			break
		case u8(OpCode.SUBTRACT):
			b := f64(pop())
			a := f64(pop())
			push(Value(a - b))
			break
		case u8(OpCode.MULTIPLY):
			b := f64(pop())
			a := f64(pop())
			push(Value(a * b))
			break
		case u8(OpCode.DIVIDE):
			b := f64(pop())
			a := f64(pop())
			push(Value(a / b))
			break
		}
	}
}

read_byte :: #force_inline proc() -> u8 {
	byte := vm.ip^
	vm.ip = mem.ptr_offset(vm.ip, 1)
	return byte
}

read_constant :: #force_inline proc() -> Value {
	return vm.chunk.constants[read_byte()]
}

//TODO: wahrscheinlich loeschen ist macro in c
// binary_op :: #force_inline proc(_: op) {
//
// 	b: double = pop()
// 	a: double = pop()
// 	push(a op b)
//
// }

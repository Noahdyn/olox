package olox

import "core:fmt"
import "core:mem"


VM :: struct {
	chunk:          ^Chunk,
	//instruction pointer
	ip:             ^u8,
	stack_capacity: int,
	stack:          [dynamic]Value,
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
	clear(&vm.stack)
}

free_VM :: proc() {
	delete(vm.stack)
}

interpret :: proc(source: string) -> InterpretResult {
	compile(source)
	return .OK
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
			fmt.printf("/n")
			return InterpretResult.OK
		case u8(OpCode.CONSTANT):
			constant := read_constant()
			push_stack(constant)
			print_value(constant)
			fmt.printf("\n")
			break
		case u8(OpCode.CONSTANT_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			constant_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			constant := vm.chunk.constants[constant_index]
			push_stack(constant)
			print_value(constant)
			fmt.printf("\n")
			break
		case u8(OpCode.NEGATE):
			last_elem := &vm.stack[len(vm.stack) - 1]
			last_elem^ = -last_elem^
			break
		case u8(OpCode.ADD):
			b := f64(pop_stack())
			a := f64(pop_stack())
			push_stack(Value(a + b))
			break
		case u8(OpCode.SUBTRACT):
			b := f64(pop_stack())
			a := f64(pop_stack())
			push_stack(Value(a - b))
			break
		case u8(OpCode.MULTIPLY):
			b := f64(pop_stack())
			a := f64(pop_stack())
			push_stack(Value(a * b))
			break
		case u8(OpCode.DIVIDE):
			b := f64(pop_stack())
			a := f64(pop_stack())
			push_stack(Value(a / b))
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

package olox

import "core:fmt"
import "core:mem"

VM :: struct {
	chunk: ^Chunk,
	//instruction pointer
	ip:    ^u8,
}

InterpretResult :: enum {
	OK,
	COMPILE_ERROR,
	RUNTIME_ERROR,
}

vm: VM

init_VM :: proc() {}

free_VM :: proc() {}

interpret :: proc(chunk: ^Chunk) -> InterpretResult {
	vm.chunk = chunk
	vm.ip = raw_data(vm.chunk.code)
	return run()
}

run :: proc() -> InterpretResult {
	for {
		instruction := read_byte()

		switch (instruction) {
		case u8(OpCode.RETURN):
			return InterpretResult.OK

		case u8(OpCode.CONSTANT):
			constant := read_constant()
			print_value(constant)
			fmt.printf("\n")
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

debug_trace_execution :: #force_inline proc() {
	disassemble_instruction(vm.chunk, int(uintptr(vm.ip) - uintptr(raw_data(vm.chunk.code))))

}

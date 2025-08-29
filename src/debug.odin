package olox

import "core:fmt"

disassemble_chunk :: proc(chunk: ^Chunk, name: string) {
	fmt.println("== ", name, "==")

	offset := 0
	for offset < len(chunk.code) {
		offset = disassemble_instruction(chunk, offset)
	}
}

disassemble_instruction :: proc(chunk: ^Chunk, offset: int) -> int {
	fmt.printf("%04d ", offset)
	if offset > 0 && get_line(chunk, offset) == get_line(chunk, offset - 1) {
		fmt.printf("   | ")
	} else {
		fmt.printf("%4d ", get_line(chunk, offset))
	}

	instruction := OpCode(chunk.code[offset])
	switch (instruction) {
	case .RETURN:
		return simple_instruction("OP_RETURN", offset)
	case .PRINT:
		return simple_instruction("OP_PRINT", offset)
	case .NEGATE:
		return simple_instruction("OP_NEGATE", offset)
	case .ADD:
		return simple_instruction("OP_ADD", offset)
	case .SUBTRACT:
		return simple_instruction("OP_SUBTRACT", offset)
	case .DIVIDE:
		return simple_instruction("OP_DIVIDE", offset)
	case .MULTIPLY:
		return simple_instruction("OP_MULTIPLY", offset)
	case .CONSTANT:
		return constant_instruction("OP_CONSTANT", chunk, offset)
	case .CONSTANT_LONG:
		return long_constant_instruction("OP_CONSTANT_LONG", chunk, offset)
	case .NIL:
		return simple_instruction("OP_NIL", offset)
	case .POP:
		return simple_instruction("OP_POP", offset)
	case .TRUE:
		return simple_instruction("OP_TRUE", offset)
	case .FALSE:
		return simple_instruction("OP_FALSE", offset)
	case .NOT:
		return simple_instruction("OP_NOT", offset)
	case .EQUAL:
		return simple_instruction("OP_EQUAL", offset)
	case .GREATER:
		return simple_instruction("OP_EQUAL", offset)
	case .LESS:
		return simple_instruction("OP_EQUAL", offset)
	case .DEFINE_GLOBAL:
		return constant_instruction("OP_DEFINE_GLOBAL", chunk, offset)
	case .DEFINE_GLOBAL_LONG:
		return long_constant_instruction("OP_DEFINE_GLOBAL_LONG", chunk, offset)
	case .GET_GLOBAL:
		return constant_instruction("OP_GET_GLOBAL", chunk, offset)
	case .GET_GLOBAL_LONG:
		return long_constant_instruction("OP_GET_GLOBAL_LONG", chunk, offset)
	case .SET_GLOBAL:
		return constant_instruction("OP_SET_GLOBAL", chunk, offset)
	case .SET_LOCAL:
		return byte_instruction("OP_SET_LOCAL", chunk, offset)
	case .GET_LOCAL:
		return byte_instruction("OP_GET_LOCAL", chunk, offset)
	case .DEFINE_GLOBAL_FINAL:
		return constant_instruction("OP_DEFINE_GLOBAL_FINAL", chunk, offset)
	case .DEFINE_GLOBAL_FINAL_LONG:
		return long_constant_instruction("OP_DEFINE_GLOBAL_FINAL_LONG", chunk, offset)
	case:
		fmt.println("Unknown opcode ", instruction)
		return offset + 1
	}
}

simple_instruction :: proc(name: string, offset: int) -> int {
	fmt.println(name)
	return offset + 1
}

byte_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	slot := chunk.code[offset + 1]
	fmt.printf("%-16s %4d\n", name, slot)
	return offset + 2
}

constant_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	constant := chunk.code[offset + 1]
	fmt.printf("%-16s %4d '", name, constant)
	print_value(chunk.constants[constant])
	fmt.printf("'\n")

	return offset + 2
}

long_constant_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	constant_pt1 := chunk.code[offset + 1]
	constant_pt2 := chunk.code[offset + 2]
	constant_pt3 := chunk.code[offset + 3]
	constant := int(constant_pt1) << 16 | int(constant_pt2) << 8 | int(constant_pt3)

	fmt.printf("%-16s %4d '", name, constant)
	print_value(chunk.constants[constant])
	fmt.printf("'\n")

	return offset + 4
}

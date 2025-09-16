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
	case .DUPLICATE:
		return simple_instruction("OP_DUPLICATE", offset)
	case .TRUE:
		return simple_instruction("OP_TRUE", offset)
	case .FALSE:
		return simple_instruction("OP_FALSE", offset)
	case .NOT:
		return simple_instruction("OP_NOT", offset)
	case .EQUAL:
		return simple_instruction("OP_EQUAL", offset)
	case .GREATER:
		return simple_instruction("OP_GREATER", offset)
	case .LESS:
		return simple_instruction("OP_LESS", offset)
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
	case .SET_GLOBAL_LONG:
		return long_constant_instruction("OP_SET_GLOBAL_LONG", chunk, offset)
	case .SET_LOCAL:
		return byte_instruction("OP_SET_LOCAL", chunk, offset)
	case .SET_LOCAL_LONG:
		return long_byte_instruction("OP_SET_LOCAL_LONG", chunk, offset)
	case .GET_LOCAL_LONG:
		return long_byte_instruction("OP_GET_LOCAL_LONG", chunk, offset)
	case .GET_LOCAL:
		return byte_instruction("OP_GET_LOCAL", chunk, offset)
	case .DEFINE_GLOBAL_FINAL:
		return constant_instruction("OP_DEFINE_GLOBAL_FINAL", chunk, offset)
	case .DEFINE_GLOBAL_FINAL_LONG:
		return long_constant_instruction("OP_DEFINE_GLOBAL_FINAL_LONG", chunk, offset)
	case .JUMP:
		return jump_instruction("OP_JUMP", 1, chunk, offset)
	case .JUMP_IF_FALSE:
		return jump_instruction("OP_JUMP_IF_FALSE", 1, chunk, offset)
	case .LOOP:
		return jump_instruction("OP_LOOP", -1, chunk, offset)
	case .CALL:
		return byte_instruction("OP_CALL", chunk, offset)
	case .CLOSURE:
		new_offset := offset + 1
		constant := chunk.code[new_offset]
		new_offset = new_offset + 1
		fmt.printf("%-16s %4d ", "OP_CLOSURE", constant)
		print_value(chunk.constants[constant])
		fmt.println()

		func := as_function(chunk.constants[constant])
		for j := 0; j < func.upvalue_count; j += 1 {
			is_local := chunk.code[new_offset]
			new_offset += 1
			idx := chunk.code[new_offset]
			new_offset += 1
			fmt.printf(
				"%04d      |                     %s %d\n",
				new_offset - 2,
				is_local != 0 ? "local" : "upvalue",
				idx,
			)
		}
		return new_offset
	case .GET_UPVALUE:
		return byte_instruction("OP_GET_UPVALUE", chunk, offset)
	case .SET_UPVALUE:
		return byte_instruction("OP_SET_UPVALUE", chunk, offset)
	case .CLOSE_UPVALUE:
		return simple_instruction("OP_CLOSE_UPVALUE", offset)
	case .CLASS:
		return constant_instruction("OP_CLASS", chunk, offset)
	case .SET_PROPERTY:
		return constant_instruction("OP_SET_PROPERTY", chunk, offset)
	case .GET_PROPERTY:
		return constant_instruction("OP_GET_PROPERTY", chunk, offset)
	case .GET_PROPERTY_LONG:
		return long_constant_instruction("OP_GET_PROPERTY_LONG", chunk, offset)
	case .SET_PROPERTY_LONG:
		return long_constant_instruction("OP_SET_PROPERTY_LONG", chunk, offset)
	case .METHOD:
		return constant_instruction("OP_METHOD", chunk, offset)
	case .INVOKE:
		return invoke_instruction("OP_INVOKE", chunk, offset)
	case .INHERIT:
		return simple_instruction("OP_INHERIT", offset)
	case .GET_SUPER:
		return constant_instruction("OP_GET_SUPER", chunk, offset)
	case .GET_SUPER_LONG:
		return long_constant_instruction("OP_GET_SUPER_LONG", chunk, offset)
	case .SUPER_INVOKE:
		return invoke_instruction("OP_SUPER_INVOKE", chunk, offset)
	case .SUPER_INVOKE_LONG:
		return long_constant_instruction("OP_SUPER_INVOKE_LONG", chunk, offset)
	case:
		fmt.println("Unknown opcode ", instruction)
		return offset + 1
	}
}

simple_instruction :: proc(name: string, offset: int) -> int {
	fmt.println(name)
	return offset + 1
}

jump_instruction :: proc(name: string, sign: int, chunk: ^Chunk, offset: int) -> int {
	jump := u16(chunk.code[offset + 1] << 8)
	jump |= u16(chunk.code[offset + 2])
	fmt.printf("%-16s %4d -> %d\n", name, offset, offset + 3 + sign * int(jump))
	return offset + 3
}

long_byte_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	byte1 := chunk.code[offset + 1]
	byte2 := chunk.code[offset + 2]
	byte3 := chunk.code[offset + 3]
	slot := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
	fmt.printf("%-16s %4d\n", name, slot)
	return offset + 4
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

invoke_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	constant := chunk.code[offset + 1]
	arg_count := chunk.code[offset + 2]
	fmt.printf("%-16v (%v args) %4v '", name, arg_count, constant)
	print_value(chunk.constants[constant])
	fmt.println()
	return offset + 3
}

long_invoke_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	byte1 := chunk.code[offset + 1]
	byte2 := chunk.code[offset + 2]
	byte3 := chunk.code[offset + 3]
	constant := int(byte1) << 16 | int(byte2) << 8 | int(byte3)

	arg_count := chunk.code[offset + 4]
	fmt.printf("%-16v (%v args) %4v '", name, arg_count, constant)
	print_value(chunk.constants[constant])
	fmt.println()
	return offset + 5
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

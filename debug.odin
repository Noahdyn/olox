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

	instruction := OpCode(chunk.code[offset])
	switch (instruction) {
	case .OP_RETURN:
		return simple_instruction("OP_RETURN", offset)
	case:
		fmt.println("Unknown opcode ", instruction)
		return offset + 1
	}
}

simple_instruction :: proc(name: string, offset: int) -> int {
	fmt.println(name)
	return offset + 1
}

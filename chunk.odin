package olox

Chunk :: struct {
	code:      [dynamic]u8,
	constants: [dynamic]Value,
	lines:     [dynamic]LineInfo,
}

OpCode :: enum u8 {
	CONSTANT,
	CONSTANT_LONG,
	NEGATE,
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
	RETURN,
}

LineInfo :: struct {
	line, count: int,
}

write_chunk :: proc {
	write_chunk_opcode,
	write_chunk_byte,
}

write_chunk_opcode :: proc(chunk: ^Chunk, op: OpCode, line: int) {
	append(&chunk.code, u8(op))
	if len(chunk.lines) > 0 && chunk.lines[len(chunk.lines) - 1].line == line {
		chunk.lines[len(chunk.lines) - 1].count += 1
	} else {
		append(&chunk.lines, LineInfo{line, 1})
	}
}

write_chunk_byte :: proc(chunk: ^Chunk, byte: u8, line: int) {
	append(&chunk.code, byte)
	if len(chunk.lines) > 0 && chunk.lines[len(chunk.lines) - 1].line == line {
		chunk.lines[len(chunk.lines) - 1].count += 1
	} else {
		append(&chunk.lines, LineInfo{line, 1})
	}
}


free_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.code)
	delete(chunk.constants)
	delete(chunk.lines)
}

write_constant :: proc(chunk: ^Chunk, val: Value, line: int) {
	idx := add_constant(chunk, val)
	if idx <= 255 {
		write_chunk_opcode(chunk, OpCode.CONSTANT, line)
		write_chunk_byte(chunk, u8(idx), line)
	} else {
		byte1 := u8((idx >> 16) & 0xFF)
		byte2 := u8((idx >> 8) & 0xFF)
		byte3 := u8(idx & 0xFF)
		write_chunk_opcode(chunk, OpCode.CONSTANT_LONG, line)
		write_chunk_byte(chunk, byte1, line)
		write_chunk_byte(chunk, byte2, line)
		write_chunk_byte(chunk, byte3, line)
	}
}

add_constant :: proc(chunk: ^Chunk, val: Value) -> int {
	append(&chunk.constants, val)
	return len(chunk.constants) - 1
}

get_line :: proc(chunk: ^Chunk, instr_idx: int) -> int {
	current_instruction := 0
	for line_info in chunk.lines {
		for i in 0 ..< line_info.count {
			if current_instruction == instr_idx do return line_info.line
			else {current_instruction += 1
			}
		}
	}
	return -1
}

package olox

Chunk :: struct {
	code: [dynamic]u8,
}

OpCode :: enum u8 {
	OP_RETURN,
}

write_chunk :: proc(chunk: ^Chunk, byte: u8) {
	append(&chunk.code, byte)
}

free_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.code)
}

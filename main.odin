package olox
import "core:os"

main :: proc() {

	chunk := Chunk{}
	write_chunk(&chunk, cast(u8)OpCode.OP_RETURN)
	write_chunk(&chunk, cast(u8)OpCode.OP_RETURN)
	write_chunk(&chunk, cast(u8)OpCode.OP_RETURN)
	write_chunk(&chunk, cast(u8)OpCode.OP_RETURN)
	disassemble_chunk(&chunk, "test chunk")
	free_chunk(&chunk)
}

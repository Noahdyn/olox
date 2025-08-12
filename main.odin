package olox
import "core:fmt"
import "core:os"

main :: proc() {
	init_VM()
	defer free_VM()
	chunk := Chunk{}
	defer free_chunk(&chunk)


	write_constant(&chunk, 1.2, 1)
	write_chunk(&chunk, OpCode.RETURN, 2)

	// disassemble_chunk(&chunk, "test")
	interpret(&chunk)
}

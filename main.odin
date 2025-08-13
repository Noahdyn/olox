package olox
import "core:fmt"
import "core:os"
import "core:time"

main :: proc() {
	init_VM()
	defer free_VM()
	chunk := Chunk{}
	defer free_chunk(&chunk)

	write_constant(&chunk, 1, 1)
	time_before := time.now()
	write_chunk(&chunk, OpCode.NEGATE, 1)
	time_after := time.now()

	fmt.println(time.duration_microseconds(time.diff(time_before, time_after)))

	write_chunk(&chunk, OpCode.RETURN, 2)


	disassemble_chunk(&chunk, "test chunk")
	interpret(&chunk)

}

package olox
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"

main :: proc() {
	init_VM()
	defer free_VM()

	if (len(os.args) == 1) {
		repl()
	} else if (len(os.args) == 2) {
		run_file(os.args[1])
	} else {
		fmt.println("Usage: olox [path]")
		os.exit(64)
	}

}

repl :: proc() {
	line: [1024]u8
	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, io.to_reader(os.stream_from_handle(os.stdin)), line[:])
	for {
		fmt.printf("> ")

		line, err := bufio.reader_read_slice(&reader, '\n')
		if err != nil {
			fmt.println(err)
			break
		}
		interpret(string(line[:]))
	}
}

run_file :: proc(path: string) {
	source, ok := os.read_entire_file(path)
	if (!ok) {
		fmt.println("Unable to open file", path)
		os.exit(74)
	}
	defer delete(source)
	res := interpret(string(source[:]))

	if (res == InterpretResult.COMPILE_ERROR) do os.exit(65)
	if (res == InterpretResult.RUNTIME_ERROR) do os.exit(70)

}

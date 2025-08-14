package olox
import "core:fmt"
import "core:os"
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
	line: [1024]byte

	for {
		fmt.printf(">")
		if (true) {
			fmt.printf("\n")
			break
		}
		interpret(line)
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

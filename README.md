This is an Odin port of the [clox vm](https://github.com/munificent/craftinginterpreters) from Robert Nystroms book "Crafting Interpreters".

# Additions over the original vm.

This implementation comes with a few additions over the original clox vm, these include:

- Run-Length-Encoding of bytecode line numbers to improve memory usage
- Support for more than 255 constants per chunk, while keeping backwards compatibility in performance for single byte constant instructions
- Support for Values as keys in hash tables
- Switch Statements
- Break Statements to break out of loops
- Final keyword, which gets checked at compile time
- Improved performance of garbage collection.

# Testing

This project includes an extensive test suite and a test runner written in c++, which can be found in test/test.cpp. To use it compile the test runner (c++ version 17+) and pass it the path to the compiled compiler/vm.

# Running the vm

## Requirements

Requires an Odin compiler.

---

```
odin build src -out=olox
```

### compiling & running a source file

```
./olox <srcfile>.lox
```

### running in REPL mode (read evaluate print loop)

```
./olox
```

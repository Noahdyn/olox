package olox

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

FRAMES_MAX :: 64
STACK_MAX :: FRAMES_MAX * 256

CallFrame :: struct {
	function: ^ObjFunction,
	ip:       int,
	slots:    []Value,
}

VM :: struct {
	chunk:          ^Chunk,
	//instruction pointer
	ip:             ^u8,
	stack_capacity: int,
	frames:         [FRAMES_MAX]CallFrame,
	frame_count:    int,
	stack:          [STACK_MAX]Value,
	stack_top:      int,
	globals:        Table,
	strings:        Table,
	objects:        ^Obj,
}

InterpretResult :: enum {
	OK,
	COMPILE_ERROR,
	RUNTIME_ERROR,
}

vm: VM
clock_native :: proc(arg_count: int, args: []Value) -> Value {
	return number_val(f64(time.now()._nsec))
}

DEBUG_TRACE_EXECUTION := false

init_VM :: proc() {
	reset_stack()

	define_native("clock", clock_native)
}

reset_stack :: proc() {
	vm.stack_top = 0
	vm.frame_count = 0
}

runtime_error :: proc(format: string, args: ..any) {
	fmt.eprintf(format, ..args)
	fmt.eprintln()

	for i := vm.frame_count - 1; i >= 0; i -= 1 {
		frame := &vm.frames[i]
		function := frame.function
		instruction_index := int(uintptr(frame.ip) - uintptr(raw_data(function.chunk.code)))
		fmt.eprintf("[line %d] in ", get_line(&function.chunk, instruction_index))
		if function.name == nil {
			fmt.eprintf("script\n")
		} else {
			fmt.eprintf("%s()\n", function.name.str)
		}

	}

	reset_stack()
}

define_native :: proc(name: string, function: NativeFn) {
	push_stack(obj_val(copy_string(name)))
	push_stack(obj_val(new_native(function)))
	table_set(&vm.globals, vm.stack[0], vm.stack[1])
	pop_stack()
	pop_stack()
}

free_VM :: proc() {
	free_table(&vm.strings)
	free_table(&vm.globals)
	free_objects()
}

free_objects :: proc() {
	object := vm.objects
	for object != nil {
		next := object.next
		free_object(object)
		object = next
	}
}

free_object :: proc(object: ^Obj) {
	switch object.type {
	case .String:
		o := cast(^ObjString)object
		delete(o.str)
		free(o)
	case .Function:
		function := cast(^ObjFunction)object
		free_chunk(&function.chunk)
		free(function)
	case .Native:
		o := cast(^ObjNative)object
		free(o)
	}
}

interpret :: proc(source: string) -> InterpretResult {
	function := compile(source)
	if function == nil do return .COMPILE_ERROR

	push_stack(obj_val(function))
	call(function, 0)

	return run()
}

push_stack :: proc(val: Value) {
	vm.stack[vm.stack_top] = val
	vm.stack_top += 1
}

pop_stack :: proc() -> Value {
	vm.stack_top -= 1
	return vm.stack[vm.stack_top]
}

run :: proc() -> InterpretResult {
	frame := &vm.frames[vm.frame_count - 1]
	for {
		if DEBUG_TRACE_EXECUTION {
			disassemble_instruction(
				&frame.function.chunk,
				int(uintptr(frame.ip) - uintptr(raw_data(frame.function.chunk.code))),
			)
			fmt.printf("          ")
			for i in 0 ..< vm.stack_top {
				fmt.printf("[ ")
				print_value(vm.stack[i])
				fmt.printf(" ]")
			}
			fmt.printf("\n")
		}
		instruction := read_byte()
		switch (instruction) {
		case u8(OpCode.RETURN):
			res := pop_stack()
			vm.frame_count -= 1
			if vm.frame_count == 0 {
				pop_stack()
				return .OK
			}
			vm.stack_top = len(vm.stack) - len(frame.slots)

			push_stack(res)
			frame = &vm.frames[vm.frame_count - 1]
		case u8(OpCode.CONSTANT):
			constant := read_constant()
			push_stack(constant)
		case u8(OpCode.CONSTANT_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			constant_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			constant := vm.chunk.constants[constant_index]
			push_stack(constant)
		case u8(OpCode.NEGATE):
			last_elem := &vm.stack[len(vm.stack) - 1]
			if !is_number(last_elem^) {
				runtime_error("Operand must be a number.")
				return .RUNTIME_ERROR
			}
			last_elem^ = number_val(-as_number(last_elem^))
		case u8(OpCode.ADD):
			if is_string(peek_vm(0)) && is_string(peek_vm(1)) {
				concatenate()
			} else if is_number(peek_vm(0)) && is_number(peek_vm(1)) {

				b := as_number(pop_stack())
				a := as_number(pop_stack())
				push_stack(number_val(a + b))

			} else {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
		case u8(OpCode.SUBTRACT):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a - b))
		case u8(OpCode.MULTIPLY):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a * b))
		case u8(OpCode.DIVIDE):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(number_val(a / b))
		case u8(OpCode.NIL):
			push_stack(nil_val())
		case u8(OpCode.TRUE):
			push_stack(bool_val(true))
		case u8(OpCode.FALSE):
			push_stack(bool_val(false))
		case u8(OpCode.NOT):
			last_elem := &vm.stack[len(vm.stack) - 1]
			if !is_bool(last_elem^) {
				runtime_error("Operand must be boolean.")
				return .RUNTIME_ERROR
			}
			last_elem^ = bool_val(is_falsey(last_elem^))
		case u8(OpCode.EQUAL):
			b := pop_stack()
			a := pop_stack()
			push_stack(bool_val(values_equal(a, b)))
		case u8(OpCode.GREATER):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(bool_val(a > b))
		case u8(OpCode.LESS):
			if !is_number(peek_vm(0)) || !is_number(peek_vm(1)) {
				runtime_error("Operands must be numbers.")
				return .RUNTIME_ERROR
			}
			b := as_number(pop_stack())
			a := as_number(pop_stack())
			push_stack(bool_val(a < b))
		case u8(OpCode.PRINT):
			print_value(pop_stack())
			fmt.println()
		case u8(OpCode.POP):
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL):
			name := read_constant()
			table_set(&vm.globals, name, peek_vm(0))
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_FINAL):
			name := read_constant()
			val := peek_vm(0)
			val.final = true
			table_set(&vm.globals, name, val)
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			name_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			name := vm.chunk.constants[name_index]
			table_set(&vm.globals, name, peek_vm(0))
			pop_stack()
		case u8(OpCode.DEFINE_GLOBAL_FINAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			name_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			name := vm.chunk.constants[name_index]
			val := peek_vm(0)
			val.final = true
			table_set(&vm.globals, name, val)
			pop_stack()
		case u8(OpCode.GET_GLOBAL):
			key := read_constant()
			value, ok := table_get(&vm.globals, key)
			if !ok {
				runtime_error("Undefined variable '%s'", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			push_stack(value)
		case u8(OpCode.GET_GLOBAL_LONG):
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			key_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			key := vm.chunk.constants[key_index]
			value, ok := table_get(&vm.globals, key)
			if !ok {
				runtime_error("Undefined variable '%s'", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			push_stack(value)
		case u8(OpCode.SET_GLOBAL):
			key := read_constant()
			val, found := table_get(&vm.globals, key)
			if !found {
				runtime_error("Undefined variable '%s'.", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			if val.final {
				runtime_error(
					"Cannot assign to final variable '%s'.",
					(cast(^ObjString)as_obj(key)).str,
				)
				return .RUNTIME_ERROR
			}
			table_set(&vm.globals, key, peek_vm(0))
		case u8(OpCode.SET_GLOBAL_LONG):
			//TODO: byte1-3 lesen zu einer procedure machen
			byte1 := read_byte()
			byte2 := read_byte()
			byte3 := read_byte()
			key_index := int(byte1) << 16 | int(byte2) << 8 | int(byte3)
			key := vm.chunk.constants[key_index]
			val, found := table_get(&vm.globals, key)
			if !found {
				runtime_error("Undefined variable '%s'.", (cast(^ObjString)as_obj(key)).str)
				return .RUNTIME_ERROR
			}
			if val.final {
				runtime_error(
					"Cannot assign to final variable '%s'.",
					(cast(^ObjString)as_obj(key)).str,
				)
				return .RUNTIME_ERROR
			}
			table_set(&vm.globals, key, peek_vm(0))
		case u8(OpCode.JUMP_IF_FALSE):
			offset := read_short()
			if is_falsey(peek_vm(0)) do frame.ip += int(offset)
		case u8(OpCode.JUMP):
			offset := read_short()
			frame.ip += int(offset)
		case u8(OpCode.GET_LOCAL):
			slot := read_byte()
			push_stack(frame.slots[slot])
		case u8(OpCode.SET_LOCAL):
			slot := read_byte()
			frame.slots[slot] = peek_vm(0)
		case u8(OpCode.LOOP):
			offset := read_short()
			frame.ip -= int(offset)
		case u8(OpCode.DUPLICATE):
			val := peek_vm(0)
			push_stack(val)
		case u8(OpCode.CALL):
			arg_count := read_byte()
			if !call_value(peek_vm(int(arg_count)), int(arg_count)) {
				return .RUNTIME_ERROR
			}
			frame = &vm.frames[vm.frame_count - 1]
		}
	}
}

concatenate :: proc() {
	b := cast(^ObjString)as_obj(pop_stack())
	a := cast(^ObjString)as_obj(pop_stack())
	new_string := strings.concatenate({a.str, b.str})
	hash := hash_string(new_string)
	result := allocate_string(new_string, hash)
	push_stack(obj_val(result))
}

read_byte :: #force_inline proc() -> u8 {
	frame := &vm.frames[vm.frame_count - 1]
	byte := frame.function.chunk.code[frame.ip]
	frame.ip += 1
	return byte
}

read_constant :: #force_inline proc() -> Value {
	frame := &vm.frames[vm.frame_count - 1]
	return frame.function.chunk.constants[read_byte()]
}

read_string :: #force_inline proc() -> ^ObjString {
	return cast(^ObjString)as_obj(read_constant())
}

read_short :: #force_inline proc() -> u16 {
	frame := &vm.frames[vm.frame_count - 1]
	frame.ip += 2
	return(
		u16(frame.function.chunk.code[frame.ip - 2]) << 8 |
		u16(frame.function.chunk.code[frame.ip - 1]) \
	)
}

peek_vm :: proc(distance: int) -> Value {
	return vm.stack[vm.stack_top - 1 - distance]
}

call :: proc(function: ^ObjFunction, arg_count: int) -> bool {
	if arg_count != function.arity {
		runtime_error("Expected %d arguments but got %d.", function.arity, arg_count)
		return false
	}

	if vm.frame_count == FRAMES_MAX {
		runtime_error("Stack overflow.")
		return false
	}
	frame := &vm.frames[vm.frame_count]
	vm.frame_count += 1
	frame.function = function
	frame.ip = 0

	slots_start := vm.stack_top - arg_count - 1
	frame.slots = vm.stack[slots_start:]

	return true
}

call_value :: proc(callee: Value, arg_count: int) -> bool {
	if is_obj(callee) {
		obj := as_obj(callee)
		#partial switch obj.type {
		case .Function:
			return call(as_function(callee), arg_count)
		case .Native:
			native := as_native(callee)
			res := native(arg_count, vm.stack[vm.stack_top - arg_count:vm.stack_top])

			vm.stack_top -= arg_count + 1
			push_stack(res)
			return true
		case:
			break

		}
	}
	runtime_error("Can only call functions and classes.")
	return false
}

is_falsey :: proc(val: Value) -> bool {
	return is_nil(val) || (is_bool(val) && !as_bool(val))
}

values_equal :: proc(a, b: Value) -> bool {
	if a.type != b.type do return false
	#partial switch a.type {
	case .BOOL:
		return as_bool(a) == as_bool(b)
	case .NIL:
		return true
	case .NUMBER:
		return as_number(a) == as_number(b)
	case .OBJ:
		return as_obj(a) == as_obj(b)
	case:
		return false // Unreachable.
	}
}

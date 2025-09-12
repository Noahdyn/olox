package olox

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

DEBUG_PRINT_CODE :: false

U8_MAX :: max(u8)

ParseFn :: proc(can_assign: bool)

Parser :: struct {
	current, previous: Token,
	had_error:         bool,
	panic_mode:        bool,
}

Precedence :: enum {
	NONE,
	ASSIGNMENT, // =
	OR, // or
	AND, // and
	EQUALITY, // == !=
	COMPARISON, // < > <= >=
	TERM, // + -
	FACTOR, // * /
	UNARY, // ! -
	CALL, // . ()
	PRIMARY,
}

ParseRule :: struct {
	prefix:     ParseFn,
	infix:      ParseFn,
	precedence: Precedence,
}

Compiler :: struct {
	enclosing:   ^Compiler,
	function:    ^ObjFunction,
	type:        FunctionType,
	locals:      [dynamic]Local,
	upvalues:    [U8_MAX]Upvalue,
	scope_depth: int,
}

Local :: struct {
	name:        Token,
	depth:       int,
	final:       bool,
	is_captured: bool,
}

Upvalue :: struct {
	idx:      u8,
	is_local: bool,
}

FunctionType :: enum {
	FUNCTION,
	SCRIPT,
}

rules: [TokenType]ParseRule = {
	.LEFT_PAREN    = {grouping, call, .CALL},
	.RIGHT_PAREN   = {nil, nil, .NONE},
	.LEFT_BRACE    = {nil, nil, .NONE},
	.RIGHT_BRACE   = {nil, nil, .NONE},
	.COMMA         = {nil, nil, .NONE},
	.DOT           = {nil, nil, .NONE},
	.MINUS         = {unary, binary, .TERM},
	.PLUS          = {nil, binary, .TERM},
	.SEMICOLON     = {nil, nil, .NONE},
	.COLON         = {nil, nil, .NONE},
	.SLASH         = {nil, binary, .FACTOR},
	.STAR          = {nil, binary, .FACTOR},
	.BANG          = {unary, nil, .NONE},
	.BANG_EQUAL    = {nil, binary, .EQUALITY},
	.EQUAL         = {nil, nil, .NONE},
	.EQUAL_EQUAL   = {nil, binary, .EQUALITY},
	.GREATER       = {nil, binary, .COMPARISON},
	.GREATER_EQUAL = {nil, binary, .COMPARISON},
	.LESS          = {nil, binary, .COMPARISON},
	.LESS_EQUAL    = {nil, binary, .COMPARISON},
	.IDENTIFIER    = {variable, nil, .NONE},
	.STRING        = {string_proc, nil, .NONE},
	.NUMBER        = {number, nil, .NONE},
	.AND           = {nil, and_proc, .AND},
	.CLASS         = {nil, nil, .NONE},
	.ELSE          = {nil, nil, .NONE},
	.FALSE         = {literal, nil, .NONE},
	.FOR           = {nil, nil, .NONE},
	.FUN           = {nil, nil, .NONE},
	.IF            = {nil, nil, .NONE},
	.NIL           = {literal, nil, .NONE},
	.OR            = {nil, or, .OR},
	.PRINT         = {nil, nil, .NONE},
	.RETURN        = {nil, nil, .NONE},
	.SUPER         = {nil, nil, .NONE},
	.THIS          = {nil, nil, .NONE},
	.TRUE          = {literal, nil, .NONE},
	.VAR           = {nil, nil, .NONE},
	.WHILE         = {nil, nil, .NONE},
	.SWITCH        = {nil, nil, .NONE},
	.CASE          = {nil, nil, .NONE},
	.FINAL         = {nil, nil, .NONE},
	.ERROR         = {nil, nil, .NONE},
	.EOF           = {nil, nil, .NONE},
}


parser: Parser
current: ^Compiler
compiling_chunk: ^Chunk

current_chunk :: proc() -> ^Chunk {
	return &current.function.chunk
}

compile :: proc(source: string) -> ^ObjFunction {
	init_scanner(source)

	compiler: Compiler
	init_compiler(&compiler, .SCRIPT)
	defer free_compiler(&compiler)


	advance()
	for !match(.EOF) {
		declaration()
	}

	function := end_compiler()
	return parser.had_error ? nil : function
}

advance :: proc() {
	parser.previous = parser.current

	for {
		parser.current = scan_token()
		if parser.current.type != .ERROR do break

		token_bytes := mem.ptr_to_bytes(parser.current.start, parser.current.length)
		token_text := string(token_bytes)
		error_at_current(token_text)
	}
}

consume :: proc(type: TokenType, msg: string) {
	if parser.current.type == type {
		advance()
		return
	}
	error_at_current(msg)
}

check :: proc(type: TokenType) -> bool {
	return parser.current.type == type
}

@(private = "file")
match :: proc(type: TokenType) -> bool {
	if !check(type) do return false
	advance()
	return true
}

emit_byte :: proc(byt: u8) {
	write_chunk(current_chunk(), byt, parser.previous.line)
}

emit_bytes :: proc(byte1, byte2: u8) {
	emit_byte(byte1)
	emit_byte(byte2)
}

emit_loop :: proc(loop_start: int) {
	emit_byte(u8(OpCode.LOOP))

	offset := len(current_chunk().code) - loop_start + 2
	if offset > int(max(u16)) do error("Loop body too large.")

	emit_byte(u8((offset >> 8) & 0xff))
	emit_byte(u8(offset & 0xff))
}

emit_jump :: proc(instruction: u8) -> int {
	emit_byte(instruction)
	emit_byte(0xff)
	emit_byte(0xff)
	return len((current_chunk().code)) - 2
}

end_compiler :: proc() -> ^ObjFunction {
	emit_return()
	function := current.function

	if DEBUG_PRINT_CODE && !parser.had_error {
		disassemble_chunk(current_chunk(), function.name != nil ? function.name.str : "<script>")
	}

	current = current.enclosing
	return function
}

begin_scope :: proc() {
	current.scope_depth += 1
}

end_scope :: proc() {
	current.scope_depth -= 1

	for len(&current.locals) > 0 &&
	    current.locals[len(&current.locals) - 1].depth > current.scope_depth {
		if current.locals[len(current.locals) - 1].is_captured {
			emit_byte(u8(OpCode.CLOSE_UPVALUE))
		} else {
			pop(&current.locals)
		}
	}
}

grouping :: proc(can_assign: bool) {
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after expression.")
}

number :: proc(can_assign: bool) {
	value, _ := strconv.parse_f64(token_text(parser.previous))
	emit_constant(number_val(value))
}

or :: proc(can_assign: bool) {
	else_jump := emit_jump(u8(OpCode.JUMP_IF_FALSE))
	end_jump := emit_jump(u8(OpCode.JUMP))

	patch_jump(else_jump)
	emit_byte(u8(OpCode.POP))

	parse_precedence(.OR)
	patch_jump(end_jump)
}

string_proc :: proc(can_assign: bool) {
	string_data := string(
		mem.slice_ptr(mem.ptr_offset(parser.previous.start, 1), parser.previous.length - 2),
	)
	emit_constant(obj_val(copy_string(string_data)))
}

variable :: proc(can_assign: bool) {
	named_variable(&parser.previous, can_assign)
}

named_variable :: proc(name: ^Token, can_assign: bool) {
	get_op, get_op_long, set_op, set_op_long: u8
	arg := resolve_local(current, name)

	//TODO: refactor dieses 3x selber code 

	if arg != -1 {
		// Local variable
		get_op = u8(OpCode.GET_LOCAL)
		set_op = u8(OpCode.SET_LOCAL)
		set_op_long = u8(OpCode.SET_LOCAL_LONG)
		get_op_long = u8(OpCode.GET_LOCAL_LONG)

		if can_assign && match(.EQUAL) {
			if current.locals[arg].final {
				error("Cannot assign to final variable.")
				return
			}
			expression()
			// Emit SET instruction
			if arg <= 255 {
				emit_bytes(set_op, u8(arg))
			} else {
				byte1 := u8((arg >> 16) & 0xFF)
				byte2 := u8((arg >> 8) & 0xFF)
				byte3 := u8(arg & 0xFF)
				emit_byte(set_op_long)
				emit_byte(byte1)
				emit_byte(byte2)
				emit_byte(byte3)
			}
		} else {
			// Emit GET instruction
			if arg <= 255 {
				emit_bytes(get_op, u8(arg))
			} else {
				byte1 := u8((arg >> 16) & 0xFF)
				byte2 := u8((arg >> 8) & 0xFF)
				byte3 := u8(arg & 0xFF)
				emit_byte(get_op_long)
				emit_byte(byte1)
				emit_byte(byte2)
				emit_byte(byte3)
			}
		}
	} else if uvarg := resolve_upvalue(current, name); uvarg != -1 {
		set_op = u8(OpCode.SET_UPVALUE)
		get_op = u8(OpCode.GET_UPVALUE)

		if can_assign && match(.EQUAL) {
			emit_bytes(set_op, u8(uvarg))
		} else {
			emit_bytes(get_op, u8(uvarg))
		}
	} else {
		// Global variable
		arg = identifier_constant(name)
		get_op = u8(OpCode.GET_GLOBAL)
		set_op = u8(OpCode.SET_GLOBAL)
		set_op_long = u8(OpCode.SET_GLOBAL_LONG)
		get_op_long = u8(OpCode.GET_GLOBAL_LONG)

		if can_assign && match(.EQUAL) {
			expression()
			// Emit SET instruction
			if arg <= 255 {
				emit_bytes(set_op, u8(arg))
			} else {
				byte1 := u8((arg >> 16) & 0xFF)
				byte2 := u8((arg >> 8) & 0xFF)
				byte3 := u8(arg & 0xFF)
				emit_byte(set_op_long)
				emit_byte(byte1)
				emit_byte(byte2)
				emit_byte(byte3)
			}
		} else {
			// Emit GET instruction
			if arg <= 255 {
				emit_bytes(get_op, u8(arg))
			} else {
				byte1 := u8((arg >> 16) & 0xFF)
				byte2 := u8((arg >> 8) & 0xFF)
				byte3 := u8(arg & 0xFF)
				emit_byte(get_op_long)
				emit_byte(byte1)
				emit_byte(byte2)
				emit_byte(byte3)
			}
		}
	}
}

unary :: proc(can_assign: bool) {
	operator_type := parser.previous.type

	// compile the operand
	parse_precedence(.UNARY)

	// emit the operator instruction
	#partial switch operator_type {
	case .MINUS:
		emit_byte(u8(OpCode.NEGATE))
	case .BANG:
		emit_byte(u8(OpCode.NOT))
	case:
		return
	}
}

binary :: proc(can_assign: bool) {
	operator_type := parser.previous.type
	rule := get_rule(operator_type)
	parse_precedence(Precedence(int(rule^.precedence) + 1))


	#partial switch operator_type {
	case .PLUS:
		emit_byte(u8(OpCode.ADD))
	case .MINUS:
		emit_byte(u8(OpCode.SUBTRACT))
	case .STAR:
		emit_byte(u8(OpCode.MULTIPLY))
	case .SLASH:
		emit_byte(u8(OpCode.DIVIDE))
	case .BANG_EQUAL:
		emit_bytes(u8(OpCode.EQUAL), u8(OpCode.NOT))
	case .EQUAL_EQUAL:
		emit_byte(u8(OpCode.EQUAL))
	case .GREATER:
		emit_byte(u8(OpCode.GREATER))
	case .LESS:
		emit_byte(u8(OpCode.LESS))
	case .GREATER_EQUAL:
		emit_bytes(u8(OpCode.LESS), u8(OpCode.NOT))
	case .LESS_EQUAL:
		emit_bytes(u8(OpCode.GREATER), u8(OpCode.NOT))
	case:
		return
	}
}

@(private = "file")
call :: proc(can_assign: bool) {
	arg_count := argument_list()
	emit_bytes(u8(OpCode.CALL), arg_count)
}

literal :: proc(can_assign: bool) {
	#partial switch parser.previous.type {
	case .FALSE:
		emit_byte(u8(OpCode.FALSE))
	case .TRUE:
		emit_byte(u8(OpCode.TRUE))
	case .NIL:
		emit_byte(u8(OpCode.NIL))

	}
}

parse_precedence :: proc(precedence: Precedence) {
	advance()
	prefix_rule := get_rule(parser.previous.type).prefix
	if prefix_rule == nil {
		error("Expect expression.")
		return
	}
	can_assign := precedence <= Precedence.ASSIGNMENT
	prefix_rule(can_assign)

	for precedence <= get_rule(parser.current.type).precedence {
		advance()
		infix_rule := get_rule(parser.previous.type).infix
		infix_rule(can_assign)
	}

	if (can_assign && match(.EQUAL)) {
		error("Invalid assignment target.")
	}
}

identifier_constant :: proc(name: ^Token) -> int {
	string_data := string(mem.slice_ptr(name.start, name.length))
	return add_constant(current_chunk(), obj_val(copy_string(string_data)))
}

identifiers_equal :: proc(a, b: ^Token) -> bool {
	if a.length != b.length do return false
	a_str_data := string(mem.slice_ptr(a.start, a.length))
	b_str_data := string(mem.slice_ptr(b.start, b.length))

	return strings.compare(a_str_data, b_str_data) == 0
}

resolve_local :: proc(compiler: ^Compiler, name: ^Token) -> int {
	for i := len(&compiler.locals) - 1; i >= 0; i -= 1 {
		local := compiler.locals[i]
		if identifiers_equal(name, &local.name) {
			if local.depth == -1 {
				error("Can't read local variable in its own initializer,")
			}
			return i
		}
	}
	return -1
}

add_upvalue :: proc(compiler: ^Compiler, idx: u8, is_local: bool) -> int {
	upvalue_count := compiler.function.upvalue_count

	for i in 0 ..< upvalue_count {
		upvalue := compiler.upvalues[i]
		if upvalue.idx == idx && upvalue.is_local == is_local do return i
	}

	if upvalue_count == int(U8_MAX) {
		error("Too many closure variables in function.")
		return 0
	}

	compiler.upvalues[upvalue_count].is_local = is_local
	compiler.upvalues[upvalue_count].idx = idx
	compiler.function.upvalue_count += 1
	return compiler.function.upvalue_count - 1
}

resolve_upvalue :: proc(compiler: ^Compiler, name: ^Token) -> int {
	if compiler.enclosing == nil do return -1

	local := resolve_local(compiler.enclosing, name)
	if local != -1 {
		compiler.enclosing.locals[local].is_captured = true
		return add_upvalue(compiler, u8(local), true)
	}

	upvalue := resolve_upvalue(compiler.enclosing, name)
	if upvalue != -1 do return add_upvalue(compiler, u8(upvalue), false)

	return -1
}

add_local :: proc(name: Token, final: bool = false) {
	local: Local
	local.name = name
	local.depth = -1
	local.final = final
	append(&current.locals, local)
}

declare_variable :: proc(final: bool = false) {
	if current.scope_depth == 0 do return

	name := parser.previous
	for i := len(&current.locals) - 1; i >= 0; i -= 1 {
		local := current.locals[i]
		if local.depth != -1 && local.depth < current.scope_depth do break

		if identifiers_equal(&name, &local.name) {
			error("Already a variable with this name in this scope.")
		}
	}
	add_local(name, final)
}

parse_variable :: proc(error_msg: string, final: bool = false) -> int {
	consume(.IDENTIFIER, error_msg)

	if current.scope_depth > 0 {
		declare_variable(final)
		return 0
	}

	return identifier_constant(&parser.previous)
}

mark_initialized :: proc() {
	if current.scope_depth == 0 do return
	current.locals[len(&current.locals) - 1].depth = current.scope_depth
}

define_variable :: proc(global: int, final: bool) {
	if current.scope_depth > 0 {
		mark_initialized()
		return
	}

	define_op, define_op_long: u8
	if final {
		define_op = u8(OpCode.DEFINE_GLOBAL_FINAL)
		define_op_long = u8(OpCode.DEFINE_GLOBAL_FINAL_LONG)
	} else {
		define_op = u8(OpCode.DEFINE_GLOBAL)
		define_op_long = u8(OpCode.DEFINE_GLOBAL_LONG)
	}

	if global <= 255 {
		emit_bytes(define_op, u8(global))
	} else {
		byte1 := u8((global >> 16) & 0xFF)
		byte2 := u8((global >> 8) & 0xFF)
		byte3 := u8(global & 0xFF)
		emit_byte(define_op_long)
		emit_byte(byte1)
		emit_byte(byte2)
		emit_byte(byte3)
	}
}

argument_list :: proc() -> u8 {
	arg_count: u8 = 0
	if !check(.RIGHT_PAREN) {
		for {
			expression()
			if arg_count == 255 {
				error("Can't have more than 255 characters")
			}
			arg_count += 1
			if !match(.COMMA) do break
		}
	}
	consume(.RIGHT_PAREN, "Expect ')' after arguments.")
	return arg_count
}

and_proc :: proc(can_assign: bool) {
	end_jump := emit_jump(u8(OpCode.JUMP_IF_FALSE))
	emit_byte(u8(OpCode.POP))
	parse_precedence(.AND)
	patch_jump(end_jump)
}

get_rule :: proc(type: TokenType) -> ^ParseRule {
	return &rules[type]
}

expression :: proc() {
	parse_precedence(.ASSIGNMENT)
}

block :: proc() {
	for !check(.RIGHT_BRACE) && !check(.EOF) {
		declaration()
	}
	consume(.RIGHT_BRACE, "Expect '}' after block.")

}

function :: proc(type: FunctionType) {
	compiler: Compiler
	init_compiler(&compiler, type)
	begin_scope()

	consume(.LEFT_PAREN, "Expect '(' after function name.")
	if !check(.RIGHT_PAREN) {
		for {
			current.function.arity += 1
			if current.function.arity > 255 {
				error_at_current("Can't have more than 255 parameters.")
			}
			constant := parse_variable("Expect parameter name.")
			define_variable(constant, false)
			if !match(.COMMA) do break
		}
	}
	consume(.RIGHT_PAREN, "Expect ')' after parameters.")
	consume(.LEFT_BRACE, "Expect '{' before function body.")
	block()

	function := end_compiler()

	constant_idx := add_constant(current_chunk(), obj_val(function))
	emit_bytes(u8(OpCode.CLOSURE), u8(constant_idx))

	for i in 0 ..< function.upvalue_count {
		emit_byte(compiler.upvalues[i].is_local ? 1 : 0)
		emit_byte(compiler.upvalues[i].idx)
	}
}


fun_declaration :: proc() {
	global := parse_variable("Expect function name.")
	mark_initialized()
	function(.FUNCTION)
	define_variable(global, false)
}

var_declaration :: proc(final: bool = false) {
	global := parse_variable("Expect variable name.", final)

	if match(.EQUAL) {
		expression()
	} else {
		emit_byte(u8(OpCode.NIL))
	}
	consume(.SEMICOLON, "Expect ';' after variable declaration.")
	define_variable(global, final = final)
}

expression_statement :: proc() {
	expression()
	consume(.SEMICOLON, "Expect ';' after expression.")
	emit_byte(u8(OpCode.POP))
}

for_statement :: proc() {
	begin_scope()
	consume(.LEFT_PAREN, "Expect '(' after 'for'.")

	if match(.SEMICOLON) {
		//no initializer
	} else if match(.VAR) {
		var_declaration()
	} else {
		expression_statement()
	}

	loop_start := len(current_chunk().code)

	exit_jump := -1
	if !match(.SEMICOLON) {
		expression()
		consume(.SEMICOLON, "Expect ';' after loop condition.")
		exit_jump = emit_jump(u8(OpCode.JUMP_IF_FALSE))
		emit_byte(u8(OpCode.POP))
	}

	if !match(.RIGHT_PAREN) {
		body_jump := emit_jump(u8(OpCode.JUMP))
		increment_start := len(current_chunk().code)
		expression()
		emit_byte(u8(OpCode.POP))
		consume(.RIGHT_PAREN, "Expect ')' after for clauses.")

		emit_loop(loop_start)
		loop_start = increment_start
		patch_jump(body_jump)
	}

	statement()
	emit_loop(loop_start)

	if exit_jump != -1 {
		patch_jump(exit_jump)
		emit_byte(u8(OpCode.POP))
	}
	end_scope()


}

if_statement :: proc() {
	consume(.LEFT_PAREN, "Expect '(' after 'if'.")
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after condition.")
	then_jump := emit_jump(u8(OpCode.JUMP_IF_FALSE))
	statement()

	else_jump := emit_jump(u8(OpCode.JUMP))

	patch_jump(then_jump)

	if match(.ELSE) do statement()
	patch_jump(else_jump)
}

switch_statement :: proc() {
	consume(.LEFT_PAREN, "Expect '(' after 'switch'.")
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after condition.")
	consume(.LEFT_BRACE, "Expect '{' after switch expression.")
	exit_jumps: [dynamic]int
	defer delete(exit_jumps)

	for !match(.RIGHT_BRACE) {
		emit_byte(u8(OpCode.DUPLICATE))
		consume(.CASE, "Expect 'case'.")
		expression()
		consume(.COLON, "Expect ':' after case value.")
		emit_byte(u8(OpCode.EQUAL))
		then_jump := emit_jump(u8(OpCode.JUMP_IF_FALSE))
		emit_byte(u8(OpCode.POP))
		statement()
		append(&exit_jumps, emit_jump(u8(OpCode.JUMP)))
		patch_jump(then_jump)
		emit_byte(u8(OpCode.POP))
	}
	emit_byte(u8(OpCode.POP))

	for jump in exit_jumps {
		patch_jump(jump)
	}


}

print_statement :: proc() {
	expression()
	consume(.SEMICOLON, "Expect ';' after value.")
	emit_byte(u8(OpCode.PRINT))
}

return_statement :: proc() {
	if current.type == .SCRIPT {
		error("Can't return from top-level code.")
	}
	if match(.SEMICOLON) {
		emit_return()
	} else {
		expression()
		consume(.SEMICOLON, "Expect ';' after return statement.")
		emit_byte(u8(OpCode.RETURN))
	}
}

while_statement :: proc() {
	loop_start := len(current_chunk().code)
	consume(.LEFT_PAREN, "Expect '(' after 'while'.")
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after condition.")

	exit_jump := emit_jump(u8(OpCode.JUMP_IF_FALSE))
	emit_byte(u8(OpCode.POP))
	statement()
	emit_loop(loop_start)

	patch_jump(exit_jump)
	emit_byte(u8(OpCode.POP))

}

synchronize :: proc() {
	parser.panic_mode = false

	for parser.current.type != .EOF {
		if parser.previous.type == .SEMICOLON do return
		#partial switch parser.current.type {
		case .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN:
			return
		case:
		}
		advance()
	}
}

declaration :: proc() {
	if match(.FUN) {
		fun_declaration()
	} else if match(.VAR) {
		var_declaration()
	} else if match(.FINAL) {
		var_declaration(final = true)
	} else {
		statement()
	}
	if parser.panic_mode do synchronize()
}

statement :: proc() {
	if match(.PRINT) {
		print_statement()
	} else if match(.FOR) {
		for_statement()
	} else if match(.IF) {
		if_statement()
	} else if match(.RETURN) {
		return_statement()
	} else if match(.SWITCH) {
		switch_statement()
	} else if match(.WHILE) {
		while_statement()
	} else if match(.LEFT_BRACE) {
		begin_scope()
		block()
		end_scope()
	} else {
		expression_statement()
	}
}

emit_return :: proc() {
	emit_byte(u8(OpCode.NIL))
	emit_byte(u8(OpCode.RETURN))
}

emit_constant :: proc(value: Value) {
	write_constant(current_chunk(), value, parser.previous.line)
}

patch_jump :: proc(offset: int) {
	jump := len(current_chunk().code) - offset - 2

	if jump > int(max(u16)) {
		error("Too much code to jump over.")
	}

	current_chunk().code[offset] = u8(jump >> 8)
	current_chunk().code[offset + 1] = u8(jump & 0xff)
}

init_compiler :: proc(compiler: ^Compiler, type: FunctionType) {
	compiler.enclosing = current
	compiler.type = type
	compiler.function = new_function()
	current = compiler

	if type != .SCRIPT {
		string_data := string(mem.slice_ptr(parser.previous.start, parser.previous.length))
		current.function.name = copy_string(string_data)
	}
	empty_str := ""

	//reserve local slot for internal use
	append(&current.locals, Local{name = Token{start = raw_data(empty_str)}})


}

free_compiler :: proc(compiler: ^Compiler) {
	delete(compiler.locals)
}

error_at_current :: proc(msg: string) {
	error_at(&parser.current, msg)
}

error :: proc(msg: string) {
	error_at(&parser.previous, msg)
}

error_at :: proc(token: ^Token, msg: string) {
	if parser.panic_mode do return
	parser.panic_mode = true
	fmt.eprintf("[line %d] Error", token.line)

	if token.type == .EOF {
		fmt.eprintf(" at end")
	} else if token.type == .ERROR {
		//nothing
	} else {
		token_str := string(mem.slice_ptr(token.start, token.length))
		fmt.eprintf(" at '%s'", token_str)
	}
	fmt.eprintf(": %s\n", msg)
	parser.had_error = true
}

token_text :: proc(token: Token) -> string {
	token_bytes := mem.ptr_to_bytes(token.start, token.length)
	return string(token_bytes)

}

package olox

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

DEBUG_PRINT_CODE :: false

U8_COUNT_MAX :: max(u8)

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
	locals:      [U8_COUNT_MAX]Local,
	local_count: int,
	scope_depth: int,
}

Local :: struct {
	name:  Token,
	depth: int,
	final: bool,
}

rules: [TokenType]ParseRule = {
	.LEFT_PAREN    = {grouping, nil, .NONE},
	.RIGHT_PAREN   = {nil, nil, .NONE},
	.LEFT_BRACE    = {nil, nil, .NONE},
	.RIGHT_BRACE   = {nil, nil, .NONE},
	.COMMA         = {nil, nil, .NONE},
	.DOT           = {nil, nil, .NONE},
	.MINUS         = {unary, binary, .TERM},
	.PLUS          = {nil, binary, .TERM},
	.SEMICOLON     = {nil, nil, .NONE},
	.SLASH         = {nil, binary, .FACTOR},
	.STAR          = {nil, binary, .FACTOR},
	.BANG          = {unary, nil, .NONE},
	.BANG_EQUAL    = {nil, binary, .EQUALITY},
	.EQUAL         = {nil, nil, .NONE},
	.EQUAL_EQUAL   = {nil, binary, .COMPARISON},
	.GREATER       = {nil, binary, .COMPARISON},
	.GREATER_EQUAL = {nil, binary, .COMPARISON},
	.LESS          = {nil, binary, .COMPARISON},
	.LESS_EQUAL    = {nil, binary, .COMPARISON},
	.IDENTIFIER    = {variable, nil, .NONE},
	.STRING        = {string_proc, nil, .NONE},
	.NUMBER        = {number, nil, .NONE},
	.AND           = {nil, nil, .NONE},
	.CLASS         = {nil, nil, .NONE},
	.ELSE          = {nil, nil, .NONE},
	.FALSE         = {literal, nil, .NONE},
	.FOR           = {nil, nil, .NONE},
	.FUN           = {nil, nil, .NONE},
	.IF            = {nil, nil, .NONE},
	.NIL           = {literal, nil, .NONE},
	.OR            = {nil, nil, .NONE},
	.PRINT         = {nil, nil, .NONE},
	.RETURN        = {nil, nil, .NONE},
	.SUPER         = {nil, nil, .NONE},
	.THIS          = {nil, nil, .NONE},
	.TRUE          = {literal, nil, .NONE},
	.VAR           = {nil, nil, .NONE},
	.WHILE         = {nil, nil, .NONE},
	.FINAL         = {nil, nil, .NONE},
	.ERROR         = {nil, nil, .NONE},
	.EOF           = {nil, nil, .NONE},
}


parser: Parser
current: ^Compiler
compiling_chunk: ^Chunk

current_chunk :: proc() -> ^Chunk {
	return compiling_chunk
}

compile :: proc(source: string, chunk: ^Chunk) -> bool {
	init_scanner(source)
	compiler: Compiler
	init_compiler(&compiler)
	compiling_chunk = chunk

	advance()
	for !match(.EOF) {
		declaration()
	}
	end_compiler()
	return !parser.had_error
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

end_compiler :: proc() {
	emit_return()
	if DEBUG_PRINT_CODE && !parser.had_error {
		disassemble_chunk(current_chunk(), "code")
	}
}

begin_scope :: proc() {
	current.scope_depth += 1
}

end_scope :: proc() {
	current.scope_depth -= 1

	for current.local_count > 0 &&
	    current.locals[current.local_count - 1].depth > current.scope_depth {
		emit_byte(u8(OpCode.POP))
		current.local_count -= 1
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
	//TODO: set global long
	get_op, get_op_long, set_op: u8
	arg := resolve_local(current, name)
	if arg != -1 {
		get_op = u8(OpCode.GET_LOCAL)
		set_op = u8(OpCode.SET_LOCAL)
		get_op_long = get_op

		if can_assign && match(.EQUAL) {
			if current.locals[arg].final {
				error("Cannot assign to final variable.")
				return
			}
			expression()
			emit_bytes(set_op, u8(arg))
		} else {
			emit_bytes(get_op, u8(arg))
		}
	} else {
		arg = identifier_constant(name)
		get_op = u8(OpCode.GET_GLOBAL)
		set_op = u8(OpCode.SET_GLOBAL)
		get_op_long = u8(OpCode.GET_GLOBAL_LONG)

		if can_assign && match(.EQUAL) {
			expression()
			emit_bytes(set_op, u8(arg))
		} else {
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
	for i := compiler.local_count - 1; i >= 0; i -= 1 {
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

add_local :: proc(name: Token, final: bool = false) {
	if current.local_count == int(U8_COUNT_MAX) {
		error("Too many local variables in function")
		return
	}
	local := &current.locals[current.local_count]
	current.local_count += 1
	local.name = name
	local.depth = -1
	local.final = final
}

declare_variable :: proc(final: bool = false) {
	if current.scope_depth == 0 do return

	name := parser.previous
	for i := current.local_count - 1; i >= 0; i -= 1 {
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

	declare_variable(final)
	if current.scope_depth > 0 do return 0

	return identifier_constant(&parser.previous)
}

mark_initialized :: proc() {
	current.locals[current.local_count - 1].depth = current.scope_depth
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

print_statement :: proc() {
	expression()
	consume(.SEMICOLON, "Expect ';' after value.")
	emit_byte(u8(OpCode.PRINT))
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
	if match(.VAR) {
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
	} else if match(.LEFT_BRACE) {
		begin_scope()
		block()
		end_scope()
	} else {
		expression_statement()
	}
}

emit_return :: proc() {
	emit_byte(u8(OpCode.RETURN))
}

emit_constant :: proc(value: Value) {
	write_constant(current_chunk(), value, parser.previous.line)
}

init_compiler :: proc(compiler: ^Compiler) {
	current = compiler
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

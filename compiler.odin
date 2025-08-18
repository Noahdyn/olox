package olox

import "core:fmt"
import "core:mem"
import "core:strconv"

DEBUG_PRINT_CODE :: false

ParseFn :: proc()

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
	.IDENTIFIER    = {nil, nil, .NONE},
	.STRING        = {nil, nil, .NONE},
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
	.ERROR         = {nil, nil, .NONE},
	.EOF           = {nil, nil, .NONE},
}


parser: Parser
compiling_chunk: ^Chunk

current_chunk :: proc() -> ^Chunk {
	return compiling_chunk
}

compile :: proc(source: string, chunk: ^Chunk) -> bool {
	init_scanner(source)
	compiling_chunk = chunk

	advance()
	expression()
	consume(.EOF, "Expect end of expression.")
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

grouping :: proc() {
	expression()
	consume(.RIGHT_PAREN, "Expect ')' after expression.")
}

number :: proc() {
	value, _ := strconv.parse_f64(token_text(parser.previous))
	emit_constant(number_val(value))
}

unary :: proc() {
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

binary :: proc() {
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

literal :: proc() {
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
	prefix_rule()

	for precedence <= get_rule(parser.current.type).precedence {
		advance()
		infix_rule := get_rule(parser.previous.type).infix
		infix_rule()
	}
}

get_rule :: proc(type: TokenType) -> ^ParseRule {
	return &rules[type]
}

expression :: proc() {
	parse_precedence(.ASSIGNMENT)
}

emit_return :: proc() {
	emit_byte(u8(OpCode.RETURN))
}

emit_constant :: proc(value: Value) {
	write_constant(current_chunk(), value, parser.previous.line)
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
		fmt.eprintf(" at '%.*s'", token.length, token.start)
	}
	fmt.eprintf(": %s\n", msg)
	parser.had_error = true
}

token_text :: proc(token: Token) -> string {
	token_bytes := mem.ptr_to_bytes(token.start, token.length)
	return string(token_bytes)

}

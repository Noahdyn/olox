package olox

import "core:mem"

Scanner :: struct {
	start:   ^u8,
	end:     ^u8,
	current: ^u8,
	line:    int,
}

Token :: struct {
	type:         TokenType,
	start:        ^u8,
	length, line: int,
}

TokenType :: enum {
	// Single-character tokens.
	LEFT_PAREN,
	RIGHT_PAREN,
	LEFT_BRACE,
	RIGHT_BRACE,
	COMMA,
	DOT,
	MINUS,
	PLUS,
	SEMICOLON,
	SLASH,
	STAR,
	// One or two character tokens.
	BANG,
	BANG_EQUAL,
	EQUAL,
	EQUAL_EQUAL,
	GREATER,
	GREATER_EQUAL,
	LESS,
	LESS_EQUAL,
	// Literals.
	IDENTIFIER,
	STRING,
	NUMBER,
	// Keywords.
	AND,
	CLASS,
	ELSE,
	FALSE,
	FOR,
	FUN,
	IF,
	NIL,
	OR,
	PRINT,
	RETURN,
	SUPER,
	THIS,
	TRUE,
	VAR,
	WHILE,
	ERROR,
	EOF,
}

scanner: Scanner

init_scanner :: proc(source: string) {
	scanner.start = raw_data(source)
	scanner.end = mem.ptr_offset(raw_data(source), len(source))
	scanner.current = raw_data(source)
	scanner.line = 1
}

scan_token :: proc() -> Token {
	scanner.start = scanner.current
	if (is_at_end()) do return make_token(.EOF)

	return error_token("Unexpected character.")

}

make_token :: proc(type: TokenType) -> Token {
	token := Token {
		type   = type,
		start  = scanner.start,
		length = (int)(uintptr(scanner.current) - uintptr(scanner.start)),
		line   = scanner.line,
	}
	return token
}

error_token :: proc(msg: string) -> Token {
	token := Token {
		type   = .ERROR,
		start  = raw_data(msg),
		length = len(msg),
		line   = scanner.line,
	}
	return token
}

is_at_end :: proc() -> bool {
	return scanner.current >= scanner.end

}

package olox

import "core:fmt"
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
	FINAL,
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

advance_scanner :: proc() -> u8 {
	c := scanner.current^
	scanner.current = mem.ptr_offset(scanner.current, 1)
	return c

}

@(private = "file")
match :: proc(expected: u8) -> bool {
	if is_at_end() do return false
	if scanner.current^ != expected do return false
	scanner.current = mem.ptr_offset(scanner.current, 1)
	return true
}

peek :: proc() -> u8 {
	return scanner.current^
}

peek_next :: proc() -> u8 {
	if is_at_end() do return 0
	return mem.ptr_offset(scanner.current, 1)^
}


scan_token :: proc() -> Token {
	skip_white_space()
	scanner.start = scanner.current
	if (is_at_end()) do return make_token(.EOF)

	c := advance_scanner()

	if is_digit(c) do return number_token()
	if is_alpha(c) do return identifier_token()

	switch c {
	case '(':
		return make_token(.LEFT_PAREN)
	case ')':
		return make_token(.RIGHT_PAREN)
	case '{':
		return make_token(.LEFT_BRACE)
	case '}':
		return make_token(.RIGHT_BRACE)
	case ';':
		return make_token(.SEMICOLON)
	case ',':
		return make_token(.COMMA)
	case '.':
		return make_token(.DOT)
	case '-':
		return make_token(.MINUS)
	case '+':
		return make_token(.PLUS)
	case '/':
		return make_token(.SLASH)
	case '*':
		return make_token(.STAR)
	case '!':
		return make_token(match('=') ? .BANG_EQUAL : .EQUAL)
	case '=':
		return make_token(match('=') ? .EQUAL_EQUAL : .EQUAL)
	case '<':
		return make_token(match('=') ? .LESS_EQUAL : .LESS)
	case '>':
		return make_token(match('=') ? .GREATER_EQUAL : .GREATER)
	case '"':
		return string_token()

	}

	return error_token("Unexpected character.")

}

is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

is_alpha :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

skip_white_space :: proc() {
	for {
		c := peek()

		switch c {
		case ' ', '\r', '\t':
			advance_scanner()
		case '/':
			if peek_next() == '/' {
				for peek() != '\n' && !is_at_end() do advance_scanner()
			} else do return
		case '\n':
			scanner.line += 1
			advance_scanner()
		case:
			return
		}
	}
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

string_token :: proc() -> Token {
	for peek() != '"' && !is_at_end() {
		if peek() == '\n' do scanner.line += 1
		advance_scanner()
	}
	if is_at_end() do return error_token("Unterminated string.")

	//closing quote
	advance_scanner()
	return make_token(.STRING)
}

number_token :: proc() -> Token {
	for is_digit(peek()) do advance_scanner()

	if peek() == '.' && is_digit(peek_next()) {
		//consume the '.'
		advance_scanner()
		for is_digit(peek()) do advance_scanner()
	}

	return make_token(.NUMBER)

}

identifier_token :: proc() -> Token {

	for is_alpha(peek()) || is_digit(peek()) do advance_scanner()
	return make_token(identifier_type())
}


identifier_type :: proc() -> TokenType {
	switch (scanner.start^) {
	case 'a':
		return check_keyword(1, 2, "nd", .AND)
	case 'c':
		return check_keyword(1, 4, "lass", .CLASS)
	case 'e':
		return check_keyword(1, 3, "lse", .ELSE)
	case 'f':
		if uintptr(scanner.current) - uintptr(scanner.start) > 1 {
			switch mem.ptr_offset(scanner.start, 1)^ {
			case 'a':
				return check_keyword(2, 3, "lse", .FALSE)
			case 'o':
				return check_keyword(2, 1, "r", .FOR)
			case 'u':
				return check_keyword(2, 1, "n", .FUN)
			case 'i':
				return check_keyword(2, 3, "nal", .FINAL)
			}
		}
	case 'i':
		return check_keyword(1, 1, "f", .IF)
	case 'n':
		return check_keyword(1, 2, "il", .NIL)
	case 'o':
		return check_keyword(1, 1, "r", .OR)
	case 'p':
		return check_keyword(1, 4, "rint", .PRINT)
	case 'r':
		return check_keyword(1, 5, "eturn", .RETURN)
	case 's':
		return check_keyword(1, 4, "uper", .SUPER)
	case 't':
		if int(uintptr(scanner.current) - uintptr(scanner.start)) > 1 {
			switch mem.ptr_offset(scanner.start, 1)^ {
			case 'h':
				return check_keyword(2, 2, "is", .THIS)
			case 'r':
				return check_keyword(2, 2, "ue", .TRUE)
			}
		}
	case 'v':
		return check_keyword(1, 2, "ar", .VAR)
	case 'w':
		return check_keyword(1, 4, "hile", .WHILE)
	}
	return .IDENTIFIER
}

check_keyword :: proc(start, length: int, rest: string, type: TokenType) -> TokenType {
	if (int(uintptr(scanner.current) - uintptr(scanner.start)) == start + length &&
		   mem.compare_byte_ptrs(
			   cast(^u8)(rawptr(uintptr(scanner.start) + uintptr(start))),
			   cast(^u8)raw_data(rest),
			   length,
		   ) ==
			   0) {
		return type
	}
	return .IDENTIFIER
}

is_at_end :: proc() -> bool {
	return scanner.current >= scanner.end

}

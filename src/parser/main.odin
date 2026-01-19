package main

import "../vm"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"

read_source_file :: proc(path: string) -> ([]byte, bool) {
	fh, err := os.open(path)
	if err != nil {
		fmt.printfln("unable to open file: %s", err)
		return nil, false
	}
	defer os.close(fh)

	size: i64
	size, err = os.file_size(fh)
	if err != nil {
		fmt.printfln("unable to get file size: %s", err)
		return nil, false
	}

	buf := make([]byte, size)

	read: int
	read, err = os.read(fh, buf)
	if err != nil {
		fmt.printfln("unable to read file: %s", err)
		return nil, false
	}
	if i64(read) != size {
		fmt.printfln("unable to read file: read %d bytes, expected %d", read, size)
		return nil, false
	}

	return buf, true
}

Lex :: enum {
	NumberLiteral,

	// keywords
	Ident,
	NumberType,

	// operators
	Colon,
	Equal,
	DoubleEqual,
	Plus,
	PlusEqual,

	// control flow
	For,
	If,
	Break,

	// separators
	BraceL,
	BraceR,
}

Token :: struct {
	kind: Lex,
	val:  []byte,
	line: int,
	char: int,
}

token_string :: proc(t: Token) -> string {
	return fmt.aprintf("%s %s", t.kind, string(t.val))
}

Parser :: struct {
	// Tokenizer
	sourceBuf:    []byte,
	i:            int,
	line:         int,
	char:         int,
	tokens:       [dynamic]Token,

	// AST
	expressions:  [dynamic]Expression,
	statements:   [dynamic]Statement,
	roots:        [dynamic]int,

	// Generator
	variables:    map[string]Variable,
	mem_offset:   u16,
	instructions: [dynamic]vm.Instruction,
	break_ixs:    [dynamic]int,
}

parser_new_token :: proc(p: ^Parser, kind: Lex, val: []byte) {
	append(&p.tokens, Token{kind, val, p.line, p.char})
}

parser_consume :: proc(p: ^Parser, expected: string) -> bool {
	for e in expected {
		if p.i >= len(p.sourceBuf) {
			return false
		}
		if byte(e) != p.sourceBuf[p.i] {
			return false
		}
		p.i += 1
	}
	return true
}

Ident :: struct {
	name: []byte,
}

Binary :: struct {
	left:  int,
	op:    Lex,
	right: int,
}

Expression :: union {
	u16,
	Binary,
	Ident,
}

// <name> : <type> = <expression>
Declaration :: struct {
	name:       []byte,
	expression: int,
	// type: NumberType,
}

// <name> = <expression>
Assignment :: struct {
	ident: Ident,
	right: int,
}

// for { <statements> }
For :: struct {
	block: []int,
}

// if <condition> { <statements> }
If :: struct {
	condition: int,
	block:     []int,
}

Break :: struct {}

Statement :: union {
	Declaration,
	Assignment,
	For,
	If,
	Break,
}

parse_literal :: proc(p: ^Parser, val: Token) -> (Expression, string) {
	#partial switch val.kind {
	case .NumberLiteral:
		v, ok := strconv.parse_u64(string(val.val))
		if !ok {
			return 0, fmt.aprintf(
				"invalid number literal: %s: line %d, char %d",
				string(val.val),
				val.line,
				val.char,
			)
		}
		if v > 65535 {
			return 0, fmt.aprintf(
				"number literal out of range: line %d, char %d",
				val.line,
				val.char,
			)
		}

		return u16(v), ""
	case:
		return 0, fmt.aprintf("expected number literal: line %d, char %d", val.line, val.char)
	}
}

parse_binary :: proc(p: ^Parser, left: Expression) -> (i: int, valid: bool, err: string) {
	if p.i + 1 >= len(p.tokens) {
		p.i += 1
		return
	}
	n := p.tokens[p.i + 1]

	#partial switch n.kind {
	case .DoubleEqual:
		// condition
		p.i += 2 // skip condition and move to next token

		lIdx := len(p.expressions)
		append(&p.expressions, left)

		rIdx: int
		rIdx, err = parse_expression(p)
		if len(err) > 0 {
			err = fmt.aprintf("invalid binary: %s", err)
			return
		}

		b := Binary{lIdx, n.kind, rIdx}
		i = len(p.expressions)
		append(&p.expressions, b)

		valid = true
		return
	case .Plus:
		// addition
		assert(false, "unimplemented")
	}

	p.i += 1
	return
}

parse_expression :: proc(p: ^Parser) -> (int, string) {
	t := p.tokens[p.i]

	try_binary :: proc(p: ^Parser, left: Expression) -> (int, string) {
		i, valid, err := parse_binary(p, left)
		if len(err) > 0 {
			err = fmt.aprintf("invalid binary expression: %s", err)
			return 0, err
		}
		if !valid {
			append(&p.expressions, left)
		}
		return len(p.expressions) - 1, ""
	}

	#partial switch t.kind {
	case .NumberLiteral:
		l, err := parse_literal(p, t)
		if len(err) > 0 {
			return 0, fmt.aprintf("invalid literal: %s", err)
		}
		return try_binary(p, l)
	case .Ident:
		return try_binary(p, Ident{t.val})
	}

	fmt.println(t)
	assert(false, "unreachable")
	return 0, ""
}

parse_var_decl :: proc(p: ^Parser) -> (d: Statement, err: string) {
	name := p.tokens[p.i].val
	p.i += 1

	colon := p.tokens[p.i]
	if colon.kind != .Colon {
		fmt.printfln("error: expected ':': line %d, char %d", colon.line, colon.char)
		return
	}
	p.i += 1

	type := p.tokens[p.i]
	if type.kind != .NumberType {
		fmt.printfln("error: expected number type: line %d, char %d", type.line, type.char)
		return
	}
	p.i += 1

	equal := p.tokens[p.i]
	if equal.kind != .Equal {
		fmt.printfln("error: expected '=': line %d, char %d", equal.line, equal.char)
		return
	}
	p.i += 1

	eIdx: int
	eIdx, err = parse_expression(p)
	if len(err) > 0 {
		err = fmt.aprintf("invalid var declaration: %s", err)
		return
	}

	d = Declaration{name, eIdx}
	return
}

parse_assignment :: proc(p: ^Parser) -> (a: Statement, err: string) {
	name := p.tokens[p.i].val
	p.i += 1

	op := p.tokens[p.i]
	p.i += 1

	#partial switch op.kind {
	case .Equal:
		assert(false, "unimplemented")
		return
	case .PlusEqual:
		rIdx: int
		rIdx, err = parse_expression(p)
		if len(err) > 0 {
			err = fmt.aprintf("invalid assignment: %s", err)
			return
		}

		append(&p.expressions, Ident{name})
		append(&p.expressions, Binary{left = len(p.expressions) - 1, op = .Plus, right = rIdx})
		a = Assignment{Ident{name}, len(p.expressions) - 1}
		return
	case:
		err = fmt.aprintf("expected '=' or '+=': line %d, char %d", op.line, op.char)
		return
	}
}

parse_for :: proc(p: ^Parser) -> (f: Statement, err: string) {
	kw := p.tokens[p.i]
	p.i += 1

	bl := p.tokens[p.i]
	p.i += 1
	if bl.kind != .BraceL {
		err = fmt.aprintf("expected '{{': line %d, char %d", bl.line, bl.char)
		return
	}

	block := [dynamic]int{}

	for p.i < len(p.tokens) {
		t := p.tokens[p.i]
		if t.kind == .BraceR {
			f = For{block[:]}

			p.i += 1
			return
		}

		st: Statement
		st, err = parse_statement(p)
		if len(err) > 0 {
			err = fmt.aprintf("invalid for statement: %s", err)
			return
		}

		append(&p.statements, st)
		append(&block, len(p.statements) - 1)
	}

	err = fmt.aprintf("unterminated for, expected '}}'")
	return
}

parse_if :: proc(p: ^Parser) -> (i: Statement, err: string) {
	kw := p.tokens[p.i]
	p.i += 1

	condition: int
	condition, err = parse_expression(p)
	if len(err) > 0 {
		err = fmt.aprintf("invalid if statement: %s", err)
		return
	}

	bl := p.tokens[p.i]
	p.i += 1
	if bl.kind != .BraceL {
		err = fmt.aprintf("expected '{{': line %d, char %d", bl.line, bl.char)
		return
	}

	block := [dynamic]int{}

	for p.i < len(p.tokens) {
		t := p.tokens[p.i]
		if t.kind == .BraceR {
			i = If{condition, block[:]}

			p.i += 1
			return
		}

		st: Statement
		st, err = parse_statement(p)
		if len(err) > 0 {
			err = fmt.aprintf("invalid if statement body: %s", err)
			return
		}

		append(&p.statements, st)
		append(&block, len(p.statements) - 1)
	}

	err = fmt.aprintf("unterminated if, expected '}}'")
	return
}

parse_statement :: proc(p: ^Parser) -> (Statement, string) {
	t := p.tokens[p.i]

	#partial switch t.kind {
	case .Ident:
		if p.i + 1 >= len(p.tokens) {
			return Declaration{}, fmt.aprintf("expected ':' or '=' after identifier: line %d, char %d", t.line, t.char)
		}
		nt := p.tokens[p.i + 1]
		#partial switch nt.kind {
		case .Colon:
			return parse_var_decl(p)
		case:
			return parse_assignment(p)
		}
	case .For:
		return parse_for(p)
	case .If:
		return parse_if(p)
	case .Break:
		p.i += 1
		return Break{}, ""
	}

	return Declaration{}, fmt.aprintf("expected statement: line %d, char %d", t.line, t.char)
}


Variable :: struct {
	offset: u16,
	// type: NumberType,
}

gen_expr :: proc(p: ^Parser, expr: Expression) -> string {
	switch expr in expr {
	case u16:
		append(
			&p.instructions,
			// LOAD expr
			vm.Instruction{op = .LI, dst = .R0, val = expr},
		)
	case Binary:
		if err := gen_expr(p, p.expressions[expr.left]); len(err) > 0 {
			return err
		}
		// need to store result in scratch
		append(&p.instructions, vm.Instruction{op = .MOV, dst = .R2, src = .R0})
		if err := gen_expr(p, p.expressions[expr.right]); len(err) > 0 {
			return err
		}

		#partial switch expr.op {
		case .DoubleEqual:
			append(
				&p.instructions,
				vm.Instruction{op = .SUB, dst = .R2, src = .R0},
				vm.Instruction{op = .MOV, dst = .R0, src = .R2},
			)
		case .Plus:
			append(&p.instructions, vm.Instruction{op = .ADD, dst = .R0, src = .R2})
		case:
			return "invalid operand in binary expression"
		}
	case Ident:
		srcName := string(expr.name)
		src, ok := p.variables[srcName]
		if !ok {
			return fmt.aprintf("variable '%s' is undefined", srcName)
		}

		append(
			&p.instructions,
			// LOAD expr
			vm.Instruction{op = .LI, dst = .R0, val = src.offset},
			vm.Instruction{op = .LOAD, dst = .R0, src = .R0},
		)
	}

	return ""
}

validate_and_gen_ix :: proc(p: ^Parser, stmt: Statement) -> string {
	switch s in stmt {
	case Declaration:
		dstName := string(s.name)
		if _, ok := p.variables[dstName]; ok {
			return fmt.aprintf("variable '%s' already declared", dstName)
		}
		dst := Variable{p.mem_offset}
		p.mem_offset += 1
		p.variables[dstName] = dst

		if err := gen_expr(p, p.expressions[s.expression]); len(err) > 0 {
			return err
		}

		append(
			&p.instructions,
			// STORE expr
			vm.Instruction{op = .LI, dst = .R1, val = dst.offset},
			vm.Instruction{op = .STORE, dst = .R1, src = .R0},
		)
	case Assignment:
		dstName := string(s.ident.name)
		dst, ok := p.variables[dstName]
		if !ok {
			return fmt.aprintf("variable '%s' is undefined", dstName)
		}

		if err := gen_expr(p, p.expressions[s.right]); len(err) > 0 {
			return err
		}


		append(
			&p.instructions,
			// STORE expr
			vm.Instruction{op = .LI, dst = .R1, val = dst.offset},
			vm.Instruction{op = .STORE, dst = .R1, src = .R0},
		)
	case For:
		start := len(p.instructions)

		for bs in s.block {
			if err := validate_and_gen_ix(p, p.statements[bs]); len(err) > 0 {
				return err
			}
		}

		append(&p.instructions, vm.Instruction{op = .J, val = u16(start)})

		for bix in p.break_ixs {
			p.instructions[bix].val = u16(len(p.instructions))
		}
		clear(&p.break_ixs)
	case If:
		if err := gen_expr(p, p.expressions[s.condition]); len(err) > 0 {
			return err
		}

		jump_ix := len(p.instructions)
		append(&p.instructions, vm.Instruction{op = .JNZ})

		for bs in s.block {
			if err := validate_and_gen_ix(p, p.statements[bs]); len(err) > 0 {
				return err
			}
		}

		p.instructions[jump_ix].val = u16(len(p.instructions))
	case Break:
		append(&p.instructions, vm.Instruction{op = .J})
		append(&p.break_ixs, len(p.instructions) - 1)
	}

	return ""
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usage: parser <file>")
		return
	}

	// track: mem.Tracking_Allocator
	// mem.tracking_allocator_init(&track, context.allocator)
	// context.allocator = mem.tracking_allocator(&track)
	//
	// defer {
	// 	if len(track.allocation_map) > 0 {
	// 		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
	// 		for _, entry in track.allocation_map {
	// 			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
	// 		}
	// 	}
	// 	mem.tracking_allocator_destroy(&track)
	// }

	sourceBuf, ok := read_source_file(os.args[1])
	if !ok {
		return
	}

	// parse into tokens

	p := Parser {
		sourceBuf = sourceBuf,
		line      = 1,
	}

	outer: for {
		if p.i >= len(sourceBuf) {
			break
		}

		c := sourceBuf[p.i]

		switch {
		case c == '\n':
			p.line += 1
			p.char = -1
		case c == '/':
			if p.i + 1 < len(sourceBuf) && sourceBuf[p.i + 1] == '/' {
				p.i += 1
				for {
					p.i += 1
					if p.i >= len(sourceBuf) {
						break
					}
					if sourceBuf[p.i] == '\n' {
						p.line += 1
						continue outer
					}
				}
			}
		case c == ':':
			parser_new_token(&p, .Colon, nil)
		case c == '=':
			n := p.i + 1
			if n < len(sourceBuf) && sourceBuf[n] == '=' {
				p.i += 1
				parser_new_token(&p, .DoubleEqual, nil)
				p.char += 1
			} else {
				parser_new_token(&p, .Equal, nil)
			}
		case c == '{':
			parser_new_token(&p, .BraceL, nil)
		case c == '}':
			parser_new_token(&p, .BraceR, nil)
		case c == '+':
			n := p.i + 1
			if n < len(sourceBuf) && sourceBuf[n] == '=' {
				p.i += 1
				parser_new_token(&p, .PlusEqual, nil)
				p.char += 1
			} else {
				parser_new_token(&p, .Plus, nil)
			}
		// keywords or idents
		case c >= 97 && c <= 122:
			start, end, ok := p.i, 0, false

			switch c {
			// control flow
			case 'f':
				// for
				p.i += 1
				p.char += 1
				if ok = parser_consume(&p, "or"); ok {
					parser_new_token(&p, .For, nil)
					p.char += 2
				}
			case 'i':
				// if
				p.i += 1
				p.char += 1
				if ok = parser_consume(&p, "f"); ok {
					parser_new_token(&p, .If, nil)
					p.char += 1
				}
			case 'b':
				// break
				p.i += 1
				p.char += 1
				if ok = parser_consume(&p, "reak"); ok {
					parser_new_token(&p, .Break, nil)
					p.char += 4
				}
			// types
			case 'n':
				// number
				p.i += 1
				p.char += 1
				if ok = parser_consume(&p, "umber"); ok {
					parser_new_token(&p, .NumberType, nil)
					p.char += 5
				}
			}

			// Ident
			if !ok {
				for {
					p.i += 1
					p.char += 1

					if p.i >= len(sourceBuf) || (sourceBuf[p.i] < 97 || sourceBuf[p.i] > 122) {
						parser_new_token(&p, .Ident, sourceBuf[start:p.i])
						continue outer
					}
				}
			}
		// number literals
		case c >= 48 && c <= 57:
			start := p.i

			for {
				p.i += 1
				p.char += 1

				if p.i >= len(sourceBuf) || (sourceBuf[p.i] < 48 || sourceBuf[p.i] > 57) {
					parser_new_token(&p, .NumberLiteral, sourceBuf[start:p.i])
					continue outer
				}
			}
		}

		p.i += 1
		p.char += 1
	}

	fmt.println()
	fmt.println("tokens:")
	for t in p.tokens {
		fmt.println(token_string(t))
	}

	// parse tokens into AST

	p.i = 0

	for p.i < len(p.tokens) {
		if st, err := parse_statement(&p); len(err) > 0 {
			assert(false, fmt.aprintf("error: %s", err))
		} else {
			append(&p.statements, st)
			append(&p.roots, len(p.statements) - 1)
		}
	}

	fmt.println()
	fmt.println("expressions:")
	for e in p.expressions {
		fmt.println(e)
	}

	fmt.println()
	fmt.println("statements:")
	for s in p.statements {
		fmt.println(s)
	}

	fmt.println()
	fmt.println("roots:")
	for i in p.roots {
		fmt.println(p.statements[i])
	}

	for i in p.roots {
		if err := validate_and_gen_ix(&p, p.statements[i]); len(err) > 0 {
			assert(false, fmt.aprintf("error: %s", err))
		}
	}

	append(&p.instructions, vm.Instruction{op = .EXIT})

	fmt.println()
	fmt.println("instructions:")
	for ix in p.instructions {
		fmt.println(ix)
	}
}

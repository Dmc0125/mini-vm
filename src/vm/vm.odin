package vm

Register :: enum u8 {
	// expression result
	R0,
	// address
	R1,
	// scratch
	R2,
	R3,
	Count,
}

Op :: enum {
	// data movement

	// load immediate value into register
	LI,
	// copy value between registers
	MOV,
	// load register value from memory addres
	LOAD,
	// store register value at memory address
	STORE,

	// arithmetic

	// add 2 registers
	ADD,
	// add register and immediate
	ADDI,
	// sub 2 registers
	SUB,
	// sub register and immediate
	SUBI,

	// control flow

	// jump
	J,
	// jump if zero
	JZ,
	// jump if not 0
	JNZ,

	//
	TRAP,
	EXIT,
}

Trap :: enum u8 {
	PUTU,
	PUTC,
	PUTS,
}

Instruction :: struct {
	op:       Op,
	dst:      Register,
	src:      Register,
	val:      u16,
	trapFlag: Trap,
}

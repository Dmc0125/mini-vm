package main

import "core:fmt"

MEMORY_MAX :: (1 << 16)

Register :: enum u8 {
	R0,
	R1,
	R2,
	R3,
}

Op :: enum u8 {
	// load immediate value into register
	LI,
	// load value between registers
	MOV,
	// load *value* from memory addres
	LOAD,
	// store *value* at memory address
	STORE,
	// add 2 values
	ADD,
	EXIT,
}


Instruction :: struct {
	op:  Op,
	dst: Register,
	src: Register,
	val: u16,
}

Vm :: struct {
	pc:        u64,
	registers: [4]u16,
	memory:    [MEMORY_MAX]u16,
}

// [8 op] [16 dst] [16 src]

main :: proc() {
	// LI R0 122
	// LI R1 12
	// ADD R0 R1
	// EXIT

	vm: Vm

	ixs := [?]Instruction {
		{op = .LI, dst = .R0, val = 122},
		{op = .MOV, dst = .R1, src = .R0},
		{op = .ADD, dst = .R0, src = .R1},
		{op = .LI, dst = .R2, val = 0},
		{op = .STORE, dst = .R2, src = .R1},
		{op = .LOAD, dst = .R3, src = .R2},
		{op = .EXIT},
	}

	outer: for {
		assert(vm.pc < len(ixs), "pc is greater than count of instructions")

		ix := ixs[vm.pc]
		fmt.println(ix)

		switch ix.op {
		case .LI:
			vm.registers[ix.dst] = ix.val
		case .MOV:
			vm.registers[ix.dst] = vm.registers[ix.src]
		case .LOAD:
			vm.registers[ix.dst] = vm.memory[vm.registers[ix.src]]
		case .STORE:
			vm.memory[vm.registers[ix.dst]] = vm.registers[ix.src]
		case .ADD:
			vm.registers[ix.dst] = vm.registers[ix.dst] + vm.registers[ix.src]
		case .EXIT:
			break outer
		}

		vm.pc += 1
	}

	fmt.println(vm.registers)
	fmt.println("exited successfully")
}

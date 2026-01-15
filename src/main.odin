package main

import "core:fmt"

MEMORY_MAX :: (1 << 16)

Register :: enum u8 {
	R0,
	R1,
	R2,
	R3,
	Count,
}

Op :: enum u8 {
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

Vm :: struct {
	pc:        u16,
	registers: [Register.Count]u16,
	memory:    [MEMORY_MAX]u16,
}

// [8 op] [4 dst] [4 src] - [16 immediate]

main :: proc() {
	vm: Vm

	// store 1 10 times in memory
	//
	// init:
	// 0: LI R0 1   ; v = 1
	// 1: LI R1 10  ; i = 10
	// 2: LI R2 100 ; ptr = 100
	//
	// loop:
	// 3: STORE [R2] R0 ; memory[ptr] = v
	// 4: ADDI R2 1     ; ptr++
	// 5: SUB R1 1      ; i--
	// 6: JNZ R1 3      ; if r1 != 0; contine loop
	//
	// 7: EXIT
	//
	// Equivalent code:
	//
	// func main() {
	//     m := make(u16, 10)
	//     i := 1
	//
	//     for i in 0..10 {
	//         m[i] = v
	//     }
	// }

	ixs := [?]Instruction {
		// init
		{op = .LI, dst = .R0, val = 1},
		{op = .LI, dst = .R1, val = 10},
		{op = .LI, dst = .R2, val = 100},

		// loop
		{op = .STORE, dst = .R2, src = .R0},
		{op = .ADDI, dst = .R2, val = 1},
		{op = .SUBI, dst = .R1, val = 1},
		{op = .JNZ, src = .R1, val = 3},

		// print res
		{op = .STORE, dst = .R2, src = .R2},
		{op = .TRAP, trapFlag = .PUTU, src = .R2},
		{op = .LI, dst = .R3, val = 10},
		{op = .TRAP, trapFlag = .PUTC, src = .R3},

		// exist
		{op = .EXIT},
	}

	outer: for {
		assert(vm.pc < len(ixs), "pc is greater than count of instructions")

		ix := ixs[vm.pc]

		switch ix.op {
		case .LI:
			// fmt.println("LI", ix)
			vm.registers[ix.dst] = ix.val
		case .MOV:
			// fmt.println("MOV", ix)
			vm.registers[ix.dst] = vm.registers[ix.src]
		case .LOAD:
			// fmt.println("LOAD", ix)
			vm.registers[ix.dst] = vm.memory[vm.registers[ix.src]]
		case .STORE:
			// fmt.println("STORE", ix)
			vm.memory[vm.registers[ix.dst]] = vm.registers[ix.src]
		case .ADD:
			// fmt.println("ADD", ix)
			vm.registers[ix.dst] = vm.registers[ix.dst] + vm.registers[ix.src]
		case .ADDI:
			// fmt.println("ADDI", ix)
			vm.registers[ix.dst] = vm.registers[ix.dst] + ix.val
		case .SUB:
			// fmt.println("SUB", ix)
			vm.registers[ix.dst] = vm.registers[ix.dst] - vm.registers[ix.src]
		case .SUBI:
			// fmt.println("SUBI", ix)
			vm.registers[ix.dst] = vm.registers[ix.dst] - ix.val
		case .J:
			// fmt.println("J", ix)
			vm.pc = ix.val
			continue outer
		case .JZ:
			// fmt.println("JZ", ix)
			src, pc := vm.registers[ix.src], ix.val
			if src == 0 {
				vm.pc = pc
				continue outer
			}
		case .JNZ:
			// fmt.println("JNZ", ix)
			src, pc := vm.registers[ix.src], ix.val
			if src != 0 {
				vm.pc = pc
				continue outer
			}
		case .TRAP:
			// fmt.println("TRAP")
			v := vm.registers[ix.src]
			#partial switch ix.trapFlag {
			case .PUTU:
				fmt.print(v)
			case .PUTC:
				fmt.printf("%c", v)
			}
		case .EXIT:
			// fmt.println("EXIT", ix)
			break outer
		}

		vm.pc += 1
	}

	// fmt.println(vm.registers)
	// fmt.println(vm.memory[100:110])
	// fmt.println("exited successfully")
}

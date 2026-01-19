package vm

import "core:fmt"
MEMORY_MAX :: (1 << 16)

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

Vm :: struct {
	pc:        u16,
	registers: [Register.Count]u16,
	memory:    [MEMORY_MAX]u16,
}

vm_process_instructions :: proc(vm: ^Vm, ixs: []Instruction) -> string {
	outer: for {
		if len(ixs) > 65536 {
			return "too many instructions"
		}
		if vm.pc >= u16(len(ixs)) {
			return "pc is greater than count of instructions"
		}

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

	return ""
}

package main

import "./parser"
import "./vm"
import "core:fmt"
import "core:os"

main :: proc() {
	if len(os.args) < 3 {
		fmt.println("usage: main <file> <action>")
		return
	}

	filePath, action := os.args[1], os.args[2]

	switch action {
	case "parse":
		instructions, err := parser.parse(filePath)
		if len(err) > 0 {
			fmt.println(err)
			return
		}
		fmt.println(instructions)
	case "run":
		instructions, err := parser.parse(filePath)
		if len(err) > 0 {
			fmt.println(err)
			return
		}
		_vm: vm.Vm
		err = vm.vm_process_instructions(&_vm, instructions[:])
		if len(err) > 0 {
			fmt.println(err)
			return
		}
	case:
		fmt.printfln("unknown action: %s", action)
	}
}

package main

import (
	"fmt"
)

func bmcGetPowerState(machine *Machine) (string, error) {
	switch machine.BmcType {
	case "redfish":
		return redfishBmcGetPowerState(machine)
	case "amt":
		return amtBmcGetPowerState(machine)
	default:
		return "", fmt.Errorf("unknown bmc type: %s", machine.BmcType)
	}
}

func bmcResetToNetwork(machine *Machine, os string) error {
	err := matchboxSetMachineOs(machine, os)
	if err != nil {
		return err
	}
	switch machine.BmcType {
	case "redfish":
		return redfishBmcResetToNetwork(machine)
	case "amt":
		return amtBmcResetToNetwork(machine)
	default:
		return fmt.Errorf("unknown bmc type: %s", machine.BmcType)
	}
}

func bmcResetToDisk(machine *Machine) error {
	switch machine.BmcType {
	case "redfish":
		return redfishBmcResetToDisk(machine)
	case "amt":
		return amtBmcResetToDisk(machine)
	default:
		return fmt.Errorf("unknown bmc type: %s", machine.BmcType)
	}
}

func bmcReset(machine *Machine) error {
	switch machine.BmcType {
	case "redfish":
		return redfishBmcReset(machine)
	case "amt":
		return amtBmcReset(machine)
	default:
		return fmt.Errorf("unknown bmc type: %s", machine.BmcType)
	}
}

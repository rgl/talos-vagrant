package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
)

func matchboxSetMachineOs(machine *Machine, osName string) error {
	var profile string

	switch osName {
	case "talos":
		profile = fmt.Sprintf("%s-%s", machine.Role, machine.Arch)
	case "rescue":
		profile = fmt.Sprintf("rescue-%s", machine.Arch)
	case "rescue-wipe":
		profile = fmt.Sprintf("rescue-wipe-%s", machine.Arch)
	default:
		return fmt.Errorf("unknown os: %s", osName)
	}

	_, err := os.Stat(fmt.Sprintf("/var/lib/matchbox/profiles/%s.json", profile))
	if err != nil {
		return err
	}

	machineGroupPath := fmt.Sprintf("/var/lib/matchbox/groups/%s.json", machine.Name)

	data, err := ioutil.ReadFile(machineGroupPath)
	if err != nil {
		return err
	}

	var group map[string]interface{}

	err = json.Unmarshal(data, &group)
	if err != nil {
		return err
	}

	group["profile"] = profile

	data, err = json.Marshal(group)
	if err != nil {
		return err
	}

	err = ioutil.WriteFile(machineGroupPath, data, 0644)

	return err
}

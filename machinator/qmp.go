package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/digitalocean/go-qemu/qmp"
)

type qomSetCommand struct {
	Execute   string          `json:"execute"`
	Arguments qomSetArguments `json:"arguments"`
}

type qomSetArguments struct {
	Path     string `json:"path"`
	Property string `json:"property"`
	Value    int    `json:"value"`
}

// set the boot order to boot from disk.
// NB this is equivalent of using the following commands:
// 		./qmp-shell /tmp/qmp-talos-vagrant_w1.socket
// 		qom-list path=/machine/peripheral
// 		qom-list path=/machine/peripheral/net0
// 		qom-get  path=/machine/peripheral/net0 property=bootindex
// 		qom-set  path=/machine/peripheral/net0 property=bootindex value=-1
// 		qom-set  path=/machine/peripheral/net0 property=bootindex value=1
// 		qom-list path=/machine/peripheral/virtio-disk1
// 		qom-get  path=/machine/peripheral/virtio-disk1 property=bootindex
// 		qom-set  path=/machine/peripheral/virtio-disk1 property=bootindex value=-1
// 		qom-set  path=/machine/peripheral/virtio-disk1 property=bootindex value=1
// NB we cannot set the same bootindex value.
// see https://gist.github.com/rgl/dc38c6875a53469fdebb2e9c0a220c6c
func qmpSetBootOrderToDisk(machine *Machine) error {
	monitor, err := qmp.NewSocketMonitor("tcp", fmt.Sprintf("%s:%d", machine.BmcIp, machine.BmcQmpPort), 2*time.Second)
	if err != nil {
		return err
	}
	monitor.Connect()
	defer monitor.Disconnect()

	// remove net0 from boot.
	command := qomSetCommand{
		Execute: "qom-set",
		Arguments: qomSetArguments{
			Path:     "/machine/peripheral/net0",
			Property: "bootindex",
			Value:    -1,
		},
	}
	commandJson, err := json.Marshal(command)
	if err != nil {
		return err
	}
	_, err = monitor.Run(commandJson)
	if err != nil {
		return err
	}

	// add virtio-disk1 to boot.
	command = qomSetCommand{
		Execute: "qom-set",
		Arguments: qomSetArguments{
			Path:     "/machine/peripheral/virtio-disk1",
			Property: "bootindex",
			Value:    1,
		},
	}
	commandJson, err = json.Marshal(command)
	if err != nil {
		return err
	}
	_, err = monitor.Run(commandJson)
	if err != nil {
		return err
	}
	return nil
}

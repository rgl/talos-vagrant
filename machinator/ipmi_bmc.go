package main

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	ipmiChassisPowerRegexp = regexp.MustCompile("^Chassis Power is (.+)$")
)

type IpmitoolExecError struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

func (err *IpmitoolExecError) Error() string {
	return fmt.Sprintf("failed to exec ipmitool: exitCode=%d stdout=%s stderr=%s", err.ExitCode, err.Stdout, err.Stderr)
}

func ipmitool(machine *Machine, args ...string) (string, error) {
	args = append([]string{
		"-I", "lanplus",
		"-U", os.Getenv("IPMI_USERNAME"),
		"-P", os.Getenv("IPMI_PASSWORD"),
		"-H", machine.BmcIp,
		"-p", strconv.Itoa(machine.BmcPort)}, args...)

	var stderr, stdout bytes.Buffer

	cmd := exec.Command("ipmitool", args...)
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout

	err := cmd.Run()

	if err != nil {
		exitCode := -1
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ProcessState.ExitCode()
		}
		return "", &IpmitoolExecError{
			ExitCode: exitCode,
			Stdout:   stdout.String(),
			Stderr:   stderr.String(),
		}
	}

	return strings.TrimSpace(stdout.String()), nil
}

func ipmiBmcGetPowerState(machine *Machine) (string, error) {
	stdout, err := ipmitool(machine, "chassis", "power", "status")
	if err != nil {
		return "", err
	}
	m := ipmiChassisPowerRegexp.FindStringSubmatch(stdout)
	if m == nil {
		return "", fmt.Errorf("failed to parse ipmitool chassis power status. stdout=%s", stdout)
	}
	return m[1], nil
}

func ipmiBmcReset(machine *Machine) error {
	log.Printf("Forcing the system restart...")
	_, err := ipmitool(machine, "chassis", "power", "reset")
	if err != nil {
		return err
	}
	return nil
}

func ipmiBmcResetToNetwork(machine *Machine) error {
	return ipmiBmcResetToBootTarget(machine, "pxe")
}

func ipmiBmcResetToDisk(machine *Machine) error {
	return ipmiBmcResetToBootTarget(machine, "disk")
}

func ipmiBmcResetToBootTarget(machine *Machine, bootDevice string) error {
	powerState, err := ipmiBmcGetPowerState(machine)
	if err != nil {
		return err
	}
	log.Printf("Current System PowerState: %s", powerState)

	log.Printf("Setting the boot order to %s...", bootDevice)
	_, err = ipmitool(machine, "chassis", "bootdev", bootDevice)
	if err != nil {
		return err
	}

	if powerState != "off" {
		log.Printf("Forcing the system off...")
		_, err = ipmitool(machine, "chassis", "power", "off")
		if err != nil {
			return err
		}
		log.Printf("Waiting for the system to be off...")
		for {
			powerState, err = ipmiBmcGetPowerState(machine)
			if err == nil && powerState == "off" {
				break
			}
			time.Sleep(1 * time.Second)
		}
	}

	log.Printf("Forcing the system on...")
	_, err = ipmitool(machine, "chassis", "power", "on")
	if err != nil {
		return err
	}
	log.Printf("Waiting for the system to be on...")
	for {
		powerState, err = ipmiBmcGetPowerState(machine)
		if err == nil && powerState == "on" {
			break
		}
		time.Sleep(1 * time.Second)
	}

	// because vbmc-emulator does not support the setting the boot device to once.
	// we must revert the bootDevice to disk again.
	// NB this will only work after a power-cycle (from off to on); which
	//    makes this useless for my purposes of having it work immediately.
	// 	  see https://storyboard.openstack.org/#!/story/2005368#comment-175052
	// NB the qemu boot order is determined by each individual device `bootindex`, e.g.;
	//     	-device scsi-hd,drive=drive0,bootindex=0
	//    NB `-boot` seems to be only supported by BIOS (not UEFI).
	// NB setting the boot order from QMP seems to work, so we do that to
	//    workaround the BMC.
	if bootDevice != "disk" {
		bootDevice = "disk"
		// NB we also do it from vbmc side; because that will apply once
		//    the VM is started again; our qmp changes only last while the
		//    VM is on.
		log.Printf("Resetting the boot order to %s...", bootDevice)
		_, err = ipmitool(machine, "chassis", "bootdev", bootDevice)
		if err != nil {
			return err
		}
		log.Printf("Resetting the boot order to %s (QMP)...", bootDevice)
		err = qmpSetBootOrderToDisk(machine)
		if err != nil {
			return err
		}
	}

	return nil
}

package main

import (
	"fmt"
	"log"
	"time"

	"github.com/stmcginnis/gofish"
	"github.com/stmcginnis/gofish/redfish"
)

func redfishBmcGetPowerState(machine *Machine) (string, error) {
	_, system, err := redfishBmcGetSystem(machine)
	if err != nil {
		return "", err
	}
	return string(system.PowerState), nil
}

func redfishBmcReset(machine *Machine) error {
	_, system, err := redfishBmcGetSystem(machine)
	if err != nil {
		return err
	}
	log.Printf("Forcing the system restart...")
	err = system.Reset(redfish.ForceRestartResetType)
	if err != nil {
		return err
	}
	return nil
}

func redfishBmcResetToNetwork(machine *Machine) error {
	return redfishBmcResetToBootTarget(machine, redfish.PxeBootSourceOverrideTarget)
}

func redfishBmcResetToDisk(machine *Machine) error {
	return redfishBmcResetToBootTarget(machine, redfish.HddBootSourceOverrideTarget)
}

func redfishBmcResetToBootTarget(machine *Machine, bootTarget redfish.BootSourceOverrideTarget) error {
	c, system, err := redfishBmcGetSystem(machine)
	if err != nil {
		return err
	}

	log.Printf("Current System State:")
	log.Printf("	ODataID: %s", system.ODataID)
	log.Printf("	UUID: %s", system.UUID)
	log.Printf("	Name: %s", system.Name)
	log.Printf("	PowerState: %s", system.PowerState)
	log.Printf("	SupportedResetTypes: %s", system.SupportedResetTypes)
	log.Printf("	BootSourceOverrideEnabled: %s", system.Boot.BootSourceOverrideEnabled)
	log.Printf("	BootSourceOverrideTarget: %s", system.Boot.BootSourceOverrideTarget)

	log.Printf("Setting the boot order to %s...", bootTarget)
	err = system.SetBoot(redfish.Boot{
		// NB sushy-vbmc-emulator does not support Once :-(
		// see https://storyboard.openstack.org/#!/story/2005368#comment-175052
		BootSourceOverrideEnabled: redfish.OnceBootSourceOverrideEnabled,
		BootSourceOverrideTarget:  bootTarget,
	})
	if err != nil {
		return err
	}

	if system.PowerState != redfish.OffPowerState {
		log.Printf("Forcing the system off...")
		err = system.Reset(redfish.ForceOffResetType)
		if err != nil {
			return err
		}
		log.Printf("Waiting for the system to the off...")
		for {
			system, err = redfish.GetComputerSystem(c, system.ODataID)
			if err == nil && system.PowerState == redfish.OffPowerState {
				break
			}
			time.Sleep(1 * time.Second)
		}
	}

	log.Printf("Forcing the system on...")
	err = system.Reset(redfish.ForceOnResetType)
	if err != nil {
		return err
	}
	log.Printf("Waiting for the system to the on...")
	for {
		system, err = redfish.GetComputerSystem(c, system.ODataID)
		if err == nil && system.PowerState == redfish.OnPowerState {
			break
		}
		time.Sleep(1 * time.Second)
	}

	// because sushy-vbmc-emulator does not support the
	// OnceBootSourceOverrideEnabled BootSourceOverrideEnabled method.
	// we must revert the bootTarget to disk again.
	// NB this will only work after a power-cycle (from off to on); which
	//    makes this useless for my purposes of having it work immediately.
	// 	  see https://storyboard.openstack.org/#!/story/2005368#comment-175052
	// NB the qemu boot order is determined by each individual device `bootindex`, e.g.;
	//     	-device scsi-hd,drive=drive0,bootindex=0
	//    NB `-boot` seems to be only supported by BIOS (not UEFI).
	// NB setting the boot order from QMP seems to work, so we do that to
	//    workaround the BMC.
	if bootTarget != redfish.HddBootSourceOverrideTarget {
		bootTarget = redfish.HddBootSourceOverrideTarget
		// NB we also do it from sushy side; because that will apply once
		//    the VM is started again; our qmp changes only last while the
		//    VM is on.
		log.Printf("Resetting the boot order to %s...", bootTarget)
		err = system.SetBoot(redfish.Boot{
			BootSourceOverrideEnabled: redfish.OnceBootSourceOverrideEnabled,
			BootSourceOverrideTarget:  bootTarget,
		})
		if err != nil {
			return err
		}
		log.Printf("Resetting the boot order to %s (QMP)...", bootTarget)
		err = qmpSetBootOrderToDisk(machine)
		if err != nil {
			return err
		}
	}

	return nil
}

func redfishBmcGetSystem(machine *Machine) (*gofish.APIClient, *redfish.ComputerSystem, error) {
	if machine.BmcIp == "" {
		return nil, nil, fmt.Errorf("machine has no defined bmcIp")
	}
	if machine.BmcPort == 0 {
		return nil, nil, fmt.Errorf("machine has no defined bmcPort")
	}

	c, err := gofish.ConnectDefault(fmt.Sprintf("http://%s:%d", machine.BmcIp, machine.BmcPort))
	if err != nil {
		return nil, nil, err
	}

	systems, err := c.Service.Systems()
	if err != nil {
		return nil, nil, err
	}
	if len(systems) == 0 {
		return nil, nil, fmt.Errorf("machine has no system")
	}
	if len(systems) > 1 {
		return nil, nil, fmt.Errorf("machine has more than one system")
	}

	return c, systems[0], nil
}

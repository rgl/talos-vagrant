package main

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

type TalosExecError struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

func (err *TalosExecError) Error() string {
	return fmt.Sprintf("failed to exec talosctl: exitCode=%d stdout=%s stderr=%s", err.ExitCode, err.Stdout, err.Stderr)
}

func talosctl(args ...string) (string, error) {
	var stderr, stdout bytes.Buffer

	cmd := exec.Command("talosctl", args...)
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout

	err := cmd.Run()

	if err != nil {
		exitCode := -1
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ProcessState.ExitCode()
		}
		return "", &TalosExecError{
			ExitCode: exitCode,
			Stdout:   stdout.String(),
			Stderr:   stderr.String(),
		}
	}

	return strings.TrimSpace(stdout.String()), nil
}

func talosReboot(machine *Machine) error {
	// NB this will directly connect to the target machine (-e and
	//    -n addresses are the same) without going tru a control
	//    plane node.
	_, err := talosctl("-e", machine.Name, "-n", machine.Name, "reboot")

	return err
}

func talosReset(machine *Machine) error {
	// NB this will directly connect to the target machine (-e and
	//    -n addresses are the same) without going tru a control
	//    plane node.
	_, err := talosctl("-e", machine.Name, "-n", machine.Name, "reset")

	return err
}

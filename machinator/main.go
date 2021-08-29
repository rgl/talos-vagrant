package main

import (
	"bufio"
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	text_template "text/template"
	"time"
	_ "time/tzdata" // include the embedded timezone database.

	"github.com/tomruk/oui/ouidata"
)

type MachineStatus struct {
	Type       string    `json:"type"`
	Name       string    `json:"name"`
	BmcType    string    `json:"bmcType"`
	PowerState string    `json:"powerState"`
	Ip         string    `json:"ip"`
	Mac        string    `json:"mac"`
	MacVendor  string    `json:"macVendor"`
	Hostname   string    `json:"hostname"`
	ClientId   string    `json:"clientId"`
	ExpiresAt  time.Time `json:"expiresAt"`
}

type machineStatusByName []MachineStatus

func (a machineStatusByName) Len() int           { return len(a) }
func (a machineStatusByName) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }
func (a machineStatusByName) Less(i, j int) bool { return a[i].Name < a[j].Name }

// read from /vagrant/shared/machines.json
type Machine struct {
	Type       string `json:"type"`
	Name       string `json:"name"`
	Role       string `json:"role"`
	Arch       string `json:"arch"`
	Ip         string `json:"ip"`
	Mac        string `json:"mac"`
	BmcType    string `json:"bmcType"`
	BmcIp      string `json:"bmcIp"`
	BmcPort    int    `json:"bmcPort"`
	BmcQmpPort int    `json:"bmcQmpPort"` // NB used by the redfish BmtType to emulate "boot once" in libvirt.
}

// read from /var/lib/misc/dnsmasq.leases
// each line is <timestamp> <mac> <ip> <hostname> <client_id>
// e.g. 1624470573 ec:b1:d7:71:ff:f3 10.3.0.131 DESKTOP-8RFCDG6 01:ec:b1:d7:71:ff:f3
type DhcpLease struct {
	ExpiresAt time.Time
	Mac       string
	Ip        string
	Hostname  string
	ClientId  string
}

func GetMachinesStatus() ([]MachineStatus, error) {
	ouiDb, err := ouidata.NewDB()
	if err != nil {
		return nil, err
	}

	machines, err := GetMachines("machines.json")
	if err != nil {
		return nil, err
	}

	dhcpLeases, err := GetDhcpLeases("dnsmasq.leases")
	if err != nil {
		return nil, err
	}

	machinesMap := make(map[string]Machine)
	for _, m := range machines {
		machinesMap[m.Mac] = m
	}

	machinesStatusMap := make(map[string]MachineStatus)

	for _, m := range machines {
		macVendor, _ := ouiDb.Lookup(m.Mac)
		powerState, _ := bmcGetPowerState(&m)
		machinesStatusMap[m.Mac] = MachineStatus{
			Type:       m.Type,
			Name:       m.Name,
			BmcType:    m.BmcType,
			PowerState: powerState,
			Ip:         m.Ip,
			Mac:        m.Mac,
			MacVendor:  macVendor,
		}
	}

	for _, l := range dhcpLeases {
		if machine, ok := machinesStatusMap[l.Mac]; ok {
			machinesStatusMap[l.Mac] = MachineStatus{
				Type:       machine.Type,
				Name:       machine.Name,
				BmcType:    machine.BmcType,
				PowerState: machine.PowerState,
				Ip:         l.Ip,
				Mac:        machine.Mac,
				MacVendor:  machine.MacVendor,
				Hostname:   l.Hostname,
				ClientId:   l.ClientId,
				ExpiresAt:  l.ExpiresAt,
			}
		} else {
			macVendor, _ := ouiDb.Lookup(l.Mac)
			machinesStatusMap[l.Mac] = MachineStatus{
				Ip:        l.Ip,
				Mac:       l.Mac,
				MacVendor: macVendor,
				Hostname:  l.Hostname,
				ClientId:  l.ClientId,
				ExpiresAt: l.ExpiresAt,
			}
		}
	}

	machineStatus := make([]MachineStatus, 0, len(machinesStatusMap))

	for _, m := range machinesStatusMap {
		machineStatus = append(machineStatus, m)
	}

	sort.Sort(machineStatusByName(machineStatus))

	return machineStatus, nil
}

func GetMachines(filePath string) ([]Machine, error) {
	data, err := ioutil.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	var machines []Machine
	if err := json.Unmarshal(data, &machines); err != nil {
		return nil, err
	}
	return machines, nil
}

func GetDhcpLeases(filePath string) ([]DhcpLease, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	dhcpLeases := make([]DhcpLease, 0)

	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		timestamp, err := strconv.ParseInt(fields[0], 10, 64)
		if err != nil {
			return nil, err
		}
		dhcpLeases = append(dhcpLeases, DhcpLease{
			ExpiresAt: time.Unix(timestamp, 0).Local(),
			Mac:       fields[1],
			Ip:        fields[2],
			Hostname:  fields[3],
			ClientId:  fields[4],
		})
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return dhcpLeases, nil
}

func executeMachineAction(machine *Machine, action string) error {
	switch action {
	case "talos-shutdown":
		return talosShutdown(machine)
	case "talos-reboot":
		return talosReboot(machine)
	case "talos-reset":
		return talosReset(machine)
	case "bmc-reset-to-network-talos":
		return bmcResetToNetwork(machine, "talos")
	case "bmc-reset-to-network-rescue":
		return bmcResetToNetwork(machine, "rescue")
	case "bmc-reset-to-network-rescue-wipe":
		return bmcResetToNetwork(machine, "rescue-wipe")
	case "bmc-reset-to-disk":
		return bmcResetToDisk(machine)
	case "bmc-reset":
		return bmcReset(machine)
	case "matchbox-network-talos":
		return matchboxSetMachineOs(machine, "talos")
	case "matchbox-network-rescue":
		return matchboxSetMachineOs(machine, "rescue")
	case "matchbox-network-rescue-wipe":
		return matchboxSetMachineOs(machine, "rescue-wipe")
	}
	return fmt.Errorf("unsupported machine action: %s", action)
}

//go:embed machines-status.html
var machinesStatusTemplateText string

var machinesStatusTemplate = template.Must(template.New("MachinesStatus").Parse(machinesStatusTemplateText))

type machinesStatusData struct {
	Location        *time.Location
	MachinesStatus  []MachineStatus
	KubernetesNodes []KubernetesNode
}

//go:embed wipe.sh
var wipeScriptTemplateText string

var wipeScriptTemplate = text_template.Must(text_template.New("WipeScript").Parse(wipeScriptTemplateText))

type wipeScriptData struct {
	WipedUrl string
}

type logWriter struct {
}

func (writer logWriter) Write(bytes []byte) (int, error) {
	return fmt.Print(time.Now().Format("2006-01-02T15:04:05.999Z") + " " + string(bytes))
}

func main() {
	log.SetFlags(0)
	log.SetOutput(new(logWriter))

	var listenAddress = flag.String("listen", ":8000", "Listen address.")

	flag.Parse()

	if flag.NArg() != 0 {
		flag.Usage()
		log.Fatalf("\nERROR You MUST NOT pass any positional arguments")
	}

	timezone, err := ioutil.ReadFile("/etc/timezone")
	if err != nil {
		log.Fatalf("\nERROR Failed to get the local time zone: %v", err)
	}

	location, err := time.LoadLocation(strings.TrimSpace(string(timezone)))
	if err != nil {
		log.Fatalf("\nERROR Failed to load local time zone: %v", err)
	}

	http.HandleFunc("/machines.json", func(w http.ResponseWriter, r *http.Request) {
		machinesStatus, err := GetMachinesStatus()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		json.NewEncoder(w).Encode(machinesStatus)
	})

	http.HandleFunc("/action", func(w http.ResponseWriter, r *http.Request) {
		actionRequest := struct {
			Action      string `json:"action"`
			MachineName string `json:"machineName"`
		}{}

		err = json.NewDecoder(r.Body).Decode(&actionRequest)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		machines, err := GetMachines("machines.json")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		for _, machine := range machines {
			if machine.Name == actionRequest.MachineName {
				err = executeMachineAction(&machine, actionRequest.Action)
				if err != nil {
					actionResult := struct {
						Error string `json:"error"`
					}{
						Error: err.Error(),
					}
					log.Printf("ERROR: machine %s action %s failed with: %s", machine.Name, actionRequest.Action, actionResult.Error)
					w.WriteHeader(http.StatusInternalServerError)
					w.Header().Set("Content-Type", "application/json")
					json.NewEncoder(w).Encode(actionResult)
				} else {
					log.Printf("INFO: machine %s action %s succeeded", machine.Name, actionRequest.Action)
					w.WriteHeader(http.StatusOK)
					w.Header().Set("Content-Type", "application/json")
					w.Write([]byte("{}"))
				}
				return
			}
		}

		w.WriteHeader(http.StatusNotFound)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte("{}"))
	})

	http.HandleFunc("/wipe.sh", func(w http.ResponseWriter, r *http.Request) {
		wipedUrl := strings.Replace(
			fmt.Sprintf("http://%s%s", r.Host, r.URL.String()),
			"/wipe.sh",
			"/wiped",
			1)
		w.Header().Set("Content-Type", "text/plain")
		err = wipeScriptTemplate.ExecuteTemplate(w, "WipeScript", wipeScriptData{
			WipedUrl: wipedUrl,
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	http.HandleFunc("/wiped", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
			return
		}

		mac := strings.ReplaceAll(r.URL.Query().Get("mac"), "-", ":")

		machines, err := GetMachines("machines.json")
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		for _, machine := range machines {
			if machine.Mac == mac {
				switch machine.BmcType {
				case "":
					err := executeMachineAction(&machine, "matchbox-network-talos")
					if err != nil {
						http.Error(w, err.Error(), http.StatusInternalServerError)
						return
					}
					w.Write([]byte("reboot"))
				default:
					err := executeMachineAction(&machine, "bmc-reset-to-network-talos")
					if err != nil {
						http.Error(w, err.Error(), http.StatusInternalServerError)
						return
					}
				}
				return
			}
		}

		w.WriteHeader(http.StatusNotFound)
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}

		machinesStatus, err := GetMachinesStatus()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		kubernetesNodes, err := GetKubernetesNodes()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/html")

		err = machinesStatusTemplate.ExecuteTemplate(w, "MachinesStatus", machinesStatusData{
			Location:        location,
			MachinesStatus:  machinesStatus,
			KubernetesNodes: kubernetesNodes,
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	log.Printf("Listening at http://%s", *listenAddress)

	err = http.ListenAndServe(*listenAddress, nil)
	if err != nil {
		log.Fatalf("Failed to ListenAndServe: %v", err)
	}
}

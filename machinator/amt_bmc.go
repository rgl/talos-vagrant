package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/VictorLowther/simplexml/dom"
	"github.com/VictorLowther/simplexml/search"
	"github.com/VictorLowther/wsman"
)

func amtBmcGetPowerState(machine *Machine) (string, error) {
	client, err := amtGetClient(machine)
	if err != nil {
		return "", err
	}
	powerState, err := client.GetPowerState()
	if err != nil {
		return "", err
	}
	return getDmtfPowerStateString(powerState.PowerState), nil
}

func amtBmcReset(machine *Machine) error {
	c, err := amtGetClient(machine)
	if err != nil {
		return err
	}
	return c.Reset()
}

func amtBmcResetToNetwork(machine *Machine) error {
	return amtBmcResetToBootDevice(machine, "pxe")
}

func amtBmcResetToDisk(machine *Machine) error {
	return amtBmcResetToBootDevice(machine, "hd")
}

func amtBmcResetToBootDevice(machine *Machine, bootDevice string) error {
	client, err := amtGetClient(machine)
	if err != nil {
		return err
	}

	err = client.ResetToBootDeviceOnce(bootDevice)
	if err != nil {
		return fmt.Errorf("failed to reset to boot device: %v", err)
	}

	return nil
}

func amtGetClient(machine *Machine) (*Client, error) {
	url := fmt.Sprintf("http://%s:%d/wsman", machine.BmcIp, machine.BmcPort)
	username := os.Getenv("AMT_USERNAME")
	password := os.Getenv("AMT_PASSWORD")

	client, err := NewClient(url, username, password)
	if err != nil {
		return nil, fmt.Errorf("failed to create amt client: %v", err)
	}

	return client, nil
}

// see https://github.com/intel/lms/blob/f7c374745ae7efb3ed7860fdc3f8abbb52dc9f8f/CIM_Framework/CIMFramework/CPPClasses/Include/CIM_AssociatedPowerManagementService.h#L143-L159
// see https://schemas.dmtf.org/wbem/cim-html/2.49.0/CIM_AssociatedPowerManagementService.html
// see https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/default.htm?turl=HTMLDocuments%2FWS-Management_Class_Reference%2FCIM_AssociatedPowerManagementService.htm
var DmtfPowerStatesStrings []string = []string{
	"Unknown",                           // 0
	"Other",                             // 1
	"On",                                // 2
	"Sleep - Light",                     // 3
	"Sleep - Deep",                      // 4
	"Power Cycle (Off - Soft)",          // 5
	"Off - Hard",                        // 6
	"Hibernate (Off - Soft)",            // 7
	"Off - Soft",                        // 8
	"Power Cycle (Off - Hard)",          // 9
	"Master Bus Reset",                  // 10
	"Diagnostic Interrupt (NMI)",        // 11
	"Off - Soft Graceful",               // 12
	"Off - Hard Graceful",               // 13
	"Master Bus Reset Graceful",         // 14
	"Power Cycle (Off - Soft Graceful)", // 15
	"Power Cycle (Off - Hard Graceful)", // 16
	"Diagnostic Interrupt (INIT)",       // 17
}

const DmtfPowerStateOn = 2
const DmtfPowerStatePowerCycleSoft = 5
const DmtfPowerStateOffHard = 6
const DmtfPowerStateOffSoft = 8
const DmtfPowerStateOffHardGraceful = 13
const DmtfPowerStateOffSoftGraceful = 12
const DmtfPowerStateMasterBusReset = 10
const DmtfPowerStateDiagnosticInterruptNmi = 11

func getDmtfPowerStateString(powerStateId int) string {
	if powerStateId >= 0 && powerStateId < len(DmtfPowerStatesStrings) {
		return fmt.Sprintf("%s (#%d)", DmtfPowerStatesStrings[powerStateId], powerStateId)
	}
	return fmt.Sprintf("(#%d)", powerStateId)
}

type PowerState struct {
	PowerState           int
	AvailablePowerStates []int
}

type Client struct {
	client *wsman.Client
}

// TODO wsman.NewClient default to InsecureSkipVerify at res.Transport = &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true},}
//      we MUST fix that by letting the user pass-in the http.Client.
func NewClient(url string, username string, password string) (*Client, error) {
	client, err := wsman.NewClient(url, username, password, true)
	if err != nil {
		return nil, fmt.Errorf("failed to create the wsman client: %v", err)
	}
	return &Client{
		client: client,
	}, nil
}

// get the current power state.
// NB this is equivalent to:
//		./wscli -d -u {username} -p {password} -e {url} -a Get -r http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_AssociatedPowerManagementService
// see getPowerState at https://github.com/rgl/intel-amt-toggle-power-example/blob/master/intel-amt-toggle-power-example.js
// see CIM_AssociatedPowerManagementService at https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/HTMLDocuments/WS-Management_Class_Reference/CIM_AssociatedPowerManagementService.htm
// see Get System Power State at https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/WordDocuments/getsystempowerstate.htm
func (c *Client) GetPowerState() (*PowerState, error) {
	cimAssociatedPowerManagementServiceNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_AssociatedPowerManagementService"
	request := c.client.Get(cimAssociatedPowerManagementServiceNs)
	response, err := request.Send()
	if err != nil {
		return nil, fmt.Errorf("failed to get CIM_AssociatedPowerManagementService: %v", err)
	}
	powerStateString := search.First(search.Tag("PowerState", cimAssociatedPowerManagementServiceNs), response.AllBodyElements()).Content
	powerState, err := strconv.Atoi(string(powerStateString))
	if err != nil {
		return nil, fmt.Errorf("failed to parse CIM_AssociatedPowerManagementService.PowerState: %v", err)
	}
	availablePowerStatesNodes := search.All(search.Tag("AvailableRequestedPowerStates", cimAssociatedPowerManagementServiceNs), response.AllBodyElements())
	availablePowerStates := make([]int, 0, len(availablePowerStatesNodes))
	for _, node := range availablePowerStatesNodes {
		v, err := strconv.Atoi(string(node.Content))
		if err != nil {
			return nil, fmt.Errorf("failed to parse CIM_AssociatedPowerManagementService.AvailableRequestedPowerStates: %v", err)
		}
		availablePowerStates = append(availablePowerStates, v)
	}
	return &PowerState{
		PowerState:           powerState,
		AvailablePowerStates: availablePowerStates,
	}, nil
}

// see setPowerState at https://github.com/rgl/intel-amt-toggle-power-example/blob/master/intel-amt-toggle-power-example.js
// see CIM_PowerManagementService at https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/HTMLDocuments/WS-Management_Class_Reference/CIM_PowerManagementService.htm
func (c *Client) SetPowerState(powerState int) error {
	// Create an Envelope like:
	// 		<Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:w="http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd" xmlns="http://www.w3.org/2003/05/soap-envelope">
	// 		    <Header>
	// 		        <a:Action>http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService/RequestPowerStateChange</a:Action>
	// 		        <a:To>/wsman</a:To>
	// 		        <w:ResourceURI>http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService</w:ResourceURI>
	// 		        <a:MessageID>1</a:MessageID>
	// 		        <a:ReplyTo>
	// 		            <a:Address>http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</a:Address>
	// 		        </a:ReplyTo>
	// 		        <w:OperationTimeout>PT60S</w:OperationTimeout>
	// 		    </Header>
	// 		    <Body>
	// 		        <r:RequestPowerStateChange_INPUT xmlns:r="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService">
	// 		            <r:PowerState>2</r:PowerState>
	// 		            <r:ManagedElement>
	// 		                <Address xmlns="http://schemas.xmlsoap.org/ws/2004/08/addressing">http://schemas.xmlsoap.org/ws/2004/08/addressing</Address>
	// 		                <ReferenceParameters xmlns="http://schemas.xmlsoap.org/ws/2004/08/addressing">
	// 		                    <ResourceURI xmlns="http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd">http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ComputerSystem</ResourceURI>
	// 		                    <SelectorSet xmlns="http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd">
	// 		                        <Selector Name="CreationClassName">CIM_ComputerSystem</Selector>
	// 		                        <Selector Name="Name">ManagedSystem</Selector>
	// 		                    </SelectorSet>
	// 		                </ReferenceParameters>
	// 		            </r:ManagedElement>
	// 		        </r:RequestPowerStateChange_INPUT>
	// 		    </Body>
	// 		</Envelope>

	cimPowerManagementServiceNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_PowerManagementService"
	cimComputerSystemNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ComputerSystem"
	request := c.client.Invoke(cimPowerManagementServiceNs, "RequestPowerStateChange")

	// PowerState parameter.
	request.Parameters("PowerState", strconv.Itoa(powerState))

	// ManagedElement parameter.
	managedElementNode := request.MakeParameter("ManagedElement")
	request.AddParameter(managedElementNode)

	// ManagedElement.Address child.
	managedElementNode.AddChild(dom.ElemC("Address", wsman.NS_WSA, wsman.NS_WSA))

	// ManagedElement.ReferenceParameters child.
	referenceParametersNode := dom.Elem("ReferenceParameters", wsman.NS_WSA)
	managedElementNode.AddChild(referenceParametersNode)

	// ManagedElement.ReferenceParameters.ResourceURI child.
	referenceParametersNode.AddChild(wsman.Resource(cimComputerSystemNs))

	// ManagedElement.ReferenceParameters.SelectorSet child.
	selectorSetNode := dom.Elem("SelectorSet", wsman.NS_WSMAN)
	referenceParametersNode.AddChild(selectorSetNode)

	// ManagedElement.ReferenceParameters.SelectorSet.Selector CreationClassName child.
	creationClassNameNode := request.MakeSelector("CreationClassName")
	creationClassNameNode.Content = []byte("CIM_ComputerSystem")
	selectorSetNode.AddChild(creationClassNameNode)

	// ManagedElement.ReferenceParameters.SelectorSet.Selector Name child.
	nameNode := request.MakeSelector("Name")
	nameNode.Content = []byte("ManagedSystem")
	selectorSetNode.AddChild(nameNode)

	// send the request.
	response, err := request.Send()
	if err != nil {
		return fmt.Errorf("failed to call CIM_PowerManagementService.RequestPowerStateChange: %v", err)
	}

	// parse the response.
	returnValueString := search.First(search.Tag("ReturnValue", cimPowerManagementServiceNs), response.AllBodyElements()).Content
	returnValue, err := strconv.Atoi(string(returnValueString))
	if err != nil {
		return fmt.Errorf("failed to convert response ReturnValue to an integer: %v", err)
	}
	if returnValue != 0 {
		if returnValue == 2 {
			return fmt.Errorf("failed with ReturnValue: %d (not ready; please note that not all state transitions are possible when remote desktop or ider is enabled", returnValue)
		} else {
			return fmt.Errorf("failed with ReturnValue: %d", returnValue)
		}
	}
	return nil
}

func (c *Client) ResetToBootDeviceOnce(bootDevice string) error {
	err := c.SetBootDeviceOnce(bootDevice)
	if err != nil {
		return fmt.Errorf("failed to set boot device: %v", err)
	}
	return c.Reset()
}

func (c *Client) Reset() error {
	powerState, err := c.GetPowerState()
	if err != nil {
		return fmt.Errorf("failed to get power state: %v", err)
	}
	var desiredPowerState int
	if powerState.PowerState == DmtfPowerStateOffSoft {
		desiredPowerState = DmtfPowerStateOn
	} else {
		desiredPowerState = DmtfPowerStateMasterBusReset
	}
	err = c.SetPowerState(desiredPowerState)
	if err != nil {
		return fmt.Errorf("failed to set power state: %v", err)
	}
	return nil
}

// see Set or Disable Boot Configuration Settings for the Next Boot at https://software.intel.com/sites/manageability/AMT_Implementation_and_Reference_Guide/WordDocuments/setordisablebootconfigurationsettingsforthenextboot.htm
func (c *Client) SetBootDeviceOnce(bootDevice string) error {
	cimBootConfigSettingNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_BootConfigSetting"
	cimBootSourceSettingNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_BootSourceSetting"

	request := c.client.Invoke(cimBootConfigSettingNs, "ChangeBootOrder")
	request.Selectors("InstanceID", "Intel(r) AMT: Boot Configuration 0")

	// Source parameter.
	sourceNode := request.MakeParameter("Source")
	request.AddParameter(sourceNode)

	// Source.Address child.
	sourceNode.AddChild(dom.ElemC("Address", wsman.NS_WSA, "http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous"))

	// Source.ReferenceParameters child.
	referenceParametersNode := dom.Elem("ReferenceParameters", wsman.NS_WSA)
	sourceNode.AddChild(referenceParametersNode)

	// Source.ReferenceParameters.ResourceURI child.
	referenceParametersNode.AddChild(wsman.Resource(cimBootSourceSettingNs))

	// Source.ReferenceParameters.SelectorSet child.
	selectorSetNode := dom.Elem("SelectorSet", wsman.NS_WSMAN)
	referenceParametersNode.AddChild(selectorSetNode)

	// ManagedElement.ReferenceParameters.SelectorSet.Selector CreationClassName child.
	instanceIdNode := request.MakeSelector("InstanceID")
	switch bootDevice {
	case "pxe":
		instanceIdNode.Content = []byte("Intel(r) AMT: Force PXE Boot")
	case "hd":
		instanceIdNode.Content = []byte("Intel(r) AMT: Force Hard-drive Boot")
	case "cd":
		instanceIdNode.Content = []byte("Intel(r) AMT: Force CD/DVD Boot")
	default:
		return fmt.Errorf("unknown bootDevice %s", bootDevice)
	}
	selectorSetNode.AddChild(instanceIdNode)

	// send the request.
	response, err := request.Send()
	if err != nil {
		return fmt.Errorf("failed to call CIM_BootConfigSetting.ChangeBootOrder: %v", err)
	}

	// parse the response.
	returnValueString := search.First(search.Tag("ReturnValue", cimBootConfigSettingNs), response.AllBodyElements()).Content
	returnValue, err := strconv.Atoi(string(returnValueString))
	if err != nil {
		return fmt.Errorf("failed to convert response ReturnValue to an integer: %v", err)
	}
	if returnValue != 0 {
		return fmt.Errorf("failed with ReturnValue: %d", returnValue)
	}

	// 1: IsNextSingleUse (aka Once)
	return c.SetBootConfigRole(1)
}

func (c *Client) SetBootConfigRole(role int) error {
	cimBootServiceNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_BootService"
	cimBootConfigSettingNs := "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_BootConfigSetting"

	request := c.client.Invoke(cimBootServiceNs, "SetBootConfigRole")
	request.Selectors("Name", "Intel(r) AMT Boot Service")

	// BootConfigSetting parameter.
	bootConfigSettingNode := request.MakeParameter("BootConfigSetting")
	request.AddParameter(bootConfigSettingNode)

	// BootConfigSetting.Address child.
	bootConfigSettingNode.AddChild(dom.ElemC("Address", wsman.NS_WSA, "http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous"))

	// BootConfigSetting.ReferenceParameters child.
	referenceParametersNode := dom.Elem("ReferenceParameters", wsman.NS_WSA)
	bootConfigSettingNode.AddChild(referenceParametersNode)

	// BootConfigSetting.ReferenceParameters.ResourceURI child.
	referenceParametersNode.AddChild(wsman.Resource(cimBootConfigSettingNs))

	// BootConfigSetting.ReferenceParameters.SelectorSet child.
	selectorSetNode := dom.Elem("SelectorSet", wsman.NS_WSMAN)
	referenceParametersNode.AddChild(selectorSetNode)

	// ManagedElement.ReferenceParameters.SelectorSet.Selector CreationClassName child.
	instanceIdNode := request.MakeSelector("InstanceID")
	instanceIdNode.Content = []byte("Intel(r) AMT: Boot Configuration 0")
	selectorSetNode.AddChild(instanceIdNode)

	// Role parameter.
	request.Parameters("Role", strconv.Itoa(role))

	// send the request.
	response, err := request.Send()
	if err != nil {
		return fmt.Errorf("failed to call CIM_BootService.SetBootConfigRole: %v", err)
	}

	// parse the response.
	returnValueString := search.First(search.Tag("ReturnValue", cimBootServiceNs), response.AllBodyElements()).Content
	returnValue, err := strconv.Atoi(string(returnValueString))
	if err != nil {
		return fmt.Errorf("failed to convert response ReturnValue to an integer: %v", err)
	}
	if returnValue != 0 {
		return fmt.Errorf("failed with ReturnValue: %d", returnValue)
	}

	return nil
}

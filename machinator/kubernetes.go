package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

type KubernetesNode struct {
	Name             string `json:"name"`
	Status           string `json:"status"`
	Roles            string `json:"roles"`
	Version          string `json:"version"`
	InternalIp       string `json:"internalIp"`
	ExternalIp       string `json:"externalIp"`
	Architecture     string `json:"architecture"`
	Cpu              string `json:"cpu"`
	Memory           string `json:"memory"`
	OsImage          string `json:"osImage"`
	KernelVersion    string `json:"kernelVersion"`
	ContainerRuntime string `json:"containerRuntime"`
}

type KubernetesIngress struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	Url       string `json:"url"`
}

type KubernetesExecError struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

func (err *KubernetesExecError) Error() string {
	return fmt.Sprintf("failed to exec kubectl: exitCode=%d stdout=%s stderr=%s", err.ExitCode, err.Stdout, err.Stderr)
}

func kubectl(args ...string) (string, error) {
	var stderr, stdout bytes.Buffer

	cmd := exec.Command("kubectl", args...)
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout

	err := cmd.Run()

	if err != nil {
		exitCode := -1
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ProcessState.ExitCode()
		}
		return "", &KubernetesExecError{
			ExitCode: exitCode,
			Stdout:   stdout.String(),
			Stderr:   stderr.String(),
		}
	}

	return strings.TrimSpace(stdout.String()), nil
}

type kubernetesNodeAddress struct {
	Address string `json:"address"`
	Type    string `json:"type"`
}

type kubernetesNodeCondition struct {
	Type   string `json:"type"`
	Status string `json:"status"`
	Reason string `json:"reason"`
}

type kubernetesNodeStatus struct {
	Addresses  []kubernetesNodeAddress   `json:"addresses"`
	Capacity   map[string]string         `json:"capacity"`
	Conditions []kubernetesNodeCondition `json:"conditions"`
	NodeInfo   map[string]string         `json:"nodeInfo"`
}

type kubernetesNodeMetadata struct {
	Name   string            `json:"name"`
	Labels map[string]string `json:"labels"`
}

type kubernetesNode struct {
	Kind     string                 `json:"kind"`
	Status   kubernetesNodeStatus   `json:"status"`
	Metadata kubernetesNodeMetadata `json:"metadata"`
}

type kubernetesGetNodesResponse struct {
	Items []kubernetesNode `json:"items"`
}

type kubernetesIngressMetadata struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
}

type kubernetesIngressRule struct {
	Host string `json:"host"`
}

type kubernetesIngressTls struct {
	SecretName string `json:"secretName"`
}

type kubernetesIngressSpec struct {
	Rules []kubernetesIngressRule `json:"rules"`
	Tls   []kubernetesIngressTls  `json:"tls"`
}

type kubernetesIngress struct {
	Kind     string                    `json:"kind"`
	Metadata kubernetesIngressMetadata `json:"metadata"`
	Spec     kubernetesIngressSpec     `json:"spec"`
}

type kubernetesGetKubernetesIngressesResponse struct {
	Items []kubernetesIngress `json:"items"`
}

func GetKubernetesNodes() ([]KubernetesNode, error) {
	stdout, err := kubectl("get", "nodes", "-o", "json")
	if err != nil {
		return nil, err
	}

	var response kubernetesGetNodesResponse
	if err := json.Unmarshal([]byte(stdout), &response); err != nil {
		return nil, err
	}

	nodes := make([]KubernetesNode, 0, len(response.Items))

	for _, item := range response.Items {
		roles := make([]string, 0)
		for label := range item.Metadata.Labels {
			if strings.HasPrefix(label, "node-role.kubernetes.io/") {
				roles = append(roles, label[len("node-role.kubernetes.io/"):])
			}
		}
		sort.Strings(roles)
		var internalIp string
		var externalIp string
		for _, address := range item.Status.Addresses {
			switch address.Type {
			case "InternalIP":
				internalIp = address.Address
			case "ExternalIP":
				externalIp = address.Address
			}
		}
		var status string
		for _, condition := range item.Status.Conditions {
			switch condition.Type {
			case "Ready":
				if condition.Status == "True" {
					status = "Ready"
				} else {
					status = "NotReady"
				}
			}
		}
		nodes = append(nodes, KubernetesNode{
			Name:             item.Metadata.Name,
			Status:           status,
			Roles:            strings.Join(roles, ","),
			InternalIp:       internalIp,
			ExternalIp:       externalIp,
			Cpu:              item.Status.Capacity["cpu"],
			Memory:           item.Status.Capacity["memory"],
			Architecture:     item.Status.NodeInfo["architecture"],
			Version:          item.Status.NodeInfo["kubeletVersion"],
			OsImage:          item.Status.NodeInfo["osImage"],
			KernelVersion:    item.Status.NodeInfo["kernelVersion"],
			ContainerRuntime: item.Status.NodeInfo["containerRuntimeVersion"],
		})
	}

	return nodes, nil
}

func GetKubernetesIngresses() ([]KubernetesIngress, error) {
	stdout, err := kubectl("get", "ingress", "-A", "-o", "json")
	if err != nil {
		return nil, err
	}

	var response kubernetesGetKubernetesIngressesResponse
	if err := json.Unmarshal([]byte(stdout), &response); err != nil {
		return nil, err
	}

	ingresses := make([]KubernetesIngress, 0, len(response.Items))

	for _, item := range response.Items {
		for _, rule := range item.Spec.Rules {
			ingresses = append(ingresses, KubernetesIngress{
				Name:      item.Metadata.Name,
				Namespace: item.Metadata.Namespace,
				Url:       fmt.Sprintf("https://%s", rule.Host),
			})
		}
	}

	return ingresses, nil
}

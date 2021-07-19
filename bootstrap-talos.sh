#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
control_plane_vip="${1:-10.10.0.3}"; shift || true


#
# bootstrap etcd.
# see https://www.talos.dev/docs/v0.11/bare-metal-platforms/matchbox/#bootstrap-etcd

control_plane_ips="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.role == "controlplane") | .ip')"
first_control_plane_ip="$(echo "$control_plane_ips" | head -1)"

title 'Adding the first control plane endpoint to the talosctl local configuration'
talosctl config endpoints $first_control_plane_ip
talosctl config nodes $first_control_plane_ip

title 'Waiting for kubelet to be ready'
while [ -z "$(talosctl service kubelet status 2>/dev/null | grep -E '^HEALTH\s+OK$')" ]; do sleep 3; done

title 'Bootstrapping etcd'
talosctl bootstrap

title 'Waiting for etcd to be ready'
while [ -z "$(talosctl service etcd status 2>/dev/null | grep -E '^HEALTH\s+OK$')" ]; do sleep 3; done

title 'Downloading Kubernetes config to ~/.kube/config'
talosctl kubeconfig
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.kube
install -m 600 -o vagrant -g vagrant ~/.kube/config /home/vagrant/.kube/config
cp ~/.kube/config /vagrant/shared/kubeconfig

title 'Waiting for Kubernetes to be ready'
while ! kubectl --namespace kube-system rollout status deployment coredns >/dev/null 2>&1; do sleep 3; done

title 'Reconfiguring the Kubernetes control plane endpoint DNS A RR to the VIP'
sed -i -E 's/^(host-record=.+?),.+? # control_plane_vip=(.+)/\1,\2/g' /etc/dnsmasq.d/local.conf
systemctl restart dnsmasq
dig "cp.$dns_domain"

title 'Adding all the control plane endpoints to the talosctl local configuration'
talosctl config endpoints $control_plane_ips
talosctl config nodes # NB this makes sure there are no default nodes.
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.talos
install -m 600 -o vagrant -g vagrant ~/.talos/config /home/vagrant/.talos/config
cp ~/.talos/config /vagrant/shared/talosconfig


#
# show information about talos.

title 'Talos version'
talosctl -n $first_control_plane_ip version

title 'Talos os-release file'
talosctl -n $first_control_plane_ip read /etc/os-release

title 'Talos resolv.conf file'
talosctl -n $first_control_plane_ip read /etc/resolv.conf

title 'Talos hosts file'
talosctl -n $first_control_plane_ip read /etc/hosts

title 'Talos disks'
talosctl -n $first_control_plane_ip disks

title 'Talos etcd members'
talosctl -n $first_control_plane_ip etcd members

title 'Talos services'
talosctl -n $first_control_plane_ip services

title 'Talos containers'
talosctl -n $first_control_plane_ip containers

title 'Talos k8s.io containers'
talosctl -n $first_control_plane_ip containers -k


#
# show information about kubernetes.

title 'Kubernetes version'
kubectl version --short

title 'Kubernetes cluster'
kubectl cluster-info

title 'Kubernetes nodes'
kubectl get nodes -o wide

title 'Kubernetes API versions'
kubectl api-versions

title 'Kubernetes API resources'
kubectl api-resources -o wide

title 'Kubernetes resources'
kubectl get all --all-namespaces


#
# show the environment summary.

bash /vagrant/summary.sh

This is a [Vagrant](https://www.vagrantup.com/) Environment for a playing with [Talos](https://www.talos.dev).

For playing with [Sidero](https://www.sidero.dev) see the [rgl/sidero-vagrant](https://github.com/rgl/sidero-vagrant) repository.

# Table Of Contents

* [Usage](#usage)
* [Network Packet Capture](#network-packet-capture)
* [Network Booting](#network-booting)
  * [Tested Physical Machines](#tested-physical-machines)
* [Troubleshoot](#troubleshoot)
* [Alternatives and Related Projects](#alternatives-and-related-projects)
* [References](#references)

# Usage

Install docker, vagrant, vagrant-libvirt, and the [Ubuntu Base Box](https://github.com/rgl/ubuntu-vagrant).

Login into docker hub to have a [higher rate limits](https://www.docker.com/increase-rate-limits).

If you want to connect to the external physical network, you must configure your host network as described in [rgl/ansible-collection-tp-link-easy-smart-switch](https://github.com/rgl/ansible-collection-tp-link-easy-smart-switch#take-ownership-procedure) (e.g. have the `br-rpi` linux bridge) and set `CONFIG_PANDORA_BRIDGE_NAME` in the `Vagrantfile`.

Bring up the cluster virtual machines:

```bash
time ./bring-up.sh
```

Access talos:

```bash
export TALOSCONFIG="$PWD/shared/talosconfig"
./shared/talosctl --nodes cp1,w1 version
```

Access kubernetes:

```bash
export KUBECONFIG="$PWD/shared/kubeconfig"
./shared/kubectl get nodes -o wide
```

Start an example service in each worker node:

```bash
vagrant ssh -c 'bash /vagrant/provision-example-daemonset.sh' pandora
```

Access the example service:

```bash
vagrant ssh -c "watch -n .2 'wget -qO- http://example-daemonset.\$(hostname --domain)?format=text | tail -25; kubectl get pod -l app=example-daemonset -o=custom-columns=NODE:.spec.nodeName,STATUS:.status.phase,NAME:.metadata.name'" pandora
```

## Network Packet Capture

You can easily capture and see traffic from the host with the `wireshark.sh`
script, e.g., to capture the traffic from the `eth1` interface:

```bash
./wireshark.sh pandora eth1
```

## Host DNS resolver

To delegate the `talos.test` zone to the kubernetes managed external dns server (running in pandora) you need to configure your system to delegate that DNS zone to the pandora DNS server, for that, you can configure your system to only use dnsmasq.

For example, on my Ubuntu 20.04 Desktop, I have uninstalled `resolvconf`, disabled `NetworkManager`, and manually configured the network interfaces:

```bash
sudo su -l
for n in NetworkManager NetworkManager-wait-online NetworkManager-dispatcher network-manager; do
    systemctl mask --now $n
done
apt-get remove --purge resolvconf
cat >/etc/network/interfaces <<'EOF'
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

auto enp3s0
iface enp3s0 inet dhcp
EOF
reboot
```

Then, replaced `systemd-resolved` with `dnsmasq`:

```bash
sudo su -l
apt-get install -y --no-install-recommends dnsutils dnsmasq
systemctl mask --now systemd-resolved
cat >/etc/dnsmasq.d/local.conf <<EOF
no-resolv
bind-interfaces
interface=lo
listen-address=127.0.0.1
# delegate the talos.test zone to the pandora DNS server IP address.
# NB use the CONFIG_PANDORA_IP variable value defined in the Vagrantfile.
server=/talos.test/10.10.0.2
# delegate to the Cloudflare/APNIC Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
server=1.1.1.1
server=1.0.0.1
# delegate to the Google Public DNS IP addresses.
# NB iif there's no entry in /etc/hosts.
#server=8.8.8.8
#server=8.8.4.4
EOF
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF
systemctl restart dnsmasq
exit
```

Then start all the machines and test the DNS resolution:

```bash
vagrant up
dig pandora.talos.test
```

## Network Booting

This environment uses PXE/TFTP/iPXE/HTTP/UEFI-HTTP to network boot the
machines.

The Virtual Machines are automatically configured to network boot.

To boot Physical Machines you have to:

* Create a Linux Bridge that can reach a Physical Switch that connects to
  your Physical Machines.
  * This environment assumes you have a setup like [rgl/ansible-collection-tp-link-easy-smart-switch](https://github.com/rgl/ansible-collection-tp-link-easy-smart-switch).
  * To configure it otherwise you must modify the `Vagrantfile`.
* Add your machines to `machines.yaml`.
* Configure your machines to PXE boot.

### Tested Physical Machines

This was tested on the following physical machines and boot modes:

* [Seeed Studio Odyssey X86J4105](https://github.com/rgl/seeedstudio-odyssey-x86j4105-notes)
  * It boots using [UEFI/HTTP/PXE](https://github.com/rgl/seeedstudio-odyssey-x86j4105-notes/tree/master/network-boot#uefi-http-pxe).
* [HP EliteDesk 800 35W G2 Desktop Mini](https://support.hp.com/us-en/product/hp-elitedesk-800-35w-g2-desktop-mini-pc/7633266)
  * It boots using UEFI/TFTP/PXE.
  * This machine can be remotely managed with [MeshCommander](https://www.meshcommander.com/meshcommander).
    * It was configured as described at [rgl/intel-amt-notes](https://github.com/rgl/intel-amt-notes).
* [Raspberry Pi 4 (8GB)](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/)
  * It boots using [UEFI/HTTP/iPXE](https://github.com/rgl/rpi4-uefi-ipxe).

# Notes

* The machine boot order must be `disk` and `network`.
  * Talos expects to be run from disk.
* Do not configure any default nodes with `talosctl config node`.
  * Instead, explicitly target the node with `talosctl -n {node}`.
  * Having default nodes could lead to mistakes (e.g. upgrading the whole cluster at the same time).
* The user only needs to access the talos control plane machines.
  * A control plane machine will proxy the requests to the internal cluster nodes.

# Troubleshoot

* Talos
  * [Troubleshooting Control Plane](https://www.talos.dev/docs/v0.14/guides/troubleshooting-control-plane/)
  * `talosctl -n cp1 dashboard`
  * `talosctl -n cp1 logs controller-runtime`
  * `talosctl -n cp1 logs kubelet`
  * `talosctl -n cp1 disks`
  * `talosctl -n cp1 get resourcedefinitions`
  * `talosctl -n cp1 get machineconfigs -o yaml`
  * `talosctl -n cp1 get staticpods -o yaml`
  * `talosctl -n cp1 get staticpodstatus`
  * `talosctl -n cp1 get manifests`
  * `talosctl -n cp1 get services`
  * `talosctl -n cp1 get addresses`
  * `talosctl -n cp1 list -l /system`
  * `talosctl -n cp1 list -l /var`
  * `talosctl -n cp1 list -l /sys/fs/cgroup`
  * `talosctl -n cp1 read /proc/cmdline | tr ' ' '\n'`
  * `talosctl -n cp1 read /proc/mounts | sort`
  * `talosctl -n cp1 read /etc/resolv.conf`
* Kubernetes
  * `kubectl get events --all-namespaces --watch`
  * `kubectl --namespace kube-system get events --watch`
  * `kubectl run -it --rm --restart=Never busybox --image=busybox:1.33 -- nslookup -type=a pandora.talos.test`

# Alternatives and Related Projects

* [sidero](https://github.com/talos-systems/sidero)
* [k3s](https://github.com/k3s-io/k3s)
* [k3os](https://github.com/rancher/k3os)
* [harvester](https://github.com/harvester/harvester)
* [neco](https://github.com/cybozu-go/neco)
* [cke](https://github.com/cybozu-go/cke)
* [sabakan](https://github.com/cybozu-go/sabakan)

# References

* Talos
  * [Talos Site](https://www.talos.dev/)
  * [Getting Started](https://www.talos.dev/docs/v0.14/introduction/getting-started/)
  * [Configuring Network Connectivity](https://www.talos.dev/docs/v0.14/guides/configuring-network-connectivity/)
  * [Troubleshooting Control Plane](https://www.talos.dev/docs/v0.14/guides/troubleshooting-control-plane/)
  * [Support Matrix](https://www.talos.dev/docs/v0.14/introduction/support-matrix/)
* Linux
  * [Kernel Parameters Index](https://www.kernel.org/doc/Documentation/admin-guide/kernel-parameters.rst)
  * [Kernel Parameters List](https://www.kernel.org/doc/Documentation/admin-guide/kernel-parameters.txt)
  * [Booloader Parameters List (AMD64)](https://www.kernel.org/doc/Documentation/x86/x86_64/boot-options.txt)
* iPXE
  * [Scripting](https://ipxe.org/scripting)
  * [Command reference](https://ipxe.org/cmd)
  * [Settings reference](https://ipxe.org/cfg)
* Raspberry Pi
  * [UEFI](https://github.com/pftf/RPi4)
  * [UEFI/iPXE](https://github.com/rgl/rpi4-uefi-ipxe)
* Matchbox
  * [PXE-enabled DHCP](https://github.com/poseidon/matchbox/blob/master/docs/network-setup.md#pxe-enabled-dhcp)
  * [Proxy-DHCP](https://github.com/poseidon/matchbox/blob/master/docs/network-setup.md#proxy-dhcp)
* Dynamic Host Configuration Protocol (DHCP)
  * [Parameters / Options](https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml)

#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
talos_version="${1:-1.0.1}"; shift || true
kubernetes_version="${1:-1.23.5}"; shift || true
control_plane_vip="${1:-10.10.0.3}"; shift || true
pandora_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"


#
# download talos.

assets=(
    vmlinuz-amd64
    initramfs-amd64.xz
    vmlinuz-arm64
    initramfs-arm64.xz
)
for asset in ${assets[@]}; do
    wget -qO /var/lib/matchbox/assets/$asset "https://github.com/siderolabs/talos/releases/download/v$talos_version/$asset"
done
wget -qO /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/v$talos_version/talosctl-$(uname -s | tr "[:upper:]" "[:lower:]")-amd64"
chmod +x /usr/local/bin/talosctl
cp /usr/local/bin/talosctl /vagrant/shared
talosctl completion bash >/usr/share/bash-completion/completions/talosctl
talosctl version --client


#
# install talos.
# see https://www.talos.dev/v1.0/bare-metal-platforms/matchbox/
# see https://www.talos.dev/v1.0/guides/vip/
# NB kubernetes_version refers to the kublet image, e.g., ghcr.io/siderolabs/kubelet:v1.23.5
#    execute `talosctl images` to show the defaults.
# NB this generates yaml file that will be interpreted by matchbox as Go
#    templates. this means we can use matchbox metadata variables like
#    `installDisk`. you can see the end result at, e.g.:
#       http://10.3.0.2/generic?mac=08:00:27:00:00:00

mkdir -p talos
pushd talos
# NB wipe:true is too slow and wasteful for our use-case as it will zero the
#    entire device. instead, we have to net boot the rescue wipe image and
#    use wipefs to wipe the boot/install disk.
# NB the kernel.kexec_load_disabled sysctl cannot be set to 0. so we must do
#    this with /machine/install/extraKernelArgs instead of using
#    /machine/sysctls.
cat >config-patch.json <<EOF
[
    {
        "op": "replace",
        "path": "/machine/install/wipe",
        "value": false
    },
    {
        "op": "replace",
        "path": "/machine/install/extraKernelArgs",
        "value": [
            "{{if not .kexec}}sysctl.kernel.kexec_load_disabled=1{{end}}"
        ]
    },
    {
        "op": "replace",
        "path": "/machine/logging",
        "value": {
            "destinations": [
                {
                    "endpoint": "tcp://$pandora_ip_address:5170",
                    "format": "json_lines"
                }
            ]
        }
    }
]
EOF
cat >config-patch-controlplane.json <<EOF
[
    {
        "op": "add",
        "path": "/machine/network/interfaces",
        "value": [
            {
                "interface": "eth0",
                "dhcp": true,
                "vip": {
                    "ip": "$control_plane_vip"
                }
            }
        ]
    }
]
EOF
# NB CoreDNS will be authoritative dns server for the given dns-domain zone.
#    it will not forward that zone unknown queries to the upstream dns server.
#    it will only fallthrough the in-addr.arpa and ip6.arpa zones.
talosctl gen config \
    talos \
    "https://cp.$dns_domain:6443" \
    --dns-domain cluster.local \
    --kubernetes-version "$kubernetes_version" \
    --install-disk '{{.installDisk}}' \
    --config-patch @config-patch.json \
    --config-patch-control-plane @config-patch-controlplane.json \
    --with-docs=false \
    --with-examples=false \
    --with-cluster-discovery=false
talosctl validate --config controlplane.yaml --mode metal
talosctl validate --config worker.yaml --mode metal
install -m 644 controlplane.yaml /var/lib/matchbox/generic
install -m 644 worker.yaml /var/lib/matchbox/generic
cp talosconfig /vagrant/shared/talosconfig
popd


#
# install into the pxe server.

python3 /vagrant/machines.py
systemctl restart dnsmasq

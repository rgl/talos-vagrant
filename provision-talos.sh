#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
talos_version="${1:-0.12.0-beta.2}"; shift || true
kubernetes_version="${1:-1.22.0}"; shift || true
control_plane_vip="${1:-10.10.0.3}"; shift || true


#
# download talos.

assets=(
    vmlinuz-amd64
    initramfs-amd64.xz
    vmlinuz-arm64
    initramfs-arm64.xz
)
for asset in ${assets[@]}; do
    wget -qO /var/lib/matchbox/assets/$asset "https://github.com/talos-systems/talos/releases/download/v$talos_version/$asset"
done
wget -qO /usr/local/bin/talosctl "https://github.com/talos-systems/talos/releases/download/v$talos_version/talosctl-$(uname -s | tr "[:upper:]" "[:lower:]")-amd64"
chmod +x /usr/local/bin/talosctl
talosctl completion bash >/usr/share/bash-completion/completions/talosctl
talosctl version --client


#
# install talos.
# see https://www.talos.dev/docs/v0.12/bare-metal-platforms/matchbox/
# see https://www.talos.dev/docs/v0.12/guides/vip/
# NB kubernetes_version refers to the kublet image, e.g., ghcr.io/talos-systems/kubelet:v1.22.0
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
            "ipv6.disable=1"
        ]
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
talosctl gen config \
    talos \
    "https://cp.$dns_domain:6443" \
    --dns-domain "$dns_domain" \
    --kubernetes-version "$kubernetes_version" \
    --install-disk '{{.installDisk}}' \
    --config-patch "$(cat config-patch.json)" \
    --config-patch-control-plane "$(cat config-patch-controlplane.json)" \
    --with-docs=false \
    --with-examples=false
talosctl validate --config controlplane.yaml --mode metal
talosctl validate --config worker.yaml --mode metal
install -m 644 controlplane.yaml /var/lib/matchbox/generic
install -m 644 worker.yaml /var/lib/matchbox/generic
install -d -m 700 ~/.talos
install -m 600 talosconfig ~/.talos/config
popd


#
# install into the pxe server.

python3 /vagrant/machines.py
systemctl restart dnsmasq


#
# copy the binaries and configuration to the host.

cp /usr/local/bin/talosctl /vagrant/shared
cp ~/.talos/config /vagrant/shared/talosconfig

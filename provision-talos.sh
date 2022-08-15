#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
talos_version="${1:-1.2.0-beta.0}"; shift || true
control_plane_vip="${1:-10.10.0.3}"; shift || true
pandora_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"
registry_domain="$(hostname --fqdn)"
registry_host="$registry_domain:5000"


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

# copy all the images to the local registry.
# see https://www.talos.dev/v1.2/advanced/air-gapped/
talosctl images | sort | while read source_image; do
    destination_image="$registry_host/$(echo $source_image | sed -E 's,^[^/]+/,,g')"
    crane copy --insecure "$source_image" "$destination_image"
done
crane catalog --insecure $registry_host

#
# install talos.
# see https://www.talos.dev/v1.2/talos-guides/install/bare-metal-platforms/matchbox/
# see https://www.talos.dev/v1.2/talos-guides/network/vip/
# NB this generates yaml file that will be interpreted by matchbox as Go
#    templates. this means we can use matchbox metadata variables like
#    `installDisk`. you can see the end result at, e.g.:
#       http://10.3.0.2/generic?mac=08:00:27:00:00:00

rm -rf talos
mkdir -p talos
pushd talos
# NB wipe:true is too slow and wasteful for our use-case as it will zero the
#    entire device. instead, we have to net boot the rescue wipe image and
#    use wipefs to wipe the boot/install disk.
# NB the kernel.kexec_load_disabled sysctl cannot be set to 0. so we must do
#    this with /machine/install/extraKernelArgs instead of using
#    /machine/sysctls.
cat >config-patch.yaml <<EOF
machine:
  install:
    wipe: false
    extraKernelArgs:
      - '{{if not .kexec}}sysctl.kernel.kexec_load_disabled=1{{end}}'
  logging:
    destinations:
      - endpoint: tcp://$pandora_ip_address:5170
        format: json_lines
  registries:
    config:
      $registry_host:
        auth:
          username: vagrant
          password: vagrant
    mirrors:
      docker.io:
        endpoints:
          - http://$registry_host
      gcr.io:
        endpoints:
          - http://$registry_host
      ghcr.io:
        endpoints:
          - http://$registry_host
      k8s.gcr.io:
        endpoints:
          - http://$registry_host
      registry.k8s.io:
        endpoints:
          - http://$registry_host
      quay.io:
        endpoints:
          - http://$registry_host
EOF
cat >config-patch-controlplane.yaml <<EOF
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
        vip:
          ip: $control_plane_vip
EOF
# NB CoreDNS will be authoritative dns server for the given dns-domain zone.
#    it will not forward that zone unknown queries to the upstream dns server.
#    it will only fallthrough the in-addr.arpa and ip6.arpa zones.
talosctl gen config \
    talos \
    "https://cp.$dns_domain:6443" \
    --dns-domain cluster.local \
    --install-disk '{{.installDisk}}' \
    --config-patch @config-patch.yaml \
    --config-patch-control-plane @config-patch-controlplane.yaml \
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

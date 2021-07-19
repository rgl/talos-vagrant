#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
ip_address="${1:-10.10.0.2}"; shift || true
dhcp_range="${1:-10.10.0.100,10.10.0.200,10m}"; shift || true
control_plane_vip="${1:-10.10.0.3}"; shift || true
# NB since we are going to use the integrated talos vip mode, while
#    bootstrapping, the DNS A RR must point to the first node. after
#    bootstrap, bootstrap-talos.sh will modify the DNS A RR to point
#    to the VIP.
first_control_plane_ip="$((jq -r '.[] | select(.role == "controlplane") | .ip' | head -1) </vagrant/shared/machines.json)"


#
# provision the DHCP/TFTP server.
# see http://www.thekelleys.org.uk/dnsmasq/docs/setup.html
# see http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
# see https://wiki.archlinux.org/title/Dnsmasq

default_dns_resolver="$(systemd-resolve --status | awk '/DNS Servers: /{print $3}')" # recurse queries through the default vagrant environment DNS server.
apt-get install -y --no-install-recommends dnsmasq
systemctl stop systemd-resolved
systemctl disable systemd-resolved
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
EOF
install -d /srv/pxe
cat >/etc/dnsmasq.d/local.conf <<EOF
# NB DHCP leases are stored at /var/lib/misc/dnsmasq.leases

# verbose
log-dhcp
log-queries

# ignore host settings
no-resolv
no-hosts

# DNS server
server=$default_dns_resolver
domain=$dns_domain # NB this is actually used by the DHCP server, but its related to our DNS domain, so we leave it here.
auth-zone=$dns_domain
auth-server=$(hostname --fqdn)
host-record=$(hostname --fqdn),$ip_address
host-record=cp.$dns_domain,$first_control_plane_ip # control_plane_vip=$control_plane_vip

# listen on specific interfaces
bind-interfaces

# TFTP
enable-tftp
tftp-root=/srv/pxe

# UEFI HTTP (e.g. X86J4105/RPI4)
dhcp-match=set:efi64-http,option:client-arch,16 # x64 UEFI HTTP (16)
dhcp-option-force=tag:efi64-http,60,HTTPClient
dhcp-boot=tag:efi64-http,tag:eth1,http://$ip_address/assets/ipxe.efi
dhcp-match=set:efiarm64-http,option:client-arch,19 # ARM64 UEFI HTTP (19)
dhcp-option-force=tag:efiarm64-http,60,HTTPClient
dhcp-boot=tag:efiarm64-http,tag:eth1,http://$ip_address/assets/ipxe-arm64.efi

# BIOS/UEFI TFTP PXE (e.g. EliteDesk 800 G2)
# NB there's was a snafu between 7 and 9 in rfc4578 thas was latter fixed in
#    an errata.
#    see https://www.rfc-editor.org/rfc/rfc4578.txt
#    see https://www.rfc-editor.org/errata_search.php?rfc=4578
#    see https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml#processor-architecture
dhcp-match=set:bios,option:client-arch,0        # BIOS x86 (0)
dhcp-boot=tag:bios,undionly.kpxe
dhcp-match=set:efi32,option:client-arch,6       # EFI x86 (6)
dhcp-boot=tag:efi32,ipxe.efi
dhcp-match=set:efi64,option:client-arch,7       # EFI x64 (7)
dhcp-boot=tag:efi64,ipxe.efi
dhcp-match=set:efibc,option:client-arch,9       # EFI EBC (9)
dhcp-boot=tag:efibc,ipxe.efi
dhcp-match=set:efiarm64,option:client-arch,11   # EFI ARM64 (11)
dhcp-boot=tag:efiarm64,ipxe-arm64.efi

# iPXE HTTP (e.g. OVMF/RPI4)
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:ipxe,tag:bios,tag:eth1,http://$ip_address/boot.ipxe
dhcp-boot=tag:ipxe,tag:efi64,tag:eth1,http://$ip_address/boot.ipxe
dhcp-boot=tag:ipxe,tag:efiarm64,tag:eth1,http://$ip_address/boot.ipxe

# DHCP.
interface=eth1
dhcp-option=option:ntp-server,$ip_address
dhcp-range=tag:eth1,$dhcp_range
dhcp-ignore=tag:!known # ignore hosts that do not match a dhcp-host line.
EOF


#
# register the machines and start dnsmasq.

mkdir -p /var/lib/matchbox/{assets,groups,profiles,ignition,cloud,generic}
python3 /vagrant/machines.py
systemctl restart dnsmasq


#
# re-configure docker to use the dnsmasq dns server.

python3 <<EOF
import json

with open('/etc/docker/daemon.json', 'r') as f:
    config = json.load(f)

config['dns'] = ['$ip_address']

with open('/etc/docker/daemon.json', 'w') as f:
    json.dump(config, f, indent=4)
EOF
systemctl restart docker


#
# install matchbox.
# see https://github.com/poseidon/matchbox

docker run \
    -d \
    --restart unless-stopped \
    --name matchbox \
    --net host \
    -v /var/lib/matchbox:/var/lib/matchbox:Z \
    quay.io/poseidon/matchbox:v0.9.0 \
        -address=0.0.0.0:80 \
        -log-level=debug

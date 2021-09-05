#!/bin/bash
source /vagrant/lib.sh


dns_domain="$(hostname --domain)"
host_ip_address="$(ip addr show eth1 | perl -n -e'/ inet (\d+(\.\d+)+)/ && print $1')"
first_vm_mac="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.type == "virtual") | .mac' | head -1)"


title 'matchbox addresses'
cat <<EOF
http://$host_ip_address/ipxe?mac=$first_vm_mac
http://$host_ip_address/metadata?mac=$first_vm_mac
http://$host_ip_address/generic?mac=$first_vm_mac
EOF

title 'addresses'
python3 <<EOF
from tabulate import tabulate

headers = ('service', 'address', 'username', 'password')

def info():
    yield ('meshcommander', 'http://pandora.$dns_domain:4000',       None,    None)
    yield ('machinator',    'http://pandora.$dns_domain:8000',       None,    None)
    yield ('traefik',       'https://traefik.$dns_domain',           None,    None)
    yield ('example',       'https://example-daemonset.$dns_domain', None,    None)

print(tabulate(info(), headers=headers))
EOF

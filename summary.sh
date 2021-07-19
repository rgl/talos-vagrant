#!/bin/bash
source /vagrant/lib.sh


host_ip_address="$(ip addr show eth1 | perl -n -e'/ inet (\d+(\.\d+)+)/ && print $1')"
first_vm_mac="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.type == "virtual") | .mac' | head -1)"
control_plane_ips="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.role == "controlplane") | .ip')"
first_control_plane_ip="$(echo "$control_plane_ips" | head -1)"


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
    yield ('meshcommander', 'http://$host_ip_address:4000',         None,    None)
    yield ('machinator',    'http://$host_ip_address:8000',         None,    None)
    yield ('example',       'http://$first_control_plane_ip:30000', None,    None)

print(tabulate(info(), headers=headers))
EOF

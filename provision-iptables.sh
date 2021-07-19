#!/bin/bash
source /vagrant/lib.sh


# configure apt for non-interactive mode.
export DEBIAN_FRONTEND=noninteractive


#
# setup routing/forwarding/nat.

# these anwsers were obtained (after installing iptables-persistent) with:
#   #sudo debconf-show iptables-persistent
#   sudo apt-get install debconf-utils
#   # this way you can see the comments:
#   sudo debconf-get-selections
#   # this way you can just see the values needed for debconf-set-selections:
#   sudo debconf-get-selections | grep -E '^iptables-persistent\s+' | sort
debconf-set-selections <<'EOF'
iptables-persistent iptables-persistent/autosave_v4 boolean false
iptables-persistent iptables-persistent/autosave_v6 boolean false
EOF
apt-get install -y iptables iptables-persistent

# enable IPv4 forwarding.
sysctl net.ipv4.ip_forward=1
sed -i -E 's,^\s*#?\s*(net.ipv4.ip_forward=).+,\11,g' /etc/sysctl.conf

# route between all interfaces.
# nat through eth0.
cat >/etc/iptables/rules.v4 <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT

*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
# NAT through eth0.
# NB use something like -s 10.10.0/24 to limit to a specific network.
-A POSTROUTING -o eth0 -j MASQUERADE
COMMIT
EOF
iptables-restore </etc/iptables/rules.v4

#!/bin/bash
source /vagrant/lib.sh


allow_network="$(ip addr show dev eth1 | awk '/inet / {print $2}')"


# install the NTP daemon.
# see https://chrony.tuxfamily.org/doc/3.5/chrony.conf.html
# see https://chrony.tuxfamily.org/doc/3.5/chronyd.html
# see https://chrony.tuxfamily.org/doc/3.5/chronyc.html

# disable systemd-timesyncd so it doesn't try to sync the time.
# the time sync will be handled by chrony.
systemctl stop systemd-timesyncd
systemctl disable systemd-timesyncd

# install chrony.
apt-get install -y chrony

# only use IPv4.
# NB unfortunately this will not prevent some IPv6 warnings like:
#       chronyd[2361]: Could not open IPv6 NTP socket : Address family not supported by protocol
sed -i -E 's,^(DAEMON_OPTS=)"(.*)",\1"-4 \2",' /etc/default/chrony 

# configure.
cat >>/etc/chrony/chrony.conf <<EOF
# NB you might need to configure the upstream ntp server pool.

# allow internal network.
allow $allow_network
EOF

# restart chrony for it to pickup the changes.
systemctl restart chrony

# wait for it to sync.
chronyc waitsync

# try chrony.
chronyc tracking
chronyc sources
chronyc clients
chronyc serverstats

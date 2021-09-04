#!/bin/bash
source /vagrant/lib.sh

pandora_ip_address="${1:-10.10.0.2}"; shift || true
domain="$(hostname --domain)"
first_control_plane_ip="$((jq -r '.[] | select(.role == "controlplane") | .ip' | head -1) </vagrant/shared/machines.json)"

#
# provision the DNS authoritative server.
# NB this will be controlled by the kubernetes external dns controller.

apt-get install -y --no-install-recommends dnsutils pdns-backend-sqlite3 sqlite3

# stop pdns before changing the configuration.
systemctl stop pdns

function pdns-set-config {
    local key="$1"; shift
    local value="${1:-}"; shift || true
    sed -i -E "s,^(\s*#\s*)?($key\s*)=.*,\2=$value," /etc/powerdns/pdns.conf
}

# save the original config.
cp /etc/powerdns/pdns.conf{,.orig}
# listen at the localhost.
pdns-set-config local-address 127.0.0.2
# do not listen on ipv6.
pdns-set-config local-ipv6
# configure the api server.
pdns-set-config api yes
pdns-set-config api-key vagrant
pdns-set-config webserver-address "$pandora_ip_address"
pdns-set-config webserver-port 8081
pdns-set-config webserver-allow-from "$pandora_ip_address/24"
# increase the logging level.
# you can see the logs with journalctl --follow -u pdns
#pdns-set-config loglevel 10
#pdns-set-config log-dns-queries yes
# diff the changes.
diff -u /etc/powerdns/pdns.conf{.orig,} || true

# initialize the sqlite3 database.
# see https://doc.powerdns.com/authoritative/backends/generic-sqlite3.html
cat >/etc/powerdns/pdns.d/gsqlite3.conf <<'EOF'
launch=gsqlite3
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
EOF
su pdns \
    -s /bin/bash \
    -c 'sqlite3 /var/lib/powerdns/pdns.sqlite3' \
    </usr/share/pdns-backend-sqlite3/schema/schema.sqlite3.sql

# load the $domain zone into the database.
# NB we use 1m for testing purposes, in real world, this should probably be 10m+.
pdnsutil load-zone $domain <(echo "
\$TTL 1m
\$ORIGIN $domain. ; base domain-name
@               IN      SOA     a.ns    hostmaster (
    2019090800 ; serial number (this number should be increased each time this zone file is changed)
    1m         ; refresh (the polling interval that slave DNS server will query the master for zone changes)
               ; NB the slave will use this value insted of \$TTL when deciding if the zone it outdated
    1m         ; update retry (the slave will retry a zone transfer after a transfer failure)
    3w         ; expire (the slave will ignore this zone if the transfer keeps failing for this long)
    1m         ; minimum (the slave stores negative results for this long)
)
                IN      NS      a.ns
pandora         IN      A       $pandora_ip_address
cp              IN      A       $first_control_plane_ip
")
# TODO add the reverse zone.
pdnsutil list-all-zones

# start it up.
systemctl start pdns

# use the API.
# see https://doc.powerdns.com/authoritative/http-api
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers | jq .
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers/localhost/zones | jq .
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers/localhost/zones/$domain | jq .

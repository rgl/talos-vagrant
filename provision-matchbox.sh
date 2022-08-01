#!/bin/bash
source /vagrant/lib.sh


#
# register the machines.

mkdir -p /var/lib/matchbox/{assets,groups,profiles,ignition,cloud,generic}
python3 /vagrant/machines.py


#
# restart dnsmasq.

systemctl restart dnsmasq


#
# install matchbox.
# see https://github.com/poseidon/matchbox/releases

docker run \
    -d \
    --restart unless-stopped \
    --name matchbox \
    --net host \
    -v /var/lib/matchbox:/var/lib/matchbox:Z \
    quay.io/poseidon/matchbox:v0.9.1 \
        -address=0.0.0.0:80 \
        -log-level=debug

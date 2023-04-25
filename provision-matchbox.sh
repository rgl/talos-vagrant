#!/bin/bash
source /vagrant/lib.sh


# see https://github.com/poseidon/matchbox/releases
# renovate: datasource=github-releases depName=poseidon/matchbox
matchbox_version='0.9.1'
matchbox_image="quay.io/poseidon/matchbox:v$matchbox_version"


#
# register the machines.

mkdir -p /var/lib/matchbox/{assets,groups,profiles,ignition,cloud,generic}
python3 /vagrant/machines.py


#
# restart dnsmasq.

systemctl restart dnsmasq


#
# install matchbox.

docker run \
    -d \
    --restart unless-stopped \
    --name matchbox \
    --net host \
    -v /var/lib/matchbox:/var/lib/matchbox:Z \
    "$matchbox_image" \
        -address=0.0.0.0:80 \
        -log-level=info

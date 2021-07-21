#!/bin/bash
source /vagrant/lib.sh
cd /vagrant/machinator

cp /vagrant/shared/machines.json "$HOME/machines.json"

docker build -t machinator .

docker rm -f machinator || true

docker run \
    -d \
    --restart unless-stopped \
    --name machinator \
    -v "$HOME/machines.json:/machines.json:ro" \
    -v "$HOME/.talos:/root/.talos:ro" \
    -v "$HOME/.kube:/root/.kube:ro" \
    -v "/var/lib/matchbox:/var/lib/matchbox" \
    -v /var/lib/misc/dnsmasq.leases:/dnsmasq.leases:ro \
    -v /etc/timezone:/etc/timezone:ro \
    -v /etc/localtime:/etc/localtime:ro \
    -e AMT_USERNAME='admin' \
    -e AMT_PASSWORD='HeyH0Password!' \
    -e IPMI_USERNAME='admin' \
    -e IPMI_PASSWORD='password' \
    -p 8000:8000 \
    machinator

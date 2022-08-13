#!/bin/bash
set -euxo pipefail

loki_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"

# see https://github.com/grafana/grafana/releases
# see https://hub.docker.com/r/grafana/grafana/tags
grafana_version="9.0.7"

mkdir -p grafana/datasources
cd grafana

# configure grafana.
# see https://grafana.com/docs/grafana/latest/administration/configure-docker/
# see https://grafana.com/docs/grafana/latest/administration/provisioning/#datasources
# see https://grafana.com/docs/grafana/latest/datasources/loki/#configure-the-data-source-with-provisioning
sed -E "s,@@loki_base_url@@,http://$loki_ip_address:3100,g" /vagrant/grafana-datasources.yml \
    >datasources/datasources.yml

# start grafana.
# see https://grafana.com/docs/grafana/latest/installation/docker/
docker run \
    -d \
    --restart unless-stopped \
    --name grafana \
    -p 3000:3000 \
    -e GF_AUTH_ANONYMOUS_ENABLED=true \
    -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
    -e GF_AUTH_DISABLE_LOGIN_FORM=true \
    -v $PWD/datasources:/etc/grafana/provisioning/datasources \
    grafana/grafana:$grafana_version

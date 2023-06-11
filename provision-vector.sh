#!/bin/bash
set -euxo pipefail

pandora_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"

# see https://github.com/vectordotdev/vector/releases
# see https://hub.docker.com/r/timberio/vector/
# renovate: datasource=docker depName=timberio/vector
vector_version="0.30.0"

# destroy the existing loki container and data.
docker rm --force vector && rm -rf ~/vector && mkdir ~/vector

cd ~/vector

sed -E "s,http://localhost:3100,http://$pandora_ip_address:3100,g" /vagrant/vector.yml >vector.yml

# see https://vector.dev/docs/reference/configuration/sources/socket/
# see https://vector.dev/docs/reference/configuration/sinks/loki/
# see https://github.com/vectordotdev/vector
# see https://vector.dev/docs/setup/installation/platforms/docker/
docker run \
    -d \
    --restart unless-stopped \
    --name vector \
    -p 5170:5170 \
    -v "$PWD/vector.yml:/etc/vector/vector.yml:ro" \
    "timberio/vector:$vector_version-debian" \
    -c /etc/vector/vector.yml

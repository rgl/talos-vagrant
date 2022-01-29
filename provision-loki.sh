#!/bin/bash
set -euxo pipefail

# see https://github.com/grafana/loki/releases
# see https://hub.docker.com/r/grafana/loki/tags
loki_version="2.4.2"

# destroy the existing loki container and data.
docker rm --force loki && rm -rf ~/loki && mkdir ~/loki

cd ~/loki

cp /vagrant/loki-config.yml .

# see https://grafana.com/docs/loki/latest/installation/docker/
# see https://grafana.com/docs/loki/latest/configuration/examples/#complete-local-config
# see https://hub.docker.com/r/grafana/loki
# see https://github.com/grafana/loki
docker run \
    -d \
    --restart unless-stopped \
    --name loki \
    -p 3100:3100 \
    -v "$PWD:/etc/loki" \
    grafana/loki:$loki_version \
        -config.file=/etc/loki/loki-config.yml

# wait for loki to be ready.
# see https://grafana.com/docs/loki/latest/api/
bash -euc 'while [ "$(wget -qO- http://localhost:3100/ready)" != "ready" ]; do sleep 5; done'
#wget -qO- http://localhost:3100/metrics
#wget -qO- http://localhost:3100/config | yq eval -

# install logcli.
# see https://grafana.com/docs/loki/latest/getting-started/logcli/
wget -q https://github.com/grafana/loki/releases/download/v$loki_version/logcli-linux-amd64.zip
unzip logcli-linux-amd64.zip
install -m 755 logcli-linux-amd64 /usr/local/bin/logcli
rm logcli-linux-amd64*

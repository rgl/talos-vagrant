#!/bin/bash
set -euxo pipefail

install -m 700 -d ~/.docker
install -m 600 /dev/null ~/.docker/config.json
cat >~/.docker/config.json <<EOF
{
    "auths": {
        "https://index.docker.io/v1/": {
            "auth": "$DOCKER_HUB_AUTH"
        }
    }
}
EOF

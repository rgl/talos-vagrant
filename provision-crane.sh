#!/bin/bash
set -euxo pipefail

# download.
# see https://github.com/google/go-containerregistry
# renovate: datasource=github-releases depName=google/go-containerregistry
crane_version='0.14.0'
crane_url="https://github.com/google/go-containerregistry/releases/download/v${crane_version}/go-containerregistry_Linux_x86_64.tar.gz"
tgz='/tmp/crane.tgz'
wget -qO $tgz "$crane_url"

# install.
tar xf $tgz -C /usr/local/bin crane
rm $tgz
crane version

# install the bash completion script.
crane completion bash >/usr/share/bash-completion/completions/crane

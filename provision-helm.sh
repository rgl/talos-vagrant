#!/bin/bash
source /vagrant/lib.sh

#
# deploy helm.

# see https://github.com/helm/helm/releases
helm_version="${1:-v3.8.1}"; shift || true

# install helm.
# see https://helm.sh/docs/intro/install/
echo "installing helm $helm_version client..."
case `uname -m` in
    x86_64)
        wget -qO- "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" | tar xzf - --strip-components=1 linux-amd64/helm
        ;;
    armv7l)
        wget -qO- "https://get.helm.sh/helm-$helm_version-linux-arm.tar.gz" | tar xzf - --strip-components=1 linux-arm/helm
        ;;
esac
install helm /usr/local/bin

# install the bash completion script.
helm completion bash >/usr/share/bash-completion/completions/helm

# kick the tires.
title 'helm version'
helm version

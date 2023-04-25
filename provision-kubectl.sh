#!/bin/bash
source /vagrant/lib.sh

kubectl_version="${1:-1.26.4}"; shift || true

url="https://dl.k8s.io/release/v$kubectl_version/bin/linux/amd64/kubectl"
t="$(mktemp -q -d --suffix=.kubectl)"
wget -qO "$t/kubectl" "$url"
install -m 755 "$t/kubectl" /usr/local/bin/kubectl
rm -rf "$t"
kubectl completion bash >/usr/share/bash-completion/completions/kubectl
kubectl version --client
cp /usr/local/bin/kubectl /vagrant/shared

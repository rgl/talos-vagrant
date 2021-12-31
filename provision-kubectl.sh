#!/bin/bash
source /vagrant/lib.sh

kubernetes_version="${1:-1.23.1}"; shift || true

# see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
wget -qO /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' >/etc/apt/sources.list.d/kubernetes.list
apt-get update
kubectl_package_version="$(apt-cache madison kubectl | awk "/$kubernetes_version-/{print \$3}")"
apt-get install -y "kubectl=$kubectl_package_version"
kubectl completion bash >/usr/share/bash-completion/completions/kubectl
kubectl version --client
cp /usr/bin/kubectl /vagrant/shared

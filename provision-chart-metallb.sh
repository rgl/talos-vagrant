#!/bin/bash
source /vagrant/lib.sh

# metallb chart.
# see https://artifacthub.io/packages/helm/bitnami/metallb
# see https://metallb.universe.tf/configuration/#layer-2-configuration
# see https://github.com/bitnami/charts/tree/master/bitnami/metallb
metallb_chart_version="${1:-2.5.4}"; shift || true
metallb_ip_addresses="${1:-10.10.0.200-10.10.0.219}"; shift || true

# add the gitlab helm charts repository.
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# search the chart and app versions, e.g.: in this case we are using:
#     NAME             CHART VERSION  APP VERSION  DESCRIPTION
#     bitnami/metallb  2.5.4          0.10.2       The Metal LB for Kubernetes
helm search repo bitnami/metallb --versions | head -5

# install.
helm upgrade --install \
  metallb \
  bitnami/metallb \
  --version $metallb_chart_version \
  --namespace metallb \
  --create-namespace \
  --values <(cat <<EOF
configInline:
  address-pools:
    - name: default
      protocol: layer2
      addresses:
        - $metallb_ip_addresses
EOF
)

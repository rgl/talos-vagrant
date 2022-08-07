#!/bin/bash
source /vagrant/lib.sh

# external-dns chart.
# see https://artifacthub.io/packages/helm/bitnami/external-dns
# see https://github.com/bitnami/charts/tree/master/bitnami/external-dns
# see https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pdns.md
# see https://github.com/kubernetes-sigs/external-dns/blob/master/docs/initial-design.md
external_dns_chart_version="${1:-6.7.4}"; shift || true
dns_domain="$(hostname --domain)"

# add the bitnami helm charts repository.
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# search the chart and app versions, e.g.: in this case we are using:
#     NAME                  CHART VERSION  APP VERSION  DESCRIPTION
#     bitnami/external-dns  6.7.4          0.12.2      	ExternalDNS is a Kubernetes addon that configur...
helm search repo bitnami/external-dns --versions | head -5

# install.
helm upgrade --install \
  external-dns \
  bitnami/external-dns \
  --version $external_dns_chart_version \
  --namespace external-dns \
  --create-namespace \
  --values <(cat <<EOF
logLevel: debug
interval: 30s
sources:
  - ingress
txtOwnerId: k8s
domainFilters:
  - $dns_domain
provider: pdns
pdns:
  apiUrl: http://pandora.$dns_domain
  apiPort: 8081
  apiKey: vagrant
EOF
)

#!/bin/bash
source /vagrant/lib.sh

# external-dns chart.
# see https://artifacthub.io/packages/helm/bitnami/external-dns
# see https://github.com/bitnami/charts/tree/master/bitnami/external-dns
# see https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pdns.md
# see https://github.com/kubernetes-sigs/external-dns/blob/master/docs/initial-design.md
external_dns_chart_version="${1:-5.4.5}"; shift || true
dns_domain="$(hostname --domain)"

# add the gitlab helm charts repository.
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# search the chart and app versions, e.g.: in this case we are using:
#     NAME                  CHART VERSION  APP VERSION  DESCRIPTION
#     bitnami/external-dns  5.4.5          0.9.0      	ExternalDNS is a Kubernetes addon that configur...
helm search repo bitnami/external-dns --versions | head -5

# install.
# NB this cannot yet use k8s 1.22 because its still using the deprecated ingress api version.
#    see https://github.com/kubernetes-sigs/external-dns/pull/2218 seems to add support for 1.22 but its not yet shipped in a release.
#    see https://github.com/kubernetes-sigs/external-dns/issues/2168
#    see https://github.com/kubernetes-sigs/external-dns/issues/961#issuecomment-895705995
helm upgrade --install \
  external-dns \
  bitnami/external-dns \
  --version $external_dns_chart_version \
  --namespace kube-system \
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

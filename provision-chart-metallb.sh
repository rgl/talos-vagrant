#!/bin/bash
source /vagrant/lib.sh

# metallb chart.
# see https://github.com/metallb/metallb/releases
# see https://github.com/metallb/metallb/tree/v0.13.10/charts/metallb
# see https://metallb.universe.tf/installation/#installation-with-helm
# see https://metallb.universe.tf/configuration/#layer-2-configuration
metallb_chart_version="${1:-0.13.10}"; shift || true
metallb_ip_addresses="${1:-10.10.0.200-10.10.0.219}"; shift || true

# add the metallb helm charts repository.
helm repo add metallb https://metallb.github.io/metallb

# search the chart and app versions, e.g.: in this case we are using:
#     NAME             CHART VERSION  APP VERSION  DESCRIPTION
#     metallb/metallb  0.13.10        v0.13.10     A network load-balancer implementation for Kube...
helm search repo metallb/metallb --versions | head -5

# create the namespace.
# see https://github.com/metallb/metallb/blob/v0.13.10/config/native/ns.yaml
# see https://github.com/metallb/metallb/issues/1457
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF

# install.
helm upgrade --install \
  metallb \
  metallb/metallb \
  --version $metallb_chart_version \
  --namespace metallb-system \
  --wait

# advertise addresses using the L2 mode.
# NB we have to sit in a loop until the metallb-webhook-service endpoint is
#    available. while its starting, it will fail with:
#       Error from server (InternalError): error when creating "STDIN": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.cluster-metallb.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.103.0.220:443: connect: connection refused
#    see https://github.com/metallb/metallb/issues/1547
while ! kubectl apply --namespace metallb-system -f - <<EOF
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
spec:
  addresses:
    - $metallb_ip_addresses
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
EOF
do sleep 5; done

#!/bin/bash
source /vagrant/lib.sh

# metallb chart.
# see https://github.com/metallb/metallb/releases
# see https://github.com/metallb/metallb/tree/v0.13.4/charts/metallb
# see https://metallb.universe.tf/installation/#installation-with-helm
# see https://metallb.universe.tf/configuration/#layer-2-configuration
metallb_chart_version="${1:-0.13.4}"; shift || true
metallb_ip_addresses="${1:-10.10.0.200-10.10.0.219}"; shift || true

# add the metallb helm charts repository.
helm repo add metallb https://metallb.github.io/metallb

# search the chart and app versions, e.g.: in this case we are using:
#     NAME             CHART VERSION  APP VERSION  DESCRIPTION
#     metallb/metallb  0.13.4         v0.13.4      A network load-balancer implementation for Kube...
helm search repo metallb/metallb --versions | head -5

# create the namespace.
# see https://github.com/metallb/metallb/blob/v0.13.4/config/native/ns.yaml
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
# TODO remove the --values when https://github.com/metallb/metallb/issues/1401 is done.
#      also see the Caution note at https://kubernetes.io/docs/concepts/security/pod-security-policy/
helm upgrade --install \
  metallb \
  metallb/metallb \
  --version $metallb_chart_version \
  --namespace metallb-system \
  --wait \
  --values <(cat <<EOF
psp:
  create: false
EOF
)

# advertise addresses using the L2 mode.
kubectl apply --namespace metallb-system -f - <<EOF
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

#!/bin/bash
source /vagrant/lib.sh

# vector chart.
# see https://artifacthub.io/packages/helm/vector/vector
# see https://github.com/vectordotdev/helm-charts
# see https://vector.dev/docs/setup/installation/package-managers/helm/
vector_chart_version="${1:-0.15.1}"; shift || true
pandora_ip_address="${1:-10.10.0.2}"; shift || true

# add the vector helm charts repository.
helm repo add vector https://helm.vector.dev
helm repo update

# search the chart and app versions, e.g.: in this case we are using:
#   NAME           CHART VERSION  APP VERSION             DESCRIPTION                                       
#   vector/vector  0.15.1         0.23.3-distroless-libc  A lightweight, ultra-fast tool for building obs...
helm search repo vector/vector --versions | head -5

# install.
# see https://vector.dev/docs/reference/configuration/sources/kubernetes_logs
# NB in talos, the /var partition is ephemeral and will be erased at the next
#    upgrade. this means the logs and the vector data_dir will be lost.
#    see https://www.talos.dev/v1.2/learn-more/architecture/
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: logging-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF
helm upgrade --install \
  vector \
  vector/vector \
  --version $vector_chart_version \
  --namespace logging-system \
  --values <(cat <<EOF
role: Agent
service:
  enabled: false
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
    operator: Exists
persistence:
  hostPath:
    path: /var/vector
customConfig:
  data_dir: /var/vector
$(
  sed \
    -E "s,http://localhost:3100,http://$pandora_ip_address:3100,g" \
    /vagrant/vector-k8s.yml \
    | sed -E 's,\{\{,{{ "{{" }},g' \
    | sed -E 's,^,  ,g')
EOF
)

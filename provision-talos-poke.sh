#!/bin/bash
source /vagrant/lib.sh
cd /vagrant/talos-poke

registry_domain="$(hostname --fqdn)"
registry_host="$registry_domain:5000"

docker build -t "$registry_host/talos-poke" .

docker push "$registry_host/talos-poke"

install -m 755 /dev/null /usr/local/bin/talos-poke
cat >/usr/local/bin/talos-poke <<'EOF_TALOS_POKE'
#!/bin/bash
set -euo pipefail

node="${1:-cp1}"; shift || true
command="${1:-images}"; shift || true
registry_domain="$(hostname --fqdn)"
registry_host="$registry_domain:5000"

kubectl -n kube-system delete --grace-period=0 --force pod/talos-poke 2>&1 | grep -v NotFound || true

kubectl -n kube-system apply -f - <<EOF
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.24/#pod-v1-core
apiVersion: v1
kind: Pod
metadata:
  name: talos-poke
spec:
  nodeSelector:
    kubernetes.io/hostname: $node
  containers:
    - name: talos-poke
      image: $registry_host/talos-poke:latest
      securityContext:
        privileged: true
      volumeMounts:
        - mountPath: /host
          name: host
  volumes:
    - name: host
      hostPath:
        path: /
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/control-plane
      operator: Exists
EOF

kubectl -n kube-system wait --for=condition=ready pod/talos-poke

function exec-images {
  kubectl -n kube-system exec -i pod/talos-poke -- bash <<'EOF'
set -euo pipefail

function get-images {
  ctr ns ls -q | while read ns; do ctr -n $ns images ls -q; done
}

# system containerd.
export CONTAINERD_ADDRESS=/host/system/run/containerd/containerd.sock
get-images | grep -v sha256: || true

# user containerd.
export CONTAINERD_ADDRESS=/host/run/containerd/containerd.sock
get-images | grep -v sha256: || true
EOF
}

case "$command" in
  images)
    exec-images
    ;;
  *)
    echo unknown command
    exit 1
    ;;
esac

kubectl -n kube-system delete --grace-period=0 --force pod/talos-poke 2>&1 | grep -v NotFound || true

EOF_TALOS_POKE

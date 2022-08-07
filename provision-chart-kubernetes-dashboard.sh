#!/bin/bash
source /vagrant/lib.sh

# kubernetes-dashboard chart.
# see https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
# see https://github.com/kubernetes/dashboard/blob/master/aio/deploy/helm-chart/kubernetes-dashboard/values.yaml
kubernetes_dashboard_chart_version="${1:-5.7.0}"; shift || true
domain="$(hostname --domain)"

# add the kubernetes helm charts repository.
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo update

# search the chart and app versions.
helm search repo kubernetes/kubernetes-dashboard --versions | head -5

# install.
helm upgrade --install \
  kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  --version $kubernetes_dashboard_chart_version \
  --namespace kubernetes-dashboard \
  --create-namespace \
  --values <(cat <<EOF
ingress:
  enabled: true
  hosts:
    - kubernetes-dashboard.$domain
  tls:
    - secretName: kubernetes-dashboard-tls
service:
  externalPort: 80
protocolHttp: true
extraArgs:
  - --enable-insecure-login
containerSecurityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
EOF
)

# expose the kubernetes dashboard at https://kubernetes-dashboard.talos.test.
kubectl apply -n kubernetes-dashboard -f - <<EOF
---
# see https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kubernetes-dashboard
spec:
  subject:
    organizations:
      - Example
    organizationalUnits:
      - Kubernetes
  commonName: Kubernetes Dashboard
  dnsNames:
    - kubernetes-dashboard.$domain
  duration: 1h # NB this is so low for testing purposes.
  privateKey:
    algorithm: ECDSA # NB Ed25519 is not yet supported by chrome 93 or firefox 91.
    size: 256
  secretName: kubernetes-dashboard-tls
  issuerRef:
    kind: ClusterIssuer
    name: ingress
EOF

# create the admin user for use in the kubernetes-dashboard.
# see https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md
# see https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/README.md
# see https://kubernetes.io/docs/concepts/configuration/secret/#service-account-token-secrets
kubectl apply -n kubernetes-dashboard -f - <<'EOF'
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
---
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: admin
  annotations:
    kubernetes.io/service-account.name: admin
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin
    namespace: kubernetes-dashboard
EOF
# save the admin token.
kubectl -n kubernetes-dashboard get secret admin -o json \
  | jq -r .data.token \
  | base64 --decode \
  >/vagrant/shared/admin-token.txt

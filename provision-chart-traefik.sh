#!/bin/bash
source /vagrant/lib.sh

# traefik chart.
# see https://artifacthub.io/packages/helm/traefik/traefik
# see https://github.com/traefik/traefik-helm-chart
# see https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml
traefik_chart_version="${1:-10.24.0}"; shift || true
domain="$(hostname --domain)"

# add the traefik helm charts repository.
helm repo add traefik https://helm.traefik.io/traefik
helm repo update

# search the chart and app versions, e.g.: in this case we are using:
#     NAME             CHART VERSION  APP VERSION  DESCRIPTION
#     traefik/traefik  10.24.0        2.8.0        A Traefik based Kubernetes ingress controller
helm search repo traefik/traefik --versions | head -5

# install.
helm upgrade --install \
  traefik \
  traefik/traefik \
  --version $traefik_chart_version \
  --namespace traefik \
  --create-namespace \
  --values <(cat <<EOF
ports:
  # enable tls.
  # NB this is not really configured. it will use a dummy
  #    self-signed certificate. this is only here to be
  #    able to login into the kubernetes dashboard.
  websecure:
    tls:
      enabled: true
# publish the traefik service IP address in the Ingress
# resources.
providers:
  kubernetesIngress:
    publishedService:
      enabled: true
# disable the dashboard IngressRoute.
# NB we will create the Ingress ourselves and expose the
#    dashboard with external-dns too.
ingressRoute:
  dashboard:
    enabled: false
logs:
  # set the logging level.
  general:
    level: ERROR
  # enable the access logs.
  access:
    enabled: true
# disable pilot.
pilot:
  enabled: false
  dashboard: false
# disable the telemetry (this is done by emptying globalArguments) and
# configure traefik to skip certificate validation.
# NB this is needed to expose the k8s dashboard as an ingress at
#    https://kubernetes-dashboard.talos.test when the dashboard is using
#    tls.
# NB without this, traefik returns "internal server error" when it
#    encounters a server certificate signed by an unknown CA.
# NB we need to use https, because the kubernetes-dashboard require it
#    to allow us to login.
# TODO see how to set the CAs in traefik.
# NB this should never be done at production.
globalArguments:
  - --serverstransport.insecureskipverify=true
securityContext:
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
EOF
)

# expose the traefik dashboard at https://traefik.talos.test.
kubectl apply -n traefik -f - <<EOF
---
# see https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik
spec:
  subject:
    organizations:
      - Example
    organizationalUnits:
      - Kubernetes
  commonName: Traefik Dashboard
  dnsNames:
    - traefik.$domain
  duration: 1h # NB this is so low for testing purposes.
  privateKey:
    algorithm: ECDSA # NB Ed25519 is not yet supported by chrome 93 or firefox 91.
    size: 256
  secretName: traefik-tls
  issuerRef:
    kind: ClusterIssuer
    name: ingress
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik
spec:
  entryPoints:
    - websecure
  tls:
    secretName: traefik-tls
  routes:
    - match: Host("traefik.$domain")
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traefik
spec:
  rules:
    # NB we do not specify any backend services. this will make traefik ignore
    #    this ingress and just use the IngressRoute we defined earlier. it will
    #    also be used by external-dns to publish the DNS A RR.
    # NB we could just point to the traefik service, but since its deployed by
    #    helm, we do not known its actual service name; its someting alike
    #    traefik-1628581297:
    #       root@c1:~# kubectl get service -A
    #       NAMESPACE     NAME                      TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
    #       default       traefik-1628581297        LoadBalancer   10.110.59.161    10.10.0.100   80:30074/TCP,443:30484/TCP   9m47s
    # NB due to the external-dns controller this will automatically configure
    #    the external DNS server (installed in the pandora box) based on this
    #    ingress rule.
    #    see https://github.com/kubernetes-incubator/external-dns
    - host: traefik.$domain
EOF

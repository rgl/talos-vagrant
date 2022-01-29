#!/bin/bash
source /vagrant/lib.sh


domain="$(hostname --domain)"


kubectl apply -f - <<EOF
---
# see https://cert-manager.io/docs/reference/api-docs/#cert-manager.io/v1.Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-daemonset
spec:
  subject:
    organizations:
      - Example
    organizationalUnits:
      - Kubernetes
  commonName: example-daemonset
  dnsNames:
    - example-daemonset.$domain
  duration: 1h # NB this is so low for testing purposes.
  privateKey:
    algorithm: ECDSA # NB Ed25519 is not yet supported by chrome 93 or firefox 91.
    size: 256
  secretName: example-daemonset-tls
  issuerRef:
    kind: ClusterIssuer
    name: ingress
---
# see https://kubernetes.io/docs/concepts/services-networking/ingress/
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#ingress-v1-networking-k8s-io
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-daemonset
spec:
  tls:
    - secretName: example-daemonset-tls
  rules:
    # NB due to the external-dns controller this will automatically configure
    #    the external DNS server (installed in the pandora box) based on this
    #    ingress rule.
    #    see https://github.com/kubernetes-incubator/external-dns
    - host: example-daemonset.$domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-daemonset
                port:
                  name: web
---
# see https://kubernetes.io/docs/concepts/services-networking/service/#nodeport
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#service-v1-core
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#serviceport-v1-core
apiVersion: v1
kind: Service
metadata:
  name: example-daemonset
spec:
  type: ClusterIP
  selector:
    app: example-daemonset
  ports:
    - name: web
      port: 80
      protocol: TCP
      targetPort: web
---
# see https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#daemonset-v1-apps
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#podtemplatespec-v1-core
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#container-v1-core
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: example-daemonset
spec:
  selector:
    matchLabels:
      app: example-daemonset
  template:
    metadata:
      labels:
        app: example-daemonset
    spec:
      containers:
        # see https://github.com/rgl/example-docker-buildx-go
        - name: example-daemonset
          image: ruilopes/example-docker-buildx-go:v1.5.0
          args:
            - -listen
            - 0.0.0.0:9000
          env:
            # see https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/
            # see https://github.com/kubernetes/kubernetes/blob/v1.23.2/test/e2e/common/node/downwardapi.go
            - name: EXAMPLE_NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: EXAMPLE_POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: EXAMPLE_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: EXAMPLE_POD_UID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.uid
            - name: EXAMPLE_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          ports:
            - name: web
              containerPort: 9000
          resources:
            requests:
              memory: 20Mi
              cpu: 0.1
            limits:
              memory: 20Mi
              cpu: 0.1
EOF

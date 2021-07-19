#!/bin/bash
source /vagrant/lib.sh

kubectl apply -f - <<'EOF'
---
# see https://kubernetes.io/docs/concepts/services-networking/service/#nodeport
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.21/#service-v1-core
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.21/#serviceport-v1-core
apiVersion: v1
kind: Service
metadata:
  name: example-daemonset
spec:
  type: NodePort
  selector:
    app: example-daemonset
  ports:
    - name: http
      nodePort: 30000
      port: 30000
      protocol: TCP
      targetPort: http
---
# see https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.21/#daemonset-v1-apps
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.21/#podtemplatespec-v1-core
# see https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.21/#container-v1-core
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
        - name: example-daemonset
          image: ruilopes/example-docker-buildx-go:v1.1.0
          args:
            - -listen
            - 0.0.0.0:9000
          ports:
            - name: http
              containerPort: 9000
          resources:
            requests:
              memory: 20Mi
              cpu: 0.1
            limits:
              memory: 20Mi
              cpu: 0.1
EOF

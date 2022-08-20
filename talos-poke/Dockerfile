# syntax=docker/dockerfile:1.4
FROM debian:11-slim
RUN <<'EOF'
set -eux
apt-get update
apt-get install -y wget
rm -rf /var/lib/apt/lists/*
EOF
RUN <<'EOF'
set -eux
cd /usr/local
wget -q https://github.com/containerd/containerd/releases/download/v1.6.8/containerd-1.6.8-linux-amd64.tar.gz
tar xf containerd-1.6.8-linux-amd64.tar.gz bin/ctr
rm containerd-1.6.8-linux-amd64.tar.gz
EOF
ENTRYPOINT ["/bin/bash", "-c", "sleep infinity"]

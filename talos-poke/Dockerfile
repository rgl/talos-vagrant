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
# renovate: datasource=github-releases depName=containerd/containerd
ctrd_version='1.6.15'
cd /usr/local
url="https://github.com/containerd/containerd/releases/download/v$ctrd_version/containerd-$ctrd_version-linux-amd64.tar.gz"
wget -q "$url"
tar xf "containerd-$ctrd_version-linux-amd64.tar.gz" bin/ctr
rm "containerd-$ctrd_version-linux-amd64.tar.gz"
EOF
RUN <<'EOF'
set -eux
# renovate: datasource=github-releases depName=etcd-io/etcd
etcd_version='3.5.8'
# install the binaries.
url="https://github.com/etcd-io/etcd/releases/download/v$etcd_version/etcd-v$etcd_version-linux-amd64.tar.gz"
filename="$(basename "$url")"
wget -q "$url"
rm -rf etcd && mkdir etcd
tar xf "$filename" --strip-components 1 -C etcd
install etcd/etcdctl /usr/local/bin
rm -rf "$filename" etcd
# configure the user environment to access etcd.
cat >/etc/profile.d/etcdctl.sh <<'STDIN'
export ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt
export ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt
export ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key
STDIN
EOF
ENTRYPOINT ["/bin/bash", "-c", "sleep infinity"]

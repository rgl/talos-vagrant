#!/bin/bash
source /vagrant/lib.sh

etcd_version="${1:-3.5.9}"; shift || true

# install the binaries.
url="https://github.com/etcd-io/etcd/releases/download/v$etcd_version/etcd-v$etcd_version-linux-amd64.tar.gz"
filename="$(basename "$url")"
wget -q "$url"
rm -rf etcd && mkdir etcd
tar xf "$filename" --strip-components 1 -C etcd
install etcd/etcdctl /usr/local/bin
rm -rf "$filename" etcd

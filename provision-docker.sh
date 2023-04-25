#!/bin/bash
source /vagrant/lib.sh


# renovate: datasource=github-releases depName=moby/moby
docker_version='20.10.21'


# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# make sure the package index cache is up-to-date before installing anything.
apt-get update

# install docker.
# see https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-repository
apt-get install -y apt-transport-https software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-cache madison docker-ce
docker_apt_version="$(apt-cache madison docker-ce | awk "/$docker_version~/{print \$3}")"
apt-get install -y "docker-ce=$docker_apt_version" "docker-ce-cli=$docker_apt_version" containerd.io

# configure it.
systemctl stop docker
cat >/etc/docker/daemon.json <<'EOF'
{
    "experimental": false,
    "debug": false,
    "features": {
        "buildkit": true
    },
    "log-driver": "journald",
    "labels": [
        "os=linux"
    ],
    "hosts": [
        "unix://"
    ]
}
EOF
# start docker without any command line flags as its entirely configured from daemon.json.
install -d /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF
systemctl daemon-reload
systemctl start docker

# let the vagrant user manage docker.
usermod -aG docker vagrant

# kick the tires.
ctr version
docker version
docker info
docker network ls
ip link
bridge link
#docker run --rm hello-world
#docker run --rm alpine ping -c1 8.8.8.8
#docker run --rm debian:10 ping -c1 8.8.8.8
#docker run --rm debian:10-slim cat /etc/os-release
#docker run --rm ubuntu:20.04 cat /etc/os-release

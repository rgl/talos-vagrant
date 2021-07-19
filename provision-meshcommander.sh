#!/bin/bash
source /vagrant/lib.sh
cd /vagrant/meshcommander

docker build -t meshcommander .

docker run \
    -d \
    --restart unless-stopped \
    --name meshcommander \
    -p 4000:4000 \
    -e NODE_ENV=production \
    meshcommander

#!/bin/bash
source lib.sh

# start the virtual machines.
# NB pandora should be first. it provide pxe boot for the other machines.
title 'Starting pandora machine'
vagrant up --provider=libvirt --no-destroy-on-error pandora
title 'Starting the cluster machines'
vagrant up --provider=libvirt --no-destroy-on-error

# bootstrap the cluster.
title 'Bootstrapping the cluster'
vagrant ssh -c 'sudo bash /vagrant/bootstrap-talos.sh' pandora

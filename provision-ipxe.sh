#!/bin/bash
source /vagrant/lib.sh

# install the amd64 architecture binaries.
apt-get install --no-install-recommends -y ipxe
install -m 644 /usr/lib/ipxe/undionly.kpxe /srv/pxe
install -m 644 /usr/lib/ipxe/ipxe.efi /srv/pxe
install -m 644 /usr/lib/ipxe/undionly.kpxe /var/lib/matchbox/assets
install -m 644 /usr/lib/ipxe/ipxe.efi /var/lib/matchbox/assets

# install the arm64 architecture binaries.
# see https://github.com/rgl/rpi4-uefi-ipxe
wget -q https://github.com/rgl/rpi4-uefi-ipxe/releases/download/v0.1.0/rpi4-uefi-ipxe.zip
unzip -d rpi4-uefi-ipxe rpi4-uefi-ipxe.zip
pushd rpi4-uefi-ipxe
install -m 644 efi/boot/bootaa64.efi /srv/pxe/ipxe-arm64.efi
install -m 644 efi/boot/bootaa64.efi /var/lib/matchbox/assets/ipxe-arm64.efi
popd
rm -rf rpi4-uefi-ipxe{,.zip}

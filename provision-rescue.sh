#!/bin/bash
source /vagrant/lib.sh


matchbox_base_url="http://$(hostname --fqdn)"
machinator_base_url="http://$(hostname --fqdn):8000"


for rescue_arch in amd64 arm64; do

# get the rescue from https://github.com/rgl/debian-live-builder-vagrant.
rescue_url="https://github.com/rgl/debian-live-builder-vagrant/releases/download/v20210714/debian-live-20210714-$rescue_arch.iso"
rescue_iso_path="/vagrant/shared/$(basename "$rescue_url")"
if [ ! -f "$rescue_iso_path" ]; then
    title "downloading rescue from $rescue_url"
    wget -qO "$rescue_iso_path" "$rescue_url"
fi

# install into the matchbox assets directory.
title "installing rescue into /var/lib/matchbox/assets/rescue-$rescue_arch"
install -d /var/lib/matchbox/assets/rescue-$rescue_arch
7z x -y \
    -o/var/lib/matchbox/assets/rescue-$rescue_arch \
    "$rescue_iso_path" \
    live/{vmlinuz-\*,initrd.img-\*,filesystem.squashfs}
mv /var/lib/matchbox/assets/rescue-$rescue_arch/{live/*,}
mv /var/lib/matchbox/assets/rescue-$rescue_arch/{vmlinuz-*,vmlinuz}
mv /var/lib/matchbox/assets/rescue-$rescue_arch/{initrd.img-*,initrd.img}
rmdir /var/lib/matchbox/assets/rescue-$rescue_arch/live

# create the matchbox profile.
# see https://manpages.debian.org/bullseye/live-boot-doc/live-boot.7.en.html
# see https://manpages.debian.org/bullseye/live-config-doc/live-config.7.en.html
# see https://manpages.debian.org/bullseye/manpages/bootparam.7.en.html
# see https://manpages.debian.org/bullseye/udev/systemd-udevd.service.8.en.html
# see https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/bootconfig.rst
# see https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/kernel-parameters.txt
title "creating the rescue matchbox-$rescue_arch profile"
cat >/var/lib/matchbox/profiles/rescue-$rescue_arch.json <<EOF
{
    "id": "rescue-$rescue_arch",
    "name": "rescue-$rescue_arch",
    "boot": {
        "kernel": "/assets/rescue-$rescue_arch/vmlinuz",
        "initrd": [
            "/assets/rescue-$rescue_arch/initrd.img"
        ],
        "args": [
            "initrd=initrd.img",
            "net.ifnames=0",
            "boot=live",
            "fetch=$matchbox_base_url/assets/rescue-$rescue_arch/filesystem.squashfs",
            "components",
            "username=vagrant",
            "matchbox.metadata=$matchbox_base_url/metadata?mac=\${mac:hexhyp}"
        ]
    }
}
EOF
# NB the only difference is the addition of the "hooks" args.
title "creating the rescue-wipe-$rescue_arch matchbox profile"
cat >/var/lib/matchbox/profiles/rescue-wipe-$rescue_arch.json <<EOF
{
    "id": "rescue-wipe-$rescue_arch",
    "name": "rescue-wipe-$rescue_arch",
    "boot": {
        "kernel": "/assets/rescue-$rescue_arch/vmlinuz",
        "initrd": [
            "/assets/rescue-$rescue_arch/initrd.img"
        ],
        "args": [
            "initrd=initrd.img",
            "net.ifnames=0",
            "boot=live",
            "fetch=$matchbox_base_url/assets/rescue-$rescue_arch/filesystem.squashfs",
            "components",
            "username=vagrant",
            "hooks=$machinator_base_url/wipe.sh?mac=\${mac:hexhyp}",
            "matchbox.metadata=$matchbox_base_url/metadata?mac=\${mac:hexhyp}"
        ]
    }
}
EOF

done

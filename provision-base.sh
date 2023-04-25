#!/bin/bash
source /vagrant/lib.sh


echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive


#
# make sure the package index cache is up-to-date before installing anything.

apt-get update


#
# expand the root partition.

apt-get install -y --no-install-recommends parted
partition_device="$(findmnt -no SOURCE /)"
partition_number="$(echo "$partition_device" | perl -ne '/(\d+)$/ && print $1')"
disk_device="$(echo "$partition_device" | perl -ne '/(.+?)\d+$/ && print $1')"
parted ---pretend-input-tty "$disk_device" <<EOF
resizepart $partition_number 100%
yes
EOF
resize2fs "$partition_device"


# enable systemd-journald persistent logs.
sed -i -E 's,^#?(Storage=).*,\1persistent,' /etc/systemd/journald.conf
systemctl restart systemd-journald


#
# install vim.

apt-get install -y --no-install-recommends vim

cat >~/.vimrc <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF


#
# configure the shell.

cat >~/.bash_history <<'EOF'
EOF

cat >~/.bashrc <<'EOF'
# If not running interactively, don't do anything
[[ "$-" != *i* ]] && return

export EDITOR=vim
export PAGER=less

alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat >~/.inputrc <<'EOF'
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
set show-all-if-ambiguous on
set completion-ignore-case on
EOF


#
# install git.

apt-get install -y git


#
# configure git.

git config --global user.name 'Rui Lopes'
git config --global user.email 'rgl@ruilopes.com'
git config --global push.default simple
git config --global core.autocrlf false


#
# install useful tools.

apt-get install -y unzip
apt-get install -y httpie
apt-get install -y jq
apt-get install -y python3-tabulate python3-yaml
apt-get install -y bash-completion
apt-get install -y p7zip-full

# etherwake lets us power-on a machine by sending a Wake-on-LAN (WOL)
# magic packet to its ethernet card.
# e.g. etherwake -i eth1 00:e0:4c:01:93:a8
apt-get install -y etherwake

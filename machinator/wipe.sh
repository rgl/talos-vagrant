#!/bin/bash
set -euo pipefail

# NB this file is executed synchronously by the live-config service
#    (/lib/systemd/system/live-config.service) from the
#    /lib/live/config/9990-hooks hook script.
# NB the systemd basic.target is only executed after this script
#    finishes (live-config.service has the WantedBy=basic.target
#    setting).

# remove all the signatures from the install disk device.
cat >/wipe.py <<'EOF'
import json
import requests
import subprocess
import time

def parse_args(lines):
    args = {}
    for l in lines:
        parts = l.split('=', 1)
        k = parts[0]
        if len(parts) > 1:
            v = parts[1]
        else:
            v = None
        args[k] = v
    return args

def get_cmdline():
    with open('/proc/cmdline', 'r') as f:
        return parse_args(f.read().rstrip().split(' '))

def get_metadata(metadata_url):
    r = requests.get(metadata_url)
    r.raise_for_status()
    return parse_args(r.text.rstrip().split('\n'))

cmdline = get_cmdline()

metadata = get_metadata(cmdline['matchbox.metadata'])

install_disk = metadata['INSTALLDISK']

if not install_disk:
    raise Exception('the INSTALLDISK metadata must not be empty')

print(f'Wiping the {install_disk} disk device...')
subprocess.run(['wipefs', '--all', install_disk], check=True)

print(f'Creating an empty GPT label in the {install_disk} disk device...')
subprocess.run(['parted', '--script', install_disk, 'mklabel', 'gpt'], check=True)

print('Sync...')
subprocess.run(['sync'], check=True)

print(f'Calling {{.WipedUrl}}...')
r = requests.post('{{.WipedUrl}}')
r.raise_for_status()

if r.text == 'reboot':
    for t in reversed(range(10)):
        print(f'Rebooting in T-{t+1}...')
        time.sleep(1)
    subprocess.run(['reboot'], check=True)
EOF

# configure the system to automatically execute wipe when the user logins.
# NB the vagrant user is automatically logged in when the username=vagrant
#    is present in the kernel command line.
# NB this file is sourced by the login shell.
profile_wipe_sh_path='/etc/profile.d/Z99-wipe.sh'
cat >$profile_wipe_sh_path <<EOF
#!/bin/bash
clear
sudo rm -f $profile_wipe_sh_path
sudo python3 /wipe.py
EOF

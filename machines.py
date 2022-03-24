import ipaddress
import json
import os.path
import re
import socket
import sys
import yaml


# matchbox profiles.
# NB the ipxe script will be available at http://{pandora}/ipxe?mac={mac:hexhyp}
#    it will be equivalent to:
#       #!ipxe
#       kernel vmlinuz-amd64 initrd=initramfs-amd64.xz ...
#       initrd initramfs-amd64.xz
#       boot
# NB the pxe supplied kernel arguments are not retained by the installed talos.
#    for that, we must patch the machine config property at
#    /machine/install/extraKernelArgs (like we do in provision-talos.sh).
def get_matchbox_profiles():
    required_files = [
        'assets/vmlinuz-amd64',
        'assets/initramfs-amd64.xz',
        'assets/vmlinuz-arm64',
        'assets/initramfs-arm64.xz',
        'generic/controlplane.yaml',
        'generic/worker.yaml',
    ]
    for required_file in required_files:
        if not os.path.exists(f'/var/lib/matchbox/{required_file}'):
            return

    matchbox_base_url = f'http://{socket.getfqdn()}'

    for arch in ('amd64', 'arm64'):
        yield {
            "id": f"controlplane-{arch}",
            "name": f"controlplane-{arch}",
            "generic_id": "controlplane.yaml",
            "boot": {
                "kernel": f"/assets/vmlinuz-{arch}",
                "initrd": [f"/assets/initramfs-{arch}.xz"],
                "args": [
                    "sysctl.kernel.kexec_load_disabled=1" if arch == 'arm64' else None,
                    f"initrd=initramfs-{arch}.xz",
                    "init_on_alloc=1",
                    "slab_nomerge",
                    "pti=on",
                    "console=tty0",
                    "console=ttyS0",
                    "printk.devkmsg=on",
                    "talos.platform=metal",
                    f"talos.config={matchbox_base_url}/generic?mac=${{mac:hexhyp}}"
                ]
            }
        }
        yield {
            "id": f"worker-{arch}",
            "name": f"worker-{arch}",
            "generic_id": "worker.yaml",
            "boot": {
                "kernel": f"/assets/vmlinuz-{arch}",
                "initrd": [f"/assets/initramfs-{arch}.xz"],
                "args": [
                    "sysctl.kernel.kexec_load_disabled=1" if arch == 'arm64' else None,
                    f"initrd=initramfs-{arch}.xz",
                    "init_on_alloc=1",
                    "slab_nomerge",
                    "pti=on",
                    "console=tty0",
                    "console=ttyS0",
                    "printk.devkmsg=on",
                    "talos.platform=metal",
                    f"talos.config={matchbox_base_url}/generic?mac=${{mac:hexhyp}}"
                ]
            }
        }


def save_matchbox_profiles():
    for profile in get_matchbox_profiles():
        with open(f'/var/lib/matchbox/profiles/{profile["id"]}.json', 'w') as f:
            json.dump(profile, f, indent=4)


# NB the ipxe script will be available at http://{pandora}/ipxe?mac={mac:hexhyp}
# NB the metadata part will be available at http://{pandora}/metadata?mac={mac:hexhyp}
def get_matchbox_groups():
    for machine in get_machines():
        name = machine['name']
        profile = f"{machine['role']}-{machine['arch']}"
        if not os.path.exists(f'/var/lib/matchbox/profiles/{profile}.json'):
            continue
        data = {
            "name": name,
            "profile": profile,
            "selector": {
                "mac": machine['mac'],
            },
            "metadata": {
                "installDisk": machine['installDisk'],
                "kexec": machine['kexec'],
            },
        }
        yield (name, data)


def save_matchbox_groups():
    for (name, data) in get_matchbox_groups():
        with open(f'/var/lib/matchbox/groups/{name}.json', 'w') as f:
            json.dump(data, f, indent=4)


def get_dnsmasq_machines():
    for machine in get_machines():
        yield (machine['type'], machine['name'], machine['mac'], machine['ip'])


def save_dnsmasq_machines():
    domain = socket.getfqdn().split('.', 1)[-1]

    def __save(machines, type):
        with open(f'/etc/dnsmasq.d/{type}-machines.conf', 'w') as f:
            for (_, hostname, mac, ip) in (m for m in machines if m[0] == type):
                f.write(f'dhcp-host={mac},{ip},{hostname}\n')

    machines = list(get_dnsmasq_machines())

    __save(machines, 'virtual')
    __save(machines, 'physical')


def get_machines(prefix='/vagrant'):
    with open(os.path.join(prefix, 'Vagrantfile'), 'r') as f:
        for line in f:
            m = re.match(r'^\s*CONFIG_PANDORA_DHCP_RANGE = \'(.+?),.+?\'', line)
            if m and m.groups(1):
                ip_address = ipaddress.ip_address(m.group(1))
            m = re.match(r'^\s*CONFIG_PANDORA_HOST_IP = \'(.+?)\'', line)
            if m and m.groups(1):
                host_ip_address = ipaddress.ip_address(m.group(1))

    with open(os.path.join(prefix, 'machines.yaml'), 'r') as f:
        machines = yaml.safe_load(f)

    # populate the missing mac address.
    for machine in machines:
        if 'mac' not in machine:
            machine['mac'] = '08:00:27:00:00:%02x' % (machine['hostNumber'])

    # populate the missing ip address.
    for machine in machines:
        if 'ip' not in machine:
            machine['ip'] = str(ip_address + machine['hostNumber'])

    # populate the virtual machines vbmc ip address and port.
    for machine in machines:
        if machine['type'] != 'virtual':
            continue
        if 'bmcType' not in machine:
            machine['bmcType'] = 'redfish'
        if 'bmcIp' not in machine:
            machine['bmcIp'] = str(host_ip_address)
        if 'bmcPort' not in machine:
            machine['bmcPort'] = 8000 + machine['hostNumber']
        if 'bmcQmpPort' not in machine:
            machine['bmcQmpPort'] = 9000 + machine['hostNumber']

    # populate the machines amt bmc ip address and port.
    for machine in machines:
        if not 'bmcType' in machine:
            continue
        if machine['bmcType'] != 'amt':
            continue
        if 'bmcIp' not in machine:
            machine['bmcIp'] = machine['ip']
        if 'bmcPort' not in machine:
            machine['bmcPort'] = 16992

    # populate the missing installDisk.
    for machine in machines:
        if 'installDisk' not in machine:
            if machine['type'] == 'virtual':
                machine['installDisk'] = '/dev/vda'
            elif machine['type'] == 'physical':
                machine['installDisk'] = '/dev/sda'

    # populate the missing kexec.
    for machine in machines:
        if 'kexec' not in machine:
            machine['kexec'] = True

    return machines


if __name__ == '__main__':
    if 'get-machines-json' in sys.argv:
        print(json.dumps(get_machines('.'), indent=4))
    else:
        save_matchbox_profiles()
        save_matchbox_groups()
        save_dnsmasq_machines()

# set the external dns zone used for ssh into the machines and ingress.
# NB the cluster dns zone must be different than this zone.
CONFIG_DNS_DOMAIN = 'talos.test'
CONFIG_PANDORA_FQDN = "pandora.#{CONFIG_DNS_DOMAIN}"
CONFIG_TALOS_VERSION = '1.2.0-beta.2' # see https://github.com/siderolabs/talos/releases and https://www.talos.dev/v1.2/introduction/support-matrix/
CONFIG_KUBERNETES_VERSION = '1.25.0' # see https://github.com/siderolabs/kubelet/releases, https://kubernetes.io/releases/, and https://www.talos.dev/v1.2/introduction/support-matrix/
CONFIG_KUBECTL_VERSION = CONFIG_KUBERNETES_VERSION # see https://kubernetes.io/releases/
CONFIG_THEILA_VERSION = '0.2.1' # see https://github.com/siderolabs/theila/releases
CONFIG_HELM_VERSION = 'v3.9.4' # see https://github.com/helm/helm/releases
CONFIG_K9S_VERSION = 'v0.26.3' # see https://github.com/derailed/k9s/releases
CONFIG_VECTOR_CHART_VERSION = '0.16.0' # see https://artifacthub.io/packages/helm/vector/vector
CONFIG_METALLB_CHART_VERSION = '0.13.4' # see https://github.com/metallb/metallb/releases
CONFIG_EXTERNAL_DNS_CHART_VERSION = '6.7.5' # see https://artifacthub.io/packages/helm/bitnami/external-dns
CONFIG_CERT_MANAGER_CHART_VERSION = '1.9.1' # see https://artifacthub.io/packages/helm/cert-manager/cert-manager
CONFIG_TRAEFIK_CHART_VERSION = '10.24.0' # see https://artifacthub.io/packages/helm/traefik/traefik
CONFIG_KUBERNETES_DASHBOARD_CHART_VERSION = '5.8.0' # see https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard

CONFIG_PANDORA_BRIDGE_NAME = nil
CONFIG_PANDORA_HOST_IP = '10.10.0.1'
CONFIG_PANDORA_IP = '10.10.0.2'
CONFIG_PANDORA_DHCP_RANGE = '10.10.0.100,10.10.0.199,10m'
CONFIG_PANDORA_LOAD_BALANCER_RANGE = '10.10.0.200-10.10.0.219'
CONFIG_CONTROL_PLANE_VIP = '10.10.0.3'

# connect to the external physical network through the given bridge.
# NB uncomment this block when using a bridge.
CONFIG_PANDORA_BRIDGE_NAME = 'br-rpi'
CONFIG_PANDORA_HOST_IP = '10.3.0.1'
CONFIG_PANDORA_IP = '10.3.0.2'
CONFIG_PANDORA_DHCP_RANGE = '10.3.0.100,10.3.0.199,10m'
CONFIG_PANDORA_LOAD_BALANCER_RANGE = '10.3.0.200-10.3.0.219'
CONFIG_CONTROL_PLANE_VIP = '10.3.0.3'

require './lib.rb'

# get the docker hub auth from the host ~/.docker/config.json file.
DOCKER_HUB_AUTH = get_docker_hub_auth

Vagrant.configure('2') do |config|
  config.vm.box = 'ubuntu-20.04-amd64'

  config.vm.provider :libvirt do |lv, config|
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    #lv.nested = true
    lv.memory = 2*1024
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs', nfs_version: '4.2', nfs_udp: false
  end

  config.vm.define :pandora do |config|
    config.vm.provider :libvirt do |lv|
      lv.cpus = 4
      lv.memory = 4*1024
    end
    config.vm.hostname = CONFIG_PANDORA_FQDN
    if CONFIG_PANDORA_BRIDGE_NAME
      config.vm.network :public_network,
        dev: CONFIG_PANDORA_BRIDGE_NAME,
        mode: 'bridge',
        type: 'bridge',
        ip: CONFIG_PANDORA_IP
    else
      config.vm.network :private_network,
        ip: CONFIG_PANDORA_IP,
        libvirt__dhcp_enabled: false,
        libvirt__forward_mode: 'none'
    end
    config.vm.provision :shell, path: 'provision-base.sh'
    config.vm.provision :shell, path: 'provision-chrony.sh'
    config.vm.provision :shell, path: 'provision-iptables.sh'
    config.vm.provision :shell, path: 'provision-docker.sh'
    config.vm.provision :shell, path: 'provision-docker-hub-auth.sh', env: {'DOCKER_HUB_AUTH' => DOCKER_HUB_AUTH} if DOCKER_HUB_AUTH
    config.vm.provision :shell, path: 'provision-registry.sh'
    config.vm.provision :shell, path: 'provision-crane.sh'
    config.vm.provision :shell, path: 'provision-meshcommander.sh'
    config.vm.provision :shell, path: 'provision-pdns.sh', args: [CONFIG_PANDORA_IP]
    config.vm.provision :shell, path: 'provision-dnsmasq.sh', args: [CONFIG_PANDORA_IP, CONFIG_PANDORA_DHCP_RANGE, CONFIG_CONTROL_PLANE_VIP]
    config.vm.provision :shell, path: 'provision-matchbox.sh'
    config.vm.provision :shell, path: 'provision-ipxe.sh'
    config.vm.provision :shell, path: 'provision-rescue.sh'
    config.vm.provision :shell, path: 'provision-loki.sh'
    config.vm.provision :shell, path: 'provision-vector.sh'
    config.vm.provision :shell, path: 'provision-grafana.sh'
    config.vm.provision :shell, path: 'provision-machinator.sh'
    config.vm.provision :shell, path: 'provision-kubectl.sh', args: [CONFIG_KUBECTL_VERSION]
    config.vm.provision :shell, path: 'provision-helm.sh', args: [CONFIG_HELM_VERSION]
    config.vm.provision :shell, path: 'provision-k9s.sh', args: [CONFIG_K9S_VERSION]
    config.vm.provision :shell, path: 'provision-talos-poke.sh'
    config.vm.provision :shell, path: 'provision-talos.sh', args: [CONFIG_TALOS_VERSION, CONFIG_KUBERNETES_VERSION, CONFIG_CONTROL_PLANE_VIP]
    config.vm.provision :shell, path: 'provision-theila.sh', args: [CONFIG_THEILA_VERSION]
  end

  virtual_machines.each do |name, arch, firmware, ip, mac, bmc_type, bmc_ip, bmc_port, bmc_qmp_port|
    config.vm.define name do |config|
      config.vm.box = nil
      config.vm.provider :libvirt do |lv, config|
        lv.loader = '/usr/share/ovmf/OVMF.fd' if firmware == 'uefi'
        lv.boot 'hd'
        lv.boot 'network'
        lv.storage :file, :size => '40G'
        if CONFIG_PANDORA_BRIDGE_NAME
          config.vm.network :public_network,
            dev: CONFIG_PANDORA_BRIDGE_NAME,
            mode: 'bridge',
            type: 'bridge',
            mac: mac,
            ip: ip,
            auto_config: false
        else
          config.vm.network :private_network,
            mac: mac,
            ip: ip,
            auto_config: false
        end
        lv.mgmt_attach = false
        lv.graphics_type = 'spice'
        lv.video_type = 'virtio'
        # set some BIOS settings that will help us identify this particular machine.
        #
        #   QEMU                | Linux
        #   --------------------+----------------------------------------------
        #   type=1,manufacturer | /sys/devices/virtual/dmi/id/sys_vendor
        #   type=1,product      | /sys/devices/virtual/dmi/id/product_name
        #   type=1,version      | /sys/devices/virtual/dmi/id/product_version
        #   type=1,serial       | /sys/devices/virtual/dmi/id/product_serial
        #   type=1,sku          | dmidecode
        #   type=1,uuid         | /sys/devices/virtual/dmi/id/product_uuid
        #   type=3,manufacturer | /sys/devices/virtual/dmi/id/chassis_vendor
        #   type=3,family       | /sys/devices/virtual/dmi/id/chassis_type
        #   type=3,version      | /sys/devices/virtual/dmi/id/chassis_version
        #   type=3,serial       | /sys/devices/virtual/dmi/id/chassis_serial
        #   type=3,asset        | /sys/devices/virtual/dmi/id/chassis_asset_tag
        [
          'type=1,manufacturer=your vendor name here',
          'type=1,product=your product name here',
          'type=1,version=your product version here',
          'type=1,serial=your product serial number here',
          'type=1,sku=your product SKU here',
          "type=1,uuid=00000000-0000-4000-8000-#{mac.tr(':', '')}",
          'type=3,manufacturer=your chassis vendor name here',
          #'type=3,family=1', # TODO why this does not work on qemu from ubuntu 18.04?
          'type=3,version=your chassis version here',
          'type=3,serial=your chassis serial number here',
          "type=3,asset=your chassis asset tag here #{name}",
        ].each do |value|
          lv.qemuargs :value => '-smbios'
          lv.qemuargs :value => value
        end
        # expose the VM QMP socket.
        # see https://gist.github.com/rgl/dc38c6875a53469fdebb2e9c0a220c6c
        lv.qemuargs :value => '-qmp'
        lv.qemuargs :value => "tcp:#{bmc_ip}:#{bmc_qmp_port},server,nowait"
        config.vm.synced_folder '.', '/vagrant', disabled: true
        config.trigger.after :up do |trigger|
          trigger.ruby do |env, machine|
            vbmc_up(machine, bmc_type, bmc_ip, bmc_port)
          end
        end
        config.trigger.after :destroy do |trigger|
          trigger.ruby do |env, machine|
            vbmc_destroy(machine, bmc_type)
          end
        end
      end
    end
  end
end

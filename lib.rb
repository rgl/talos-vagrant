require 'open3'

def virtual_machines
  save_config
  save_virtual_machines_config
  machines = JSON.load(File.read('shared/machines.json')).select{|m| m['type'] == 'virtual'}
  machines.each_with_index.map do |m, i|
    [m['name'], m['arch'], m['firmware'], m['ip'], m['mac'], m['bmcType'], m['bmcIp'], m['bmcPort'], m['bmcQmpPort']]
  end
end

def save_config
  FileUtils.mkdir_p 'shared'
  File.write('shared/config.json', {
    'CONFIG_PANDORA_IP': CONFIG_PANDORA_IP,
    'CONFIG_CONTROL_PLANE_VIP': CONFIG_CONTROL_PLANE_VIP,
    'CONFIG_PANDORA_LOAD_BALANCER_RANGE': CONFIG_PANDORA_LOAD_BALANCER_RANGE,
    'CONFIG_METALLB_CHART_VERSION': CONFIG_METALLB_CHART_VERSION,
    'CONFIG_EXTERNAL_DNS_CHART_VERSION': CONFIG_EXTERNAL_DNS_CHART_VERSION,
    'CONFIG_CERT_MANAGER_CHART_VERSION': CONFIG_CERT_MANAGER_CHART_VERSION,
    'CONFIG_TRAEFIK_CHART_VERSION': CONFIG_TRAEFIK_CHART_VERSION,
    'CONFIG_KUBERNETES_DASHBOARD_CHART_VERSION': CONFIG_KUBERNETES_DASHBOARD_CHART_VERSION,
  }.to_json)
end

def save_virtual_machines_config
  stdout, stderr, status = Open3.capture3('python3', 'machines.py', 'get-machines-json')
  if status.exitstatus != 0
    raise "failed to run python3 machines.py get-machines-json. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  FileUtils.mkdir_p 'shared'
  File.write('shared/machines.json', stdout)
end

def vbmc_domain_name(machine)
  "#{File.basename(File.dirname(__FILE__))}_#{machine.name}"
end

def vbmc_container_name(machine, bmc_type)
  "vbmc-emulator-#{bmc_type}-#{vbmc_domain_name(machine)}"
end

def vbmc_up(machine, bmc_type, bmc_ip, bmc_port)
  case bmc_type
  when 'redfish'
    vbmc_up_redfish(machine, bmc_type, bmc_ip, bmc_port)
  when 'ipmi'
    vbmc_up_ipmi(machine, bmc_type, bmc_ip, bmc_port)
  end
end

def vbmc_up_redfish(machine, bmc_type, bmc_ip, bmc_port)
  vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  machine.ui.info("Creating the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3(
    'docker',
    'run',
    '--rm',
    '--name',
    container_name,
    '--detach',
    '-v',
    '/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock',
    '-v',
    '/var/run/libvirt/libvirt-sock-ro:/var/run/libvirt/libvirt-sock-ro',
    '-e',
    "SUSHY_EMULATOR_ALLOWED_INSTANCES=#{machine.id}",
    '-p',
    "#{bmc_ip}:#{bmc_port}:8000/tcp",
    'ruilopes/sushy-vbmc-emulator')
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to run the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
end

def vbmc_up_ipmi(machine, bmc_type, bmc_ip, bmc_port)
  vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  machine.ui.info("Creating the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3(
    'docker',
    'run',
    '--rm',
    '--name',
    container_name,
    '--detach',
    '-v',
    '/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock',
    '-v',
    '/var/run/libvirt/libvirt-sock-ro:/var/run/libvirt/libvirt-sock-ro',
    '-e',
    "VBMC_EMULATOR_DOMAIN_NAME=#{vbmc_domain_name(machine)}",
    '-e',
    "VBMC_EMULATOR_USERNAME=admin",
    '-e',
    "VBMC_EMULATOR_PASSWORD=password",
    '-p',
    "#{bmc_ip}:#{bmc_port}:6230/udp",
    'ruilopes/vbmc-emulator')
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to run the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
end

def vbmc_destroy(machine, bmc_type)
  container_name = vbmc_container_name(machine, bmc_type)
  stdout, stderr, status = Open3.capture3('docker', 'inspect', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such object'
      return
    end
    raise "failed to inspect the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  machine.ui.info("Destroying the #{container_name} docker container...")
  stdout, stderr, status = Open3.capture3('docker', 'kill', '--signal', 'INT', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to kill the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  stdout, stderr, status = Open3.capture3('docker', 'wait', container_name)
  if status.exitstatus != 0
    if stderr.include? 'No such container'
      return
    end
    raise "failed to wait for the #{container_name} docker container. status=#{status.exitstatus} stdout=#{stdout} stderr=#{stderr}"
  end
  return
end

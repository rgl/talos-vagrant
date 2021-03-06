#!/bin/bash
source /vagrant/lib.sh


pandora_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"
dns_domain="$(hostname --domain)"
control_plane_fqdn="cp.$dns_domain"
control_plane_vip="$(jq -r .CONFIG_CONTROL_PLANE_VIP /vagrant/shared/config.json)"


#
# bootstrap etcd.
# see https://www.talos.dev/v1.0/bare-metal-platforms/matchbox/#bootstrap-etcd

control_plane_ips="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.role == "controlplane") | .ip')"
first_control_plane_ip="$(echo "$control_plane_ips" | head -1)"

title 'Adding the first control plane endpoint to the talosctl local configuration'
rm -rf ~/.talos/* /vagrant/shared/kubeconfig
install -d -m 700 ~/.talos
install -m 600 /vagrant/shared/talosconfig ~/.talos/config
talosctl config endpoints $first_control_plane_ip
talosctl config nodes $first_control_plane_ip

title 'Waiting for kubelet to be ready'
while [ -z "$(talosctl service kubelet status 2>/dev/null | grep -E '^HEALTH\s+OK$')" ]; do sleep 3; done

title 'Bootstrapping etcd'
talosctl bootstrap

title 'Waiting for etcd to be ready'
while [ -z "$(talosctl service etcd status 2>/dev/null | grep -E '^HEALTH\s+OK$')" ]; do sleep 3; done

title 'Downloading Kubernetes config to ~/.kube/config'
rm -rf ~/.kube/*
talosctl kubeconfig
chmod 600 ~/.kube/config
rm -rf /home/vagrant/.kube
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.kube
install -m 600 -o vagrant -g vagrant ~/.kube/config /home/vagrant/.kube/config

title 'Waiting for Kubernetes to be ready'
# wait for the api server to be ready.
while ! kubectl get ns >/dev/null 2>&1; do sleep 3; done
# wait for all the deployments to be rolled out.
kubectl get deployments --all-namespaces -o json | jq -r '.items[].metadata | [.namespace,.name] | @tsv' | while read ns deployment_name; do
    kubectl -n "$ns" rollout status deployment "$deployment_name"
done

title 'Waiting for nodes to be ready'
cat /vagrant/shared/machines.json | jq -r '.[] | select(.type == "virtual") | .name' | while read name; do
    echo "Waiting for node $name to be ready..."
    while [ -z "$(kubectl get node "$name" 2>/dev/null | grep -E '\s+Ready\s+')" ]; do sleep 3; done
done

title 'Reconfiguring the Kubernetes control plane endpoint DNS A RR to the VIP'
# see https://doc.powerdns.com/authoritative/http-api
# see https://doc.powerdns.com/md/httpapi/api_spec/
http \
    --print '' \
    PATCH \
    http://$pandora_ip_address:8081/api/v1/servers/localhost/zones/$dns_domain \
    X-API-Key:vagrant \
    rrsets:="$(cat <<EOF
[
    {
        "name": "cp.$dns_domain.",
        "type": "A",
        "changetype": "REPLACE",
        "ttl": 0,
        "records": [
            {
                "content": "$control_plane_vip",
                "disabled": false
            }
        ]
    }
]
EOF
)"
dig $control_plane_fqdn

title 'Adding all the control plane endpoints to the talosctl local configuration'
talosctl config endpoints $control_plane_ips
talosctl config nodes # NB this makes sure there are no default nodes.
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.talos
install -m 600 -o vagrant -g vagrant ~/.talos/config /home/vagrant/.talos/config
cp ~/.talos/config /vagrant/shared/talosconfig

title 'Copying Kubernetes config to the host'
control_plane_vip="$(dig +short $control_plane_fqdn)"
sed "s,$control_plane_fqdn,$control_plane_vip,g" ~/.kube/config >/vagrant/shared/kubeconfig


#
# deploy helm charts.

function get-config-value {
    jq -r ".$1" /vagrant/shared/config.json
}
bash /vagrant/provision-chart-metallb.sh \
    "$(get-config-value CONFIG_METALLB_CHART_VERSION)" \
    "$(get-config-value CONFIG_PANDORA_LOAD_BALANCER_RANGE)"
bash /vagrant/provision-chart-external-dns.sh \
    "$(get-config-value CONFIG_EXTERNAL_DNS_CHART_VERSION)"
bash /vagrant/provision-chart-cert-manager.sh \
    "$(get-config-value CONFIG_CERT_MANAGER_CHART_VERSION)"
bash /vagrant/provision-chart-traefik.sh \
    "$(get-config-value CONFIG_TRAEFIK_CHART_VERSION)"
bash /vagrant/provision-chart-kubernetes-dashboard.sh \
    "$(get-config-value CONFIG_KUBERNETES_DASHBOARD_CHART_VERSION)"


#
# show information about talos.

title 'Talos version'
talosctl -n $first_control_plane_ip version

title 'Talos os-release file'
talosctl -n $first_control_plane_ip read /etc/os-release

title 'Talos resolv.conf file'
talosctl -n $first_control_plane_ip read /etc/resolv.conf

title 'Talos hosts file'
talosctl -n $first_control_plane_ip read /etc/hosts

title 'Talos disks'
talosctl -n $first_control_plane_ip disks

title 'Talos etcd members'
talosctl -n $first_control_plane_ip etcd members

title 'Talos services'
talosctl -n $first_control_plane_ip services

title 'Talos containers'
talosctl -n $first_control_plane_ip containers

title 'Talos k8s.io containers'
talosctl -n $first_control_plane_ip containers -k


#
# show information about kubernetes.

title 'Kubernetes version'
kubectl version --short

title 'Kubernetes cluster'
kubectl cluster-info

title 'Kubernetes nodes'
kubectl get nodes -o wide

title 'Kubernetes API versions'
kubectl api-versions

title 'Kubernetes API resources'
kubectl api-resources -o wide

title 'Kubernetes resources'
kubectl get all --all-namespaces

title 'Kubernetes running pods container images'
kubectl get pods --all-namespaces -o jsonpath='{.items[*].spec.containers[*].image}' \
    | tr -s '[[:space:]]' '\n' \
    | sort \
    | uniq


#
# show the environment summary.

bash /vagrant/summary.sh

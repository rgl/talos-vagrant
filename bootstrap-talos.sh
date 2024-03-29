#!/bin/bash
source /vagrant/lib.sh


pandora_ip_address="$(jq -r .CONFIG_PANDORA_IP /vagrant/shared/config.json)"
dns_domain="$(hostname --domain)"
control_plane_fqdn="cp.$dns_domain"
control_plane_vip="$(jq -r .CONFIG_CONTROL_PLANE_VIP /vagrant/shared/config.json)"


#
# bootstrap etcd.
# see https://www.talos.dev/v1.4/talos-guides/install/bare-metal-platforms/matchbox/#bootstrap-etcd

control_plane_ips="$(cat /vagrant/shared/machines.json | jq -r '.[] | select(.role == "controlplane") | .ip')"
first_control_plane_ip="$(echo "$control_plane_ips" | head -1)"

function set-control-plane-dns-rr {
    local ip_address="$1"
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
        "name": "$control_plane_fqdn.",
        "type": "A",
        "changetype": "REPLACE",
        "ttl": 0,
        "records": [
            {
                "content": "$ip_address",
                "disabled": false
            }
        ]
    }
]
EOF
)"
    title "Waiting for DNS $control_plane_fqdn to resolve to $ip_address"
    while [ "$(dig +short $control_plane_fqdn 2>/dev/null)" != "$ip_address" ]; do sleep 3; done
    dig $control_plane_fqdn
}

# ensure the k8s control plane DNS RR points to the talos managed VIP.
set-control-plane-dns-rr $control_plane_vip

title 'Adding the first control plane endpoint to the talosctl local configuration'
rm -rf ~/.talos/* /vagrant/shared/kubeconfig
install -d -m 700 ~/.talos
install -m 600 /vagrant/shared/talosconfig ~/.talos/config
talosctl config endpoints $first_control_plane_ip
talosctl config nodes $first_control_plane_ip

title 'Bootstrapping talos'
t=$SECONDS
while ! talosctl bootstrap; do sleep 10; done
echo "talos is bootstrapped (took $(($SECONDS - t))s)!"

title 'Waiting for talos to be healthy'
t=$SECONDS
controllers="$(jq -r '.[] | select(.type == "virtual" and .role == "controlplane") | .ip' /vagrant/shared/machines.json | tr '\n' ',' | sed 's/,$/\n/')"
workers="$(jq -r '.[] | select(.type == "virtual" and .role == "worker") | .ip' /vagrant/shared/machines.json | tr '\n' ',' | sed 's/,$/\n/')"
talosctl -n $first_control_plane_ip \
    health \
    --control-plane-nodes $controllers \
    --worker-nodes $workers
echo "healthy in $(($SECONDS - t))s"

title 'Downloading Kubernetes config to ~/.kube/config'
rm -rf ~/.kube/*
talosctl kubeconfig
chmod 600 ~/.kube/config
rm -rf /home/vagrant/.kube
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.kube
install -m 600 -o vagrant -g vagrant ~/.kube/config /home/vagrant/.kube/config

title 'Adding all the control plane endpoints to the talosctl local configuration'
talosctl config endpoints $control_plane_ips
talosctl config nodes # NB this makes sure there are no default nodes.
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.talos
install -m 600 -o vagrant -g vagrant ~/.talos/config /home/vagrant/.talos/config
cp ~/.talos/config /vagrant/shared/talosconfig

title 'Copying Kubernetes config to the host'
sed "s,$control_plane_fqdn,$control_plane_vip,g" ~/.kube/config >/vagrant/shared/kubeconfig

title 'Downloading etcd credentials to /etc/talos/etcd'
rm -rf /etc/talos/etcd
install -m 700 -d /etc/talos/etcd
# TODO instead of using the kube-apiserver credentials, create new ones?
talosctl -n $first_control_plane_ip read /system/secrets/etcd/ca.crt >/etc/talos/etcd/ca.crt
talosctl -n $first_control_plane_ip read /system/secrets/kubernetes/kube-apiserver/etcd-client.crt >/etc/talos/etcd/client.crt
talosctl -n $first_control_plane_ip read /system/secrets/kubernetes/kube-apiserver/etcd-client.key >/etc/talos/etcd/client.key
ETCDCTL_ENDPOINTS="$(echo $controllers | tr ',' '\n' | while read ip; do echo "https://$ip:2379"; done | tr '\n' ',' | sed -E 's/,$//')"
cat >/etc/profile.d/etcdctl.sh <<STDIN
export ETCDCTL_CACERT=/etc/talos/etcd/ca.crt
export ETCDCTL_CERT=/etc/talos/etcd/client.crt
export ETCDCTL_KEY=/etc/talos/etcd/client.key
export ETCDCTL_ENDPOINTS="$ETCDCTL_ENDPOINTS"
STDIN
source /etc/profile.d/etcdctl.sh


#
# deploy helm charts.

function get-config-value {
    jq -r ".$1" /vagrant/shared/config.json
}

title 'Provisioning vector'
bash /vagrant/provision-chart-vector.sh \
    "$(get-config-value CONFIG_VECTOR_CHART_VERSION)" \
    "$pandora_ip_address"

title 'Provisioning metallb'
bash /vagrant/provision-chart-metallb.sh \
    "$(get-config-value CONFIG_METALLB_CHART_VERSION)" \
    "$(get-config-value CONFIG_PANDORA_LOAD_BALANCER_RANGE)"

title 'Provisioning external-dns'
bash /vagrant/provision-chart-external-dns.sh \
    "$(get-config-value CONFIG_EXTERNAL_DNS_CHART_VERSION)"

title 'Provisioning cert-manager'
bash /vagrant/provision-chart-cert-manager.sh \
    "$(get-config-value CONFIG_CERT_MANAGER_CHART_VERSION)"

title 'Provisioning traefik'
bash /vagrant/provision-chart-traefik.sh \
    "$(get-config-value CONFIG_TRAEFIK_CHART_VERSION)"

title 'Provisioning kubernetes-dashboard'
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
etcdctl --write-out table member list
etcdctl --write-out table endpoint status

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
# show information about the container images.

title 'Bootstrap container images'
cat /vagrant/shared/talos-images.txt

title 'Current container images'
(
    talos-poke cp1 images
    talos-poke w1 images
) \
    | grep -v -E '/talos-poke:' \
    | grep -E '.+?/.+:.+' \
    | sort --uniq \
    >/vagrant/shared/images.txt
cat /vagrant/shared/images.txt

title 'Difference'
diff -u /vagrant/shared/talos-images.txt /vagrant/shared/images.txt || true


#
# show the environment summary.

bash /vagrant/summary.sh

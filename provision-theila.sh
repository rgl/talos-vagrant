#!/bin/bash
source /vagrant/lib.sh


theila_version="${1:-0.2.1}"; shift || true


# download.
wget -qO /usr/local/bin/theila "https://github.com/siderolabs/theila/releases/download/v$theila_version/theila-$(uname -s | tr "[:upper:]" "[:lower:]")-amd64"
chmod +x /usr/local/bin/theila

# create and enable the systemd service unit.
# TODO run as non-root user and somehow generate proper talos/k8s credentials for theila.
cat >/etc/systemd/system/theila.service <<'EOF'
[Unit]
Description=theila
After=network.target

[Service]
Type=simple
Environment=HOME=/root
WorkingDirectory=/root
ExecStart=/usr/local/bin/theila \
    --address 0.0.0.0 \
    --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable theila
systemctl start theila

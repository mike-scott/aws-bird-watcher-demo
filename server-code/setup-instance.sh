#!/bin/bash

set -ex

cd /srv
wget https://dl.grafana.com/enterprise/release/grafana-enterprise-7.3.6.linux-amd64.tar.gz
tar -zxvf grafana-enterprise-7.3.6.linux-amd64.tar.gz

cd grafana-7.3.6
./bin/grafana-cli plugins install grafana-timestream-datasource
mkdir -p data/plugins
mv /var/lib/grafana/plugins/grafana-timestream-datasource ./data/plugins/

cat >/etc/systemd/system/grafana.service <<EOF
[Unit]
Description=grafana
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=1
WorkingDirectory=/srv/grafana-7.3.6
ExecStart=/srv/grafana-7.3.6/bin/grafana-server web

[Install]
WantedBy=multi-user.target
EOF

systemctl start grafana

## Dynamic update of DNS with DHCP lease info between dual redundant pihole servers
### https://discourse.pi-hole.net/t/dynamic-update-of-dns-with-dhcp-lease-info-between-dual-redundant-pihole-servers/65027
function service_SyncDHCP_lease {
    cp -f ./SyncDHCP.sh /usr/bin/SyncDHCP.sh

    cat << EOF | sudo tee -i /lib/systemd/system/SyncDHCP.service
[Unit]
Description=Updates DHCP DNS between two pihole servers
After=network.target

[Service]
ExecStart=/usr/bin/SyncDHCP.sh Start
ExecStop=/usr/bin/SyncDHCP.sh Stop
ExecRestart=/usr/bin/SyncDHCP.sh Restart

[Install]
WantedBy=multi-user.target
EOF
}

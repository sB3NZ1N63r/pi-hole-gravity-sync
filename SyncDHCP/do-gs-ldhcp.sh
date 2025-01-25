#!/usr/bin/env bash
# shellcheck shell=bash

## required dependetis
### inotify-tools
#apt install -y inotify-tools

Flag="/tmp/SyncDHCP.running"
#Src="/etc/pihole/dhcp.leases"
Src="/etc/pihole/dhcp.leases.gsb"

function Msg {
	printf "%s - %s\n" $(date +%u%m%d%H%M%S) "$*"
}

## Adds option to delay replying to DHCP packets by one or more seconds.
### https://lists.thekelleys.org.uk/pipermail/dnsmasq-discuss/2017q1/011317.html
function set_gs_dhcp_reply_delay {
	echo "dhcp-reply-delay=2" >> /etc/dnsmasq.d/99-gs-lease-dhcp.conf
}

function set_gs_dhcp_script {
	### The arguments to the process are "add", "old" or "del"
	echo "dhcp-script=/etc/gravity-sync/___.sh" >> /etc/dnsmasq.d/99-gs-lease-dhcp.conf

	### Use the specified file to store DHCP lease information.
	#dhcp-leasefile
}

function Stop {
	Msg "Stopping SyncDHCP service..."
	rm -f $Flag
	proc=$(ps -aux | awk '/inotifywait.*dhcp\.leases/{print $2}')
	[ -n "$proc" ] && kill -HUP $proc
	
	# Wait for filesystem cleanup
	sleep 3
}

function Start {
	Msg "Starting SyncDHCP service..."
	Dst=$(mktemp)
	Tmp=$(mktemp)

	echo "Dst=$Dst"
	echo "Tmp=$Tmp"
	set_gs_dhcp_reply_delay
	
	# Modify these target names to conform to your deployment
	if [ $(hostname) == "pi-hole-01" ]; then
		Target=pi-hole-02
	else
		Target=pi-hole-01
	fi

	# Create the "run flag file"
	touch $Flag
	while [ -e $Flag ]; do
		inotifywait -e modify $Src | \
		while read -r f a; do
			size=$(cksum $Src | awk '{print $2}')
			if [ "$size" -ne 0 ]; then
				awk '$4!="*"{printf "%s %s\n",$3,$4}' $Src | sort -k3 > $Tmp
				if ! cmp -s $Dst $Tmp; then
					diff $Dst $Tmp | awk '$1~/<|>/{
						if ($1~/</)printf "released %s %s\n",$2,$3;
						if ($1~/>/)printf "assigned %s %s\n",$2,$3;
					}'

					#scp $Tmp root@$Target:/etc/pihole/custom.list > /dev/null && \
					#ssh root@$Target "chmod 744 /etc/pihole/custom.list;pihole restartdns reload" && \
					
					cp $Tmp $Dst && \
					Msg "Updated custom.list on $Target"
				fi
			fi
		done
	done
	
	rm -f $Dst
	rm -f $Tmp
}

function Restart {
	Stop
	Start
}

case "$1" in
	Start) Start;;
	Stop) Stop;;
	Restart) Restart;;
	Status) systemctl status SyncDHCP.service;;
	*) echo "Usage: $0 {Start|Stop|Restart|Status}";;
esac

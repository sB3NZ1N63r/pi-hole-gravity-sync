#!/usr/bin/env bash
# shellcheck shell=bash


#GS_CU_LIST="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/custom.list"
GS_CU_LIST="/var/log/gs-custom.list"
#SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#GS_DHCP_SCRIPT_LOG="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/gs-dhcp-script.log"
GS_DHCP_SCRIPT_LOG="/var/log/gs-dhcp-script.log"

### https://stackoverflow.com/questions/20572934/get-the-name-of-the-caller-script-in-bash-script
### http://pubs.opengroup.org/onlinepubs/009604499/utilities/ps.html
PARENT_COMMAND=$(ps -o comm= $PPID)
PARENT_COMMAND_ARGS=$(ps -o args= $PPID)

ARG_TRIG="$1"
MAC_ADDR="$2"
IP_ADDR="$3"
HOST_NAME="$4"

HANDLE_NON=0
HANDLE_ADD=1
HANDLE_OLD=2
HANDLE_DEL=3

LINE_EXISTS=0

function Msg {
	printf "%s - %s\n" $(date +%u%m%d%H%M%S) "$*" | tee -a "$GS_DHCP_SCRIPT_LOG"
}

## "/etc/pihole/dhcp.leases"
### 1711184732 bc:17:b8:bd:8d:5a 192.168.178.59 GSU-NB-FD035044 01:bc:17:b8:bd:8d:5a

## "/etc/pihole/custom.list"
### 192.168.178.251 pi-hole-01.fritz.box

function get_custom {
	# read 'custom.list'
	lines_arr=()
	line_exist=0
	update_list=1
	while read line; do
		line_arr=()
		IFS=' ' read -r -a line_arr <<< "$line"

		if [ "${line_arr[0]}" == "$IP_ADDR" ]; then
			if [ $line_handle -eq $HANDLE_DEL ]; then
				line=""
				#update_list=1
			elif [ "${line_arr[1]}" == "$HOST_NAME" ]; then
				line_exist=1
				update_list=0
				#break
			else
				if [ "$HOST_NAME" == "" ]; then
					Msg "Warning, empty name: IP_ADDR=$IP_ADDR, HOST_NAME=EMPTY"
				fi
				line="$IP_ADDR $HOST_NAME"
				#update_list=1
			fi
		fi

		lines_arr+=("$line")
	done < "$GS_CU_LIST"

	result=$?
	Msg "Debug: while GS_CU_LIST result=$result"
}

function update_gs_custom {
	result=""
	Msg "Info: PARENT_COMMAND=$PARENT_COMMAND"
	Msg "Info: PARENT_COMMAND_ARGS=$PARENT_COMMAND_ARGS"

	line_handle=$HANDLE_NON
	message="dhcp.lease: MAC=$MAC_ADDR, IP=$IP_ADDR, NAME=$HOST_NAME"
	if [ "$ARG_TRIG" == "add" ]; then
		Msg "adding $message"
		get_custom
		line_handle=$HANDLE_ADD
	elif [ "$ARG_TRIG" == "old" ]; then
		Msg "checking $message"
		line_handle=$HANDLE_OLD
	elif [ "$ARG_TRIG" == "del" ]; then
		Msg "deleting $message"
		line_handle=$HANDLE_DEL
	else
		Msg "Error: ARG_TRIG=$ARG_TRIG"
		exit 1
	fi

	if [ "$IP_ADDR" == "" ]; then
		Msg "Error: IP_ADDR=$IP_ADDR"
		exit 1
	fi

	

	Msg "Debug: update_list=$update_list, GS_CU_LIST=$GS_CU_LIST"
	if [ $update_list -eq 1 ]; then
		if [ $line_handle -eq $HANDLE_OLD ]; then
			Msg "Warning, must be exist: IP_ADDR=$IP_ADDR, HOST_NAME=$HOST_NAME"
		fi
		
		if [ $line_handle -eq $HANDLE_ADD ]; then
			lines_arr+=("$IP_ADDR $HOST_NAME")
		fi

		echo "" > "$GS_CU_LIST"
		result=$?
		Msg "Debug: echo GS_CU_LIST result=$result"

		for line in "${lines_arr[@]}"; do
			if [ "$line" == "" ]; then
				continue
			fi
			echo "$line" >> "$GS_CU_LIST"
		done
	fi
}

function set_gs_dhcp_script {
	### The arguments to the process are "add", "old" or "del"
	echo "dhcp-script=/etc/gravity-sync/gs-dhcp-script.sh" >> /etc/dnsmasq.d/100-gs-lease-dhcp.conf

	###
	chmod 775 "/etc/gravity-sync/gs-dhcp-script.sh"

	###
	/usr/local/bin/pihole restartdns


	### restart dnsmasq server
	/etc/init.d/dnsmasq restart


	### basic syntax checks on the config files
	dnsmasq --test

	### will print errors to the terminal if you run it directly
	dnsmasq --no-daemon --log-queries=extra --log-dhcp --log-debug -C /path/to/dnsmasq.conf

	### Use the specified file to store DHCP lease information.
	#dhcp-leasefile
}


# MAIN

if [ ! -f "$GS_DHCP_SCRIPT_LOG" ]; then
    touch "$GS_DHCP_SCRIPT_LOG"
fi

if [ ! -f "$GS_CU_LIST" ]; then
    Msg "Error, does not exist: GS_CU_LIST=$GS_CU_LIST"
	exit 1
fi

# The arguments to the process are "add", "old" or "del", the MAC address of the host, the IP address, and the hostname, if known.

case "$ARG_TRIG" in
	add) update_gs_custom;; # "add" means a lease has been created
	old) update_gs_custom;; # "old" is a notification of an existing lease when dnsmasq starts or a change to MAC address or hostname of an existing lease
	del) update_gs_custom;; # "del" means it has been destroyed
	*) echo "Usage: $0 {add|old|del}";;
esac

exit 0

#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

# TO DO : auto detect NIC
WAN_INTERFACE=wlp2s0
LAN_INTERFACE=enp1s0f1

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo -e "${ORANGE}You need to run this script as ${RED}root"
		exit 1
	fi
}

function assignIp() {
	# Check OS version
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}"

    # debian or raspbian
		if [[ ${ID} == "debian" || ${ID} == "raspbian" || ${ID} == "parrot" ]]; then
			if [[ ${VERSION_ID} -lt 10 ]]; then
				echo -e "Your OS version ${RED}(${VERSION_ID}) is not supported. Please \
          use at least Debian 10 Buster"
				exit 1
      else
        # assign ip to /etc/network/interfaces
				echo -e "
					# The primary network interface
					allow-hotplug ${LAN_INTERFACE}
					auto ${LAN_INTERFACE}
					iface ${LAN_INTERFACE} inet static
					address 192.168.220.1
					netmask 255.255.255.0 " >> /etc/network/interfaces.d/${LAN_INTERFACE}

					systemctl restart networking.service
      fi

    # ubuntu
	elif [[ "${ID}" -eq "ubuntu" ]]; then
	      if [[ $(sed "s/\.[0-9]\+//g" <<< "$VERSION_ID") -lt 20 ]]; then
	        echo -e "Your OS version ${RED}(${VERSION_ID}) is not supported. Please \
	          use Debian 10 Buster"
	        exit 1
	      else
					systemctl stop systemd-resolved
echo "network:
  version: 2
  renderer: networkd
  ethernets:
    ens3:
      dhcp4: no
      addresses:
        - 192.168.121.221/24
      gateway4: 192.168.121.1
      nameservers:
          addresses: [8.8.8.8, 1.1.1.1]" > /etc/netplan/01-netcfg.yaml

					netplan apply

					# isPermanent
					if [[ $1 ]]; then
						systemctl disable systemd-resolved
					fi

	      fi
		else
			echo -e "${RED}Looks like you aren't running this installer on a Debian, Ubuntu, \
	      or raspbian Linux system"
			exit 1
    fi

	fi
}

# install dnsmasq
function requirement() {
	dpkg -s dnsmasq > /dev/null 2>&1

	if [ $? != 0 ]; then
	  apt install dnsmasq -y
	else
		echo -e "${ORANGE}dnsmasq is already installed"
	fi

	# dnsmasq conf
	mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig

	LISTEN_ADDRESS=192.168.220.1
	DNS_SERVER=1.1.1.1
	DHCP_RANGE=192.168.220.50,192.168.220.150,12h

	echo -e "interface=${LAN_INTERFACE}       # Use interface eth0
	      listen-address=${LISTEN_ADDRESS}    # Specify the address to listen on
	      bind-interfaces                     # Bind to the interface
	      server=${DNS_SERVER}                # Use Google DNS
	      domain-needed                       # Don't forward short names
	      bogus-priv                          # Drop the non-routed address spaces.
	      dhcp-range=${DHCP_RANGE}            # IP range and lease time
	      " > /etc/dnsmasq.conf
}

# enable ipv4 Forwarding
function ipForwarding() {
	if [[ $1 ]]; then
		if [[ $(grep "#net.ipv4.ip_forward=1" "/etc/sysctl.conf") ]]; then
		  sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' "/etc/sysctl.conf"
		fi
	fi

	# temporary ip forwarding
	sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
}


function firewallRules() {

	iptables -t nat -A POSTROUTING -o ${WAN_INTERFACE} -j MASQUERADE
	iptables -A FORWARD -i ${LAN_INTERFACE} -o ${WAN_INTERFACE} -j ACCEPT
	iptables -A FORWARD -i ${WAN_INTERFACE} -o ${LAN_INTERFACE} -m state \
	 --state RELATED,ESTABLISHED -j ACCEPT

	# save iptables rules
	if [[ $1 ]]; then
		sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

		# create systemd unit file to restore iptables rules
		if [[ ! -e /etc/systemd/system/restore-iptables-rules.service ]]; then
		  echo -e "[Unit]
		  Description=Restore iptables rules

		  [Service]
		  Type=simple
		  ExecStart=/bin/bash /home/ec2-user/reboot_message.sh

		  [Install]
		  WantedBy=multi-user.target" \
		    > /etc/systemd/system/restore-iptables-rules.service

		  chmod 644 /etc/systemd/system/restore-iptables-rules.service
		  systemctl enable restore-iptables-rules.service
		  systemctl start restore-iptables-rules.service
		fi

	fi
}

function uninstall() {
	apt autoremove --purge dnsmasq -y
	rm /etc/dnsmasq.conf.orig

	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}"

    # debian or raspbian
		if [[ ${ID} == "debian" || ${ID} == "raspbian" || ${ID} == "parrot" ]]; then
			if [[ -e /etc/network/interfaces.d/${LAN_INTERFACE}  ]]; then
				rm /etc/network/interfaces.d/${LAN_INTERFACE}
			fi
			systemctl restart networking.service
		fi

    # ubuntu
		if [[ "${ID}" -eq "ubuntu" ]]; then
	      systemctl start systemd-resolved
				systemctl enable systemd-resolved
				if [[ -e /etc/netplan/01-netcfg.yaml  ]]; then
					rm /etc/netplan/01-netcfg.yaml
				fi
				netplan apply
		fi
	fi

		sh -c "echo 0 > /proc/sys/net/ipv4/ip_forward"
		if [[ $(grep "net.ipv4.ip_forward=1" "/etc/sysctl.conf") ]]; then
			sed -i 's/net.ipv4.ip_forward=1/#net.ipv4.ip_forward=1/g' "/etc/sysctl.conf"
		fi

		iptables -t nat -D POSTROUTING -o ${WAN_INTERFACE} -j MASQUERADE
		iptables -D FORWARD -i ${WAN_INTERFACE} -o ${LAN_INTERFACE} -m state \
		 --state RELATED,ESTABLISHED -j ACCEPT
		 iptables -D FORWARD -i ${LAN_INTERFACE} -o ${WAN_INTERFACE} -j ACCEPT

		 if [[ -e /etc/iptables.ipv4.nat ]]; then
			rm /etc/iptables.ipv4.nat
		 fi

		 if [[ -e /etc/systemd/system/restore-iptables-rules.service ]]; then
			rm /etc/systemd/system/restore-iptables-rules.service
		 fi
}

function initialize() {
	isRoot
	assignIp $1
	requirement
	ipForwarding $1
	firewallRules $1
}


echo "	1 - Wifi to Ethernet bridge one-time
	2 - Wifi to Ethernet bridge permanent
	3 - Remove Wifi to Ethernet bridge"

read -p "Please choose a number : " USER_INPUT

case $USER_INPUT in
  1)
    initialize
    ;;

  2)
    initialize 1
    ;;

  3)
    uninstall
    ;;

  *)
    echo -n "Unknown number"
    ;;
esac

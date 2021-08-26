function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "You need to run this script as root"
		exit 1
	fi
}

function checkOS() {
	# Check OS version
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}"

    # debian or raspbian
		if [[ ${ID} == "debian" || ${ID} == "raspbian" ]]; then
			if [[ ${VERSION_ID} -lt 10 ]]; then
				echo "Your version of Debian (${VERSION_ID}) is not supported. Please \
          use Debian 10 Buster"
				exit 1
      else
        #/etc/network/interfaces
      fi

    # ubuntu
    elif [[ ${ID} == "debian" ]]; then
      if [[ ${VERSION_ID} -lt 20 ]]; then
        echo "Your version of Debian (${VERSION_ID}) is not supported. Please \
          use Debian 10 Buster"
        exit 1
      else
        # assign static ip in /etc/netplan/01-network-manager-all.yaml
      fi
    fi

	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, \
      or raspbian Linux system"
		exit 1
	fi
}

# if ubuntu
systemctl stop systemd-resolved


# install dnsmasq
dpkg -s dnsmasq
if [ $? != 0 ]; then
  apt install dnsmasq
fi


# dnsmasq conf
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
WAN_INTERFACE=wlan0
LAN_INTERFACE=eth0

LISTEN_ADDRESS=192.168.220.1
DNS_SERVER=1.1.1.1
DHCP_RANGE=192.168.220.50,192.168.220.150,12h

echo  "interface=${LAN_INTERFACE}         # Use interface eth0
      listen-address=${LISTEN_ADDRESS}    # Specify the address to listen on
      bind-interfaces                     # Bind to the interface
      server=${DNS_SERVER}                # Use Google DNS
      domain-needed                       # Don't forward short names
      bogus-priv                          # Drop the non-routed address spaces.
      dhcp-range=${DHCP_RANGE}            # IP range and lease time
      " > /etc/dnsmasq.conf

# enable ipv4 Forwarding
if [[ $(grep "#net.ipv4.ip_forward=1" "/etc/sysctl.conf") ]]; then
  sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' "/etc/sysctl.conf"
fi

# temporary ip forwarding
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# for debian and linux
sudo iptables -t nat -A POSTROUTING -o ${WAN_INTERFACE} -j MASQUERADE
sudo iptables -A FORWARD -i ${LAN_INTERFACE} -o ${WAN_INTERFACE} -j ACCEPT
sudo iptables -A FORWARD -i ${WAN_INTERFACE} -o ${LAN_INTERFACE} -m state \
  --state RELATED,ESTABLISHED -j ACCEPT

# save iptables rules
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# create systemd unit file to restore iptables rules
if [[ ! -e /etc/systemd/system/restore-iptables-rules.service ]]; then
  echo "[Unit]
  Description=Reboot message systemd service.

  [Service]
  Type=simple
  ExecStart=/bin/bash /home/ec2-user/reboot_message.sh

  [Install]
  WantedBy=multi-user.target" \
    > /etc/systemd/system/restore-iptables-rules.service

  chmod 644 /etc/systemd/system/reboot_message.service
  systemctl enable restore-iptables-rules.service
  systemctl start restore-iptables-rules.service
fi

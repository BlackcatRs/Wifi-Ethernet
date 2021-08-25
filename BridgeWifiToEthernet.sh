apt update

# if ubuntu
systemctl stop systemd-resolved


# install dnsmasq
dpkg -s dnsmasq
if [ $? != 0 ]; then
  apt install dnsmasq
fi


# dnsmasq conf
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
INTERFACE=eth0
LISTEN_ADDRESS=192.168.220.1
SERVER=1.1.1.1
DHCP_RANGE=192.168.220.50,192.168.220.150,12h

echo  "interface=${INTERFACE}             # Use interface eth0
      listen-address=${LISTEN_ADDRESS}    # Specify the address to listen on
      bind-interfaces                     # Bind to the interface
      server=${SERVER}                    # Use Google DNS
      domain-needed                       # Don't forward short names
      bogus-priv                          # Drop the non-routed address spaces.
      dhcp-range=${DHCP_RANGE}            # IP range and lease time
      " > /etc/dnsmasq.conf

#!/bin/bash

# Parse command line arguments for port
SNELL_PORT=${1:-6160}  # Default port is 6160 if not specified

echo "Installing Snell Server on port $SNELL_PORT..."

# Install dependencies based on the Linux distribution
if cat /etc/*-release | grep -q -E -i "debian|ubuntu|armbian|deepin|mint"; then
    apt-get install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "centos|red hat|redhat"; then
    yum install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "arch|manjaro"; then
    pacman -S wget dpkg unzip --noconfirm
elif cat /etc/*-release | grep -q -E -i "fedora"; then
    dnf install wget unzip dpkg -y
fi

# Enable BBR
# echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
# echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
# sysctl -p
# sysctl net.ipv4.tcp_available_congestion_control

# Download and install snell
cd
ARCH=$(uname -m)
BASE_URL="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux"
case $ARCH in
    "x86_64")
        PACKAGE="${BASE_URL}-amd64.zip"
        ;;
    "i686" | "i386")
        PACKAGE="${BASE_URL}-i386.zip"
        ;;
    "aarch64")
        PACKAGE="${BASE_URL}-aarch64.zip"
        ;;
    "armv7l")
        PACKAGE="${BASE_URL}-armv7l.zip"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
wget $PACKAGE

if [ $? -ne 0 ]; then
    echo "Download failed!"
    exit 1
fi
unzip -o ${PACKAGE##*/} -d /usr/local/bin/
rm -f ${PACKAGE##*/}

# Create systemd service
echo \
"[Unit]
Description=snell server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/etc/snell
ExecStart=/usr/local/bin/snell-server -l info
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell
[Install]
WantedBy=multi-user.target" | tee /etc/systemd/system/snell.service > /dev/null
mkdir -p /etc/snell
cd /etc/snell

# Generate PSK
SNELL_PSK=$(openssl rand -base64 32 | tr -d '=')

# Create config file with specified port
tee /etc/snell/snell-server.conf > /dev/null <<EOF
[snell-server]
listen = :::$SNELL_PORT
psk = $SNELL_PSK
ipv6 = false
EOF

systemctl start snell
systemctl enable snell


# print snell server info
echo
echo "========================================"
echo "Snell Server Installation Complete!"
echo "========================================"
echo "Port: $SNELL_PORT"
echo "PSK: $SNELL_PSK"
echo
echo "Copy the following line to Surge, under the [Proxy] section:"
echo "$(curl -s --max-time 5 ipinfo.io/city 2>/dev/null || echo 'Server') = snell, $(curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || echo 'YOUR_SERVER_IP'), $SNELL_PORT, psk=$SNELL_PSK, version=5"
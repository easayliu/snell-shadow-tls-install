#!/bin/bash


# Install dependencies based on the Linux distribution
if cat /etc/*-release | grep -q -E -i "debian|ubuntu|armbian|deepin|mint"; then
    sudo apt-get install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "centos|red hat|redhat"; then
    sudo yum install wget unzip dpkg -y
elif cat /etc/*-release | grep -q -E -i "arch|manjaro"; then
    sudo pacman -S wget dpkg unzip --noconfirm
elif cat /etc/*-release | grep -q -E -i "fedora"; then
    sudo dnf install wget unzip dpkg -y
fi

# Enable BBR
# echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
# echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
# sudo sysctl -p
# sudo sysctl net.ipv4.tcp_available_congestion_control

# Download and install snell
cd
ARCH=$(uname -m)
BASE_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux"
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
unzip -o ${PACKAGE##*/} 





# Create systemd service
echo -e "[Unit]\nDescription=snell server\n[Service]\nUser=$(whoami)\nWorkingDirectory=$HOME\nExecStart=$HOME/snell-server\nRestart=always\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/snell.service > /dev/null
echo "y" | sudo ./snell-server
sed -i 's/0.0.0.0/127.0.0.1/g' ./snell-server.conf
sudo systemctl start snell
sudo systemctl enable snell

# install shadows-tls
SHADOW_TLS_VERSION=$(curl --silent "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
sudo wget https://github.com/ihciah/shadow-tls/releases/download/$SHADOW_TLS_VERSION/shadow-tls-x86_64-unknown-linux-musl -O /usr/local/bin/shadow-tls
sudo chmod +x /usr/local/bin/shadow-tls

Snell_Port=$(cat snell-server.conf | grep -i listen | cut --delimiter=':' -f2)
Snell_Psk=$(grep 'psk' snell-server.conf | cut -d= -f2 | tr -d ' ')

# add systemd service 
echo "[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen 0.0.0.0:8443 --server 127.0.0.1:$Snell_Port --tls  gateway.icloud.com  --password $Snell_Psk
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target"| sudo tee /etc/systemd/system/shadow-tls.service
sudo systemctl start shadow-tls
sudo systemctl enable shadow-tls

# print snell server info
echo
echo "Copy the following line to Surge, under the [Proxy] section:" 
echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ipinfo.io/ip), 8443, psk=$Snell_Psk, version=4, tfo=true,shadow-tls-password=$Snell_Psk, shadow-tls-sni=gateway.icloud.com, shadow-tls-version=3"
#!/bin/bash

ARCHITECTURE=$(dpkg --print-architecture)
rm -f snell-server-v4.0.1-linux-$ARCHITECTURE.zip
rm -f snell-server
rm -f snell-server.conf
systemctl stop snell.service
systemctl disable snell.service
rm -f /etc/systemd/system/snell.service


systemctl stop shadow-tls.service
systemctl disable shadow-tls.service
rm -f /etc/systemd/system/shadow-tls.service


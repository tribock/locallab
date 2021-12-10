#!/usr/bin/bash

sudo cp podman/87-podman-bridge.conflist /etc/cni/net.d/87-podman-bridge.conflist
sudo virsh net-undefine default
sudo virsh net-destroy default
sudo virsh net-define libvirt/default-net.xml
sudo virsh net-start default
sudo virsh net-autostart default
sudo cp NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
sudo rm /etc/resolv.conf
sudo touch /etc/resolv.conf
sudo systemctl restart NetworkManager
sudo cp NetworkManager/podman-libvirt-dns.conf /etc/NetworkManager/dnsmasq.d/podman-libvirt-dns.conf
sudo pkill -f '[d]nsmasq.*--enable-dbus=org.freedesktop.NetworkManager.dnsmasq'



#!/bin/bash

ISOIMAGE=discovery_image_itix-control-plane.iso
ISOPATH=/var/lib/libvirt/images/
sudo cp ~/Downloads/$ISOIMAGE $ISOPATH/
sudo virt-install -n ocp-control-plane --memory 32768 --vcpus=8 --os-variant=fedora-coreos-stable --accelerate -v --cpu host-passthrough,cache.mode=passthrough --disk path=$ISOPATH/ocp-control-plane.qcow2,size=120 --network network=ocp-dev,mac=02:01:00:00:00:67 --cdrom $ISOPATH/$ISOIMAGE

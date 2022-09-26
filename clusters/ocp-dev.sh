#!/bin/bash

ISOIMAGE=discovery_image_itix-dev-local.iso
ISOPATH=/var/lib/libvirt/images/
sudo cp ~/Downloads/$ISOIMAGE $ISOPATH/
sudo virt-install -n ocp-dev --memory 32768 --vcpus=8 --os-variant=fedora-coreos-stable --accelerate -v --cpu host-passthrough,cache.mode=passthrough --disk path=$ISOPATH/ocp-dev.qcow2,size=120 --network network=ocp-dev,mac=02:01:00:00:00:66 --cdrom $ISOPATH/$ISOIMAGE

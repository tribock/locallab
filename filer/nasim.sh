#!/bin/bash

IMGSRC=$HOME/Downloads
IMGDST=/var/lib/libvirt/images/

ImageFile=vsim-netapp-DOT9.9.1-cm_nodar.ova

cd $IMGSRC


tar vxf $ImageFile || exit 1
for i in {1..4}; do
    qemu-img convert -f vmdk -O qcow2 vsim-NetAppDOT-simulate-disk${i}.vmdk vsim-NetAppDOT-simulate-disk${i}.qcow2
done

sudo mv *.qcow2 $IMGDST

sudo virt-install --name nasim01a --memory 12288 --vcpus 2 --os-variant freebsd11.2 \
 --disk=$IMGDST/vsim-NetAppDOT-simulate-disk{1..4}.qcow2,bus=ide --autostart \
 --network network=ocp-dev,model=e1000,mac=02:18:A6:97:B3:A0 \
 --network network=ocp-dev,model=e1000,mac=02:d6:ca:b8:90:ce \
 --network network=ocp-dev,model=e1000,mac=02:0a:1f:e3:5f:ef \
 --network network=ocp-dev,model=e1000,mac=02:c0:80:ec:5b:93 \
 --autostart --vnc --virt-type kvm --machine pc --boot hd,network,menu=on --noautoconsole

sudo virsh net-undefine ocp-dev
sudo virsh net-destroy ocp-dev
sudo virsh net-define libvirt/ocp-net.xml
sudo virsh net-start ocp-dev
sudo virsh net-autostart ocp-dev
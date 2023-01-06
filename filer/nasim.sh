#!/bin/bash

Rundir=/tmp/ontap-simulator-s-$$
mkdir -p $Rundir
clean() { rm -rf $Rundir; }
trap "clean" EXIT

image_binarize() {
	local srcf=${1}
	local dstf=${2:-new-${srcf}}

	if command -v anytopnm >/dev/null; then
		anytopnm $srcf | ppmtopgm | pgmtopbm -threshold | pnmtopng > $dstf
	else
		local ConvertCmd="gm convert"
		! command -v gm >/dev/null && {
			if ! command -v convert >/dev/null; then
				echo "{VM:WARN} command gm or convert are needed by 'vncget' function!" >&2
				return 1
			else
				ConvertCmd=convert
			fi
		}
		$ConvertCmd $srcf -threshold 30% $dstf
	fi

	return 0
}

vncget() {
	local _vncaddr=$1

	[[ -z "$_vncaddr" ]] && return 1
	vncdo -s ${_vncaddr} capture $Rundir/_screen.png
	image_binarize $Rundir/_screen.png $Rundir/_screen2.png || return 1
	gocr -i $Rundir/_screen2.png 2>/dev/null
}
colorvncget() { vncget "$@" | GREP_COLORS='ms=01;30;47' grep --color .; }

vncput() {
	local vncport=$1
	shift

	which vncdo >/dev/null || {
		echo "{WARN} could not find command 'vncdo'" >&2
		return 1
	}

	[[ -n "$*" ]] && echo -e "\033[1;33m[vncput>$vncport] $*\033[0m"

	local msgArray=()
	for msg; do
		if [[ -n "$msg" ]]; then
			if [[ "$msg" = key:* ]]; then
				msgArray+=("$msg")
			else
				regex='[~@#$%^&*()_+|}{":?><!]'
				_msg="${msg#type:}"
				if [[ "$_msg" =~ $regex ]]; then
					while IFS= read -r line; do
						[[ "$line" =~ $regex ]] || line="type:$line"
						msgArray+=("$line")
					done < <(sed -r -e 's;[~!@#$%^&*()_+|}{":?><]+;&\n;g' -e 's;[~!@#$%^&*()_+|}{":?><];\nkey:shift-&;g' <<<"$_msg")
				else
					msgArray+=("$msg")
				fi
			fi
			msgArray+=("")
		else
			msgArray+=("$msg")
		fi

	done
	for msg in "${msgArray[@]}"; do
		if [[ -n "$msg" ]]; then
			if [[ "$msg" = key:* ]]; then
				vncdo -s $vncport key "${msg#key:}"
			else
				vncdo -s $vncport type "${msg#type:}"
			fi
		else
			sleep 1
		fi
	done
}
vncputln() {
	vncput "$@" "key:enter"
}

ocrgrep() {
	local pattern=$1
	local ignored_charset=${2:-ijkfwe[|:}
	pattern=$(sed "s,[${ignored_charset}],.,g" <<<"${pattern}")
	grep -i "${pattern}"
}
vncwait() {
	local addr=$1
	local pattern="$2"
	local tim=${3:-1}
	local ignored_charset="$4"
	local maxloop=60
	local loop=0
	local screentext=

	echo -e "\n=> waiting: \033[1;36m$pattern\033[0m prompt ..."
	screentext=$(vncget $addr)
	if echo "$screentext"|egrep '^(PANIC *:|vpanic)'; then
		kill -SIGALRM $CPID
	fi
	while true; do
		vncget $addr | ocrgrep "$pattern" "$ignored_charset" && break
		sleep $tim
		let loop++
		if [[ $loop = $maxloop ]]; then
			echo "{WARN}: vncwait has been waiting for more than $(bc <<< "600*$tim") seconds"
			screentext=$(vncget $addr)
			if echo "$screentext"|egrep '^(PANIC *:|vpanic)'; then
				kill -SIGALRM $CPID
			else
				echo "$screentext"
			fi
			loop=0
		fi
	done
}

IMGSRC=$HOME/isos/ntap
IMGDST=$HOME/VMs/ONTAP-SIMULATOR/nasim01a

ImageFile=vsim-netapp-DOT9.9.1-cm_nodar.ova
LicenseFile=$IMGSRC/CMode_licenses_9.9.1.txt

node_managementif_addr=192.168.123.200
cluster_name=nasim01
password=tabstop1
NTP_SERVER=${NTP_SERVER:-time.google.com}

vmnode=nasim01a
node_managementif_port=e0c
node_managementif_addr=$node_managementif_addr #10.66.12.108
node_managementif_mask=255.255.255.0
node_managementif_gateway=192.168.123.1
cluster_managementif_port=e0a
cluster_managementif_addr=192.168.123.201
cluster_managementif_mask=255.255.255.0
cluster_managementif_gateway=192.168.123.1

OSV=freebsd11.2
dns_domains=ocplocal.itix
dns_addrs=192.168.123.1
controller_located=AtTheBar

if [[ ! -f $LicenseFile ]]; then
	echo "{WARN} license file '${LicenseFile}' does not exist." >&2
	exit 1
fi

cd $IMGSRC


tar vxf $ImageFile || exit 1
for i in {1..4}; do
    qemu-img convert -f vmdk -O qcow2 vsim-NetAppDOT-simulate-disk${i}.vmdk vsim-NetAppDOT-simulate-disk${i}.qcow2
done

mkdir -p $IMGDST

mv *.qcow2 $IMGDST

cd $IMGDST

sudo vm create -n $vmnode ONTAP-SIMULATOR --cpus 2,cores=2 --osv $OSV \
  -i vsim-NetAppDOT-simulate-disk1.qcow2 \
 --disk=vsim-NetAppDOT-simulate-disk{2..4}.qcow2,bus=ide \
 --net=ocp-dev,e1000 \
 --net=ocp-dev,e1000 \
 --net-macvtap=-,e1000 \
 --net-macvtap=-,e1000 \
 --noauto --nocloud --video auto --diskbus=ide \
 --vncput-after-install key:enter  --force \
 --msize $((6*1024)) --vncput-after-install key:enter  --force 

read vncaddr <<<"$(vm vnc $vmnode)"
vncaddr=${vncaddr/:/::}
[[ -z "$vncaddr" ]] && {
	echo "{WARN}: something is wrong, exit ..." >&2
	exit 1
}

echo; expect -c "spawn virsh console $vmnode
	set timeout 8
	expect {
		-exact {Hit [Enter] to boot immediately} { send \"\\r\"; send_user \" #exit#\\n\"; exit }
		{cryptomod_fips:} { send_user \" #exit#\\n\"; exit }
	}"

vncwait ${vncaddr} "^login:" 5
[[ -z "$node_managementif_addr" ]] &&
	node_managementif_addr=$(vncget $vncaddr | sed -nr '/^.*https:..([0-9.]+).*$/{s//\1/; p}')
[[ -z "$node_managementif_addr" ]] &&
	node_managementif_addr=$(freeIpList "${ExcludeIpList[@]}"|sort -R|tail -1)
ExcludeIpList+=($node_managementif_addr)
vncputln ${vncaddr} "admin" ""
vncputln ${vncaddr} "reboot"

vncwait ${vncaddr} "Are you sure you want to reboot node.*? {y|n}:" 5
vncputln ${vncaddr} "y"

echo; expect -c "spawn virsh console $vmnode
	set timeout 120
	expect {
		-exact {Hit [Enter] to boot immediately} { send \"\\r\"; send_user \" #exit#\\n\"; exit }
		{cryptomod_fips:} { send_user \" #exit#\\n\"; exit }
	}"

: <<'COMM'
vncwait ${vncaddr} "Press Ctrl-C for Boot Menu." 5
vncput ${vncaddr} key:ctrl-c

vncwait ${vncaddr} "Selection (1-9)?" 5
vncputln ${vncaddr} "4"

vncwait ${vncaddr} "Zero disks, reset config and install a new file system?" 5
vncputln ${vncaddr} "yes"

vncwait ${vncaddr} "This will erase all the data on the disks, are you sure?" 5
vncputln ${vncaddr} "yes"

echo; expect -c "spawn virsh console $vmnode
	set timeout 120
	expect {
		-exact {Hit [Enter] to boot immediately} { send \"\\r\"; send_user \" #exit#\\n\"; exit }
		{cryptomod_fips:} { send_user \" #exit#\\n\"; exit }
	}"
COMM

vncwait ${vncaddr} "Type yes to confirm and continue {yes}:" 10
vncputln ${vncaddr} "yes"

vncwait ${vncaddr} "Enter the node management interface port" 2
vncputln ${vncaddr} "${node_managementif_port}"

vncwait ${vncaddr} "Enter the node management interface .. address" 2
vncputln ${vncaddr} "$node_managementif_addr"

vncwait ${vncaddr} "Enter the node management interface netmask" 2
vncputln ${vncaddr} "$node_managementif_mask"

vncwait ${vncaddr} "Enter the node management interface default gateway" 2
vncputln ${vncaddr} "$node_managementif_gateway"

vncwait ${vncaddr} "complete cluster setup using the command line" 2
vncputln ${vncaddr}

vncwait ${vncaddr} "create a new cluster or join an existing cluster?" 2
vncputln ${vncaddr} "create"

vncwait ${vncaddr} "used as a single node cluster?" 2
vncputln ${vncaddr} "yes"

vncwait ${vncaddr} "administrator.* password:" 2
vncputln ${vncaddr} "$password"

vncwait ${vncaddr} "Retype the password:" 2
vncputln ${vncaddr} "$password"

vncwait ${vncaddr} "Enter the cluster name:" 2
vncputln ${vncaddr} "$cluster_name"

vncwait ${vncaddr} "Enter an additional license key" 2
vncputln ${vncaddr}

vncwait ${vncaddr} "Enter the cluster management interface port" 2
vncputln ${vncaddr} "${cluster_managementif_port}"

vncwait ${vncaddr} "Enter the cluster management interface .. address" 2
vncputln ${vncaddr} "$cluster_managementif_addr"

vncwait ${vncaddr} "Enter the cluster management interface netmask" 2
vncputln ${vncaddr} "$cluster_managementif_mask"

vncwait ${vncaddr} "Enter the cluster management interface default gateway" 2
vncputln ${vncaddr} "$cluster_managementif_gateway"

vncwait ${vncaddr} "Enter the DNS domain names" 2
vncputln ${vncaddr} "$dns_domains"

vncwait ${vncaddr} "Enter the name server .. addresses" 2
vncputln ${vncaddr} "$dns_addrs"

vncwait ${vncaddr} "where is the controller located" 2
vncputln ${vncaddr} "$controller_located"

vncwait ${vncaddr} "backup destination address" 2
vncputln ${vncaddr}
sleep 2

:; echo -e "\n\033[1;36m------------------------------------------------------\033[0m"
colorvncget $vncaddr
:; echo -e "\n\033[1;36m------------------------------------------------------\033[0m"

:; echo -e "\n\033[1;36m=> now ssh(admin@$node_managementif_addr and admin@$cluster_managementif_addr) is available,\n please complete other configurations in ssh session ...\033[0m"

:; echo -e "\n\033[1;30m================================================================================\033[0m"
:; echo -e "\033[1;30m=> Delete snapshots and add disk shelf ...\033[0m"

vncwait ${vncaddr} "^login:" 1

nodename=${cluster_name}-01
diagpasswd=d1234567
expect -c "spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@$cluster_managementif_addr
	set timeout 120
	expect {*?assword:} { send \"${password}\\r\" }
	expect {${cluster_name}::>} { send \"run -node ${nodename}\\r\" }
	expect {${nodename}>} { send \"snap delete -a -f vol0\\r\" }
	expect {${nodename}>} { send \"snap sched vol0 0 0 0\\r\" }
	expect {${nodename}>} { send \"snap autodelete vol0 on\\r\" }
	expect {${nodename}>} { send \"snap autodelete vol0 target_free_space\\r\" }
	expect {${nodename}>} { send \"snap autodelete vol0\\r\" }
	expect {${nodename}>} { send \"exit\\r\" }

	expect {${cluster_name}::*>} { send \"system node reboot -node ${nodename}\\r\" }
	expect {Are you sure you want to reboot node} { send \"y\\r\"}
	set timeout 10
	expect eof
"

aggr0name=aggr0_${nodename//-/_}
expect -c "spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@$cluster_managementif_addr
	set timeout 120
	expect {*?assword:} { send \"${password}\\r\" }
	expect {${cluster_name}::>} { send \"disk assign -all true -node ${nodename}\\r\" }
	expect {${cluster_name}::>} {
		send \"aggr add-disks -aggregate $aggr0name -diskcount 5\\r\"
		send \"y\\r\"
		send \"y\\r\"
	}
	while 1 {
		expect {${cluster_name}::>} { send \"aggr show -aggregate $aggr0name -fields size\\r\" }
		expect {
			{*GB} break
			{*MB} { sleep 2; continue }
		}
	}
	expect {${cluster_name}::>} { send \"vol modify -vserver ${nodename} -volume vol0 -size 4G\\r\" }
	expect {${cluster_name}::>} { send \"exit\\r\" }
	expect eof
"

#don't do any pre-configuration after system initialization
if [[ -n "$RAW" ]]; then
	expect -c "*?spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@$cluster_managementif_addr
		set timeout 120
		expect {*?assword:} { send \"${password}\\r\" }
		expect {${cluster_name}::>} { send \"aggr show\\r\" }
		expect {${cluster_name}::>} { send \"vol show\\r\" }
		expect {${cluster_name}::>} { send \"network port show\\r\" }
		expect {${cluster_name}::>} { send \"network interface show\\r\" }
		expect {${cluster_name}::>} { send \"exit\\r\" }
		expect eof
	"
	exit
fi

getBaseLicense() { local lf=$1; awk 'BEGIN{RS="[\x0d\x0a\x0d]"} /Cluster Base license/ {printf $NF}' $lf; }
getFirstNodeLicenses() { local lf=$1; awk '$2 ~ /^[A-Z]{28}$/ && $2 ~ /ABG/ {print $2}' $lf | paste -sd,; }
BaseLicense=$(getBaseLicense $LicenseFile)
FirstNodeLicenses=$(getFirstNodeLicenses $LicenseFile)
LicenseList=$BaseLicense,$FirstNodeLicenses
expect -c  "spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@$cluster_managementif_addr
	set timeout 120
	expect {*?ssword:} { send \"${password}\\r\" }
	expect {${cluster_name}::>} { send \"aggr show\\r\" }
	expect {${cluster_name}::>} { send \"system license add -license-code $LicenseList\\r\" }
	expect {${cluster_name}::>} { send \"aggr show\\r\" }
	expect {${cluster_name}::>} { send \"vol show\\r\" }
	expect {${cluster_name}::>} { send \"network port show\\r\" }
	expect {${cluster_name}::>} { send \"network interface show\\r\" }
	expect {${cluster_name}::>} { send \"exit\\r\" }
	expect eof
"
#!/bin/bash
#
# rhev_v2v.sh
#
# USAGE: rhev_v2v.sh  [-h] -i inputfile -o outputdir -l logfile -t tempdir [-L sysprep_log]
# 
# DESCRIPTION:
#	virtual-to-virtual script to migrate an OVA file from disk,
#	to a rhev export domain suitable for RHEV.
#
# LIMITATIONS:
#	Below is an inclusive list of guest Operating Systems which are supported:
#		- Windows 2008 R2
#		- RHEL6
#		- RHEL7
#
# REQUIREMENTS: rpm virt-v2v v1.28+
#		Runs under RHEL7
#
#----------------------------------------------------------------------------------------------------

ulimit -c unlimited

v2v_help() {
cat << EOF 
Usage: ${0##*/} [-h] -i inputfile -o rhev_export_path -l logfile -t tempdir -n #nics [-d] [-I IP_Address]
Convert an OVA file to a raw image file

	-h	show this help screen
	-i	full path to input OVA file (mandatory)
	-o	RHEV export domain NFS mount path, i.e. 10.0.0.1:/exports/rhev/export
	-l	full path to logging file that will be made (mandatory)
	-t	full path to temporary directory (used to untar the ova) (mandatory)
        -I	IP address to assign host for migration
	-L	full path to logging file for virt-sysprep
	-n	number of nics that will be converted to dhcp. defaults to 1 to change eth0. 0 will not replace eth0, using existing eth0.
EOF
}

stop_time() {
   echo "Stop time:  `date`"
}

V2V_INPUT=""
V2V_OUTPUT=""
V2V_TMPDIR=""
V2V_LOG=""
V2V_DEBUG_ARGS="-x -v"
SDA_PATH=""
SYSPREP_LOG=""
NUM_NICS=1

if [[ $1 == "" ]]; then 
	echo -e "No options specified\n"
	v2v_help >&2
	exit 1
fi
   
##
## 
##
   
while getopts "hi:l:o:t:d:L:n:I:" opt; do
	case "$opt" in

		h)
			v2v_help
			exit 0
			;;
		i)	
			V2V_INPUT=$OPTARG
			;;
		l)
			V2V_LOG=$OPTARG
			;;
		o)
			V2V_OUTPUT=$OPTARG
			;;
		t)
			V2V_TMPDIR=$OPTARG
			;;
		d)
			V2V_DEBUG_ARGS="-x -v"
			;;
		L)
			echo "got $OPTARG"
			SYSPREP_LOG=$OPTARG
			;;
		n)
			NUM_NICS=$OPTARG
			;;
                I)	
			IPADDR=$OPTARG
			;;
		\?)
			echo -e "Invalid option specified\n"
			v2v_help >&2
			stop_time
			exit 1
			;;
		':')	
			echo "Option -$OPTARG requires an argument" >&2
	esac
done

##
## Input File (-i) is mandatory; verify it was specified with -i and that it exists.
##

if [ x$V2V_INPUT == "x" ]; then
   	echo "ERROR: Input ova file (-i) is mandatory but was not specified.  "
	v2v_help
	stop_time
	exit 1
fi
if [ ! -f ${V2V_INPUT} ]; then
	echo "Input file ${V2V_INPUT} does not exist.  Exiting...."
	stop_time
	exit 1
fi

##
## RHEV Export Domain (-o) is mandatory; verify it was specified with -o and that it exists.
##

if [ x$V2V_OUTPUT == "x" ]; then
   	echo "ERROR: RHEV export domain (-o) is mandatory but was not specified.  "
	v2v_help
	stop_time
	exit 1
fi
# This won't work for RHEV export domain.
#if [ ! -d ${V2V_OUTPUT} ]; then
#	echo "Ouput directory ${V2V_OUTPUT} does not exist.  Creating..."
#	mkdir -p ${V2V_OUTPUT}
#	#stop_time
#	#exit 1
#fi

##
## Output Directory must not be the same as the input directory.
##
# Can't happen with RHEV.

#if [[ $(dirname ${V2V_INPUT}) == ${V2V_OUTPUT} ]]; then
#   	echo "ERROR: Attempting to overwrite input file"
#	stop_time
#	exit 1
#fi

##
## Log file (-l) is mandatory; verify it was specified by -l argument and that its directory exists.
##

if [ x$V2V_LOG == "x" ]; then
   	echo "ERROR: Log file is mandatory but was not specified.  "
	v2v_help
	stop_time
	exit 1
fi
if [ ! -d $(dirname ${V2V_LOG}) ]; then
	echo "Directory for Log file ${V2V_LOG} does not exist.  Exiting..."
	stop_time
	exit 1
fi

##
## Temp dir (-t) is mandatory; verify it was specified by -t argument and that it exists.
##

if [ x$V2V_TMPDIR == "x" ]; then
   	echo "ERROR: TMP directory is mandatory but was not specified.  "
	v2v_help
	stop_time
	exit 1
fi
if [ ! -d ${V2V_TMPDIR} ]; then
	echo "Temp directory ${V2V_TMPDIR} does not exist.  Exiting..."
	stop_time
	exit 1
fi

export TMPDIR=${V2V_TMPDIR}

export LIBGUESTFS_BACKEND=direct

##
## RPM virtio-win is required to convert Windows images (but not RHEL images).  I cannot tell if the 
## image being converted here is a Windows or RHEL image, so I'll complain either way.  
## Once it's installed, we won't need to deal with the decision again.
##

rpm -q virtio-win &>/dev/null 
if [ "$?" -ne "0" ]; then
	echo "Package virtio-win is not installed. Please install the virtio-win rpm on this machine and try again.  Exiting..."
	stop_time
	exit 1
fi

##
## Convert the image to a qcow image, output it to RHEV export datastore, and log the work
##


echo "Converting ova file ${V2V_INPUT} to qcow image and loading to ${V2V_OUTPUT}, logging to ${V2V_LOG} "
echo "Start time:  `date`"

#/usr/bin/virt-v2v ${V2V_DEBUG_ARGS} -i ova ${V2V_INPUT} -o local -of raw -os ${V2V_OUTPUT} > ${V2V_LOG} 2>&1
/usr/bin/virt-v2v ${V2V_DEBUG_ARGS} -i ova ${V2V_INPUT} -o rhev -of qcow2 -os ${V2V_OUTPUT} --network rhevm > ${V2V_LOG} 2>&1

# Determine the location of the image(s) on RHEV Export from the log.

QCOW_FILES=""
for i in $(/usr/bin/awk '/^qemu-img convert/ {print $NF}' $V2V_LOG | /usr/bin/sed -e "s/'//g" -e "s|^$TMPDIR||" | /usr/bin/perl -pe 's|^/.*?/|/|')
do
	j="/mnt/${i}"
	if [ ! -f "$j" ]
	then
		echo "QCOW file <$j> not found!"
		stop_time
		exit 1
	fi
	QCOW_FILES+=" ${j}"
done

##
## Run virt-sysprep if the log file has been provided. Build out the command by getting any converted disks a through z in the v2v output
##

if [ ! -z "$SYSPREP_LOG" ]; then
	if [ -z "$QCOW_FILES" ]
	then
		echo "No image file was found in $V2V_LOG, unable to run sysprep."
		stop_time
		exit 1
	fi
        echo "Running virt-sysprep against disks in ${V2V_OUTPUT} and logging to ${SYSPREP_LOG}"
        call_later="/usr/bin/virt-sysprep --enable net-hwaddr,udev-persistent-net,customize "

	# This section will switch NICs to DHCP.  Commenting out for now as we don't have DHCP in RHEV.
        if [ -n "$IPADDR" ]
        then
                BOOTPROTO=none
                NETCFG="IPADDR=$IPADDR\nPREFIX=24\nGATEWAY=172.16.0.1\nDNS1=172.16.0.25\n"
        else
                BOOTPROTO=dhcp
                NETCFG=""
        fi
        # Fallback to at least one eth0 if host had non ethX interfaces -prutledg
        call_later+=" --run-command 'if [ ! -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]; then echo -e \"NAME=eth0\nDEVICE=eth0\nBOOTPROTO=$BOOTPROTO\n$NETCFG\nONBOOT=yes\" > /etc/sysconfig/network-scripts/ifcfg-eth0; fi' "

	for f in $QCOW_FILES
	do
		call_later+=" -a $f"
	done
	call_later+=" > ${SYSPREP_LOG} 2>&1"
	echo $call_later
	eval $call_later
fi

stop_time

#!/bin/sh
# Add to ESXi to path /etc/rc.local.d/ to ensure all VMs start on boot
vmid=$(vim-cmd vmsvc/getallvms | awk '{print $1}' | grep -v Vmid)
state1=$(vim-cmd vmsvc/power.getstate "$vmid" | grep "off")

if [ "$state1" == "Powered off" ]
  then
    vim-cmd vmsvc/power.on "$vmid"
fi


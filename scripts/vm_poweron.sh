#!/bin/sh
#
# Add to /etc/rc.local.d/local.sh  before "exit 0" to ensure all VMs start on boot
# It can be used as standalone script also to poweron all VMs that are off

sleep 10

vmid_list=$(vim-cmd vmsvc/getallvms | awk '{print $1}' | grep -v Vmid)

for vmid in $vmid_list; do

  state1=$(vim-cmd vmsvc/power.getstate "$vmid" | grep "off")

  if [ "$state1" == "Powered off" ]; then
    vim-cmd vmsvc/power.on "$vmid"
  fi

done

exit 0


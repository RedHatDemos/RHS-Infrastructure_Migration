#!/bin/bash 
hosts=(oracledb tomcat)
guid=$(hostname -s | awk -F - '{print $2}')

echo ""
echo -n "Please wait, updating hostnames with your guid: $guid ."

for hostname in "${hosts[@]}"
do 
    echo -n "."
    ssh root@$hostname.example.com "hostnamectl --transient set-hostname $hostname-$guid.example.com"
    ssh root@$hostname.example.com "hostnamectl set-hostname $hostname-$guid.example.com"
    sed -i "s/$hostname/$hostname-$guid/g" /etc/hosts
    systemctl restart dnsmasq
done
echo ""

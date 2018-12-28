 mkdir ~/images
mkdir ~/templates
hostname
hostname -f
sudo hostnamectl director.example.com
sudo hostnamectl set-hostname director.example.com
sudo hostnamectl set-hostname director.example.com --transient
hostname -f
vi /etc/hosts
ip a
yum install vim
sudo yum install vim
sudo vim /etc/host
sudo vim /etc/hosts
sudo yum install -y python-tripleoclient
ls
vim undercloud.conf 
sudo chown stack -R *
vim undercloud.conf 
ip a
vim undercloud.conf 
vim /usr/share/instack-undercloud/undercloud.conf.sample
vim undercloud.conf 
ll
vim undercloud.conf 
ping 10.100.0.2
ll
ip a
sudo vim /etc/sysconfig/network-scripts/ifcfg-eth0 
sudo systemctl restart network
ipmitool -I lanplus -H 10.10.10.151 -U admin -P redhat power status
yum install vim
sudo yum install vim
sudo yum install -y python-tripleoclient
sudo yum install ipmi
yum search ipmi
sudo yum install ipmitool
ipmitool -I lanplus -H 10.10.10.150 -U admin -P redhat power status
cat undercloud.conf 
ip a
openstack undercloud install
ip a
f -h
df -h
ip a
netstat -ln | grep 35357
cd .instack/
ll
vim install-undercloud.log 
vim /etc/hosts
sudo vim /etc/hosts
openstack stack list
cd
ls
cat undercloud-passwords.conf 
ls
openstack undercloud install
openstack
ll
. stackrc 
openstack baremetal node list
sudo systemctl list-units openstack-*
openstack
nova list
network list
openstack network list
openstack network show ctlplane
cat undercloud.conf 
openstack subnet list
openstack subnet show ctlplane-subnet
cat undercloud.conf 
 sudo yum install rhosp-director-images rhosp-director-images-ipa
cd ~/images
for i in /usr/share/rhosp-director-images/overcloud-full-latest-13.0.tar /usr/share/rhosp-director-images/ironic-python-agent-latest-13.0.tar; do tar -xvf $i; done
 openstack overcloud image upload --image-path /home/stack/images/
 openstack image list
ls -l /httpboot
openstack subnet set --dns-nameserver 8.8.8.8 ctlplane-subnet
cd
vim prepare_images.sh
chmod +x prepare_images.sh 
netstat -ln | grep 878
vim prepare_images.sh
ls
cd templates
ll
cd ..
ll
tar xvfz templates.tgz 
cd templates
ll
rm 10-overcloud-images.yaml 
cd ..
ll
vim prepare_images.sh 
./prepare_images.sh 
sudo openstack overcloud container image upload   --config-file  /home/stack/local_registry_images.yaml   --verbose
curl http://192.0.2.5:8787/v2/_catalog | jq .repositories[]
curl http://10.100.0.20:8787/v2/_catalog | jq .repositories[]
nova list
. stackrc 
nova list
top
ls
ll
openstack baremetal node list
vi instackenv.json 
 openstack overcloud node import ~/instackenv.json
nova list
cat instackenv.json 
ipmitool -I ipmitool -H 10.10.10.151 -U admin -P redhat power status
ipmitool 
cd /var/log/ironic
ll
cat prepare_images.sh 
cat subscribe.sh 
mv subscribe.sh repos.sh
vim repos.sh 
sudo ./repos.sh 

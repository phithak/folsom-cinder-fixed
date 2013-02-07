#  This is a set of scripts to install OpenStack Folsom on 
#  ubuntu 12.10. This work is inspired by the script written by  
#  Tung Ns (tungns.inf@gmail.com) at 
#       https://github.com/neophilo/openstack-scripts
#  We have divided the origiginal script into several parts and 
#  change nova-network configuration to FlatDHCP. We also write
#  a new script to install OpenStack on a compute node. 
#
#  kasidit chanchio (kasiditchanchio@gmail.com)   
#
#  ----
#
#!/bin/bash

# Check if user is root

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   echo "Please run $ sudo bash then rerun this script"
   exit 1
fi

source ~/setup_paramrc

source ~/openrc

cat >> ~/.bashrc <<EOF
source ~/openrc
EOF

source ~/.bashrc

mysql -u root -p$MYSQL_PASS -e 'CREATE DATABASE cinder_db;'
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON cinder_db.* TO 'cinder'@'%' IDENTIFIED BY 'cinder';"
mysql -u root -p$MYSQL_PASS -e "GRANT ALL ON cinder_db.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder';"

echo "
#####################################
	Install Cinder
#####################################
"
sleep 1


sudo apt-get install -y cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms python-cinderclient tgt

# Update /etc/cinder/api-paste.ini
sed -i "s/127.0.0.1/$IP/g" /etc/cinder/api-paste.ini
sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" /etc/cinder/api-paste.ini
sed -i "s/%SERVICE_USER%/cinder/g" /etc/cinder/api-paste.ini
sed -i "s/%SERVICE_PASSWORD%/cinder/g" /etc/cinder/api-paste.ini

# Update /etc/cinder/cinder.conf
cat >> /etc/cinder/cinder.conf <<EOF
sql_connection = mysql://cinder:cinder@$IP/cinder_db
EOF

# Sync database
cinder-manage db sync

# ------------------------------------------------------------
# Create 4GB test loop file, mount it then initialise it as an lvm, 
# create a cinder-volumes group
# This section is modified by Phithak Thaenkaew
apt-get -y purge iscsitarget iscsitarget-dkms
apt-get -y autoremove
service open-iscsi restart

mkdir /home/cinder
cat >> /home/cinder/cinder.fdisk <<EOF
n
p
1


t
8e
p
w
EOF

dd if=/dev/zero of=/home/cinder/cinder-volumes bs=1 count=0 seek=4G
losetup /dev/loop2 /home/cinder/cinder-volumes
fdisk /dev/loop2 < /home/cinder/cinder.fdisk
fdisk -l /dev/loop2
sleep 2

pvcreate /dev/loop2
vgcreate cinder-volumes /dev/loop2
vgdisplay cinder-volumes
sleep 2

sed -i "s/^exit 0/losetup \/dev\/loop2 \/home\/cinder\/cinder-volumes/g" /etc/rc.local
echo "sleep 5" >> /etc/rc.local
echo "service tgt restart" >> /etc/rc.local
echo "sleep 5" >> /etc/rc.local
echo "service cinder-volume restart" >> /etc/rc.local
echo "service cinder-api restart" >> /etc/rc.local
echo "service cinder-scheduler restart" >> /etc/rc.local
echo "sleep 5" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
mv /etc/tgt/conf.d/nova_tgt.conf /etc/tgt/conf.d/nova_tgt.conf.bak
sed -i "s/*.conf/cinder_tgt.conf/1g" /etc/tgt/targets.conf
service tgt restart
# ------------------------------------------------------------

# Restart cinder service
service cinder-volume restart
service cinder-api restart
service cinder-scheduler restart

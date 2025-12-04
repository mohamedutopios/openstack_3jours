#!/usr/bin/env bash
set -euo pipefail

#############################################
# VARIABLES À PERSONNALISER
#############################################
HOST_IP="192.168.56.10"
RABBIT_PASS="rabbit_123!"
ADMIN_PASS="admin_123!"

KEYSTONE_DBPASS="ks_db_123!"
GLANCE_DBPASS="gl_db_123!"
GLANCE_PASS="gl_srv_123!"

NOVA_DBPASS="nv_db_123!"
PLACEMENT_DBPASS="pl_db_123!"
NOVA_PASS="nv_srv_123!"
PLACEMENT_PASS="pl_srv_123!"

NEUTRON_DBPASS="nt_db_123!"
NEUTRON_PASS="nt_srv_123!"
METADATA_SECRET="meta_123!"

CINDER_DBPASS="cd_db_123!"
CINDER_PASS="cd_srv_123!"


#############################################
echo "[STEP 0] Préparation système"
#############################################

apt update && apt -y upgrade
apt -y install software-properties-common net-tools vim python3-pip chrony

hostnamectl set-hostname controller

cat >/etc/hosts <<EOF
127.0.0.1 localhost
$HOST_IP controller
EOF


#############################################
echo "[STEP 1] Ajout Cloud Archive Caracal"
#############################################

add-apt-repository -y cloud-archive:caracal
apt update && apt -y dist-upgrade
apt -y install python3-openstackclient


#############################################
echo "[STEP 2] Install DB + RabbitMQ + Memcached + etcd"
#############################################

apt -y install mariadb-server python3-pymysql rabbitmq-server memcached python3-memcache etcd

# MariaDB
cat >/etc/mysql/mariadb.conf.d/99-openstack.cnf <<EOF
[mysqld]
bind-address = $HOST_IP
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
character-set-server = utf8
collation-server = utf8_general_ci
EOF

systemctl restart mariadb

# RabbitMQ
rabbitmqctl add_user openstack "$RABBIT_PASS"
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Memcached
sed -i "s/^-l .*/-l $HOST_IP/" /etc/memcached.conf
systemctl restart memcached


#############################################
echo "[STEP 3] Keystone"
#############################################

mysql -uroot <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF

apt -y install keystone apache2 libapache2-mod-wsgi-py3

crudini --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:${KEYSTONE_DBPASS}@controller/keystone
crudini --set /etc/keystone/keystone.conf token provider fernet

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

keystone-manage bootstrap \
  --bootstrap-password "$ADMIN_PASS" \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne

echo "ServerName controller" >/etc/apache2/conf-available/servername.conf
a2enconf servername
a2enmod wsgi
systemctl restart apache2

# openrc admin
cat >/root/admin-openrc.sh <<EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF


#############################################
echo "[STEP 4] Glance"
#############################################

mysql -uroot <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';
FLUSH PRIVILEGES;
EOF

source /root/admin-openrc.sh
openstack user create --domain default --password "$GLANCE_PASS" glance
openstack role add --project service --user glance admin
openstack service create --name glance image

openstack endpoint create --region RegionOne image public   http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin    http://controller:9292

apt -y install glance

crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://glance:${GLANCE_DBPASS}@controller/glance
crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS
crudini --set /etc/glance/glance-api.conf glance_store default_store file
crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/

su -s /bin/sh -c "glance-manage db_sync" glance
systemctl restart glance-api


#############################################
echo "[STEP 5] Nova + Placement"
#############################################

mysql -uroot <<EOF
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
CREATE DATABASE placement;

GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.*     TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';

GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';
FLUSH PRIVILEGES;
EOF

source /root/admin-openrc.sh

openstack user create --domain default --password "$NOVA_PASS" nova
openstack role add --project service --user nova admin
openstack service create --name nova compute

openstack endpoint create --region RegionOne compute public   http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin    http://controller:8774/v2.1

openstack user create --domain default --password "$PLACEMENT_PASS" placement
openstack role add --project service --user placement admin
openstack service create --name placement placement

openstack endpoint create --region RegionOne placement public   http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin    http://controller:8778

apt -y install placement-api nova-api nova-scheduler nova-conductor nova-novncproxy

# Placement
crudini --set /etc/placement/placement.conf placement_database connection mysql+pymysql://placement:${PLACEMENT_DBPASS}@controller/placement
crudini --set /etc/placement/placement.conf keystone_authtoken password $PLACEMENT_PASS

su -s /bin/sh -c "placement-manage db sync" placement
systemctl restart apache2

# Nova
crudini --set /etc/nova/nova.conf DEFAULT my_ip $HOST_IP
crudini --set /etc/nova/nova.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@controller
crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://nova:${NOVA_DBPASS}@controller/nova_api
crudini --set /etc/nova/nova.conf database connection mysql+pymysql://nova:${NOVA_DBPASS}@controller/nova
crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
crudini --set /etc/nova/nova.conf vnc server_proxyclient_address $HOST_IP
crudini --set /etc/nova/nova.conf vnc novncproxy_base_url http://controller:6080/vnc_auto.html
crudini --set /etc/nova/nova.conf glance api_servers http://controller:9292

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1" nova
su -s /bin/sh -c "nova-manage db sync" nova

apt -y install nova-compute
crudini --set /etc/nova/nova-compute.conf libvirt virt_type qemu

systemctl restart nova-api nova-scheduler nova-conductor nova-novncproxy nova-compute



#############################################
echo "[STEP 6] Neutron (provider flat)"
#############################################

mysql -uroot <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
FLUSH PRIVILEGES;
EOF

source /root/admin-openrc.sh

openstack user create --domain default --password "$NEUTRON_PASS" neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron network

openstack endpoint create --region RegionOne network public   http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin    http://controller:9696

apt -y install neutron-server neutron-plugin-ml2 \
  neutron-linuxbridge-agent neutron-dhcp-agent \
  neutron-metadata-agent neutron-l3-agent

# neutron.conf
crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
crudini --set /etc/neutron/neutron.conf DEFAULT transport_url rabbit://openstack:${RABBIT_PASS}@controller
crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://neutron:${NEUTRON_DBPASS}@controller/neutron
crudini --set /etc/neutron/neutron.conf keystone_authtoken password ${NEUTRON_PASS}

# ML2
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers flat
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types ""
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge
crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks provider

# Bridge
crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings provider:enp0s8
crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan false
crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

# metadata
crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET

# sysctl
cat >>/etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
EOF

modprobe br_netfilter
sysctl -p

su -s /bin/sh -c "neutron-db-manage upgrade head" neutron

systemctl restart neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent nova-api


#############################################
echo "[STEP 7] Horizon"
#############################################

apt -y install openstack-dashboard

sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = \"controller\"/" /etc/openstack-dashboard/local_settings.py
sed -i "s/ALLOWED_HOSTS.*/ALLOWED_HOSTS = ['*']/" /etc/openstack-dashboard/local_settings.py
sed -i "s/#TIME_ZONE.*/TIME_ZONE = 'Europe\\/Paris'/" /etc/openstack-dashboard/local_settings.py

cd /usr/share/openstack-dashboard
python3 manage.py collectstatic --noinput
python3 manage.py compress --force

chown -R horizon:horizon /var/lib/openstack-dashboard/

systemctl restart apache2 memcached


#############################################
echo "[STEP 8] Installation terminée !"
#############################################

echo
echo "🔵 Connecte-toi à Horizon : http://$HOST_IP/horizon"
echo "🔵 Login : admin / $ADMIN_PASS"
echo
echo "Installation complète !"

## 0. Topologie et réseaux dans VirtualBox

### 0.1. VM OpenStack dans VirtualBox

Crée une VM avec :

* **OS** : Ubuntu Server 22.04 64-bit
* **vCPU** : 4
* **RAM** : 12–16 Go (8 Go minimum mais ça sera serré)
* **Disque** : 80–120 Go (plus si tu comptes faire Cinder avec LVM)

### 0.2. Interfaces réseau VirtualBox

Dans les paramètres de la VM :

* **Carte 1** :

  * Activée
  * Mode : **NAT**
  * Rôle : accès Internet (apt, etc.)
    → Correspond en général à **`enp0s3`** dans la VM.

* **Carte 2** :

  * Activée
  * Mode : **Réseau privé hôte (Host-only)**, par ex `vboxnet0`
  * Rôle : **réseau management + provider** (API OpenStack, Horizon, trafic VM)
    → Correspond souvent à **`enp0s8`**.

On met **toute l’API OpenStack et le réseau provider** sur `enp0s8` (topologie simple).

### 0.3. Netplan dans la VM (Ubuntu)

```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

Exemple :

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: true         # NAT, IP auto, route par défaut
    enp0s8:
      addresses:
        - 192.168.56.10/24   # IP management/provider
      routes: []             # pas de route par défaut ici
```

Applique :

```bash
sudo netplan apply
ip a
```

Tu dois voir :

* `enp0s3` avec une IP genre `10.0.2.15`
* `enp0s8` avec `192.168.56.10`

---

## 1. Préparation OS & dépôts OpenStack

### 1.1. Mise à jour & paquets de base

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install software-properties-common vim net-tools python3-pip
```

### 1.2. Hostname & /etc/hosts

```bash
sudo hostnamectl set-hostname controller
```

`/etc/hosts` :

```bash
127.0.0.1   localhost
192.168.56.10 controller
```

### 1.3. NTP (chrony)

```bash
sudo apt -y install chrony
sudo systemctl enable --now chrony
```

### 1.4. Dépôt OpenStack Caracal + client

```bash
sudo add-apt-repository cloud-archive:caracal
sudo apt update && sudo apt -y dist-upgrade
sudo apt -y install python3-openstackclient
```

### 1.5. Tests de cette phase

* `ping -c 3 8.8.8.8` → Internet OK
* `ping -c 3 controller` depuis la VM
* Sur ta machine hôte : `ping 192.168.56.10`
* `openstack --version` → le client est installé

---

## 2. Services de base : MariaDB, RabbitMQ, Memcached, etcd

### 2.1. Base de données MariaDB

```bash
sudo apt -y install mariadb-server python3-pymysql
```

Créer `/etc/mysql/mariadb.conf.d/99-openstack.cnf` :

```ini
[mysqld]
bind-address = 192.168.56.10

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
```

Puis :

```bash
sudo systemctl restart mariadb
sudo mysql_secure_installation
```

Crée un mot de passe root SQL (ex : `DBPASS`).

### 2.2. RabbitMQ

```bash
sudo apt -y install rabbitmq-server
sudo rabbitmqctl add_user openstack RABBIT_PASS
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
```

`RABBIT_PASS` = mot de passe que tu veux.

### 2.3. Memcached

```bash
sudo apt -y install memcached python3-memcache
sudo sed -i 's/^-l .*/-l 192.168.56.10/' /etc/memcached.conf
sudo systemctl restart memcached
```

### 2.4. etcd

```bash
sudo apt -y install etcd
```

Dans `/etc/default/etcd` (ou `/etc/etcd/etcd.conf`) configure `192.168.56.10` sur les URLs client.

```bash
sudo systemctl enable --now etcd
```

### 2.5. Tests

```bash
mysql -uroot -p -e "SHOW DATABASES;"
sudo rabbitmqctl list_users
systemctl status memcached
systemctl status etcd
```

---

## 3. Keystone (Identity)

### 3.1. DB Keystone

```bash
sudo mysql -uroot -p <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF
```

### 3.2. Installer Keystone

```bash
sudo apt -y install keystone apache2 libapache2-mod-wsgi-py3
```

Édite `/etc/keystone/keystone.conf` :

```ini
[database]
connection = mysql+pymysql://keystone:KEYSTONE_DBPASS@controller/keystone

[token]
provider = fernet
```

(assure-toi qu’il n’y a pas de `admin_token` actif dans la section `[DEFAULT]`.)

### 3.3. Sync DB et initialisation

```bash
sudo su -s /bin/sh -c "keystone-manage db_sync" keystone
sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

sudo keystone-manage bootstrap \
  --bootstrap-password ADMIN_PASS \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne
```

### 3.4. Apache / WSGI Keystone

Crée (si pas déjà fait) `/etc/apache2/sites-available/keystone.conf` :

```bash
sudo tee /etc/apache2/sites-available/keystone.conf >/dev/null <<'EOF'
Listen 5000

<VirtualHost *:5000>
    ServerName controller

    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LimitRequestBody 114688

    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>

    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        Require all granted
    </Directory>
</VirtualHost>
EOF
```

Active `wsgi` + le site + un `ServerName` propre :

```bash
echo "ServerName controller" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
sudo a2enmod wsgi
sudo a2ensite keystone
sudo systemctl restart apache2
```

### 3.5. Fichier `admin-openrc`

`/root/admin-openrc.sh` :

```bash
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
```

### 3.6. Tests Keystone

```bash
source /root/admin-openrc.sh
openstack token issue
openstack project list
openstack user list
```

Si ça répond → Keystone OK.

---

## 4. Glance (Image)

### 4.1. DB, utilisateur, service Glance

export GLANCE_DB_PASS="glance_db_123!"
export GLANCE_PASS="glance_srv_123!"

```bash
sudo mysql -uroot -p <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DB_PASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DB_PASS';
FLUSH PRIVILEGES;
EOF
```

```bash
source /root/admin-openrc.sh

openstack user create --domain default --password  "$GLANCE_PASS" glance
openstack role add --project service --user glance admin

openstack service create --name glance --description "OpenStack Image" image

openstack endpoint create --region RegionOne image public   http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin    http://controller:9292
```

### 4.2. Installation Glance

```bash
sudo apt -y install glance
```

`/etc/glance/glance-api.conf` :

```ini
[DEFAULT]
auth_strategy = keystone

[database]
connection = mysql+pymysql://glance:glance_db_123!@controller/glance

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = glance_srv_123!

[paste_deploy]
flavor = keystone

[glance_store]
stores = file
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
```

Sync DB :

```bash
sudo su -s /bin/sh -c "glance-manage db_sync" glance
sudo systemctl restart glance-api
```

### 4.3. Tests Glance

```bash
cd /tmp
wget http://download.cirros-cloud.net/0.5.2/cirros-0.5.2-x86_64-disk.img

source /root/admin-openrc.sh
openstack image create "cirros" \
  --file /tmp/cirros-0.5.2-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public

openstack image list
```

---

## 5. Nova (Compute : contrôleur + compute sur le même nœud)

### 5.1. DB Nova & Placement

```bash
sudo mysql -uroot -p <<EOF
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
CREATE DATABASE placement;

GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';

GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'PLACEMENT_DBPASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'PLACEMENT_DBPASS';

FLUSH PRIVILEGES;
EOF
```

### 5.2. Utilisateurs et endpoints Nova/Placement

```bash
source /root/admin-openrc.sh

openstack user create --domain default --password NOVA_PASS nova
openstack role add --project service --user nova admin

openstack user create --domain default --password PLACEMENT_PASS placement
openstack role add --project service --user placement admin

openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public   http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin    http://controller:8774/v2.1

openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public   http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin    http://controller:8778
```

### 5.3. Installation & configuration Placement API

```bash
sudo apt install placement-api
```

`/etc/placement/placement.conf` :

```ini
[placement_database]
connection = mysql+pymysql://placement:PLACEMENT_DBPASS@controller/placement

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = PLACEMENT_PASS
```

Sync DB Placement :

```bash
sudo su -s /bin/sh -c "placement-manage db sync" placement
sudo systemctl restart apache2
```

Test :

```bash
placement-status upgrade check
```

### 5.4. Installation Nova (controller)

```bash
sudo apt -y install nova-api nova-conductor nova-novncproxy nova-scheduler
```

`/etc/nova/nova.conf` (principales sections) :

```ini
[DEFAULT]
my_ip = 192.168.56.10
transport_url = rabbit://openstack:RABBIT_PASS@controller
use_neutron = True
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api_database]
connection = mysql+pymysql://nova:NOVA_DBPASS@controller/nova_api

[database]
connection = mysql+pymysql://nova:NOVA_DBPASS@controller/nova

[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVA_PASS

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = 192.168.56.10
novncproxy_base_url = http://controller:6080/vnc_auto.html

[glance]
api_servers = http://controller:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = PLACEMENT_PASS
```

### 5.5. Sync DB & cells

```bash
sudo su -s /bin/sh -c "nova-manage api_db sync" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1" nova
sudo su -s /bin/sh -c "nova-manage db sync" nova
```

vérifier que cela est bien installé : 
sudo apt -y install qemu-kvm libvirt-daemon-system libvirt-clients
sudo systemctl enable --now libvirtd
sudo systemctl status libvirtd


Redémarre les services :

```bash
sudo systemctl restart nova-api nova-scheduler nova-conductor nova-novncproxy
```

### 5.6. Installation Nova compute (sur le même nœud)

```bash
sudo apt -y install nova-compute
```

Dans `/etc/nova/nova.conf`, s’assurer que `my_ip = 192.168.56.10` (même fichier que plus haut).

Dans `/etc/nova/nova-compute.conf` :

```ini
[libvirt]
virt_type = qemu   # recommandé dans VirtualBox (pas de nested virt)
```

Puis :

```bash
sudo systemctl restart nova-compute
```

### 5.7. Tests Nova

```bash
source /root/admin-openrc.sh
openstack compute service list
openstack hypervisor list
```

Tu dois voir `nova-compute` UP et 1 hyperviseur.

---

## 6. Neutron (réseau provider simple sur enp0s8)

On va faire **un seul réseau provider flat** sur `enp0s8`, déjà en `192.168.56.0/24`.

### 6.1. DB, utilisateur, service Neutron

```bash
sudo mysql -uroot -p <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'NEUTRON_DBPASS';
FLUSH PRIVILEGES;
EOF
```

```bash
source /root/admin-openrc.sh

openstack user create --domain default --password NEUTRON_PASS neutron
openstack role add --project service --user neutron admin

openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public   http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin    http://controller:9696
```

### 6.2. Installation Neutron

```bash
sudo apt -y install neutron-server neutron-plugin-ml2 \
  neutron-linuxbridge-agent neutron-dhcp-agent \
  neutron-metadata-agent neutron-l3-agent
```

### 6.3. Config `/etc/neutron/neutron.conf`

```ini
[DEFAULT]
core_plugin = ml2
service_plugins = router
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[database]
connection = mysql+pymysql://neutron:NEUTRON_DBPASS@controller/neutron

[experimental]
linuxbridge = true
ipv6_pd_enabled = false

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = neutron
password = NEUTRON_PASS

[nova]
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = nova
password = NOVA_PASS
```

### 6.4. ML2 : `/etc/neutron/plugins/ml2/ml2_conf.ini`

```ini
[ml2]
type_drivers = flat,vlan
tenant_network_types =
mechanism_drivers = linuxbridge
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[securitygroup]
enable_ipset = true
```

### 6.5. Linuxbridge agent : `/etc/neutron/plugins/ml2/linuxbridge_agent.ini`

```ini
[linux_bridge]
physical_interface_mappings = provider:enp0s8

[vxlan]
enable_vxlan = false

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
```

### 6.6. L3 / DHCP / metadata

`/etc/neutron/l3_agent.ini` :

```ini
[DEFAULT]
interface_driver = linuxbridge
external_network_bridge =
agent_mode = legacy
allow_automatic_l3agent_failover = false
verbose = true
debug = false
```

`/etc/neutron/dhcp_agent.ini` :

```ini
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
```

`/etc/neutron/metadata_agent.ini` :

```ini
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = METADATA_SECRET
```

Dans `/etc/nova/nova.conf`, ajoute :

```ini
[neutron]
url = http://controller:9696
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRON_PASS
service_metadata_proxy = true
metadata_proxy_shared_secret = METADATA_SECRET
```

### 6.7. sysctl réseau pour Neutron

```bash
sudo tee -a /etc/sysctl.conf >/dev/null <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

sudo modprobe br_netfilter
sudo sysctl -p
```

### 6.8. DB sync et restart

```bash
sudo su -s /bin/sh -c "neutron-db-manage upgrade head" neutron

sudo systemctl restart nova-api
sudo systemctl restart neutron-server neutron-linuxbridge-agent \
  neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent
```

### 6.9. Tests Neutron

```bash
source /root/admin-openrc.sh
openstack network agent list
```

Tu dois voir les agents L3, DHCP, Linuxbridge, Metadata en `alive`.

Crée un réseau provider :

```bash
openstack network create provider \
  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat

openstack subnet create provider-subnet \
  --network provider \
  --subnet-range 192.168.56.0/24 \
  --allocation-pool start=192.168.56.100,end=192.168.56.200 \
  --gateway 192.168.56.1 \
  --dns-nameserver 8.8.8.8
```

---

## 7. Horizon (dashboard)

```bash
sudo apt -y install openstack-dashboard
```

Fichier `/etc/openstack-dashboard/local_settings.py` :

* `OPENSTACK_HOST = "controller"`
* `ALLOWED_HOSTS = ['*']`
* `TIME_ZONE = 'Europe/Paris'`

Redémarre :

```bash
sudo systemctl restart apache2
sudo systemctl restart memcached
```

### Test Horizon

Depuis ta machine hôte, dans le navigateur :

`http://192.168.56.10/horizon`

→ Login : `admin` / `ADMIN_PASS`

---

SI ça marche pas : **PARFAIT !** J'ai trouvé le problème ! 

L'erreur est claire :
```
OfflineGenerationError: You have offline compression enabled but key "..." is missing from offline manifest. 
You may need to run "python manage.py compress".
```

## Solution

```bash
cd /usr/share/openstack-dashboard

# Régénérer les fichiers statiques compressés
sudo python3 manage.py collectstatic --noinput
sudo python3 manage.py compress --force

# Corriger les permissions
sudo chown -R horizon:horizon /var/lib/openstack-dashboard/

# Redémarrer Apache
sudo systemctl restart apache2
```

Maintenant, **teste Horizon dans ton navigateur** : http://192.168.56.10/horizon



---

## 8. (Optionnel) Cinder (stockage bloc LVM)

### 8.1. Volume LVM

```bash
sudo fallocate -l 20G /var/lib/cinder.img
sudo losetup /dev/loop2 /var/lib/cinder.img
sudo pvcreate /dev/loop2
sudo vgcreate cinder-volumes /dev/loop2
```

### 8.2. DB, utilisateur, service Cinder

```bash
sudo mysql -uroot -p <<EOF
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'CINDER_DBPASS';
FLUSH PRIVILEGES;
EOF
```

```bash
source /root/admin-openrc.sh

openstack user create --domain default --password CINDER_PASS cinder
openstack role add --project service --user cinder admin

openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack endpoint create --region RegionOne volumev2 public   http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 admin    http://controller:8776/v2/%\(project_id\)s
```

### 8.3. Installation Cinder

```bash
sudo apt -y install cinder-api cinder-scheduler cinder-volume
```

`/etc/cinder/cinder.conf` :

```ini
[database]
connection = mysql+pymysql://cinder:CINDER_DBPASS@controller/cinder

[DEFAULT]
transport_url = rabbit://openstack:RABBIT_PASS@controller
auth_strategy = keystone
my_ip = 192.168.56.10
enabled_backends = lvm
glance_api_servers = http://controller:9292

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = cinder
password = CINDER_PASS

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
volumes_dir = /var/lib/cinder/volumes

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
```

Sync DB :

```bash
sudo su -s /bin/sh -c "cinder-manage db sync" cinder
sudo systemctl restart cinder-scheduler cinder-volume cinder-api
```

Dans `/etc/nova/nova.conf` ajoute :

```ini
[cinder]
os_region_name = RegionOne
```

Restart `nova-api` :

```bash
sudo systemctl restart nova-api
```

### Tests Cinder

```bash
source /root/admin-openrc.sh
openstack volume service list

openstack volume create --size 1 test-volume
openstack volume list
```

---

## 9. Test final : lancer une VM depuis la ligne de commande

1. Créer un flavor :

```bash
openstack flavor create --id 1 --vcpus 1 --ram 512 --disk 5 m1.tiny
```

2. Clé SSH :

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_openstack
openstack keypair create --public-key ~/.ssh/id_rsa_openstack.pub mykey
```

3. Règles de sécurité :

```bash
openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default
```

4. Lancer une instance sur le réseau `provider` :

```bash
openstack server create --flavor m1.tiny \
  --image cirros \
  --nic net-id=$(openstack network show provider -f value -c id) \
  --security-group default \
  --key-name mykey \
  test-vm
```

5. Vérifier :

```bash
openstack server list
```

Quand la VM est en `ACTIVE`, récupère son IP dans `192.168.56.x` (pool 100–200) et depuis la machine hôte :

```bash
ping IP_DE_LA_VM
```


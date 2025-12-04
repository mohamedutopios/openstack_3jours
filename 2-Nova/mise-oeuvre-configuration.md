# 1) Pré-requis

* OS supporté : Ubuntu 22.04 LTS (ou Rocky/Alma 9, Debian 12).
* Paquets : `nova-api`, `nova-conductor`, `nova-scheduler`, `nova-novncproxy` (contrôleur), `nova-compute` (compute).
* Services déjà installés :

  * **Keystone** (auth)
  * **Glance** (images)
  * **Neutron** (réseau)
  * **Placement** (capacité → indispensable depuis Pike)
  * **RabbitMQ** (MQ)
  * **MariaDB/MySQL** (DB API + DB cell)

---

# 2) Installation des paquets (Ubuntu 22.04)

Sur **contrôleur** :

```bash
sudo apt update
sudo apt install nova-api nova-conductor nova-scheduler nova-novncproxy
```

Sur **compute** :

```bash
sudo apt update
sudo apt install nova-compute
```

---

# 3) Configuration (`/etc/nova/nova.conf`)

### Contrôleur

```ini
[DEFAULT]
transport_url = rabbit://openstack:RABBITPASS@controller
my_ip = 10.0.0.11
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
enabled_apis = osapi_compute,metadata

[api_database]
connection = mysql+pymysql://nova:NOVAPASS@controller/nova_api

[database]
connection = mysql+pymysql://nova:NOVAPASS@controller/nova

[keystone_authtoken]
auth_url = http://controller:5000/v3
www_authenticate_uri = http://controller:5000/v3
memcached_servers = controller:11211
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVASERVICEPASS
auth_type = password

[glance]
api_servers = http://controller:9292

[placement]
auth_url = http://controller:5000/v3
project_name = service
username = placement
password = PLACEMENTPASS
user_domain_name = Default
project_domain_name = Default
region_name = RegionOne
auth_type = password

[neutron]
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = NEUTRONPASS
service_metadata_proxy = true
metadata_proxy_shared_secret = METADATASECRET

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html

[libvirt]
virt_type = kvm
```

### Compute node

```ini
[DEFAULT]
transport_url = rabbit://openstack:RABBITPASS@controller
my_ip = 10.0.0.31
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api_database]
connection = mysql+pymysql://nova:NOVAPASS@controller/nova_api

[database]
connection = mysql+pymysql://nova:NOVAPASS@controller/nova

[keystone_authtoken]
auth_url = http://controller:5000/v3
www_authenticate_uri = http://controller:5000/v3
memcached_servers = controller:11211
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = NOVASERVICEPASS
auth_type = password

[glance]
api_servers = http://controller:9292

[placement]
auth_url = http://controller:5000/v3
project_name = service
username = placement
password = PLACEMENTPASS
user_domain_name = Default
project_domain_name = Default
region_name = RegionOne
auth_type = password

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip

[libvirt]
virt_type = kvm
```

---

# 4) Base de données & Cells v2

Sur le contrôleur :

```bash
# Initialiser DB
sudo su -s /bin/sh -c "nova-manage api_db sync" nova
sudo su -s /bin/sh -c "nova-manage db sync" nova

# Mapper cell0 et créer cell1
sudo su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
sudo su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
```

---

# 5) Démarrage des services

```bash
sudo systemctl enable --now nova-api nova-scheduler nova-conductor nova-novncproxy
sudo systemctl enable --now nova-compute
```

---

# 6) Vérifications

```bash
# Vérifier services
openstack compute service list

# Découverte des hôtes compute
sudo su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova

# Vérifier hyperviseurs
openstack hypervisor list

# Vérifier état global
nova-status upgrade check
```

---

# 7) Mise en œuvre pratique (lab)

* **VM VirtualBox Ubuntu 22.04**

  * NIC1 : NAT (Internet)
  * NIC2 : Host-Only (gestion interne OpenStack)
  * NIC3 : Optionnel (provider/externe pour Floating IP)
* **Contrôleur** : installe Nova API, scheduler, conductor, novncproxy.
* **Compute** : installe Nova Compute, configure libvirt/KVM.
* **Optionnel** : tu peux mettre tout en **AIO** (All-in-One).

---

# 8) Paramétrages avancés

* **Flavors** : `openstack flavor create m1.small --ram 2048 --disk 20 --vcpus 2`
* **AZ / agrégats** : `openstack aggregate create gpu_hosts --zone nova --property trait:CUSTOM_GPU=required`
* **Extra_specs** : pour NUMA, CPU pinning, hugepages, vGPU.
* **Server Groups** : affinité/anti-affinité.
* **Console** : noVNC activé ([http://controller:6080](http://controller:6080)).


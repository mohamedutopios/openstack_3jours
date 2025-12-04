# 🔹 Vue d’ensemble : Ubuntu 22.04 + VirtualBox

* Ta VM Ubuntu 22.04 aura **2 cartes réseau** :

  * **Carte 1 = NAT** → accès Internet pour apt/updates.
  * **Carte 2 = Host-only** → permet d’accéder à Horizon depuis ton PC hôte (ex. 192.168.56.x).

* On configure côté VM :

  * `enp0s3` = NAT (laisse DHCP)
  * `enp0s8` = Host-only (sera utilisé pour `br-ex`)
  * `br-mgmt` = réseau de gestion interne OSA (`172.29.236.0/22`)
  * `br-vxlan` = overlay OVN Geneve (`172.29.240.0/22`)
  * `br-ex` = branché sur `enp0s8` → donnera accès aux Floating IP depuis ton PC hôte

👉 Contrairement au provider cloud, ici **on peut brancher `br-ex` à une vraie interface** (`enp0s8`), donc les Floating IP seront **accessibles depuis ton PC** via le réseau Host-only VirtualBox.

---

# 1) Pré-requis système

```bash
sudo apt update && sudo apt -y dist-upgrade
sudo apt install -y git python3-venv python3-pip python3-dev \
  libffi-dev libssl-dev gcc bridge-utils lvm2 thin-provisioning-tools chrony \
  openvswitch-switch
```

---

# 2) Réseau hôte (Netplan)

## 2.1 Vérifier les interfaces

```bash
ip a
```

Tu devrais voir :

* `enp0s3` (NAT, IP genre 10.0.2.x)
* `enp0s8` (Host-only, pas encore configurée)

## 2.2 Configurer Netplan

On crée `/etc/netplan/01-osa.yaml` :

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s3:
      dhcp4: true   # NAT, laisse DHCP
    enp0s8:
      dhcp4: no

  bridges:
    br-mgmt:
      dhcp4: no
      addresses: [172.29.236.10/22]

    br-vxlan:
      dhcp4: no
      addresses: [172.29.240.1/22]

    br-ex:
      interfaces: [enp0s8]
      dhcp4: no
      addresses: [192.168.56.10/24]
      gateway4: 192.168.56.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

Appliquer :

```bash
sudo chmod 600 /etc/netplan/01-osa.yaml
sudo netplan apply
```

Vérifier :

```bash
ip a show br-mgmt
ip a show br-vxlan
ip a show br-ex
```

👉 Ici :

* `br-ex` est sur le **réseau Host-only VirtualBox (192.168.56.0/24)**
* Tu pourras accéder à Horizon depuis ton PC : `http://192.168.56.10/horizon`

---

# 3) Récupérer OpenStack-Ansible (OSA 2025.1 Epoxy)

```bash
cd /opt
sudo git clone https://opendev.org/openstack/openstack-ansible
cd openstack-ansible

# Choisir le dernier tag stable 31.x (Epoxy)
git tag -l | grep '^31\.' | sort -V | tail -n1
git checkout <dernier-tag>
```

Bootstrap :

```bash
sudo scripts/bootstrap-ansible.sh
sudo scripts/bootstrap-aio.sh
```

---

# 4) Inventaire OSA

`/etc/openstack_deploy/openstack_user_config.yml` :

```yaml
---
cidr_networks:
  container: 172.29.236.0/22
  tunnel:    172.29.240.0/22
  storage:   172.29.244.0/22

global_overrides:
  internal_lb_vip_address: 172.29.236.10
  external_lb_vip_address: 192.168.56.10   # IP de br-ex
  management_bridge: "br-mgmt"
  tunnel_bridge:     "br-vxlan"

shared-infra_hosts:
  aio1: { ip: 172.29.236.11 }

identity_hosts:
  aio1: { ip: 172.29.236.11 }

network_hosts:
  aio1: { ip: 172.29.236.11 }

compute_hosts:
  aio1:
    ip: 172.29.236.11
    container_vars:
      nova_compute_virt_type: "qemu"   # VirtualBox ne supporte pas KVM imbriqué

haproxy_hosts:
  aio1: { ip: 172.29.236.11 }

network-northd_hosts:
  aio1: { ip: 172.29.236.11 }

network-gateway_hosts:
  aio1: { ip: 172.29.236.11 }
```

---

# 5) Variables Neutron/OVN

`/etc/openstack_deploy/user_variables.yml` :

```yaml
neutron_plugin_type: ml2.ovn
neutron_plugin_base:
  - ovn-router
neutron_ml2_drivers_type: "vlan,local,geneve,flat"

neutron_provider_networks:
  network_types: "geneve"
  network_geneve_ranges: "1:1000"
  network_mappings: "physnet1:br-ex"
```

---

# 6) Secrets

```bash
cd /opt/openstack-ansible
sudo scripts/pw-token-gen.py --file /etc/openstack_deploy/user_secrets.yml
```

---

# 7) Déploiement

```bash
cd /opt/openstack-ansible
sudo openstack-ansible setup-hosts.yml
sudo openstack-ansible setup-infrastructure.yml
sudo openstack-ansible setup-openstack.yml
```

---

# 8) Test réseau

Dans le conteneur utility :

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc
  curl -L -o /root/cirros.img http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
  openstack image create cirros --file /root/cirros.img \
    --disk-format qcow2 --container-format bare --public
'
```

Créer réseaux :

```bash
openstack network create --share --external \
  --provider-physical-network physnet1 \
  --provider-network-type flat public

openstack subnet create --network public \
  --subnet-range 192.168.56.0/24 --gateway 192.168.56.1 \
  --dns-nameserver 8.8.8.8 --allocation-pool start=192.168.56.100,end=192.168.56.200 \
  public-subnet

openstack network create private
openstack subnet create --network private --subnet-range 10.0.0.0/24 private-subnet

openstack router create r1
openstack router set r1 --external-gateway public
openstack router add subnet r1 private-subnet
```

Lancer VM :

```bash
openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny
openstack server create --flavor m1.tiny --image cirros --network private vm1
FIP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip vm1 $FIP
echo "Floating IP = $FIP"
```

---

# 9) Horizon

Accède depuis ton PC :
👉 `http://192.168.56.10/horizon`



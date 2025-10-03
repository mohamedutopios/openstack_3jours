# 🎯 1. À quoi sert `globals.yml` ?

* C’est le fichier **principal de configuration utilisateur** dans **Kolla-Ansible**.
* Il sert à **surcharger les valeurs par défaut** fournies par Kolla (dans `ansible/group_vars/all.yml`).
* C’est **là que tu définis ton architecture OpenStack** :

  * OS de base (Ubuntu, CentOS, Rocky…).
  * Version OpenStack (Yoga, Zed, 2025.1…).
  * Adresse(s) IP (VIP interne/externe, interfaces réseau).
  * Backend de stockage (Ceph, LVM, dir).
  * Backend de messagerie (RabbitMQ, etcd…).
  * Activation/désactivation des services.
  * Type de réseau (OVN, OVS, VXLAN, VLAN…).
  * Options spécifiques (Horizon, TLS, HAProxy, etc.).

👉 **En résumé** : `globals.yml` dicte la "personnalité" de ton cloud OpenStack déployé avec Kolla.

---

# 🧩 2. Composition globale de `globals.yml`

Voici les **grandes sections** typiques :

### 🔹 **Paramètres généraux**

```yaml
kolla_base_distro: "ubuntu"          # OS de base pour les conteneurs
kolla_install_type: "binary"         # binary ou source
openstack_release: "2025.1"          # version d’OpenStack
```

### 🔹 **Adresses IP & Réseau**

```yaml
kolla_internal_vip_address: "9.11.93.4"   # IP virtuelle interne (API internes)
kolla_external_vip_address: "9.12.93.4"   # IP externe (Horizon, API exposées)

network_interface: "eth0"                 # interface mgmt
neutron_external_interface: "eth1"        # interface réseau externe
```

### 🔹 **Services OpenStack**

```yaml
enable_horizon: "yes"
enable_cinder: "yes"
enable_swift: "no"
enable_heat: "yes"
enable_magnum: "no"
```

### 🔹 **Backends de stockage**

```yaml
glance_backend_file: "yes"
glance_backend_ceph: "no"

cinder_backend_lvm: "yes"
cinder_backend_ceph: "no"
```

### 🔹 **Messagerie & BDD**

```yaml
database_type: "mariadb"
messaging_service: "rabbitmq"
```

### 🔹 **Réseau (Neutron)**

```yaml
neutron_plugin_agent: "openvswitch"   # ou "ovn"
```

### 🔹 **Sécurité & TLS**

```yaml
kolla_enable_tls_internal: "no"
kolla_enable_tls_external: "no"
```

### 🔹 **Divers**

```yaml
enable_prometheus: "no"
enable_grafana: "no"
```

---

# 📌 3. Exemple minimal (Ubuntu + KVM + Neutron OVS)

```yaml
kolla_base_distro: "ubuntu"
kolla_install_type: "binary"
openstack_release: "2025.1"

kolla_internal_vip_address: "9.11.93.4"
kolla_external_vip_address: "9.12.93.4"

network_interface: "enp0s3"
neutron_external_interface: "enp0s8"

enable_cinder: "yes"
enable_horizon: "yes"
enable_heat: "yes"

glance_backend_file: "yes"
cinder_backend_lvm: "yes"

neutron_plugin_agent: "openvswitch"
```

---

# 🗂 4. Où il se situe et comment il est utilisé ?

* Localisation : `etc/kolla/globals.yml` (copié depuis `/usr/share/kolla-ansible/etc_examples/kolla/globals.yml`).
* Utilisation :

  1. Tu modifies `globals.yml` selon ton environnement.
  2. `kolla-ansible genconfig` lit ce fichier + les defaults.
  3. Il génère les **templates Jinja2** des services (nova.conf, neutron.conf…).
  4. Puis `kolla-ansible deploy` déploie avec Docker.


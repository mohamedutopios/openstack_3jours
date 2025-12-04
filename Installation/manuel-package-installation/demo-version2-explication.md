## 0. Topologie VirtualBox + netplan

### 🎯 Objectif

* Avoir une **VM unique** qui joue :

  * **controller** (Keystone, Glance, Nova-api, Neutron-server, Horizon…)
  * **compute** (nova-compute, libvirt, KVM/QEMU)
* Dans **VirtualBox**, donc **pas de vrai réseau physique** → on simule tout.

### 🔧 Ce qu’on met en place

* **Carte 1 – NAT (`enp0s3`)**
  Sert uniquement à **sortir sur Internet** : `apt`, `wget`, etc.
  → IP automatique via DHCP (ex : `10.0.2.15`)

* **Carte 2 – Host-only (`enp0s8`)**
  C’est le **vrai réseau OpenStack** :

  * IP de management : `192.168.56.10`
  * API OpenStack accessibles depuis ta machine hôte
  * Réseau provider pour les VMs (les instances auront des IP dans `192.168.56.0/24`)

Dans Netplan :

* `enp0s3` en DHCP → route par défaut vers Internet
* `enp0s8` IP fixe `192.168.56.10/24` → pas de route par défaut, juste du L2 / L3 local

### 🤔 Pourquoi ?

* **NAT** : tu n’as rien à configurer, ça marche partout.
* **Host-only** : ta machine hôte et ta VM OpenStack sont dans le **même LAN virtuel** :

  * tu accèdes à Horizon via `http://192.168.56.10/horizon`
  * tu ping et SSH sur les VMs Cirros depuis ton laptop.

---

## 1. Préparation OS + dépôts OpenStack

### 🔧 Ce qu’on fait

1. `apt update && upgrade` → OS à jour.
2. `hostnamectl set-hostname controller` + `/etc/hosts` :

   * résoudre `controller` → `192.168.56.10`
3. NTP (`chrony`) → éviter les problèmes de tokens / horodatage.
4. Ajout du **cloud-archive:caracal** → paquets OpenStack 2024.1.
5. Installation du `python3-openstackclient`.

### 🤔 Pourquoi ?

* OpenStack est **très sensible à la résolution DNS/hostname**.
  Tous les fichiers sont bourrés de `controller` → il faut que ça résolve vers l’IP mgmt.
* Si l’heure dérive → keystone refuse des tokens (problèmes de TTL).
* cloud-archive = paquets OpenStack **supportés par Canonical**, pas une PPA obscure.
* `openstackclient` = ton **couteau suisse** : tu testes chaque brique avec ça.

---

## 2. Services de base : MariaDB, RabbitMQ, Memcached, etcd

> Tous les services OpenStack ont besoin de **stockage**, de **messagerie** et souvent de **cache**.

### 🔧 MariaDB

* Fichier `99-openstack.cnf` :

  * `bind-address = 192.168.56.10` → écoute sur l’IP management
  * `innodb_file_per_table`, `utf8` → tuning classique OpenStack
  * `max_connections` augmenté → beaucoup de services se connectent.

👉 **Rôle** : toutes les bases (`keystone`, `glance`, `nova`, `neutron`, `cinder`, …) y vivent.

### 🔧 RabbitMQ

* Création de l’utilisateur `openstack` avec un mot de passe (`RABBIT_PASS`).
* Tous les services (Nova, Neutron, Cinder…) s’y connectent via `transport_url = rabbit://...`.

👉 **Rôle** : bus de messages, coordination asynchrone (RPC, événements).

### 🔧 Memcached

* Écoute sur `192.168.56.10`.
* Utilisé par Keystone et Horizon pour **mettre en cache les tokens et sessions**.

👉 **Rôle** : performance → éviter de taper la DB en permanence.

### 🔧 etcd

* Store clé/valeur distribué.
* Utilisé par Nova/Neutron entre autres pour le **locking, coordination, metadata** moderne.

👉 **Rôle** : remplacer certains usages de DB pour la coordination.

---

## 3. Keystone (Identity) + Apache/WSGI

### 🎯 Objectif

Avoir un **service d’identité central** qui gère :

* utilisateurs
* projets
* rôles
* tokens d’authentification

### 🔧 Ce qu’on met en place

1. **DB `keystone`** dans MariaDB.
2. Paquets `keystone`, `apache2`, `libapache2-mod-wsgi-py3`.
3. `keystone.conf` :

   * `[database]` → URL MySQL
   * `[token] provider = fernet` → tokens chiffrés symétriquement
4. `keystone-manage db_sync`, `fernet_setup`, `credential_setup` :

   * création des tables
   * génération des secrets pour chiffrer les tokens
5. `keystone-manage bootstrap` :

   * création de l’**admin**, du **tenant admin**, de la région, des endpoints par défaut.
6. VirtualHost Apache sur **port 5000** :

   * `WSGIScriptAlias / /usr/bin/keystone-wsgi-public`
   * Apache joue le rôle de **front HTTP** pour Keystone.

### 🤔 Pourquoi Apache + WSGI ?

Historiquement :

* Keystone est une app Python WSGI.
* Apache gère :

  * les workers,
  * la montée en charge,
  * les logs HTTP,
  * la TLS potentielle.

Aujourd’hui certains services OpenStack utilisent `uwsgi` ou des api-servers propres, mais Keystone en APT sur Ubuntu reste sous Apache.

### 💡 Résultat

Tu peux faire :

```bash
source admin-openrc.sh
openstack token issue
openstack user list
```

→ tu as une **PKI d’auth centralisée** pour tout le cloud.

---

## 4. Glance (Image Service)

### 🎯 Objectif

Avoir un dépôt d’images (QCOW2, RAW…) que Nova utilisera pour créer les disques des instances.

### 🔧 Ce qu’on met en place

1. DB `glance`.
2. Utilisateur `glance` + projet `service` + rôle `admin` pour ce service.
3. Service `image` + endpoints (public/internal/admin sur port **9292**).
4. `glance-api.conf` :

   * `[database]` → URL SQL
   * `[keystone_authtoken]` → comment Glance parle à Keystone
   * `[glance_store]` → `stores=file`, répertoire `/var/lib/glance/images/`
5. `glance-manage db_sync` → création des tables.

Puis on **uploade une image Cirros** pour tester.

### 🤔 Pourquoi file backend ?

* Simple.
* Suffisant pour un lab AIO.
* En prod tu utiliserais Swift, Ceph RBD ou autre.

---

## 5. Nova + Placement (Compute)

### 🎯 Objectif

* **Nova** = gestion des instances (VM), planification, lifecycle.
* **Placement** = inventaire des ressources (vCPU, RAM, disque) et scheduling plus fin.

### 🔧 Ce qu’on met en place

1. DBs :

   * `nova_api`, `nova`, `nova_cell0`, `placement`
   * c’est important pour la notion de **cells v2** (scalabilité horizontale).

2. Utilisateurs `nova` et `placement` + services + endpoints.

3. `placement-api` + Apache (port 8778) avec DB propre :

   * gère la **description des ressources** et des allocations.

4. Installation des services Nova côté controller :

   * `nova-api`, `nova-scheduler`, `nova-novncproxy`, `nova-conductor`

5. Fichier **central** `/etc/nova/nova.conf` :

   * `[DEFAULT] my_ip = 192.168.56.10` → IP mgmt
   * `transport_url` → RabbitMQ
   * `use_neutron = True` → réseau géré par Neutron
   * `[api_database]` / `[database]` → DBs Nova
   * `[keystone_authtoken]` → authentification vers Keystone
   * `[vnc]` :

     * `server_listen = 0.0.0.0`
     * `novncproxy_base_url = http://controller:6080/vnc_auto.html`
       → pour accéder à la console graphique des VMs depuis Horizon
   * `[glance]` → URL du service image
   * `[placement]` → comment Nova parle à Placement

6. **Cells v2** :

```bash
nova-manage api_db sync
nova-manage cell_v2 map_cell0
nova-manage cell_v2 create_cell --name=cell1
nova-manage db_sync
```

➡ ça prépare Nova à gérer potentiellement **plusieurs groupes de compute nodes** (cells).

7. Installation côté **compute** (même nœud dans AIO) :

   * `nova-compute`
   * `nova-compute.conf` → `[libvirt] virt_type = qemu`

### 🤔 Pourquoi `virt_type = qemu` ?

* Tu es dans une VM VirtualBox → **pas de virtualisation imbriquée (nested)** fiable.
* KVM ne marche pas bien (ou pas du tout).
* `qemu` = full virtualisation software : plus lent, mais ça fonctionne partout.

### 🔎 Résultat

Avec `openstack compute service list` + `openstack hypervisor list` :

* tu vois ton hyperviseur (`controller`) déclaré
* `nova-compute` UP
  → tu peux lancer des VMs.

---

## 6. Neutron (réseau) + sysctl

### 🎯 Objectif

Fournir :

* des réseaux L2/L3
* des IPs pour les instances
* du DHCP, du NAT éventuel
* de la sécurité (Security Groups)

Dans ta recette : **un réseau provider flat** sur `enp0s8`.

### 🔧 Ce qu’on met en place

1. DB `neutron`, utilisateur `neutron`, service + endpoints.

2. Services installés :

   * `neutron-server` (API Neutron)
   * `neutron-plugin-ml2` (framework de plugins)
   * `neutron-linuxbridge-agent` (L2)
   * `neutron-dhcp-agent`
   * `neutron-metadata-agent`
   * `neutron-l3-agent` (routing/NAT)

3. `neutron.conf` :

   * `[DEFAULT]` :

     * `core_plugin = ml2` → abstraction réseau
     * `service_plugins = router` → support L3
     * `transport_url` → RabbitMQ
     * `notify_nova_on_*` → synchro ports / instances
   * `[database]` → DB Neutron
   * `[keystone_authtoken]` → auth
   * `[nova]` → interaction pour la gestion de ports attachés aux VMs

4. ML2 (`ml2_conf.ini`) :

   * `type_drivers = flat,vlan`
   * `tenant_network_types =` (vide → on ne gère que provider)
   * `mechanism_drivers = linuxbridge`
   * `flat_networks = provider`
     → tu dis : *il existe une “physnet” appelée provider, en type flat.*

5. Linuxbridge (`linuxbridge_agent.ini`) :

   * `physical_interface_mappings = provider:enp0s8`
     → physiquement, la physnet `provider` correspond à ta NIC `enp0s8`.

6. L3 / DHCP / metadata : configuration standard.

7. Côté Nova (`nova.conf`, section `[neutron]`) :

   * Nova sait où est l’API Neutron, avec quels credentials.
   * `service_metadata_proxy` + `metadata_proxy_shared_secret` :
     → permet aux VMs de parler au service `metadata` via Neutron.

### 🧠 sysctl pour Neutron

Tu ajoutes :

```bash
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
```

👉 **Pourquoi ?**

* `ip_forward=1` → autoriser le routage IP (sinon ton L3 agent ne route pas).
* `rp_filter=0` → éviter que le kernel considère certains paquets comme spoofés (important avec les bridges / virtualisation).
* `bridge-nf-call-iptables=1` → pour que les paquets qui passent dans les bridges Linux soient filtrés par iptables (Security Groups).

---

## 7. Horizon (Dashboard)

### 🎯 Objectif

Avoir une interface web graphique pour administrer ton cloud.

### 🔧 Ce qu’on met en place

* `openstack-dashboard` (Horizon)
* `local_settings.py` :

  * `OPENSTACK_HOST = "controller"` → parle au Keystone sur `controller:5000`
  * `ALLOWED_HOSTS = ['*']` → pour ne pas se faire bloquer
  * `TIME_ZONE = 'Europe/Paris'`

Horizon est un **projet Django** :

* sert les pages via Apache
* utilise Keystone pour authentification
* parle ensuite aux autres services (Nova, Neutron, Glance…).

---

## 8. Cinder (optionnel, stockage bloc LVM)

### 🎯 Objectif

Permettre de créer **des volumes bloc** (comme des disques supplémentaires) que :

* tu peux attacher aux instances
* tu peux snapshotter, détacher, réattacher…

### 🔧 Ce qu’on met en place

1. On simule un disque avec un `loop` :

   * fichier `/var/lib/cinder.img`
   * attaché à `/dev/loop2`
   * `pvcreate` + `vgcreate cinder-volumes`

2. DB `cinder`, utilisateur `cinder`, service, endpoints.

3. Installation `cinder-api`, `cinder-scheduler`, `cinder-volume`.

4. `cinder.conf` :

   * `[database]` → DB Cinder
   * `[DEFAULT]` :

     * `transport_url` → RabbitMQ
     * `enabled_backends = lvm`
     * `glance_api_servers = http://controller:9292`
   * `[lvm]` :

     * `volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver`
     * `volume_group = cinder-volumes`
   * `[oslo_concurrency] lock_path` → lock des opérations.

5. Intégration Nova :

   * section `[cinder] os_region_name = RegionOne` dans `nova.conf`.

### 🤔 Résultat

Tu peux :

```bash
openstack volume create --size 1 demo-volume
openstack volume list
```

Puis attacher ce volume à une VM.

---

## 9. Test de bout en bout : lancer une VM

Tout ce que tu as fait avant sert à ça 👇

1. **Flavor** (Nova) → décrit les ressources virtuelles.
2. **Image** (Glance) → disque de base.
3. **Network** (Neutron) → provider flat `192.168.56.0/24`.
4. **Keypair** (Nova + SSH) → accès à la VM.
5. **Security Groups** (Neutron) → autoriser ICMP + SSH.
6. `openstack server create` → Nova orchestre :

   * parle à Glance → télécharge l’image
   * réserve des ressources via Placement
   * demande à Neutron un port réseau
   * crée et boote la VM via libvirt/QEMU
   * publie les infos dans Keystone pour Horizon, etc.

Ensuite tu **ping** et tu **SSH** depuis ta machine hôte vers l’IP de la VM (dans le pool 192.168.56.100–200).



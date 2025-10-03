Excellent 🚀 tu veux un **lab clé en main** avec :

* Un **Vagrantfile** qui déploie ta VM Ubuntu (OpenStack AIO avec Kolla-Ansible).
* Le fichier **globals.yml** prêt à l’emploi avec Nova, Neutron, Cinder, Heat, Horizon, Swift.
* Les étapes précises pour créer les réseaux, lancer une VM Nova et y accéder depuis ton Windows.

Je vais tout te donner **complet, copiable-collable**.

---

# 1️⃣ Vagrantfile complet

👉 Ce fichier va créer une VM Ubuntu 22.04 avec deux interfaces réseau :

* `192.168.56.10` → **management** (API, Horizon).
* `bridged` → **provider** (Floating IPs accessibles depuis ton LAN Windows).

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "openstack-aio"

  # Interface management (API, Horizon, SSH depuis hôte)
  config.vm.network "private_network", ip: "192.168.56.10"

  # Interface provider (Floating IPs / external)
  config.vm.network "public_network", bridge: "Intel(R) Wi-Fi 6", auto_config: true

  config.vm.provider "virtualbox" do |vb|
    vb.name = "OpenStack-AIO"
    vb.memory = 16384
    vb.cpus = 6
  end

  # Préparation minimale (Docker + dépendances)
  config.vm.provision "shell", inline: <<-SHELL
    apt update && apt upgrade -y
    apt install -y python3-venv python3-pip git vim docker.io docker-compose ansible
    usermod -aG docker vagrant
  SHELL
end
```

> ⚠️ Adapte `bridge: "Intel(R) Wi-Fi 6"` avec **le nom de ta carte réseau Windows**.
> (`Get-NetAdapter` dans PowerShell pour voir le nom exact).

---

# 2️⃣ globals.yml complet

👉 Place-le dans `/etc/kolla/globals.yml` après avoir installé Kolla-Ansible.

```yaml
kolla_base_distro: "ubuntu"
kolla_install_type: "binary"
openstack_release: "2025.1"

# Réseaux
network_interface: "enp0s3"              # management (192.168.56.10)
neutron_external_interface: "enp0s8"     # provider (bridged)
kolla_internal_vip_address: "192.168.56.254"

# Services OpenStack
enable_horizon: "yes"
enable_neutron: "yes"
enable_nova: "yes"
enable_cinder: "yes"
enable_heat: "yes"
enable_swift: "yes"

# Swift configuration
swift_devices: "{{ node_config_directory }}/swift/devices"
swift_mount_check: false

# Enable monitoring (optionnel)
enable_prometheus: "no"
enable_grafana: "no"
```

> ⚠️ Vérifie bien avec `ip a` que `enp0s3` = carte privée (`192.168.56.10`) et `enp0s8` = bridged.

---

# 3️⃣ Déploiement OpenStack (rappel des commandes)

Depuis la VM Ubuntu :

```bash
# Activer venv
python3 -m venv /opt/kolla-venv
source /opt/kolla-venv/bin/activate

# Installer kolla-ansible
pip install -U pip wheel setuptools
pip install "kolla-ansible==16.0.0"

# Préparer conf
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one .

# Générer mots de passe
kolla-genpwd

# Bootstrap + pré-checks
kolla-ansible -i all-in-one bootstrap-servers
kolla-ansible -i all-in-one prechecks

# Déploiement complet
kolla-ansible -i all-in-one deploy

# Post-déploiement
kolla-ansible post-deploy
source /etc/kolla/admin-openrc.sh
```

---

# 4️⃣ Configuration réseaux dans OpenStack

Créer **réseau externe (public)** lié à `enp0s8` :

```bash
openstack network create --external --share \
  --provider-network-type flat \
  --provider-physical-network physnet1 public

openstack subnet create --network public \
  --allocation-pool start=192.168.1.200,end=192.168.1.220 \
  --dns-nameserver 8.8.8.8 \
  --gateway 192.168.1.1 \
  --subnet-range 192.168.1.0/24 public-subnet
```

👉 Ici :

* Le **pool d’IP flottantes** est `192.168.1.200-220` (doit être libre sur ton LAN).
* La **gateway** est ton routeur (`192.168.1.1`).

Créer **réseau privé + router** :

```bash
openstack network create private
openstack subnet create --network private \
  --subnet-range 10.0.0.0/24 private-subnet

openstack router create router1
openstack router add subnet router1 private-subnet
openstack router set router1 --external-gateway public
```

---

# 5️⃣ Déployer une VM Nova

1. Importer une image test (CirrOS) :

```bash
openstack image create "cirros" \
  --file /usr/share/cirros/cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 --container-format bare --public
```

2. Créer un flavor minimal :

```bash
openstack flavor create --ram 512 --disk 1 --vcpus 1 m1.tiny
```

3. Créer la VM :

```bash
openstack server create \
  --image cirros \
  --flavor m1.tiny \
  --nic net-id=$(openstack network show private -f value -c id) \
  test-vm
```

4. Associer une Floating IP :

```bash
openstack floating ip create public
openstack server add floating ip test-vm <FLOATING_IP>
```

---

# 6️⃣ Tester depuis Windows

👉 Depuis ton hôte Windows, tu peux directement ping/ssh sur la **Floating IP** :

```powershell
ssh cirros@192.168.1.200
```

(ou autre IP flottante attribuée).

Tu peux aussi ouvrir Horizon :

* URL : `http://192.168.56.254/`
* User : `admin`
* Pass : contenu de `/etc/kolla/passwords.yml` (`keystone_admin_password`).

---

# 📌 Résumé final

* **Vagrantfile** → crée une VM Ubuntu avec deux interfaces (mgmt + bridged).
* **globals.yml** → active Nova, Neutron, Cinder, Heat, Horizon, Swift.
* **Kolla-Ansible** → déploie OpenStack dans ta VM.
* **Neutron réseau public** → mappé sur ta carte bridgée → Floating IPs directement accessibles depuis Windows.
* Tu peux créer des VMs Nova et les joindre via SSH depuis ton hôte Windows.

---

👉 Veux-tu que je te prépare aussi un **script Bash automatisé** qui s’exécute directement dans ta VM (post-`vagrant up`) et qui installe Kolla-Ansible + configure globals.yml + déploie OpenStack en un seul run ?

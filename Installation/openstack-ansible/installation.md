Parfait — tu as déjà une VM « en ligne » avec une IP publique statique sur `enp3s0`.
Voici **toutes les étapes OpenStack-Ansible (OSA) adaptées à TON réseau**, avec **le “pourquoi” de chaque phase**. J’utilise la branche **2025.1 (Epoxy)** — c’est la série actuelle d’OSA et elle **supporte Ubuntu 24.04** en déploiement “source” ; OSA utilise **OVN (ml2.ovn)** par défaut depuis Antelope/Zed (LinuxBridge n’est plus supporté en 2025.1). ([docs.openstack.org][1])

---

# 0) Vue d’ensemble (ce que l’on déploie)

* **Type** : All-in-One (AIO) sur une seule VM (pour POC/lab).
  Pourquoi : plus simple, tout est sur 1 hôte (API, DB, RabbitMQ, Neutron, Nova, Horizon, etc.). ([docs.openstack.org][2])
* **Réseau OSA “référence”** :

  * `br-mgmt` (172.29.236.0/22) = réseau de gestion/containers
  * `br-vxlan` (172.29.240.0/22) = overlay (OVN → Geneve)
  * **br-ex (OVS)** relié à **ton** `enp3s0` = sortie Internet / réseau externe
    Pourquoi : OSA sépare proprement gestion/overlay/externe. En AIO, une seule NIC peut suffire (scénario “single interface”). ([docs.openstack.org][3])

---

# 1) Pré-requis & vérifs

```bash
# À jour
sudo apt update && sudo apt -y dist-upgrade

# Outils nécessaires
sudo apt install -y git python3-venv python3-pip python3-dev \
  libffi-dev libssl-dev gcc bridge-utils lvm2 thin-provisioning-tools chrony \
  openvswitch-switch
```

**Pourquoi**

* Paquets build/python/SSL → requis par les rôles Ansible et clients OpenStack.
* `openvswitch-switch` → OVS crée **br-ex** utilisé par **OVN** (driver par défaut). ([docs.openstack.org][4])

---

# 2) Réseau hôte (Netplan) — *sans perdre l’accès SSH*

Tu as aujourd’hui :

```yaml
# /etc/netplan/90-lv.yaml (existant)
network:
  version: 2
  ethernets:
    enp3s0:
      addresses: [209.182.239.240/24, 2602:ff16:6:10c9::1/48]
      gateway4: 209.182.239.1
      gateway6: 2602:ff16:6::1
      nameservers:
        addresses: [8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844]
      dhcp4: false
      dhcp6: false
```

On va :

1. **Créer `br-ex` (OVS)** et **y déplacer** tes adresses/gateways.
2. Créer des **bridges internes** `br-mgmt` et `br-vxlan` pour OSA.
3. Appliquer avec `netplan try` pour éviter toute coupure.

> ⚠️ Une interface **ne peut pas** être esclave de 2 bridges. On **attache** `enp3s0` à **`br-ex` (OVS)** et **on retire** l’IP d’`enp3s0` (on la met sur `br-ex`).

Crée un nouveau fichier (en laissant l’ancien pour rollback si besoin) :

```yaml
# /etc/netplan/01-osa.yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp3s0: {}   # deviendra un port d'OVS br-ex

  bridges:
    # Bridge externe OVS (sortie Internet + réseau externe OpenStack)
    br-ex:
      openvswitch: {}                 # <- OVS
      interfaces: [enp3s0]
      addresses:
        - 209.182.239.240/24
        - 2602:ff16:6:10c9::1/48
      gateway4: 209.182.239.1
      gateway6: 2602:ff16:6::1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4, 2001:4860:4860::8888, 2001:4860:4860::8844]

    # Bridges internes pour OSA (pas d'interface physique)
    br-mgmt:
      addresses: [172.29.236.10/22]
      dhcp4: no
    br-vxlan:
      addresses: [172.29.240.1/22]
      dhcp4: no
```

Appliquer **en sécurité** :

```bash
sudo netplan try     # valide avec Enter pour confirmer
sudo netplan apply
ip a | egrep 'br-ex|br-mgmt|br-vxlan|enp3s0'
ovs-vsctl show
```

**Pourquoi**

* `br-ex` portera l’IP publique → OVN s’en servira pour **SNAT/FIP** (egress) et exposer Horizon/API.
* `br-mgmt`/`br-vxlan` isolent gestion et overlay sur des plages OSA standard.
* `netplan try` évite de te verrouiller hors serveur. (Syntaxe OVS/Netplan telle que documentée.) ([Netplan][5])

---

# 3) Récupérer OSA (bonne branche/tag)

```bash
sudo mkdir -p /opt && cd /opt
sudo git clone https://opendev.org/openstack/openstack-ansible /opt/openstack-ansible
cd /opt/openstack-ansible

# Recommandé: déployer le dernier tag 31.x de la série 2025.1 (Epoxy)
git tag -l | grep '^31\.' | sort -V | tail -n1   # repère le dernier tag
git checkout <le-dernier-tag-31.x>
```

**Pourquoi**

* Le **Quickstart AIO** conseille d’utiliser un **tag** (plus stable) plutôt que la tête de branche. ([docs.openstack.org][2])
* **2025.1 (Epoxy)** est la série courante et supporte Ubuntu 24.04. ([docs.openstack.org][1])

---

# 4) Bootstrap d’Ansible & de l’AIO

```bash
# installe Ansible + rôles/collections pinées par OSA
sudo scripts/bootstrap-ansible.sh

# prépare l’hôte AIO (dossiers, sysctl, lxc, etc.)
sudo scripts/bootstrap-aio.sh
```

**Pourquoi**

* `bootstrap-ansible.sh` crée l’environnement Ansible conforme à OSA.
* `bootstrap-aio.sh` prépare l’hôte (réseaux/paquets/containers) pour un AIO. ([docs.openstack.org][2])

---

# 5) Inventaire OSA (layout des hôtes)

Édite `/etc/openstack_deploy/openstack_user_config.yml` :

```yaml
---
cidr_networks:
  container: 172.29.236.0/22
  tunnel:    172.29.240.0/22
  storage:   172.29.244.0/22    # optionnel ici (pas de Ceph)

global_overrides:
  internal_lb_vip_address: 172.29.236.10
  external_lb_vip_address: 209.182.239.240
  management_bridge: "br-mgmt"
  tunnel_bridge:     "br-vxlan"

# Groupes AIO: tout sur le même hôte
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
      # En VM "cloud", la virtualisation imbriquée peut être absente
      nova_compute_virt_type: "qemu"

haproxy_hosts:
  aio1: { ip: 172.29.236.11 }

# OVN: qui joue northd & gateway (en AIO, le même hôte)
network-northd_hosts:
  aio1: { ip: 172.29.236.11 }

network-gateway_hosts:
  aio1: { ip: 172.29.236.11 }
```

**Pourquoi**

* On **déclare les bridges** et les **VIP** interne/externe qu’utiliseront HAProxy et les services.
* On **indique** que cet hôte fait **northd** (base de données OVN) et **gateway chassis** (N/S routing, NAT/FIP). ([docs.openstack.org][4])

---

# 6) Variables Neutron/OVN & mappage externe

Crée `/etc/openstack_deploy/user_variables.yml` :

```yaml
# Activer OVN (par défaut depuis Zed, on explicite pour lisibilité)
neutron_plugin_type: ml2.ovn
neutron_plugin_base:
  - ovn-router
neutron_ml2_drivers_type: "vlan,local,geneve,flat"

# Définir le réseau "provider" externe via br-ex (OVS)
neutron_provider_networks:
  network_types: "geneve"
  network_geneve_ranges: "1:1000"
  network_mappings: "physnet1:br-ex"
  # network_interface_mappings optionnel si br-ex a déjà enp3s0 via netplan
  # network_interface_mappings: "br-ex:enp3s0"
```

**Pourquoi**

* On fige le **backend OVN** (génére logique overlay **Geneve**).
* On mappe **physnet1 → br-ex** pour que les réseaux **externes/Provider** utilisent ta carte publique via OVS. (LinuxBridge est retiré en 2025.1.) ([docs.openstack.org][4])

---

# 7) Secrets / mots de passe

```bash
cd /opt/openstack-ansible
sudo scripts/pw-token-gen.py --file /etc/openstack_deploy/user_secrets.yml
```

**Pourquoi**

* Génère tous les passwords/keys (Keystone admin, DB, RabbitMQ, etc.) de manière sûre.

---

# 8) Lancer les playbooks

```bash
cd /opt/openstack-ansible
sudo openstack-ansible setup-hosts.yml
sudo openstack-ansible setup-infrastructure.yml
sudo openstack-ansible setup-openstack.yml
```

**Pourquoi**

* **setup-hosts** : prépare l’hôte et les conteneurs (LXC).
* **setup-infrastructure** : déploie Galera, RabbitMQ, Memcached, HAProxy, etc.
* **setup-openstack** : installe/configure Keystone, Glance, Nova, Neutron (OVN), Horizon.
* C’est exactement l’ordre recommandé par le **Quickstart AIO**. ([docs.openstack.org][2])

---

# 9) Vérifications de base

```bash
# Identifiants admin (dans le conteneur utility si besoin)
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc 'source /root/openrc && openstack token issue && openstack service list'
```

Accès Horizon :

* **[https://209.182.239.240/](https://209.182.239.240/)** (ou http si SSL désactivé).
* User: `admin`, mot de passe dans `/etc/openstack_deploy/user_secrets.yml`.
  **Pourquoi**
* En AIO, OSA expose Horizon en 443 (HTTPS auto-signé) par défaut. ([docs.openstack.org][2])

---

# 🔟 Créer les réseaux & tester une VM

> Sur de la VM “cloud”, **exposer directement** une VM sur ton /24 public peut être **bloqué par l’amont** (anti-spoofing MAC). Le chemin **le plus sûr** est d’utiliser un réseau privé (Geneve) + **Floating IP** (DNAT/SNAT via OVN).

1. **Image** de test (Cirros) :

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc
  curl -L -o /root/cirros.img http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
  openstack image create cirros --file /root/cirros.img --disk-format qcow2 --container-format bare --public
'
```

2. **Réseau privé** (overlay Geneve) + **routeur vers l’externe** (`public`) :

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc

  # Externe (provider=physnet1 via br-ex)
  openstack network create --share --external \
    --provider-physical-network physnet1 \
    --provider-network-type flat public

  openstack subnet create --network public --subnet-range 209.182.239.0/24 \
    --gateway 209.182.239.1 --dns-nameserver 8.8.8.8 \
    --allocation-pool start=209.182.239.200,end=209.182.239.230 \
    --no-dhcp public-subnet

  # Privé (Geneve par défaut avec OVN)
  openstack network create private
  openstack subnet create --network private --subnet-range 10.0.0.0/24 private-subnet

  # Routeur projet → NAT vers public
  openstack router create r1
  openstack router set r1 --external-gateway public
  openstack router add subnet r1 private-subnet
'
```

3. **Démarrer une instance + Floating IP** :

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc
  openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny || true
  openstack keypair create demo > /root/demo.pem && chmod 600 /root/demo.pem
  openstack server create --flavor m1.tiny --image cirros --network private vm1
  FIP=$(openstack floating ip create public -f value -c floating_ip_address)
  openstack server add floating ip vm1 $FIP
  echo "Floating IP: $FIP"
'
```

**Pourquoi**

* **public** = réseau **provider “flat”** sur **physnet1:br-ex** → sortie Internet.
* **private** = overlay **Geneve/OVN**. Le routeur **OVN** fait **SNAT/DNAT** via `br-ex`.
* **Floating IP** = le moyen le plus fiable d’exposer une VM depuis une VM “cloud”. ([docs.openstack.org][4])

---

# 11) Dépannage utile (OVN/OVS)

```bash
# État OVS/OVN
ovs-vsctl show
sudo systemctl --no-pager --type=service | egrep 'ovn|ovs'

# BDD OVN (côté northd)
lxc-attach -n $(lxc-ls -1 | grep "neutron_ovn_northd" || true) -- bash -lc 'ovn-sbctl show'

# L3/GW chassis (sur l’hôte gateway)
ip r
```

**Pourquoi**

* OVN ne crée pas d’“agents Neutron” classiques (LinuxBridge/OVS) → on vérifie **ovn-controller/northd** et la **bridge-mapping** `physnet1:br-ex`. ([docs.openstack.org][4])

---

## Notes & choix de conception (pourquoi on fait cela)

* **OVN par défaut** : plus moderne, stateless, remplaçant LinuxBridge/agents OVS. En **2025.1**, LinuxBridge est retiré. ([docs.openstack.org][4])
* **br-ex (OVS) connecté à enp3s0** : indispensable pour que le **gateway chassis OVN** fasse le NAT et publie les Floating IP. (On met l’IP publique **sur br-ex**, pas sur `enp3s0`.) ([docs.openvswitch.org][6])
* **Single-NIC** supporté : OSA documente le déploiement avec une seule interface (non-prod), ce qui est notre cas ici. ([docs.openstack.org][3])
* **Tag/branche** : le **Quickstart AIO** recommande d’utiliser un **tag** de la série visée pour la stabilité. ([docs.openstack.org][2])
* **Ubuntu 24.04 OK** pour **2025.1** : matrice de compatibilité OSA. ([docs.openstack.org][1])

---

Si tu veux, je peux te générer **les fichiers prêts à copier-coller** suivants :

* `/etc/netplan/01-osa.yaml` (tel qu’au-dessus)
* `/etc/openstack_deploy/openstack_user_config.yml`
* `/etc/openstack_deploy/user_variables.yml`

…ou bien ajuster le plan si tu **veux absolument attribuer des IP publiques directes aux VMs** (possible seulement si ton amont accepte le pontage/MACs supplémentaires).

[1]: https://docs.openstack.org/openstack-ansible/latest/admin/upgrades/compatibility-matrix.html "Compatibility Matrix — openstack-ansible 31.1.0.dev251 documentation"
[2]: https://docs.openstack.org/openstack-ansible/latest/user/aio/quickstart.html "Quickstart: AIO — openstack-ansible 31.1.0.dev251 documentation"
[3]: https://docs.openstack.org/openstack-ansible/latest/user/network-arch/example.html "Network architectures — openstack-ansible 31.1.0.dev251 documentation"
[4]: https://docs.openstack.org/openstack-ansible-os_neutron/latest/app-ovn.html "Default Scenario - Open Virtual Network (OVN) — OpenStack-Ansible Neutron 18.1.0.dev704 documentation"
[5]: https://netplan.readthedocs.io/en/latest/netplan-yaml/?utm_source=chatgpt.com "YAML configuration - Netplan documentation"
[6]: https://docs.openvswitch.org/en/latest/faq/configuration/?utm_source=chatgpt.com "Basic Configuration"

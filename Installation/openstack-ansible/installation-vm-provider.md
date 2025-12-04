# ✅ Vue d’ensemble (sécurisée pour VM chez un provider)

* **On garde `enp3s0` avec l’IP publique** (pas de bridge, pas de changement Netplan dessus).
* On crée côté hôte :

  * `br-mgmt` (Linux bridge) : réseau de **gestion** des conteneurs OSA (172.29.236.0/22).
  * `br-vxlan` (Linux bridge) : **overlay** OVN Geneve (172.29.240.0/22).
  * `br-ex` (OVS) **sans interface physique**, avec un **veth** vers l’hôte (sous-réseau **172.24.4.0/24** réservé aux Floating IP).
  * **NAT** IPv4 : le trafic 172.24.4.0/24 sort via **`enp3s0`** (MASQUERADE).
  * **DNAT d’accès** (optionnel) : tu peux publier des ports du **public** → **Floating IP** (ex : 22, 80, 443).
* OSA est configuré en **OVN** (défaut) avec **physnet1 → br-ex**. ([docs.openstack.org][2])

---

# 1) Pré-requis système

```bash
sudo apt update && sudo apt -y dist-upgrade
sudo apt install -y git python3-venv python3-pip python3-dev \
  libffi-dev libssl-dev gcc bridge-utils lvm2 thin-provisioning-tools chrony \
  openvswitch-switch nftables
```

---

# 2) Réseau hôte – **sans toucher `enp3s0`**

## 2.1 Créer `br-mgmt` et `br-vxlan` (bridges **internes**)

On ajoute un petit Netplan **qui n’affecte pas `enp3s0`** :

```bash
sudo tee /etc/netplan/02-osa-internal.yaml >/dev/null <<'YAML'
network:
  version: 2
  renderer: networkd

  bridges:
    br-mgmt:
      dhcp4: no
      addresses: [172.29.236.10/22]
    br-vxlan:
      dhcp4: no
      addresses: [172.29.240.1/22]
YAML

sudo chmod 600 /etc/netplan/02-osa-internal.yaml
sudo netplan apply
ip a show br-mgmt
ip a show br-vxlan
```

> `enp3s0` **inchangé** → ton SSH reste OK.

## 2.2 Créer `br-ex` (OVS) **sans interface physique** + veth de sortie

```bash
# Bridge OVS "externe" (sans carte physique)
sudo ovs-vsctl --may-exist add-br br-ex

# Créer un veth pair entre l'hôte et br-ex
sudo ip link add veth-ex type veth peer name veth-pub
sudo ip link set veth-ex up
sudo ip link set veth-pub up

# Attacher veth-ex à br-ex (OVS)
sudo ovs-vsctl --may-exist add-port br-ex veth-ex

# Adresses côté "réseau externe OpenStack" (br-ex)
sudo ip addr add 172.24.4.1/24 dev br-ex

# Adresses côté "hôte" (passerelle NAT)
sudo ip addr add 172.24.4.254/24 dev veth-pub

# Activer le forward IPV4
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-osa-nat.conf
sudo sysctl -p /etc/sysctl.d/99-osa-nat.conf
```

> Ici **172.24.4.0/24** est notre “externe logique” : les Floating IP OpenStack seront **172.24.4.x**.
> Elles **ne sont pas routées** par le provider, donc on fait du **NAT** via l’hôte.

## 2.3 NAT (IPv4) avec **nftables** (recommandé en 24.04)

```bash
sudo tee /etc/nftables.conf >/dev/null <<'NFT'
flush ruleset
table ip nat {
  chain prerouting {
    type nat hook prerouting priority 0;
  }
  chain postrouting {
    type nat hook postrouting priority 100;
    # NAT sortant : tout ce qui vient du subnet FIP 172.24.4.0/24 sort via enp3s0
    oifname "enp3s0" ip saddr 172.24.4.0/24 counter masquerade
  }
  chain output {
    type nat hook output priority 0;
  }
}
NFT
sudo systemctl enable --now nftables
sudo nft list ruleset
```

> Résultat : **SNAT** des FIP (172.24.4.0/24) vers Internet via `enp3s0`.
> **Optionnel (DNAT)** : tu pourras publier des ports (voir §8.4).

## 2.4 (Optionnel) rendre `br-ex` & NAT persistants via systemd

```bash
sudo tee /etc/systemd/system/osa-br-ex.service >/dev/null <<'UNIT'
[Unit]
Description=Setup OVS br-ex with veth and addresses
After=network-online.target openvswitch-switch.service nftables.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c '\
  ovs-vsctl --may-exist add-br br-ex; \
  ip link show veth-ex >/dev/null 2>&1 || ip link add veth-ex type veth peer name veth-pub; \
  ip link set veth-ex up; ip link set veth-pub up; \
  ovs-vsctl --may-exist add-port br-ex veth-ex; \
  ip addr show dev br-ex | grep -q "172.24.4.1/24" || ip addr add 172.24.4.1/24 dev br-ex; \
  ip addr show dev veth-pub | grep -q "172.24.4.254/24" || ip addr add 172.24.4.254/24 dev veth-pub; \
  sysctl -w net.ipv4.ip_forward=1 \
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl enable --now osa-br-ex.service
```

---

# 3) Récupérer OpenStack-Ansible (2025.1 **Epoxy**)

```bash
sudo mkdir -p /opt && cd /opt
sudo git clone https://opendev.org/openstack/openstack-ansible
cd openstack-ansible

# Utiliser un tag stable de la série 31.x (2025.1 Epoxy)
# (affiche les tags 31.*, prends le dernier)
git tag -l | grep '^31\.' | sort -V | tail -n1
git checkout <dernier-tag-31.x>
```

> 2025.1 = **Epoxy** (release courante). ([releases.openstack.org][3])

Bootstrap :

```bash
sudo scripts/bootstrap-ansible.sh
sudo scripts/bootstrap-aio.sh
```

> Ordre AIO officiel : **préparer l’hôte → bootstrap Ansible → bootstrap AIO → playbooks**. ([docs.openstack.org][1])

---

# 4) Inventaire OSA (AIO)

`/etc/openstack_deploy/openstack_user_config.yml` :

```yaml
---
cidr_networks:
  container: 172.29.236.0/22
  tunnel:    172.29.240.0/22
  storage:   172.29.244.0/22

global_overrides:
  internal_lb_vip_address: 172.29.236.10    # IP de br-mgmt (VIP interne)
  external_lb_vip_address: {{ TON_IP_PUBLIQUE }}  # ex: 209.182.239.240
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
      nova_compute_virt_type: "qemu"   # en provider/VM sans KVM

haproxy_hosts:
  aio1: { ip: 172.29.236.11 }

# OVN roles (northd/gateway co-localisés en AIO)
network-northd_hosts:
  aio1: { ip: 172.29.236.11 }

network-gateway_hosts:
  aio1: { ip: 172.29.236.11 }
```

> **`external_lb_vip_address` = ton IP publique actuelle** → HAProxy exposera Horizon/API dessus (pas besoin de br-ex). ([docs.openstack.org][1])

---

# 5) Variables Neutron/OVN (mapping **physnet1 → br-ex**)

`/etc/openstack_deploy/user_variables.yml` :

```yaml
# Forcer OVN (défaut depuis Zed/Dalmatian/Epoxy)
neutron_plugin_type: ml2.ovn
neutron_plugin_base:
  - ovn-router
neutron_ml2_drivers_type: "vlan,local,geneve,flat"

# Mapping provider: physnet1 -> br-ex (notre OVS "virtuel")
neutron_provider_networks:
  network_types: "geneve"
  network_geneve_ranges: "1:1000"
  network_mappings: "physnet1:br-ex"
```

> Doc OVN OSA & scénarios gateway. ([docs.openstack.org][2])

---

# 6) Secrets

```bash
cd /opt/openstack-ansible
sudo scripts/pw-token-gen.py --file /etc/openstack_deploy/user_secrets.yml
```

---

# 7) Déploiement OSA

```bash
cd /opt/openstack-ansible
sudo openstack-ansible setup-hosts.yml
sudo openstack-ansible setup-infrastructure.yml
sudo openstack-ansible setup-openstack.yml
```

> Ordre recommandé AIO. ([docs.openstack.org][1])

---

# 8) Tests réseau & Floating IP (avec NAT hôte)

## 8.1 Creds & image

```bash
# Dans le conteneur "utility" (ou sur l'hôte si client installé)
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc
  curl -L -o /root/cirros.img http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
  openstack image create cirros --file /root/cirros.img \
    --disk-format qcow2 --container-format bare --public
'
```

## 8.2 Réseaux “public” (FIP 172.24.4.0/24) et “private”

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc

  # "public" = external network sur physnet1:br-ex
  openstack network create --share --external \
    --provider-physical-network physnet1 \
    --provider-network-type flat public

  openstack subnet create --network public \
    --subnet-range 172.24.4.0/24 --gateway 172.24.4.254 \
    --dns-nameserver 8.8.8.8 --no-dhcp public-subnet

  # "private" = overlay Geneve (défaut OVN)
  openstack network create private
  openstack subnet create --network private \
    --subnet-range 10.0.0.0/24 private-subnet

  # Routeur OVN (SNAT via br-ex -> NAT hôte)
  openstack router create r1
  openstack router set r1 --external-gateway public
  openstack router add subnet r1 private-subnet
'
```

> Sortant : **VM 10.0.0.x** → SNAT OVN vers **172.24.4.x** → **MASQUERADE nftables** vers Internet via `enp3s0`.
> **Entrant** : voir DNAT §8.4 (car 172.24.4.0/24 n’est pas routé par le provider).

## 8.3 Lancer une VM + FIP

```bash
lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
  source /root/openrc
  openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny || true
  openstack keypair create demo > /root/demo.pem && chmod 600 /root/demo.pem
  openstack server create --flavor m1.tiny --image cirros --network private vm1
  FIP=$(openstack floating ip create public -f value -c floating_ip_address)
  openstack server add floating ip vm1 $FIP
  echo "Floating IP (172.24.4.x) = $FIP"
'
```

* **Ping sortant** depuis la VM doit fonctionner (SNAT).
* SSH sortant vers Internet aussi.

## 8.4 (Optionnel) **publier** un service vers ta VM (DNAT hôte)

Exemple : exposer **SSH** de ta VM (FIP=172.24.4.10) sur le port **2222** de **ton IP publique** :

```bash
FIP="172.24.4.10"   # remplace par la vraie FIP
PUBIF="enp3s0"

sudo nft add rule ip nat prerouting iifname "$PUBIF" tcp dport 2222 \
  counter dnat to ${FIP}:22
```

Tu peux alors te connecter depuis l’extérieur :

```
ssh -p 2222 cirros@<TON_IP_PUBLIQUE>
```

> Pour d’autres services (80/443…), ajoute des règles **prerouting** analogues.
> (Option plus “propre” : mettre **HAProxy**/Nginx sur l’hôte pour exposer plusieurs VMs/services.)

---

# 9) Horizon & vérifs

* **Horizon** : `https://<TON_IP_PUBLIQUE>/horizon` (ou `http://` selon ton choix).
* Identifiants admin dans `/etc/openstack_deploy/user_secrets.yml`.
* Vérifs CLI :

  ```bash
  lxc-attach -n $(lxc-ls -1 | grep utility) -- bash -lc '
    source /root/openrc
    openstack service list
    openstack network agent list
  '
  ovs-vsctl show
  sudo systemctl status nftables openvswitch-switch
  ```

---

# 10) Points clés / limites de ce mode “provider cloud”

* **Aucun changement sur `enp3s0`** → on ne casse pas l’SSH.
* Les **Floating IP (172.24.4.x)** **ne sont pas routées publiquement** (c’est voulu) ;

  * **Sortant** OK (SNAT via nftables).
  * **Entrant** : publier **au cas par cas** via **DNAT** (ou proxy L4/L7).
* C’est la manière **la plus sûre** d’avoir un OpenStack AIO **en ligne** chez un provider **avec anti-spoofing/MAC filtrées**.
* Si ton provider **autorise** le bridgé (MAC supplémentaires) **et** t’offre une **console**, tu peux basculer plus tard vers le schéma classique `enp3s0 → br-ex` (directement routé), et tes FIP seront alors **publiquement routées**.

---

## (Annexe) Rendre DNAT persistants

Ajoute tes règles DNAT dans `/etc/nftables.conf`, section `table ip nat { chain prerouting { ... } }`, puis :

```bash
sudo systemctl reload nftables
```


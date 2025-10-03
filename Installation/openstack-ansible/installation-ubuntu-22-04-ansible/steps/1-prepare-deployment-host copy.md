Très bien 👌, je vais t’expliquer **Prepare the target hosts** pour **OpenStack-Ansible** comme si tu étais en train de préparer ton propre lab VirtualBox/VMs.

L’idée : tu vas préparer chaque **target host** (contrôleur, compute, storage) pour qu’Ansible puisse ensuite déployer OpenStack dessus.
Voilà ce que chaque section veut dire 👉

---

# 🔹 1. Installer le système d’exploitation

* Choisis un OS supporté :

  * **Ubuntu 22.04** (recommandé en 2025, stable et bien supporté)
  * Ubuntu 24.04, Debian 12, CentOS Stream 9/10, Rocky 9 (autres alternatives).
* Exigences :

  * **Au moins une interface réseau** avec accès à Internet (ou dépôts internes).
  * Corriger `/etc/hosts` → ne pas laisser la ligne `127.0.1.1 hostname` (ça casse la résolution).
  * Installer `openssh-server` (sinon tu ne pourras pas te connecter à distance en SSH).
  * Configurer la locale `en_US.UTF-8` (sinon certains playbooks plantent).

---

# 🔹 2. Mise à jour et paquets nécessaires

### ✅ Sur Debian

```bash
apt update
apt dist-upgrade -y
apt install bridge-utils debootstrap ifenslave ifenslave-2.6 \
  lsof lvm2 openssh-server sudo tcpdump vlan python3 -y
reboot
```

### ✅ Sur Ubuntu

```bash
apt update
apt dist-upgrade -y
apt install bridge-utils debootstrap openssh-server \
  tcpdump vlan python3 -y
apt install linux-modules-extra-$(uname -r) -y
reboot
```

### ✅ Sur CentOS / Rocky

```bash
dnf upgrade -y
# Désactiver SELinux
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
dnf install iputils lsof openssh-server sudo tcpdump python3 -y
dnf group install "Development Tools" -y
echo "kernel.printk='4 1 7 4'" >> /etc/sysctl.conf
reboot
```

⚠️ **SELinux** n’est pas supporté dans OSA → obligation de le désactiver.

---

# 🔹 3. Configurer SSH keys

* Ansible se connecte en SSH.
* Tu génères une clé sur le **deployment host** :

  ```bash
  ssh-keygen -t rsa -b 4096
  ssh-copy-id root@target-host
  ```
* Test :

  ```bash
  ssh root@target-host
  ```

👉 Si tu rentres directement dans le shell sans mot de passe, c’est prêt.

---

# 🔹 4. Configurer le stockage

* OSA peut utiliser **LVM** pour stocker :

  * Les volumes Cinder.
  * Les conteneurs LXC (optionnel).
* Exemple pour préparer un disque `/dev/sdb` :

  ```bash
  pvcreate --metadatasize 2048 /dev/sdb
  vgcreate cinder-volumes /dev/sdb
  ```
* Si tu veux aussi LXC sur LVM :

  ```bash
  vgcreate lxc /dev/sdc
  ```

  puis dans `/etc/openstack_deploy/user_variables.yml` :

  ```yaml
  lxc_container_backing_store: lvm
  ```

Sinon par défaut, LXC utilise `/var/lib/lxc`.

---

# 🔹 5. Configurer le réseau (super important ⚡)

OSA repose sur des **bridges Linux** pour relier :

* Les interfaces physiques (cartes VirtualBox, VLANs…)
* Aux interfaces virtuelles des conteneurs LXC.

Bridges attendus :

| Bridge         | Rôle                                                         | Où ?              | IP ?                        |
| -------------- | ------------------------------------------------------------ | ----------------- | --------------------------- |
| **br-mgmt**    | Management des conteneurs OpenStack (Keystone, Glance, etc.) | Tous les nœuds    | ✅ Toujours une IP statique  |
| **br-storage** | Réseau stockage (Cinder, Swift, Ceph)                        | Nœuds storage     | ✅ si storage sur bare-metal |
| **br-vxlan**   | Overlay Neutron (tunnels VXLAN entre computes)               | Compute + Network | ✅ Toujours une IP statique  |
| **br-vlan**    | Provider network (VLAN/flat pour VMs)                        | Compute + Network | ❌ Pas d’IP (L2 seulement)   |

### Exemple typique (VirtualBox)

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s3:   # Internet / repo
      dhcp4: true
    enp0s8:   # External provider
      dhcp4: no

  bridges:
    br-mgmt:
      addresses: [172.29.236.10/22]
    br-vxlan:
      addresses: [172.29.240.10/22]
    br-ex:
      interfaces: [enp0s8]
      addresses: [192.168.56.10/24]
      gateway4: 192.168.56.1
      nameservers:
        addresses: [8.8.8.8,8.8.4.4]
```

* `br-mgmt` = management (containers Ansible)
* `br-vxlan` = overlay réseau pour VM internes
* `br-ex` = external (pour accéder en SSH et Floating IP)
* `br-storage` = seulement si tu fais du Cinder/Swift

---

# 🔹 6. Bridges spéciaux

* **lxcbr0** : créé automatiquement par OSA.
  → fournit DHCP/NAT aux conteneurs (sortie Internet).
* Tu n’as rien à faire, OSA le gère.

---

✅ **En résumé, préparer un target host c’est :**

1. Installer un OS supporté (Ubuntu conseillé).
2. Mise à jour + installation paquets (bridge-utils, vlan, lvm2, openssh, etc.).
3. Corriger `/etc/hosts` et locale.
4. Installer & tester les clés SSH (deployment ↔ target).
5. Configurer LVM (optionnel pour Cinder / LXC).
6. Créer les bridges réseaux (`br-mgmt`, `br-vxlan`, `br-ex`, `br-storage`, `br-vlan`).

---

👉 Veux-tu que je t’écrive un **fichier Netplan complet clé en main pour Ubuntu 22.04 target host** (avec toutes les interfaces br-mgmt, br-vxlan, br-ex, br-storage, br-vlan) comme modèle ?


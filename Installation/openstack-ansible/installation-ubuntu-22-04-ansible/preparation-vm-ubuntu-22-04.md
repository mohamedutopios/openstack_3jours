# 🔹 1. Paramètres VirtualBox

### 📌 Ressources VM

* **CPU** : 4 vCPU minimum (6 ou 8 si ta machine hôte peut suivre)
* **RAM** : 12 Go minimum (16 Go recommandé)
* **Disque** : 80 Go (100 Go recommandé, disque dynamique OK)
* **Contrôleur disque** : SATA ou VirtIO (plus performant)

### 📌 Cartes réseau

* **Carte 1** : NAT

  * Sert à donner l’accès Internet à ta VM Ubuntu pour apt, git, etc.
  * DHCP activé (Ubuntu recevra une IP 10.0.2.x).

* **Carte 2** : Host-only (par défaut `vboxnet0`)

  * Sert à créer le réseau externe (`br-ex`) que tu utiliseras pour Horizon et les Floating IP.
  * IP côté hôte : en général `192.168.56.1/24`.
  * La VM aura une IP statique (ex. `192.168.56.10`).

👉 Avec ça, tu as :

* Internet depuis Ubuntu (via NAT).
* Accès à Horizon et aux VMs OpenStack depuis ton PC (via Host-only).

---

# 🔹 2. Préparation d’Ubuntu 22.04 (après install)

### 📌 Packages de base

```bash
sudo apt update && sudo apt -y dist-upgrade
sudo apt install -y qemu-guest-agent curl wget vim htop net-tools
```

Active le **qemu-guest-agent** → utile si tu utilises d’autres hyperviseurs plus tard (statut, shutdown propre).

### 📌 Vérification réseau

```bash
ip a
```

Tu dois voir :

* `enp0s3` → IP DHCP genre `10.0.2.15` (NAT)
* `enp0s8` → pas encore configurée (Host-only)

---

# 🔹 3. Configuration réseau (avant OSA)

On prépare Netplan pour :

* Laisser `enp0s3` en DHCP (NAT).
* Associer `enp0s8` à `br-ex` avec une IP statique (192.168.56.10).
* Ajouter deux bridges internes (`br-mgmt` et `br-vxlan`) pour OSA.

👉 Fichier `/etc/netplan/01-osa.yaml` :

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s3:
      dhcp4: true
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
ip a show br-ex
ip a show br-mgmt
ip a show br-vxlan
```

---

# 🔹 4. Vérifications avant installation OSA

* **Internet OK**

  ```bash
  ping -c3 8.8.8.8
  ping -c3 google.com
  ```
* **Accès Horizon futur**
  Vérifie que ton PC peut joindre `192.168.56.10` (ping depuis ton hôte).
* **Espace disque suffisant**

  ```bash
  df -h
  ```
* **Mémoire & CPU corrects**

  ```bash
  free -h
  nproc
  ```

---

# ✅ Résumé

Ta VM Ubuntu 22.04 VirtualBox doit être préparée comme suit **avant d’installer OSA** :

* **4–6 vCPU, 12–16 Go RAM, 80–100 Go disque.**
* **Carte 1 = NAT (DHCP)** pour Internet.
* **Carte 2 = Host-only (statique)** → `br-ex = 192.168.56.10`.
* **Bridges internes** `br-mgmt` et `br-vxlan` créés via Netplan.
* Vérifier Internet + connectivité Host-only.

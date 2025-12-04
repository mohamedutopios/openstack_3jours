# 🟦 **LÉGENDE**

* **Couche 2 (L2)** → switching, MAC, ponts, veth, tap
* **Couche 3 (L3)** → routage, IP, SNAT/DNAT, gateway
* **OpenStack** → créé par Neutron
* **Libvirt** → créé par qemu/KVM
* **OVS** → Open vSwitch
* **LinuxBridge** → br/qbr
* **Namespace NETNS** → isolation réseau L3

---

# 🟥 **1️⃣ Interface de ta VM : *eth0* (dans la VM)**

### ✔ Couche : **L2 + L3 dans la VM**

### ✔ Produit par : **cloud-init + DHCP Neutron**

### ✔ Rôle :

* Interface réseau principale de la VM (OS invité)
* Reçoit une IP du DHCP Neutron (ex. 192.168.0.119)
* Envoie/Recoit ping, TCP, HTTP…
* MAC = FAKE par OpenStack (fa:16:3e:XX:XX:XX)

👉 **C’est l’interface “noyau de la VM” – le début du trafic.**

---

# 🟧 **2️⃣ tap10f0e841-e6 — Interface TAP (hyperviseur)**

### ✔ Couche : **L2 pur (switching virtuel)**

### ✔ Produit par : **libvirt / qemu-kvm**

### ✔ Liaison : **relie la VM au réseau de l’hyperviseur**

### ✔ Rôle :

* Représente la carte réseau *eth0* de la VM **dans l’hôte OpenStack**.
* Chaque paquet envoyé/reçu par la VM passe **physiquement** par ce TAP.
* MAC = MAC de la VM (fa:16:3e:f3:85:9b).

👉 **Le tap est la “prise murale” de la VM dans l’hôte.**

✔ Visible dans `ip a` :
`35: tap10f0e841-e6`

⚠ **Si pas de TAP → pas de réseau pour la VM.**

---

# 🟦 **3️⃣ qbr10f0e841-e6 — LinuxBridge (Security Groups)**

### ✔ Couche : **L2 (switching) + L3 filtrage (iptables)**

### ✔ Produit par : **Neutron LinuxBridge agent**

### ✔ Rôle :

* Sert de **pare-feu L2/L3** pour la VM.
* Implémente **Security Groups** via iptables.
* Sépare la VM du reste du trafc via un mini switch Linux.

👉 **Il joue le rôle de “switch + firewall” privé pour la VM.**

✔ Visible dans `ip a`:
`32: qbr10f0e841-e6`

---

# 🟩 **4️⃣ veth pair : qvb10f0e841-e6 ↔ qvo10f0e841-e6**

### ✔ Couche : **L2 pur (veth)**

### ✔ Produit par :

* **qvb** = côté LinuxBridge
* **qvo** = côté OVS / br-int
* Créés par **Neutron** (LinuxBridge ↔ OVS ML2)

### ✔ Rôle :

### 🔹 **qvb10f0e841-e6**

* côté bridge Linux (qbr)
* reçoit le trafic du firewall LinuxBridge

### 🔹 **qvo10f0e841-e6**

* côté OVS
* connecté au bridge OVS **br-int**

### ✔ Fonction :

Ils forment un “câble virtuel”, comme :

```
[qbr] — qvb ==== qvo — [br-int]
```

👉 **C’est la jonction entre le firewall Neutron et le SDN Open vSwitch.**

---

# 🟦 **5️⃣ br-int — Bridge OVS interne (Plan de données Neutron)**

### ✔ Couche : **L2 (switch OVS) + pipeline OpenFlow**

### ✔ Produit par : **Open vSwitch** (géré par Neutron OVS agent)

### ✔ Rôle stratégique :

* Cœur du réseau Neutron.
* Répartit le trafic entre :

  * VMs
  * Ports du routeur L3 (qr-*)
  * Ports de gateway (qg-*)
  * Ports de DHCP (tap-*)
  * Tunnel VXLAN (patch-int)

### ✔ Ports VM présents :

* qvo10f0e841-e6  → port VM de ton instance vm-demo
* qvo69a54f26-97  → port d'une autre VM
* qvoceceaca3-2f  → port d'une autre VM

### ✔ Ports L3 (router Neutron) :

* qr-6b789bb0-6b  → interface du routeur vers réseau privé
* qr-c46a992c-d8  → interface vers un autre réseau privé

### ✔ Ports gateway (externe) :

* qg-1ab75116-33
* qg-eb2b003a-d0

👉 **C’est TON SWITCH SDN PRINCIPAL.**
Il applique les **OVS flows** : anti-spoofing, ARP, DHCP, tunnels, NAT-forwarding.

---

# 🟧 **6️⃣ br-tun — Bridge OVS pour VXLAN (overlay tunnel)**

### ✔ Couche : **L2/L3 (encapsulation VXLAN)**

### ✔ Produit par : **OVS (Neutron OVS agent)**

### ✔ Rôle :

* Encapsule les trames L2 en VXLAN (UDP 4789)
* Transporte les paquets entre compute nodes (même si tu es AIO)
* Traffic sort de br-tun via **br-int ↔ br-tun patch ports**

### Ports :

* patch-int
* patch-tun

👉 **Il transforme ton réseau privé Neutron en overlay VXLAN.**

---

# 🟥 **7️⃣ Namespace qrouter-xxxx — Routeur virtuel Neutron (L3 + NAT)**

### ✔ Couche : **L3 (routage) + L4 (NAT)**

### ✔ Produit par : **Neutron L3 Agent**

### ✔ Interfaces dedans :

* **qr-*** : vers réseaux privés
* **qg-*** : vers br-ex (sortie externe)

### ✔ Rôle :

* Route le trafic privé → externe
* Applique SNAT (VM → Internet)
* Applique DNAT (Floating IP → VM)
* A sa propre table de routage
* Utilise iptables pour NAT

👉 **C’est le routeur virtuel d’OpenStack.**

Sans qrouter → pas de floating IP, pas de sortie.

---

# 🟩 **8️⃣ NAT iptables (dans qrouter)**

### ✔ Couche : **L3/L4**

### ✔ Produit par : **Neutron L3 agent**

### ✔ Rôle :

* SNAT : 192.168.0.119 → 9.12.93.196
* DNAT : 9.12.93.196 → 192.168.0.119

👉 **Il remplace l’IP privée par une IP publique.**

Commande pour voir :

```
ip netns exec qrouter-XXXX iptables -t nat -L -n -v
```

---

# 🟦 **9️⃣ br-ex — Bridge externe (réseau fournisseur)**

### ✔ Couche : **L2**

### ✔ Produit par : **OVS**

### ✔ Rôle :

* Représente le réseau externe OpenStack (provider network)
* Relie le router au monde réel via **enp0s10**
* Supporte les floating IP

### Ports :

* **phy-br-ex** ↔ enp0s10
* **int-br-ex** ↔ br-int
* **qg-* ports** (interface du routeur L3)

👉 **C’est ton switch L2 vers Internet.**

---

# 🟧 **🔟 enp0s10 — Interface physique externe**

### ✔ Couche : **L2 + L3**

### ✔ Produit par : **Ubuntu / VirtualBox**

### ✔ Rôle :

* Connecte OpenStack à ton réseau externe (9.12.93.0/24)
* Porte les floating IPs
* Ultime sortie vers Internet

👉 **C’est l’interface physique qui transporte les VM vers le monde réel.**

---

# 🟩 **PHASE RÉCAP : Schéma simplifié + rôles**

```
VM eth0       → Couche 2/3 (OS invité)
tapXXX        → L2 (interface VM côté hyperviseur)
qbrXXX        → L2/L3 firewall (Security Groups)
qvb/qvo       → L2 veth pair (bridge Linux ↔ OVS)
br-int        → L2 SDN switch (OVS) cœur du réseau Neutron
br-tun        → L2 overlay (VXLAN encapsulation)
qrouter       → L3 + NAT (OpenStack router)
br-ex         → L2 external network
enp0s10       → L2/L3 interface physique vers internet
```

---

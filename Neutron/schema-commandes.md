# 🟦 **0. Générer du trafic depuis la VM**

Tu lances un ping AUTOMATIQUE depuis ton hôte :

```
openstack server ssh vm-demo --login ubuntu -- ping -i 0.2 8.8.8.8
```

Ou, si problème d'openstack ssh :

```
openstack console url show vm-demo
```

Puis dans la console de la VM :

```
ping -i 0.2 8.8.8.8
```

---

# 🟥 **1️⃣ TAP de la VM — vérifier que la VM ÉMET**

Interface dans ton host : **tap10f0e841-e6**

### Commande :

```
sudo tcpdump -ni tap10f0e841-e6 icmp
```

### Diagnostic attendu :

```
IP 192.168.0.119 > 8.8.8.8: ICMP echo request
```

### Si rien ne sort :

* VM ne génère pas de trafic
* DHCP cassé
* VM freeze / firewall VM
* Mauvaise interface

---

# 🟧 **2️⃣ qbr10f0e841-e6 — firewall L2 (Security Groups)**

Interface : **qbr10f0e841-e6**

### Commande :

```
sudo tcpdump -ni qbr10f0e841-e6 icmp
```

### Résultat attendu :

Même trafic que sur le TAP.

### Si tap OK mais qbr vide :

* Security Groups bloquent
* Anti-spoofing
* Filtrage MAC / ARP

---

# 🟦 **3️⃣ qvb10f0e841-e6 — côté LinuxBridge**

Interface : **qvb10f0e841-e6**

### Commande :

```
sudo tcpdump -ni qvb10f0e841-e6 icmp
```

### Résultat attendu :

Même trafic.

---

# 🟩 **4️⃣ qvo10f0e841-e6 — entrée dans OVS (br-int)**

Interface côté OVS : **qvo10f0e841-e6**

### Commande :

```
sudo tcpdump -ni qvo10f0e841-e6 icmp
```

### Résultat attendu :

Même trafic.

### Si qvb OK et qvo vide :

* ML2 OVS agent arrêté
* Port non attaché
* Flow drop dans OVS

---

# 🟥 **5️⃣ br-int — switch interne SDN OVS**

⚠️ Tu ne peux pas faire tcpdump sur br-int directement.
Tu dois **capturer sur OVS au niveau OpenFlow**.

### Voir le trafic ARP/ICMP traité :

```
sudo docker exec -it openvswitch_vswitchd tcpdump -ni any icmp
```

OU utiliser les flows :

```
sudo docker exec -it openvswitch_vswitchd ovs-ofctl dump-flows br-int
```

### Analyse dans flows :

Tu as déjà vu :

```
priority=9,in_port="qvo10f0e841-e6" actions=resubmit(,25)
```

➡️ preuve que ton trafic passe bien par **table 0 → table 25 → table 60**.

---

# 🟦 **6️⃣ br-tun — VXLAN Overlay**

Tu veux vérifier l’encapsulation VXLAN :

```
sudo tcpdump -ni br-tun udp port 4789
```

### Résultat attendu :

```
VXLAN, flags [...], vni 1001
```

Si rien :

* VXLAN désactivé
* ML2 OVS agent DOWN
* tunnel overlay cassé

---

# 🟫 **7️⃣ Namespace du routeur L3 (SNAT/DNAT + forwarding)**

## Trouver le namespace :

```
sudo ip netns
```

Tu verras :
`qrouter-6b789bb0-6b` (par exemple)

---

## Vérifier les interfaces du routeur :

```
sudo ip netns exec qrouter-6b789bb0-6b ip a
```

Tu dois voir :

* qr-xxxx (réseau privé)
* qg-xxxx (gateway externe)

---

## Vérifier le trafic dans le routeur :

```
sudo ip netns exec qrouter-6b789bb0-6b tcpdump -ni any icmp
```

### Résultat attendu :

```
192.168.0.119 > 8.8.8.8 (avant NAT)
9.12.93.196 > 8.8.8.8 (après NAT)
```

➡️ Preuve que le routeur applique bien le SNAT.

---

## Vérifier les règles NAT :

```
sudo ip netns exec qrouter-6b789bb0-6b iptables -t nat -L -n -v
```

Tu DOIS voir :

```
MASQUERADE  all  --  192.168.0.0/24  0.0.0.0/0
DNAT        tcp  --  9.12.93.196     192.168.0.119
```

---

# 🟧 **8️⃣ br-ex — Bridge externe (sortie vers enp0s10)**

Port : **int-br-ex**, **phy-br-ex**

### Commande :

```
sudo tcpdump -ni br-ex icmp
```

### Résultat attendu :

```
9.12.93.196 > 8.8.8.8
```

Si rien :

* Port qg-* pas attaché
* NAT non fonctionnel
* route incorrecte

---

# 🟦 **9️⃣ NIC physique : enp0s10 (sortie finale)**

```
sudo tcpdump -ni enp0s10 icmp
```

### Résultat attendu :

```
9.12.93.196 > 8.8.8.8: icmp echo request
8.8.8.8 > 9.12.93.196: icmp echo reply
```

Si rien :

* Pas d’IP valide
* Pas de route par défaut
* SNAT non appliqué

---

# 🟩 **🔟 DHCP diagnostics (pour attribution d’IP)**

## Trouver le namespace DHCP :

```
sudo ip netns | grep qdhcp
```

## Observer le DHCP :

```
sudo ip netns exec qdhcp-XXXXXXXX tcpdump -ni any port 67 or port 68
```

Tu dois voir :

```
DHCP Discover
DHCP Offer
DHCP Request
DHCP ACK
```

---

# 🟦 **🔚 RÉCAP VISUEL (ordonné)**

Voici l’ordre EXACT des commandes quand tu suis le ping :

```
1) sudo tcpdump -ni tap10f0e841-e6 icmp
2) sudo tcpdump -ni qbr10f0e841-e6 icmp
3) sudo tcpdump -ni qvb10f0e841-e6 icmp
4) sudo tcpdump -ni qvo10f0e841-e6 icmp
5) sudo docker exec -it openvswitch_vswitchd ovs-ofctl dump-flows br-int
6) sudo tcpdump -ni br-tun udp port 4789
7) sudo ip netns exec qrouter-XXXX tcpdump -ni any icmp
8) sudo ip netns exec qrouter-XXXX iptables -t nat -L -n -v
9) sudo tcpdump -ni br-ex icmp
10) sudo tcpdump -ni enp0s10 icmp
```

---

# 🟣 Si tu veux, je te génère :

✔ un **diagramme complet “packet walk-through”** étape par étape
✔ un **PDF pédagogique** pour tes apprenants
✔ un **script automatisé** qui lance TOUTES les captures en parallèle
✔ une **simulation complète** avec sortie typique de chaque étape

Que veux-tu ?

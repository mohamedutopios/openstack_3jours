# 🧩 1. Manager et contrôleurs

```
Manager "ptcp:6640:127.0.0.1"
Controller "tcp:127.0.0.1:6633"
```

* OVS peut être piloté à distance via **OpenFlow**.
* Ici, il écoute en local (`127.0.0.1`) → c’est **Neutron ML2 OVS agent** qui lui installe les flux de routage/sécurité.

---

# 🧩 2. Bridge `br-ex` (bridge externe)

```
Bridge br-ex
    Port "enp0s9"
    Port br-ex
        type: internal
    Port phy-br-ex
        type: patch peer=int-br-ex
```

* **`br-ex` = pont vers le réseau externe/provider**.
* **`enp0s9`** : ton interface physique reliée au LAN extérieur ou NAT VirtualBox.
* **`phy-br-ex` <-> int-br-ex`** : patch ports reliant `br-ex`à`br-int`.
* Sert à faire sortir les VM vers Internet via NAT (floating IP, external gateway).

---

# 🧩 3. Bridge `br-int` (bridge interne principal)

```
Bridge br-int
    Port "qvo69a54f26-97"
    Port "qg-1ab75116-33" type: internal
    Port "qr-6b789bb0-6b" type: internal
    Port "tap7af2a988-2b" type: internal
    Port patch-tun peer=patch-int
    Port int-br-ex peer=phy-br-ex
```

* **Rôle : switch interne L2** où toutes les VM, routeurs, DHCP agents sont branchés.
* **`tapXXXX`** → interface d’une VM.
* **`qvoXXXX`** → veth côté OVS pour brancher une VM (pair avec `qvb` côté linuxbridge).
* **`qr-XXXX`** → port routeur Neutron (interface interne du routeur virtuel).
* **`qg-XXXX`** → port gateway externe du routeur Neutron (vers br-ex).
* **`int-br-ex`** → lien vers `br-ex`.
* **`patch-tun`** → lien vers `br-tun`.

👉 Ici tu vois clairement :

* au moins **une VM** connectée (`tap7af2a988-2b`),
* un **routeur Neutron** avec ses interfaces (`qr-*` interne, `qg-*` externe).

---

# 🧩 4. Bridge `br-tun` (tunnels VXLAN/GRE)

```
Bridge br-tun
    Port patch-int peer=patch-tun
```

* Sert aux **overlays VXLAN/GRE** pour connecter des VM sur différents hyperviseurs.
* Dans ton AIO, il n’y a pas encore de `vxlan-xxxx` car un seul nœud.
* Mais `patch-int` ↔ `patch-tun` relie `br-int` ↔ `br-tun`.

---

# 📐 Schéma logique basé sur ta sortie

```
VM (tap7af2a988-2b) ---- qvoXXXX --- br-int ---- int-br-ex ---- phy-br-ex ---- br-ex ---- enp0s9 --> LAN/Internet
                                    |          \
                                    |           \
                                    |            qg-XXXX  (gateway ext)
                                    |            qr-XXXX  (interface routeur)
                                    |
                                    +--- patch-tun --- br-tun --- (VXLAN vers autres nœuds)
```

---

# ✅ Résumé

Dans ton `ovs-vsctl show` :

* **br-ex** = sortie vers le LAN physique (`enp0s9`).
* **br-int** = switch interne principal :

  * ports `tap*` = VM,
  * ports `qr-*` = routeur interne,
  * ports `qg-*` = routeur externe.
* **br-tun** = pour VXLAN (overlay inter-nœuds).

👉 Tu as donc sous les yeux la **plomberie complète** entre tes VM, les routeurs Neutron et le monde extérieur.



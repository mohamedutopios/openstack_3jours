# 🚀 Démo complète : Switchs virtuels avec OVS

---

## 1️⃣ Principe général

* OVS est un **switch logiciel L2** qui permet de connecter des interfaces virtuelles (tap devices, veth, bridges).
* Dans OpenStack, il est utilisé par **Neutron ML2 OVS agent** pour brancher les interfaces des VM dans différents réseaux virtuels.
* Bridges principaux en OpenStack :

  * `br-int` → bridge interne, cœur du dataplane.
  * `br-tun` → utilisé pour VXLAN/GRE overlay.
  * `br-ex` → connecté au monde extérieur (provider network).

---

## 2️⃣ Vérification sur ton host OpenStack

Liste les bridges créés par OVS :

```bash
sudo ovs-vsctl show
```

Exemple de sortie :

```
Bridge br-int
    Port "tap1234"    # interface de ta VM
    Port "qr-xxxx"    # port routeur Neutron
Bridge br-ex
    Port "enp0s9"     # interface physique vers l’extérieur
Bridge br-tun
    Port "vxlan-0a000002"   # tunnel VXLAN vers un autre hyperviseur
```

Parfait 👍 tu es tombé sur un **classique avec Kolla** :

```
ovs-vsctl: unix:/var/run/openvswitch/db.sock: database connection failed (Permission denied)
```

👉 En fait, dans ton conteneur `neutron_openvswitch_agent`, il **n’y a pas le démon `ovsdb-server`** → c’est juste l’agent Neutron qui parle à OVS.
Le vrai démon OVS tourne dans le conteneur **`openvswitch_vswitchd`** (ou équivalent selon ta version Kolla).

---

# 🔹 Étape 1 : Trouver le bon conteneur OVS

Liste tous les conteneurs et cherche `vswitchd` ou `db` :

```bash
sudo docker ps --format "table {{.ID}}\t{{.Names}}"
```

Tu devrais voir quelque chose comme :

```
openvswitch_vswitchd
openvswitch_db
neutron_openvswitch_agent
...
```

---

# 🔹 Étape 2 : Lancer la commande dans le bon conteneur

Exemple :

```bash
sudo docker exec -it openvswitch_vswitchd ovs-vsctl show
```

ou

```bash
sudo docker exec -it openvswitch_db ovs-vsctl show
```

👉 Dans la plupart des cas, c’est le conteneur `openvswitch_db` qui détient le `db.sock`.

---

# 🔹 Étape 3 : Autres commandes utiles

* Lister les bridges :

  ```bash
  sudo docker exec -it openvswitch_vswitchd ovs-vsctl list-br
  ```
* Lister les ports d’un bridge (ex: br-int) :

  ```bash
  sudo docker exec -it openvswitch_vswitchd ovs-vsctl list-ports br-int
  ```
* Voir les flux OpenFlow :

  ```bash
  sudo docker exec -it openvswitch_vswitchd ovs-ofctl dump-flows br-int
  ```

---

# 🔹 Exemple de sortie attendue

```
Bridge br-int
    Port "tap1234"
    Port "qr-xxxx"
Bridge br-ex
    Port "eth0"
Bridge br-tun
    Port "vxlan-0a000002"
```
---

## 3️⃣ Créer un réseau et des VM (cas pratique)

### a) Réseau privé et VM

```bash
openstack network create private-net
openstack subnet create --network private-net --subnet-range 10.10.10.0/24 private-subnet

openstack server create --flavor m1.small --image cirros \
  --network private-net --key-name mykey vm1

openstack server create --flavor m1.small --image cirros \
  --network private-net --key-name mykey vm2
```

### b) Vérifier les interfaces dans OVS

```bash
sudo ovs-vsctl list-ports br-int
```

Tu verras deux ports `tapxxxx` correspondant aux NIC des VM.

### c) Test

Depuis la console de `vm1` :

```bash
ping 10.10.10.6   # IP de vm2
```

➡️ Les deux VM communiquent via **OVS br-int** (switch virtuel pur, sans routage).

---

## 4️⃣ Ajouter un routeur virtuel Neutron

### a) Routeur pour sortir du réseau

```bash
openstack router create demo-router
openstack router add subnet demo-router private-subnet
openstack router set demo-router --external-gateway public-net
```

### b) Vérifier dans OVS

```bash
sudo ovs-vsctl list-ports br-int | grep qr-
```

➡️ Tu vois le port `qr-xxx` du routeur Neutron connecté au réseau privé.

---

## 5️⃣ Exemple avec overlay VXLAN

### a) Créer un réseau tenant (VXLAN)

```bash
openstack network create tenant-net
openstack subnet create --network tenant-net --subnet-range 192.168.100.0/24 tenant-subnet
```

### b) Vérifier les tunnels VXLAN

```bash
sudo ovs-vsctl list-ports br-tun
```

Exemple de sortie :

```
vxlan-0a000002
```

➡️ Ce port VXLAN encapsule le trafic entre hyperviseurs (si tu avais un cluster multi-nœuds).

---

## 6️⃣ Fonctions avancées avec OVS

### a) Sniffer le trafic d’une VM

Liste les ports OVS :

```bash
sudo ovs-vsctl list-ports br-int
```

Puis sniffe :

```bash
sudo tcpdump -i tap1234 -n
```

### b) Ajouter une règle QoS (limiter la bande passante d’une VM)

```bash
sudo ovs-vsctl set port tap1234 qos=@newqos -- \
--id=@newqos create qos type=linux-htb other-config:max-rate=1000000 queues:123=@q1 -- \
--id=@q1 create queue other-config:max-rate=1000000
```

➡️ Ici, tu limites la VM à **1 Mbps**.

### c) Mirroring (SPAN virtuel)

Créer un port miroir pour analyser le trafic :

```bash
sudo ovs-vsctl -- set Bridge br-int mirrors=@m \
  -- --id=@tap1234 get Port tap1234 \
  -- --id=@tapmirror create Port name=tapmirror \
  -- --id=@m create Mirror name=m0 select-dst-port=@tap1234 select-src-port=@tap1234 output-port=@tapmirror
```

---

# 📐 Schéma ASCII d’un cas réel

```
   [ VM1 10.10.10.5 ] --tap--\
                               br-int (OVS) ---- qr-xxx ---- qg-xxx ---- br-ex --- Internet
   [ VM2 10.10.10.6 ] --tap--/         | VXLAN
                                        \--- br-tun --- vxlan-0a000002 ---- autre compute
```


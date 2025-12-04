# 🟦 **SCHÉMA GLOBAL – VUE D’ENSEMBLE**

```
                        ┌─────────────────────────────────────────┐
                        │           OpenStack AIO Host            │
                        │        (VM Ubuntu 22.04 sous VBox)      │
                        └─────────────────────────────────────────┘
                                        │
                                        │
                         ┌──────────────────────────┐
                         │   Réseau Physique VBox   │
                         │  enp0s3 / enp0s8 / enp0s10│
                         └──────────────────────────┘
```

---

# 🟥 **1. RÉSEAUX PHYSIQUES SUR TON HOST OPENSTACK**

```
enp0s3  → 9.10.93.4/24   (management / internal)
enp0s8  → 9.11.93.4/24   (API / internal)
enp0s10 → 9.12.93.6/24   (EXTERNAL NETWORK / Floating IPs)
```

➡️ C’est **enp0s10** qui permet d’accéder à Internet.

➡️ C’est lui qui est relié à **br-ex** via un patch-port.

---

# 🟦 **2. BRIDGES OVS (DATA PLANE)**

Tu as :

* **br-int** → switching interne (ports VM, ports router, ports DHCP)
* **br-tun** → overlay VXLAN
* **br-ex** → réseau externe / NAT

---

# 🟩 **3. FLOW COMPLET D’UNE VM vers Internet**


```
                          VM (ubuntu-20.04)
                              eth0
                                │
                                ▼
                    ┌─────────────────────┐
                    │ tap10f0e841-e6      │   ← interface virtuelle VM
                    └─────────────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │ qbr10f0e841-e6      │   ← LinuxBridge Security Groups
                    └─────────────────────┘
                                │
              (veth pair)   qvb10f0e841-e6  ↔  qvo10f0e841-e6
                                │                    │
                                ▼                    ▼
                    ┌─────────────────────┐   ← port attaché à br-int
                    │       br-int        │
                    │ ports VM :          │
                    │   - qvo10f0e841-e6  │
                    │   - qvo69a54f26-97  │
                    │   - qvoceceaca3-2f  │
                    │ ports router :      │
                    │   - qr-6b789bb0-6b  │
                    │   - qr-c46a992c-d8  │
                    │ ports gateway :     │
                    │   - qg-1ab75116-33  │
                    └─────────────────────┘
                                │
                                ▼
                    ┌─────────────────────┐
                    │       br-tun        │   ← VXLAN Overlay
                    │   patch-int ↔ patch-tun
                    └─────────────────────┘
                                │
                                ▼
              ┌──────────────────────────────────┐
              │       Namespace du router L3      │
              │     qrouter-xxxx (L3 + NAT)       │
              │ Interfaces :                       │
              │   - qr-*   (réseaux privés)        │
              │   - qg-*   (gateway externe)       │
              └──────────────────────────────────┘
                                │
                        iptables NAT SNAT/DNAT
                                │
                                ▼
                    ┌─────────────────────┐
                    │       br-ex         │   ← Bridge externe
                    │   - phy-br-ex       │
                    │   - int-br-ex       │
                    └─────────────────────┘
                                │
                                ▼
                            enp0s10
                              │
                              ▼
                           Internet
```

---

# 🟪 **4. VUE STRUCTURÉE PAR PLAN**

## 🌐 **PLAN PHYSIQUE (PHY)**

```
enp0s3   → management
enp0s8   → API / internal
enp0s10  → external (NAT / Floating IP)
```

## 🟦 **PLAN VIRTUEL – OPEN vSWITCH**

### 🔹 br-int (interne Neutron)

Ports présents (réels !) :

* qvo10f0e841-e6 (ta VM)
* qvo69a54f26-97 (autre port VM)
* qvoceceaca3-2f (autre VM)
* qr-* (ports router)
* qg-* (ports gateway external)
* tap0cb59d4c-c6 (DHCP port)
* tap7af2a988-2b (DHCP port)
* int-br-ex
* patch-tun

### 🔹 br-tun (VXLAN overlay)

* patch-int
* patch-tun

### 🔹 br-ex (réseau externe)

* phy-br-ex
* int-br-ex
* enp0s10

---

# 🟧 **5. VUE SPÉCIFIQUE DE TON PORT VM**

Port Neutron → Interface host → Bridge → L3

```
Neutron Port ID → tap10f0e841-e6 → qbr10f0e841-e6 → qvo10f0e841-e6 → br-int → qrouter → NAT → br-ex → enp0s10 → Internet
```

---

# 🟥 **6. VUE “ENTRAILS” (les entrailles du routing)**

Les namespaces dans ta config :

```
qrouter-6b789bb0-6b
qdhcp-10f0e841-e6
qdhcp-ceceaca3-2f
```

Dans qrouter :

Interfaces :

```
qr-6b789bb0-6b → réseau privé 192.168.0.0/24
qg-1ab75116-33 → gateway externe
qg-eb2b003a-d0 → floating IP
```

---

# 🟩 **7. VUE “UPLINK” exacte à partir de ton `ip a`**

```
qvo10f0e841-e6 (VM)
 ↓
ovs-system
 ↓
br-int
 ↓
patch-int
 ↓
br-tun
 ↓
VXLAN
 ↓
router namespace
 ↓
br-ex
 ↓
enp0s10
 ↓
INTERNET
```

---

# 🟦 **8. VUE PACKETS FLOW (capture depuis ton infra)**

### 🎯 Ping de la VM vers 8.8.8.8

```
tap10f0e841-e6       → trafic brut VM
qbr10f0e841-e6       → SG filtering
qvb/qvo               → L2 boundary
br-int                → switching L2
br-tun                → encapsulation VXLAN
qrouter namespace      → routage + NAT
br-ex                 → uplink
enp0s10               → sortie physique
```


# 🟥 **1. SCHÉMA : ML2/OVS-ONLY (modern OpenStack, recommandé)**

➡️ **Plus de LinuxBridge**
➡️ **Plus de qbr, qvb, qvo**
➡️ **Security Groups = conntrack OVS**
➡️ **VM directement dans br-int**

```
VM (eth0)
   │
   ▼
tap-VMID
   │
   ▼
┌──────────────────────────┐
│         br-int           │   ← Switch SDN OVS
│  - Ports VMs             │
│  - Ports router qr-*     │
│  - Ports gateway qg-*    │
│  - patch-int ↔ patch-tun │
└──────────────────────────┘
   │
   ▼
┌──────────────────────────┐
│         br-tun           │   ← VXLAN/Geneve tunnels
│   UDP 4789               │
└──────────────────────────┘
   │
VXLAN encapsulation
   │
   ▼
┌──────────────────────────┐
│       qrouter-XXXX        │ ← Namespace L3
│  NAT, DNAT, forwarding    │
└──────────────────────────┘
   │
   ▼
┌──────────────────────────┐
│         br-ex             │ ← réseau externe
└──────────────────────────┘
   │
   ▼
NIC externe (enp0s10)
```

➡️ **Pipeline simple, performant, moderne.**

---

# 🟦 **2. SCHÉMA : LinuxBridge + OVS (configuration hybride)**

➡️ **Ce que tu as actuellement**
➡️ Mélange **LinuxBridge + OVS**
➡️ pipeline L2 complexe

```
VM (eth0)
   │
   ▼
tap10f0e841-e6
   │
   ▼
qbr10f0e841-e6             ← LinuxBridge (Security Groups)
   │
qvb10f0e841-e6             
   │  veth pair
qvo10f0e841-e6              
   │
   ▼
┌──────────────────────────┐
│         br-int           │   ← OVS SDN switch
│  Ports VMs qvo-*         │
│  Ports router qr-*       │
│  Ports gateway qg-*      │
│  patch-int ↔ patch-tun   │
└──────────────────────────┘
   │
   ▼
┌──────────────────────────┐
│         br-tun           │   ← VXLAN overlay
└──────────────────────────┘
   │
   ▼
qrouter-XXXX (namespace L3)
   │
   ▼
br-ex
   │
   ▼
enp0s10 (NIC physique)
```

➡️ **Pipeline long, legacy, mais robuste.**

---

# 🟩 **3. SCHÉMA : ML2/OVN (Open Virtual Network)**

➡️ Le **futur** d’OpenStack
➡️ Plus de br-int, br-tun, qbr, qvb, qvo
➡️ Tout est LOGIQUE (Software-Defined L2/L3/NAT)

```
VM (eth0)
   │
   ▼
tap-VMID
   │
   ▼
┌──────────────────────────┐
│        ovn-controller     │   ← Local OVN agent
│   - met à jour OVS flows  │
└──────────────────────────┘
   │
Geneve Tunnel (L3 overlay)
   │
   ▼
┌──────────────────────────┐
│      OVN Northbound DB    │
│  Logical Switches         │
│  Logical Routers          │
│  NAT, LB, ACLs            │
└──────────────────────────┘
   │
   ▼
┌──────────────────────────┐
│     Logical Router (LR)   │  ← NAT, DNAT, routing
└──────────────────────────┘
   │
   ▼
External network (provider)
```

➡️ **Architecture cloud moderne, puissante, scalable.**

---

# 🟪 **4. TABLEAU RÉCAPITULATIF ULTRA-COMPLET**

| Architecture                | Technologie      | Où se trouve la VM ?          | Security Groups | Pipeline L2              | Pipeline L3        | Types de tunnels | NAT               | Avantages                                   | Inconvénients                       |
| --------------------------- | ---------------- | ----------------------------- | --------------- | ------------------------ | ------------------ | ---------------- | ----------------- | ------------------------------------------- | ----------------------------------- |
| **OVS-only**                | ML2/OVS          | Directement dans br-int       | OVS conntrack   | Très simple              | qrouter L3 agent   | VXLAN            | Oui               | Moderne, performant, simple                 | Debug OpenFlow                      |
| **LinuxBridge + OVS** (toi) | ML2 LB + ML2 OVS | tap → qbr → qvb/qvo           | iptables (L3)   | Pipeline long            | qrouter L3 agent   | VXLAN            | Oui               | Stable, compatible, pédagogique             | Lent, pipeline complexe             |
| **OVN**                     | ML2/OVN          | tap → OVS → logical switching | ACL OVN         | Virtuel (logical switch) | Logical Router OVN | Geneve           | Oui (logical NAT) | Très scalable, futur OpenStack, no L3 agent | Complexité initiale                 |
| **LinuxBridge-only**        | ML2 LB           | tap → brq                     | iptables        | Simple mais limité       | qrouter            | VXLAN            | Oui               | Simple                                      | Obsolète                            |
| **OVS-DPDK**                | ML2/OVS          | br-int userspace              | conntrack       | Très rapide              | qrouter            | VXLAN            | Oui               | Performance immense                         | Très complexe                       |
| **SR-IOV**                  | SR-IOV NICs      | NIC virtuelle matérielle      | Aucun           | Pas de pipeline SDN      | Routeur externe    | Aucun tunnel     | Non               | Très rapide                                 | Pas de SG, pas de NAT, pas de VXLAN |

---

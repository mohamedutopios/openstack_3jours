Parfait 👌 tu veux un **scénario concret avec 2 VM dans 2 réseaux différents**, reliées par un **routeur Neutron (L3 agent)**, **sans SSH** (uniquement via la **console Horizon/NoVNC ou série**).

Voici un **TP complet étape par étape**.

---

# 🚀 Scénario : 2 VM dans 2 réseaux privés, reliées par un routeur virtuel

---

## 1️⃣ Créer les réseaux et sous-réseaux

```bash
openstack network create net-a
openstack subnet create --network net-a --subnet-range 10.20.0.0/24 subnet-a

openstack network create net-b
openstack subnet create --network net-b --subnet-range 10.30.0.0/24 subnet-b
```

---

## 2️⃣ Créer un routeur Neutron

```bash
openstack router create router-ab
openstack router add subnet router-ab subnet-a
openstack router add subnet router-ab subnet-b
```

👉 Cela crée un namespace Linux `qrouter-xxxx` avec 2 interfaces internes :

* `qr-...` sur `10.20.0.1` (gateway de net-a)
* `qr-...` sur `10.30.0.1` (gateway de net-b)

---

## 3️⃣ Lancer deux VM

```bash
openstack server create \
  --flavor m1.small --image cirros \
  --network net-a \
  --key-name mykey \
  --security-group <ID_SG> \
  vm-a

openstack server create \
  --flavor m1.small --image cirros \
  --network net-b \
  --key-name mykey \
  --security-group <ID_SG> \
  vm-b
```

⚠️ Utilise l’**ID** du security group, pas le nom `default` (tu avais eu une erreur).

---

## 4️⃣ Accéder aux VM via **console**

* Dans **Horizon** → onglet **Console** → tu entres dans `vm-a`.
* Ou via CLI (console série si activée) :

  ```bash
  openstack console url show --serial vm-a
  openstack console url show --serial vm-b
  ```

  Tu récupères un lien `ws://…:6083/?token=…` → ouvrable dans Horizon ou via `wscat`.

---

## 5️⃣ Tester la connectivité

Dans la console de **vm-a** :

```bash
ping 10.30.0.5
```

➡️ Si `vm-b` a l’IP `10.30.0.5`, le ping doit répondre car le **routeur Neutron route entre net-a et net-b**.

---

## 6️⃣ Vérifications côté infra (en parallèle)

* Liste des ports dans OVS :

  ```bash
  sudo docker exec -it openvswitch_vswitchd ovs-vsctl list-ports br-int
  ```

  Tu dois voir :

  * `tap...` pour vm-a et vm-b
  * `qr-...` pour les interfaces du routeur

* Namespace du routeur :

  ```bash
  ip netns
  ip netns exec qrouter-xxxx ip addr
  ```

  Tu verras `10.20.0.1` et `10.30.0.1`.

---

# 📐 Schéma logique

```
 [ vm-a 10.20.0.5 ] -- net-a -- qr-xxxx (10.20.0.1) 
                                    |
                                    |   qrouter-xxxx  (L3 agent Neutron)
                                    |
 [ vm-b 10.30.0.5 ] -- net-b -- qr-yyyy (10.30.0.1)
```

---

# ✅ Résumé

* Tu as **2 VM isolées sur 2 réseaux privés distincts**.
* Un **routeur Neutron** route entre `net-a` et `net-b`.
* Tu testes la connectivité **depuis la console VM** (NoVNC ou série), **sans SSH**.
* Côté infra → tu vois les ports `tap*` et `qr-*` dans **OVS (`br-int`)** et les interfaces dans le namespace `qrouter`.

---

👉 Veux-tu que je t’écrive ce scénario en **version TP pédagogique complet** (énoncé + corrigé + commandes d’observation côté OVS + namespace) comme si c’était pour une classe ?

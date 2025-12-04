# 🔎 Rôle de `init-runonce`

C’est un script fourni avec **Kolla-Ansible** (dans les exemples) pour :

* **Initialiser ton cloud OpenStack après le premier déploiement**
* Créer un environnement **demo prêt à l’emploi** :

  * Télécharge l’image Cirros
  * Crée un réseau externe (`public1`) et un réseau locataire (`demo-net`)
  * Configure un routeur
  * Ajoute des règles de sécurité de base (ICMP, SSH)
  * Ajoute une paire de clés (`mykey`)
  * Définit des quotas pour permettre de lancer 40 VMs
  * Crée les flavors classiques (`m1.tiny`, `m1.small`, etc.)

---

# 🟢 Ton cas spécifique

J’ai noté dans ton script que tu as ces variables :

```bash
EXT_NET_CIDR='9.12.93.0/24'
EXT_NET_RANGE='start=9.12.93.150,end=9.12.93.199'
EXT_NET_GATEWAY='9.12.93.1'
```

👉 Ça correspond à ton interface **`enp0s9 (9.12.93.4)`**, que tu avais vu dans ton `ip a`.
Donc ce script a **directement configuré Neutron pour utiliser enp0s9 comme réseau externe**.

---

# ⚙️ Comment l’utiliser

1. Charge tes credentials admin :

   ```bash
   source /etc/kolla/admin-openrc.sh
   ```

2. Lance le script :

   ```bash
   ./init-runonce
   ```

3. Vérifie les ressources créées :

   ```bash
   openstack image list
   openstack network list
   openstack router list
   openstack flavor list
   ```

---

# 🟢 Résultat attendu

* **Image Cirros** disponible :

  ```
  +--------------------------------------+--------+--------+
  | ID                                   | Name   | Status |
  +--------------------------------------+--------+--------+
  | a1b2c3d4-5678-...                    | cirros | active |
  +--------------------------------------+--------+--------+
  ```

* **Réseaux créés** :

  ```
  public1  (external, 9.12.93.0/24)
  demo-net (tenant, 10.0.0.0/24)
  ```

* **Flavors créés** :

  ```
  m1.tiny, m1.small, m1.medium, m1.large, m1.xlarge
  ```

* **Quota admin augmenté** : 40 instances, 96GB RAM.

---

# 🚀 Tu peux ensuite lancer ta première VM

```bash
openstack server create \
  --image cirros \
  --flavor m1.tiny \
  --key-name mykey \
  --network demo-net \
  demo1
```

👉 Tu auras une VM **connectée à demo-net** et routée vers Internet via `public1`.
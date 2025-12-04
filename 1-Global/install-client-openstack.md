# 🟢 1. Installer le client OpenStack

Sous Ubuntu (22.04/24.04), la bonne commande est :

```bash
apt update
apt install -y python3-openstackclient
```

👉 Cela va installer la commande `openstack`.

---

# 🟢 2. Charger les credentials admin

Avant de taper tes commandes OpenStack, tu dois **sourcer ton fichier credentials** généré par Kolla :

```bash
source /etc/kolla/admin-openrc.sh
```

👉 Ce fichier définit :

* `OS_USERNAME=admin`
* `OS_PASSWORD=...`
* `OS_AUTH_URL=http://9.11.93.4:5000/v3`
* etc.

Sans ça, la CLI ne sait pas comment parler à Keystone.

---

# 🟢 3. Tester avec quelques commandes

Une fois installé + credentials chargés :

```bash
openstack service list
openstack endpoint list
openstack compute service list
openstack network agent list
openstack volume service list
```

👉 Là tu verras tous les services actifs dans ton cloud.

---

# 🟢 4. Vérifier que tout marche

Exemple rapide :

```bash
openstack image list
openstack network list
openstack server list
```

---

# 🚀 Résumé pratique

1. Installe la CLI :

   ```bash
   apt install -y python3-openstackclient
   ```
2. Source le fichier credentials :

   ```bash
   source /etc/kolla/admin-openrc.sh
   ```
3. Liste les services :

   ```bash
   openstack service list
   openstack compute service list
   openstack network agent list
   ```



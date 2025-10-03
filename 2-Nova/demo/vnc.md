Très bonne question ⚡!
Pour te donner un **vrai exemple utile et réaliste** de modification Nova, je vais prendre un cas courant en lab et en prod :

👉 **Activer la console VNC pour accéder à tes VMs via Horizon**

---

# 🎯 Pourquoi c’est utile ?

* Par défaut, tu ne peux pas voir la console graphique de tes VMs.
* Avec **noVNC**, tu peux ouvrir un terminal web depuis Horizon (pratique si ta VM ne répond pas en SSH).
* C’est souvent la première modif que font les admins après un déploiement Kolla-Ansible.

---

# ⚙️ Étapes détaillées

### 1. Créer un override Nova

```bash
sudo mkdir -p /etc/kolla/config/nova
sudo nano /etc/kolla/config/nova/nova.conf
```

### 2. Ajouter cette configuration

```ini
[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = 192.168.56.11
novncproxy_base_url = http://192.168.56.11:6080/vnc_auto.html
```

👉 Remplace `192.168.56.11` par l’IP de ton **contrôleur** (celle où Horizon est accessible).

---

### 3. Redéployer Nova

```bash
kolla-ansible -i /etc/kolla/all-in-one deploy --tags nova
docker restart nova_novncproxy
```

---

### 4. Lancer une VM pour tester

```bash
openstack server create \
  --flavor m1.tiny \
  --image cirros \
  --network demo-net \
  --security-group default \
  --key-name mykey \
  test-vm
```

---

### 5. Vérifier dans Horizon

* Va dans **Projet → Instances → test-vm → Console**.
* Tu dois voir l’écran de login Cirros (`cirros login:`).

---

# ✅ Résultat attendu

* Tu peux ouvrir la console VNC directement dans ton navigateur.
* Même si la VM n’a pas de Floating IP ou que SSH est bloqué, tu as un accès.
* C’est la méthode standard de **troubleshooting OpenStack**.

---

# 📝 Bonus : Démo CLI

Tu peux aussi tester depuis la CLI :

```bash
openstack console url show test-vm
```

👉 Résultat attendu :

```
+-------+---------------------------------------------------------------------------+
| Field | Value                                                                     |
+-------+---------------------------------------------------------------------------+
| type  | novnc                                                                     |
| url   | http://192.168.56.11:6080/vnc_auto.html?token=xxxxxxxxxxxxxxxxxxxxxxxxxxx |
+-------+---------------------------------------------------------------------------+
```

En ouvrant l’URL → tu accèdes à la console.

---

👉 Ça, c’est un **exemple concret et très utile** de modification Nova.

Veux-tu que je t’en donne un deuxième, orienté **optimisation des ressources** (ex : limiter la surallocation CPU/RAM pour éviter que les compute soient surchargés) ?

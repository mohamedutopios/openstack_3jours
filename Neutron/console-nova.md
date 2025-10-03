Très bien 👌 je vais te donner un **guide complet pas-à-pas** pour mettre en place la console (VNC + Serial) dans OpenStack avec **Kolla-Ansible**, jusqu’à pouvoir entrer dans ta VM sans SSH.

---

# 🚀 Étapes pour activer et utiliser la console dans OpenStack

---

## 1️⃣ Activer la console dans Kolla-Ansible

### Dans `/etc/kolla/globals.yml` :

```yaml
# Console VNC (graphique via noVNC)
enable_nova_console: "yes"

# Console série (texte via websocket proxy)
enable_nova_serialconsole_proxy: "yes"
```

👉 Cela active :

* le conteneur `nova-novncproxy` (port 6080),
* le conteneur `nova-serialproxy` (port 6083).

---

## 2️⃣ (Optionnel) Override Nova pour configurer le proxy

Crée un fichier override :
`/etc/kolla/config/nova/nova.conf`

```ini
[vnc]
enabled = true
novncproxy_host = 0.0.0.0
novncproxy_port = 6080
novncproxy_base_url = http://<IP_CONTROLLER>:6080/vnc_auto.html
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = <IP_CONTROLLER>

[serial_console]
enabled = true
base_url = ws://<IP_CONTROLLER>:6083/
listen = 0.0.0.0
proxyclient_address = <IP_CONTROLLER>
```

⚠️ `<IP_CONTROLLER>` = l’IP que tu utilises pour Horizon depuis ton hôte (ex: 9.11.93.4).

---

## 3️⃣ Reconfigurer Nova et Horizon

```bash
kolla-ansible -i /etc/kolla/all-in-one reconfigure -t nova
kolla-ansible -i /etc/kolla/all-in-one reconfigure -t horizon
```

---

## 4️⃣ Vérifier les services

```bash
docker ps | grep nova-novncproxy
docker ps | grep nova-serialproxy
```

Tu dois voir les deux conteneurs actifs.

Vérifie aussi que les ports sont ouverts :

```bash
ss -lntp | grep 608
```

---

## 5️⃣ Créer une VM avec console activée

Exemple :

```bash
openstack server create \
  --flavor m1.small \
  --image cirros \
  --network demo-net \
  --key-name mykey \
  --security-group <ID_SG> \
  vm-console
```

*(utilise l’ID du security group pour éviter le conflit avec plusieurs `default`).*

---

## 6️⃣ Accéder à la console

### 🔹 Depuis Horizon

* **VNC** : onglet *Console* → tu verras l’écran de ta VM.
* **Serial** : Horizon bascule automatiquement si VNC ne marche pas (texte brut).

### 🔹 Depuis CLI (serial)

Obtenir l’URL :

```bash
openstack console url show --serial vm-console
```

Tu verras :

```
ws://9.11.93.4:6083/?token=xxxxxxxx
```

➡️ Ouvre Horizon → Console, ou connecte-toi avec `wscat` :

```bash
npm install -g wscat
wscat -c "ws://9.11.93.4:6083/?token=xxxxxxxx"
```

---

## 7️⃣ Accès direct via virsh (admin uniquement)

Si tu veux forcer l’accès depuis l’hôte :

```bash
sudo docker exec -it nova_libvirt virsh list --all
sudo docker exec -it nova_libvirt virsh console <ID_VM>
```

⚠️ Ça ne marche que si `[serial_console] enabled = true` et l’image supporte la console série.

---

# ✅ Résumé

1. Activer `enable_nova_console` et `enable_nova_serialconsole_proxy` dans `globals.yml`.
2. Ajouter overrides `nova.conf` (VNC + Serial).
3. `kolla-ansible reconfigure -t nova,horizon`.
4. Vérifier les conteneurs et ports 6080 (VNC) / 6083 (Serial).
5. Créer une nouvelle VM.
6. Accéder via Horizon (Console) ou `openstack console url show`.
7. Debug possible avec `virsh console`.

---

👉 Veux-tu que je t’écrive aussi le **checklist rapide de debug** (commandes à lancer si la console reste grise dans Horizon) ?

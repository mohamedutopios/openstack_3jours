Tu as raison, dans la “version complète” il manquait :

1. **La mise en place propre de l’environnement kolla-ansible (venv + dépendances)**
2. **Le rappel / contrôle de l’inventaire `all-in-one` pour Swift**

Je te redonne donc **le projet Swift de A à Z**, en intégrant ces deux points, et en corrigeant les détails qu’on a découverts ensemble.

> 💡 On part de ton contexte réel :
> Ubuntu 18.04, OpenStack Ussuri déjà installé avec Kolla-Ansible dans une VM VirtualBox (`9.11.93.4`), services Nova/Neutron/Glance/Cinder/Keystone/Horizon OK.

---

# 🧩 0. Préparer l’environnement kolla-ansible (venv + dépendances)

👉 À faire **en root** sur l’hôte (pas dans un container).

```bash
sudo -i
apt update
apt install -y python3-venv python3-dev libffi-dev gcc libssl-dev libyaml-dev
```

Créer un virtualenv dédié pour kolla-ansible :

```bash
python3 -m venv /root/kolla-openstack
source /root/kolla-openstack/bin/activate
```

Mettre à jour `pip`/`setuptools` pour éviter l’erreur `setuptools_rust` avec `cryptography` :

```bash
python -m pip install --upgrade "pip==21.3.1" "setuptools<60" "wheel"
```

Installer une version de `cryptography` compatible Python 3.6 **sans Rust** :

```bash
pip install "cryptography==3.4.8"
```

Installer kolla-ansible + ansible dans ce venv :

```bash
pip install "ansible==2.9.27" "kolla-ansible==10.2.0"
```

Vérifier :

```bash
kolla-ansible --version
ansible --version
```

> 🔁 **À chaque fois que tu veux utiliser kolla-ansible** :
> `sudo -i` puis
> `source /root/kolla-openstack/bin/activate`

---

# 🗂 1. Vérifier / préparer l’inventaire `all-in-one`

On va utiliser ton inventaire **AIO** (fichier `all-in-one`) et vérifier que Swift est bien mappé sur `localhost`.

Dans ton cas, il ressemble déjà à ceci (extrait important) :

```ini
[control]
localhost       ansible_connection=local

[network]
localhost       ansible_connection=local

[compute]
localhost       ansible_connection=local

[storage]
localhost       ansible_connection=local

[monitoring]
localhost       ansible_connection=local

[deployment]
localhost       ansible_connection=local

# ...

[swift:children]
control

[swift-proxy-server:children]
swift

[swift-account-server:children]
storage

[swift-container-server:children]
storage

[swift-object-server:children]
storage
```

✅ Ce mapping est **parfait pour un AIO** :

* Proxy sur le groupe `swift` (qui est `control` donc `localhost`)
* Account / Container / Object sur le groupe `storage` (`localhost` aussi)

Juste pour être sûr, tu peux mettre ce fichier à un endroit “classique” :

```bash
mkdir -p /etc/kolla
cp /home/devops/all-in-one /etc/kolla/all-in-one
```

On utilisera ensuite `/etc/kolla/all-in-one` dans les commandes `kolla-ansible`.

---

# 💽 2. Ajouter et préparer le disque Swift

## 2.1. Ajouter un disque dans VirtualBox

1. Éteindre la VM.
2. VirtualBox → **Paramètres → Stockage**.
3. Ajouter un nouveau disque VDI :

   * Taille : **20 Go**
   * Type : Dynamique
4. Démarrer la VM.

Dans la VM :

```bash
lsblk
```

Tu dois voir un disque sans partition, style :

```text
sdb      20G   disk
```

---

## 2.2. Partitionner + formater en XFS avec label `SWIFT_DATA`

```bash
sudo parted /dev/sdb --script mklabel gpt
sudo parted /dev/sdb --script mkpart primary 0% 100%
```

Formater avec un **label court (≤ 12 caractères)** :

```bash
sudo mkfs.xfs -f -L SWIFT_DATA /dev/sdb1
```

Vérifier :

```bash
lsblk -f
```

Attendu :

```text
sdb1    xfs   SWIFT_DATA   UUID...
```

---

## 2.3. Monter le disque sur `/srv/node/sdb1`

```bash
sudo mkdir -p /srv/node/sdb1
echo 'LABEL=SWIFT_DATA /srv/node/sdb1 xfs defaults 0 0' | sudo tee -a /etc/fstab
sudo mount -a
df -h | grep /srv || echo "AUCUN_MONTAGE_SRV"
```

Tu dois voir :

```text
/dev/sdb1   21G  ...  /srv/node/sdb1
```

---

## 2.4. Permissions UID pour l’utilisateur `swift` (point clé)

Dans Kolla, l’utilisateur `swift` n’a pas un UID classique (c’est un UID dans la plage 42xxx).
On **vérifie dans un container** (par ex. `swift_account_server`) :

```bash
docker exec -it swift_account_server id swift
```

Tu verras quelque chose comme :

```text
uid=42445(swift) gid=42445(swift) groups=42445(swift)
```

➡️ C’est **cet UID-là** qu’il faut appliquer sur l’hôte.

Donc :

```bash
sudo chown -R 42445:42445 /srv/node/sdb1
sudo chmod -R 755 /srv/node/sdb1
```

(Adapte `42445` si ton `id swift` renvoie un autre UID.)

Vérifier :

```bash
ls -lan /srv/node
ls -lan /srv/node/sdb1
```

Attendu :

```text
drwxr-xr-x 2 42445 42445  ...  sdb1
```

---

# ⚙️ 3. Configuration Swift dans `globals.yml`

Éditer `/etc/kolla/globals.yml` et ajouter/modifier la partie Swift :

```yaml
# Swift - Object Storage Options
enable_swift: "yes"

# Le disque est détecté par label XFS
swift_devices_match_mode: "strict"
swift_devices_name: "SWIFT_DATA"
# enable_swift_s3api: "no"   # tu pourras l'activer plus tard si tu veux l'API S3
```

Enregistrer.

---

# 🧱 4. Installer les outils Swift *sur l’hôte* (pour créer les rings)

Il te faut `swift-ring-builder` **sur l’hôte** (pas dans les containers) :

```bash
apt update
apt install -y swift swift-account swift-container swift-object
```

Si tu as déjà corrigé DNS, ça passe désormais.
(En cas de souci DNS : vérifier `/etc/resolv.conf`.)

sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf'


---

# 🔁 5. Créer les Swift rings dans `/etc/kolla/config/swift`

Les rings doivent être créés **sur l’hôte** dans le répertoire de config Kolla :

```bash
sudo mkdir -p /etc/kolla/config/swift
cd /etc/kolla/config/swift
```

## 5.1. Account Ring

```bash
sudo swift-ring-builder account.builder create 10 1 1

sudo swift-ring-builder account.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6001 \
  --device sdb1 --weight 100

sudo swift-ring-builder account.builder rebalance
```

## 5.2. Container Ring

```bash
sudo swift-ring-builder container.builder create 10 1 1

sudo swift-ring-builder container.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6002 \
  --device sdb1 --weight 100

sudo swift-ring-builder container.builder rebalance
```

## 5.3. Object Ring

```bash
sudo swift-ring-builder object.builder create 10 1 1

sudo swift-ring-builder object.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6000 \
  --device sdb1 --weight 100

sudo swift-ring-builder object.builder rebalance
```

Vérifier l’état des rings :

```bash
swift-ring-builder account.builder
swift-ring-builder container.builder
swift-ring-builder object.builder
```

Puis vérifier les fichiers `.ring.gz` :

```bash
ls -lh /etc/kolla/config/swift/*.ring.gz
```

Tu dois voir :

```text
account.ring.gz
container.ring.gz
object.ring.gz
```

---

# 🚀 6. (Re)déployer Swift avec kolla-ansible

Toujours dans le **virtualenv** :

```bash
sudo -i
source /root/kolla-openstack/bin/activate
cd /etc/kolla
```

### 6.1. Préchecks

```bash
kolla-ansible -i ./all-in-one prechecks --tags swift
```

### 6.2. Déploiement Swift uniquement

```bash
kolla-ansible -i ./all-in-one deploy --tags swift
```

### 6.3. Post-deploy (si pas déjà fait)

```bash
kolla-ansible post-deploy
```

### 6.4. Vérifier les containers Swift

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep swift
```

Attendu :

```text
swift_proxy_server
swift_account_server
swift_container_server
swift_object_server
swift_rsyncd
swift_account_auditor
swift_account_replicator
swift_account_reaper
swift_container_auditor
swift_container_replicator
swift_container_updater
swift_object_auditor
swift_object_replicator
swift_object_updater
swift_object_expirer
```

> Si un container est en `Restarting`, faire `docker logs <nom>`.

---

# 🔍 7. Vérifier que les rings sont bien dans les containers

```bash
docker exec -it swift_proxy_server   ls -l /etc/swift/*.ring.gz
docker exec -it swift_account_server ls -l /etc/swift/account.ring.gz
docker exec -it swift_container_server ls -l /etc/swift/container.ring.gz
docker exec -it swift_object_server    ls -l /etc/swift/object.ring.gz
```

Tout doit exister, propriétaire `swift:swift`.

---

# 🧪 8. Tests côté OpenStack (CLI)

```bash
source /etc/kolla/admin-openrc.sh

# Vérifier que le service "object-store" existe
openstack service list | grep -i object

# Lister tes endpoints Swift
openstack endpoint list | grep -i object

# Créer un container
openstack container create demo

# Ajouter un objet
openstack object create demo /etc/hosts

# Lister les objets


# Télécharger l’objet
openstack object save demo /etc/hosts --file /tmp/hosts-downloaded
diff /etc/hosts /tmp/hosts-downloaded
```

Si ça fonctionne → ✅ Swift OK.

En cas d’erreur 503, regarder en priorité :

```bash
docker logs swift_proxy_server --tail 50
docker logs swift_account_server --tail 50
docker logs swift_container_server --tail 50
docker logs swift_object_server --tail 50
```

---

# 🌐 9. Tests dans Horizon

1. Aller sur Horizon (`http://9.11.93.4` ou l’IP de ton VIP).
2. Se connecter en `admin`.
3. Menu **Project → Object Store → Containers**.
4. Créer un container `demo`.
5. Uploader un fichier → tu dois voir l’objet apparaître.

---

## ✅ Résumé de ce qui était “manquant” et est maintenant intégré

* ✔️ Mise en place correcte d’un **virtualenv kolla-ansible** avec :

  * `pip` + `setuptools` compatibles
  * `cryptography==3.4.8`
  * `ansible==2.9.27`
  * `kolla-ansible==10.2.0`
* ✔️ Clarification sur **l’inventaire `all-in-one`** :

  * `localhost` dans `[storage]`
  * groupes `[swift]`, `[swift-account-server]`, `[swift-container-server]`, `[swift-object-server]`
* ✔️ Correction de l’UID **réel** de `swift` (lecture via `docker exec id swift`), puis `chown` du disque.
* ✔️ Chemin **exact** des rings : `/etc/kolla/config/swift/*.ring.gz` et propagation dans les containers.
* ✔️ Séquence complète : disque → filesystem → permissions → `globals.yml` → rings → `kolla-ansible` → tests CLI + Horizon.

Si tu veux, au prochain message, tu peux juste coller :

* `id swift` dans un container
* la sortie de `openstack container list` (après ces étapes)

et on valide ensemble que ton Swift est désormais “production ready” pour ton lab.

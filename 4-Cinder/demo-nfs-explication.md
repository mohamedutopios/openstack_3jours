# 🚀 **Cinder avec un backend NFS**

*(explication complète et commentée)*

---

# 🟦 **1. Préparer un répertoire NFS sur ton hôte (Ubuntu)**

👉 Objectif : créer un **point de stockage partagé** accessible par les containers Cinder.

---

## ► Installer le serveur NFS

```bash
sudo apt update
sudo apt install nfs-kernel-server -y
```

### 💬 Pourquoi ?

* Cinder peut utiliser **NFS** comme backend de stockage.
* Donc ton hôte doit **exporter un dossier NFS** qui sera monté dans le container `cinder-volume`.
* `nfs-kernel-server` fournit :

  * le démon NFS
  * les exports
  * tout le RPC nécessaire

---

## ► Créer le dossier où seront stockés les volumes Cinder

```bash
sudo mkdir -p /var/lib/cinder-nfs
sudo chown -R nobody:nogroup /var/lib/cinder-nfs
sudo chmod 777 /var/lib/cinder-nfs
```

### 💬 Pourquoi ?

* Chaque volume OpenStack sera un **fichier** dans ce dossier NFS.
  Exemple : `/var/lib/cinder-nfs/volume-123456.qcow2`
* On donne des permissions larges :

  * `nobody:nogroup` = user par défaut utilisé par NFS (pour éviter root_squash)
  * `777` = simple pour un lab AIO, aucune friction avec Docker/Kolla

*(en production, on ferait plus propre, mais c’est parfait pour lab)*

---

## ► Configurer l’export NFS

```bash
echo "/var/lib/cinder-nfs *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

### 💬 Pourquoi ?

* On indique au serveur NFS :
  “Ce dossier est exporté pour **tous les clients** (*) en lecture/écriture.”
* `no_root_squash` permet au container `cinder-volume` (root dans Docker) d'écrire sans être limité.
* `sync` = écriture synchronisée → plus fiable, moins performant.
* `no_subtree_check` = évite des vérifications inutiles si on déplace le dossier.

---

## ► Vérification de l’export

```bash
showmount -e localhost
```

### 💬 Pourquoi ?

* Confirme que ton dossier est bien exposé par NFS.
* Le container Cinder va chercher **exactement la même info**.

Attendu :

```
/var/lib/cinder-nfs *
```

---

# 🟩 **2. Configurer Cinder pour utiliser NFS dans Kolla-Ansible**

👉 Objectif : dire à Cinder et Kolla-Ansible :
**“Arrête d'utiliser LVM, utilise ce serveur NFS comme backend.”**

---

## ► Modifier `/etc/kolla/globals.yml`

```yaml
enable_cinder: "yes"
# Active Cinder dans ton déploiement

enable_cinder_backend_lvm: "no"
# Désactive LVM : utile en VirtualBox car LVM+iSCSI pose souvent des problèmes de kernel

enable_cinder_backend_nfs: "yes"
# Active le backend NFS

cinder_nfs_servers: "localhost:/var/lib/cinder-nfs"
# Déclare le serveur NFS utilisé par Cinder
# Format obligatoire : HOST:/CHEMIN
```

### 💬 Pourquoi ?

* Kolla doit savoir quel backend activer.
* On **désactive LVM** (backend par défaut).
* On **active NFS**.
* Cinder va monter ce NFS dans son container `cinder-volume`.

---

## ► Fichier attendu par Cinder : `nfs_shares`

Kolla-Ansible attend un fichier dans :

```
/etc/kolla/config/cinder/nfs_shares
```

Donc on le crée :

```bash
sudo mkdir -p /etc/kolla/config/cinder
echo "localhost:/var/lib/cinder-nfs" | sudo tee /etc/kolla/config/cinder/nfs_shares
```

### 💬 Pourquoi ?

* Cinder lit directement ce fichier pour connaître les serveurs NFS autorisés.
* Chaque ligne = un export NFS que Cinder peut utiliser.
* Dans ton cas : un seul export : `localhost:/var/lib/cinder-nfs`.

---

## ► Permissions du fichier

```bash
sudo chmod 644 /etc/kolla/config/cinder/nfs_shares
```

### 💬 Pourquoi ?

* Le fichier doit être lisible par :

  * Ansible (en root)
  * Le container Cinder (root)
* 644 = lecture globale, écriture root.

---

## ► Re-déployer uniquement Cinder

```bash
kolla-ansible -i /etc/kolla/all-in-one reconfigure -t cinder
```

### 💬 Pourquoi ?

* Pas besoin de tout redéployer.
* `reconfigure` applique uniquement les changements de conf.
* `-t cinder` = exécute uniquement les rôles Cinder.
* Le container `cinder-volume` va :

  * monter le NFS
  * lire le fichier `nfs_shares`
  * se configurer en backend NFS

---

## ► Vérifier que le backend NFS est reconnu

```bash
openstack volume service list
```

Attendu :

```
cinder-volume  ...  enabled  up   ...  opendstack@nfs-1
```

### 💬 Pourquoi ?

* Cela affiche la liste des backends Cinder actifs.
* Si `nfs-1` apparaît → backend actif.
* Si DOWN → problème de montage NFS.

---

# 🟧 **5. Tester un volume**

## ► Créer un volume

```bash
openstack volume create --size 1 test-nfs
```

### 💬 Ce que fait Cinder :

* Cinder crée un fichier de 1 GB dans le répertoire NFS :

```
/var/lib/cinder-nfs/volume-UUID
```

* Ce volume est exposé à Nova via NFS mount indirect.

---

## ► Vérifier

```bash
openstack volume list
```

### Statut attendu :

```
available
```

---

## ► Attacher à une VM

```bash
openstack server add volume <ID_VM> test-nfs
```

### 💬 Ce que fait OpenStack :

1. Nova contacte Cinder pour attacher le volume.
2. Cinder appelle le driver NFS.
3. Nova injecte dans la VM un device virtuel correspondant.

Dans VirtualBox, **ça marche très bien**, pas de dépendance avec iSCSI ou multipath.

---

# 🎯 **Résumé expliqué pour comprendre complètement**

| Élément                               | Rôle                                             |
| ------------------------------------- | ------------------------------------------------ |
| NFS serveur                           | Stocke les volumes Cinder sous forme de fichiers |
| `globals.yml`                         | Dit à Kolla d'activer le backend NFS             |
| `nfs_shares`                          | Indique le chemin NFS à monter                   |
| `kolla-ansible reconfigure -t cinder` | Applique les changements                         |
| `openstack volume create`             | Crée un fichier `.img` dans /var/lib/cinder-nfs  |
| `server add volume`                   | Nova attache le volume à la VM                   |


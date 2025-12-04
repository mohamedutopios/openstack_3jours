# 1. INTRO : Comment fonctionne Cinder dans OpenStack ?

Cinder = Le service **Block Storage** d’OpenStack.
Il fournit des **volumes attachables** aux VM Nova, comme un disque virtuel.

### Cinder comporte :

| Composant            | Rôle                                                          |
| -------------------- | ------------------------------------------------------------- |
| **cinder-api**       | API REST que les clients (Horizon / CLI) appellent            |
| **cinder-scheduler** | Choisit le backend/pool où créer le volume                    |
| **cinder-volume**    | Le service qui gère le backend réel (LVM, Ceph, NetApp, etc.) |
| **backends**         | Là où les volumes sont physiquement stockés (LVM, Ceph RBD…)  |

> Kolla-Ansible déploie ces services en containers Docker.

---

# 2. Que sont les *pools de stockage* ?

Un pool = une zone de stockage d’un backend donné.

Exemples :

* **LVM** : un *pool* correspond à un **volume group LVM** (ex : `cinder-volumes`)
* **Ceph** : un *pool* correspond à un **pool Ceph RBD** (ex : `volumes`)
* **NetApp / SolidFire** : un pool correspond à un agrégat ou un LUN group.
* **NFS** : un pool = un backend (monte un export NFS).

Le scheduler Cinder choisit un **pool** selon :

* Taille libre
* Capacité restante
* Backend choisi par “volume_type”
* Politiques QoS / extra_specs

Tu peux voir tes pools :

```bash
openstack volume service list
openstack volume type list
cinder list --all
openstack volume pool list --detail
```

---

# 3. Backends supportés par Cinder

Voici une liste complète des backends Cinder connus et supportés :

### 🧪 **Backends simples / Lab**

* **LVM / iSCSI** (hyper simple à mettre en place)
* **NFS**
* **ISCSI generic backend**

### 🏭 **Backends Enterprise**

* **Ceph RBD (le plus courant en production)**
* **NetApp ONTAP**
* **Dell EMC PowerStore / PowerMax / XtremIO**
* **IBM Spectrum**
* **Pure Storage**
* **HPE 3PAR / Primera**
* **Huawei**
* **Hitachi**

### ☁️ Backends Cloud

* **Amazon EBS**
* **Google Persistent Disk**
* **VMware VMDK**
* **Azure Managed Disks (via drivers externes)**

Kolla-Ansible supporte officiellement **LVM** et **Ceph** très facilement.

---

# 4. Architecture Cinder avec Kolla-Ansible

Pour Kolla :

* Les backends sont définis dans :

```
/etc/kolla/config/cinder/cinder.conf
```

* Tu peux activer les backends dans :

```
/etc/kolla/globals.yml
```

Exemple d’activation :

```yaml
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
enable_cinder_backend_ceph: "no"
```

---

# 5. Backend 1 — **LVM (iSCSI)**

C’est **LE backend le plus simple** pour un lab AIO.

## 5.1. PRINCIPE

On crée :

1. Un **disque / loopback**
2. Un **volume group LVM**
3. On dit à Cinder que ce VG = backend

---

## 5.2. ÉTAPE 1 — Préparer un disque pour LVM

Dans un lab, tu crées un fichier de 20 Go :

```bash
fallocate -l 20G /var/lib/cinder.img
losetup /dev/loop3 /var/lib/cinder.img
pvcreate /dev/loop3
vgcreate cinder-volumes /dev/loop3
```

⚠️ **VG doit obligatoirement s’appeler `cinder-volumes`.**

---

## 5.3. ÉTAPE 2 — Activer backend LVM dans Kolla

Édite `/etc/kolla/globals.yml` :

```yaml
enable_cinder: "yes"
enable_cinder_backup: "yes"
enable_cinder_backend_lvm: "yes"
```

---

## 5.4. ÉTAPE 3 — Configurer cinder.conf

Le fichier de conf Kolla pour Cinder est :

```
/etc/kolla/config/cinder/cinder-volume.conf
```

Créer / éditer :

```ini
[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
iscsi_protocol = iscsi
iscsi_helper = lioadm
volumes_dir = /var/lib/cinder/volumes
```

---

## 5.5. ÉTAPE 4 — Déployer Cinder LVM

```bash
kolla-ansible -i /etc/kolla/inventory reconfigure --tags cinder
```

---

## 5.6. ÉTAPE 5 — Vérifications

```bash
docker ps | grep cinder
openstack volume service list
openstack volume pool list
```

Créer un volume :

```bash
openstack volume create --size 1 testvol
```

Attacher à une VM :

```bash
openstack server add volume myvm testvol
```

---

# 6. Backend 2 — **Ceph RBD**

C’est le backend **recommandé en production** et très performant.

## 6.1. PRINCIPE

* Cinder utilise **RBD** pour stocker ses volumes.
* Nova peut **boot-from-volume** directement depuis Ceph.
* Glance peut stocker ses images dedans aussi (optionnel mais recommandé).

---

## 6.2. ÉTAPE 1 — Installer Ceph (dans Kolla ou indépendamment)

Deux options :

### 🔵 Option A : Ceph via **Kolla-Ansible**

Tu actives :

```yaml
enable_ceph: "yes"
enable_ceph_rgw: "yes"
enable_cinder_backend_ceph: "yes"
enable_glance_backend_ceph: "yes"
```

Puis :

```bash
kolla-ansible -i inventory deploy --tags ceph
```

Kolla va :

* Déployer les OSD
* Créer les pools : `volumes`, `images`, `vms`
* Créer le client keyring `/etc/ceph/ceph.client.admin.keyring`

### 🟢 Option B : Ceph externe (cluster Ceph déjà existant)

Tu dois fournir à Kolla :

* `/etc/kolla/config/cinder/ceph.conf`
* `/etc/kolla/config/cinder/ceph.client.cinder.keyring`

---

## 6.3. ÉTAPE 2 — Créer les pools Ceph pour Cinder

Si Ceph n’a pas encore créé les pools :

```bash
ceph osd pool create volumes 128
ceph osd pool create images 128
ceph osd pool create vms 128
```

Autoriser Cinder :

```bash
ceph auth get-or-create client.cinder mon 'allow r' osd 'allow rwx pool=volumes'
```

---

## 6.4. ÉTAPE 3 — Config Cinder backend Ceph

Dans Kolla :

```
/etc/kolla/config/cinder/cinder-volume.conf
```

Contenu :

```ini
[ceph]
volume_driver = cinder.volume.drivers.rbd.RBDDriver
volume_backend_name = ceph
rbd_pool = volumes
rbd_ceph_conf = /etc/ceph/ceph.conf
rbd_user = cinder
rbd_secret_uuid = 00000000-0000-0000-0000-000000000000
```

Créer la clé :

```bash
ceph auth get-or-create client.cinder > /etc/kolla/config/cinder/ceph.client.cinder.keyring
```

---

## 6.5. ÉTAPE 4 — Déployer le backend Ceph

```bash
kolla-ansible -i inventory reconfigure --tags cinder
```

---

## 6.6. ÉTAPE 5 — Tests

Créer un volume Ceph :

```bash
openstack volume create --size 1 ceph-test
```

Tu dois voir dans Ceph :

```bash
rbd ls volumes
```

---

# 7. Backend 3 — **NFS** (simple)

Un backend intéressant pour stocker des snapshots ou backups.

## 7.1. Préparer NFS

Sur un serveur NFS :

```
/srv/nfs/cinder  *(rw,sync,no_root_squash,no_subtree_check)
```

---

## 7.2. Config Cinder

```
/etc/kolla/config/cinder/cinder-volume.conf
```

```ini
[nfs1]
volume_driver = cinder.volume.drivers.nfs.NfsDriver
nfs_shares_config = /etc/cinder/nfs_shares
nfs_mount_point_base = $state_path/mnt_nfs
```

Contenu de `/etc/cinder/nfs_shares` :

```
10.0.0.20:/srv/nfs/cinder
```

---

## 7.3. Déployer

```bash
kolla-ansible reconfigure --tags cinder
```

---

# 8. Résumé des étapes clés (LVM + Ceph)

## Pour **LVM** :

1. Créer disque loop
2. Créer VG `cinder-volumes`
3. Activer backend LVM dans globals.yml
4. Ajouter conf dans `cinder-volume.conf`
5. `kolla-ansible reconfigure --tags cinder`

## Pour **Ceph** :

1. Installer Ceph via Kolla ou externe
2. Créer pool `volumes`
3. Créer user `client.cinder`
4. Ajouter `cinder-volume.conf`
5. Déployer avec Kolla
6. Tester volume RBD


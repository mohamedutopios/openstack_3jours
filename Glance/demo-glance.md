# 🚀 1. Vue d’ensemble : la brique **Glance**

Glance est le service qui gère les **images systèmes** (Ubuntu, CentOS, Cirros, etc.) qu’on utilise pour lancer des VMs dans Nova.

* **Glance API** : interface REST pour uploader/télécharger les images.
* **Backend de stockage** : par défaut c’est **file** (stockage local sur disque), mais on peut utiliser **Swift**, **Ceph/RBD**, ou **NFS**.
* **Base de données** : stocke les métadonnées (nom, format, taille, checksum, etc.).

👉 Glance ne stocke pas directement les données en DB, seulement les métadonnées. Les fichiers sont stockés sur un backend.

---

# 🚀 2. Création de la base de données (démo manuelle)

En déploiement manuel (hors Kolla), on fait :

```sql
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_PASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_PASS';
```

Puis on initialise le schéma :

```bash
su -s /bin/sh -c "glance-manage db_sync" glance
```

👉 En **Kolla-Ansible**, ça se fait automatiquement via MariaDB et les playbooks (`kolla-ansible bootstrap-servers` + `deploy` créent les bases nécessaires : keystone, glance, nova, neutron, etc.).

---

# 🚀 3. Mise en œuvre et configuration (Kolla-Ansible AIO)

## a) Activer Glance

Dans `/etc/kolla/globals.yml` :

```yaml
enable_glance: "yes"
```

⚠️ En AIO, c’est activé par défaut.

## b) Configurer le backend de stockage

Toujours dans `globals.yml`, tu peux choisir :

```yaml
glance_backend_file: "yes"    # stockage local (par défaut)
glance_backend_swift: "no"
glance_backend_rbd: "no"
```

En mode **file**, les images sont stockées dans le volume docker :

```
/var/lib/docker/volumes/kolla_glance/_data/images/
```

---

# 🚀 4. Gestion du stockage des images (démos)

## a) Téléverser une image Cirros

```bash
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
openstack image create "cirros" \
  --file cirros-0.6.2-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --public
```

## b) Vérifier l’image

```bash
openstack image list
openstack image show cirros
```

Tu verras la taille, le format (`qcow2`), l’ID, etc.

## c) Lancer une VM depuis Glance

```bash
openstack server create --flavor m1.tiny --image cirros --network demo-net --key-name mykey demo-vm
```

---

# 🚀 5. Explorer le backend de stockage

### a) Backend File (par défaut)

Les images uploadées via Glance se trouvent ici :

```bash
ls /var/lib/docker/volumes/kolla_glance/_data/images/
```

Chaque image est stockée par son **UUID**.

### b) Backend Swift (optionnel)

Si tu actives Swift comme backend :

```yaml
glance_backend_swift: "yes"
```

Les images sont stockées comme objets dans un conteneur Swift (par ex. `glance_images`).

Test :

```bash
openstack container list
```

### c) Backend RBD (Ceph)

Si tu avais un cluster Ceph, les images seraient placées dans un **pool RBD** dédié (par ex. `images`).
👉 C’est la config typique en production (permet un boot direct des VMs depuis Ceph).

---

# ✅ Résumé démo

1. **Glance** = brique de gestion des images (API + DB + backend).
2. **DB** : gérée par MariaDB (en Kolla, automatique).
3. **Mise en œuvre** : activer dans `globals.yml`, choisir backend.
4. **Stockage** : file (local), Swift (object storage), ou Ceph RBD (prod).
5. **Démos** : upload d’une image, vérification, lancement d’une VM.



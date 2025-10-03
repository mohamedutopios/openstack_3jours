Parfait 👍 tu veux une **démonstration pédagogique complète** autour de **Swift (Object Storage d’OpenStack)** avec trois angles :

* Vue d’ensemble (concepts & architecture)
* Mise en œuvre et configuration (Kolla-Ansible AIO)
* Gestion des pools de stockage (comment Swift répartit les objets)

Je vais t’écrire ça comme un **TP / Démo guidée**, que tu pourrais refaire dans ton lab.

---

# 🚀 1. Vue d’ensemble de Swift

Swift est le **service de stockage objet** d’OpenStack.
👉 Il est comparable à Amazon S3, MinIO, ou Ceph RGW.

* Les données sont stockées sous forme **d’objets** dans des **containers** (similaires aux buckets S3).
* Pas de filesystem classique → accès par API HTTP (REST).
* Caractéristiques clés :

  * **Scalabilité horizontale** (ajout de serveurs facilement).
  * **Tolérance aux pannes** grâce à la réplication automatique.
  * **Éventuellement cohérent** (BASE, pas ACID).
  * **Multi-tenant** via Keystone.

**Architecture simplifiée :**

* **Proxy Server** : point d’entrée, gère l’authentification (via Keystone) et route les requêtes.
* **Storage Nodes** : stockent réellement les objets, conteneurs, et comptes.
* **Ring** : métadonnées distribuées (hash → emplacement physique).

---

# 🚀 2. Mise en œuvre et configuration (AIO Kolla-Ansible)

## a) Activer Swift

Dans `/etc/kolla/globals.yml` :

```yaml
enable_swift: "yes"
swift_devices_match_mode: "strict"
swift_devices_name: "SWIFT_DATA"
```

Configurer les devices de stockage Swift :
👉 Pour un lab AIO, on utilise un loopback device :

```bash
sudo mkdir -p /var/lib/kolla-swift
sudo truncate -s 5G /var/lib/kolla-swift.img
sudo losetup /dev/loop3 /var/lib/kolla-swift.img
sudo mkfs.xfs /dev/loop3
```

- sudo mkdir -p /etc/kolla/config/swift
- cd /etc/kolla/config/swift

- source kolla/virtualenv/bin/activate

- which swift-ring-builder

- sudo apt update
- sudo apt install swift swift-proxy python-swift python-swiftclient swift-account swift-container swift-object -y

- nano /usr/local/bin/gen-swift-rings.sh

#!/bin/bash
set -e

# Répertoire de config Swift
CONF_DIR="/etc/kolla/config/swift"
mkdir -p $CONF_DIR
cd $CONF_DIR

# Device utilisé
DEVICE="loop3"

echo "=== Génération des Swift rings avec device: $DEVICE ==="

# Account ring
swift-ring-builder account.builder create 10 1 1
swift-ring-builder account.builder add --region 1 --zone 1 --ip 127.0.0.1 --port 6002 --device $DEVICE --weight 100
swift-ring-builder account.builder rebalance

# Container ring
swift-ring-builder container.builder create 10 1 1
swift-ring-builder container.builder add --region 1 --zone 1 --ip 127.0.0.1 --port 6001 --device $DEVICE --weight 100
swift-ring-builder container.builder rebalance

# Object ring
swift-ring-builder object.builder create 10 1 1
swift-ring-builder object.builder add --region 1 --zone 1 --ip 127.0.0.1 --port 6000 --device $DEVICE --weight 100
swift-ring-builder object.builder rebalance

echo "=== Rings générés avec succès dans $CONF_DIR ==="
ls -lh $CONF_DIR


- sudo chmod +x /usr/local/bin/gen-swift-rings.sh

- sudo /usr/local/bin/gen-swift-rings.sh

- ls -lh /etc/kolla/config/swift/


3. Vérifier l’inventaire

Dans /etc/kolla/all-in-one, tu dois avoir un groupe [swift]. Exemple :

[swift]
localhost       ansible_connection=local



- kolla-ansible -i all-in-one deploy --tags swift


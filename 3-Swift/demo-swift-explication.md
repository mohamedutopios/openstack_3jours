# 🧩 0. Préparer l’environnement kolla-ansible (venv + dépendances)

👉 À faire **en root** sur l’hôte (pas dans un container).

```bash
sudo -i
# Passe en root (shell de connexion root). Obligatoire car :
# - on va installer des paquets système
# - on va créer un venv dans /root
# - kolla-ansible s'utilise généralement depuis root

apt update
# Met à jour la liste des paquets disponibles (index APT).
# Toujours à faire avant un apt install sur une machine qui n’est pas à jour.

apt install -y python3-venv python3-dev libffi-dev gcc libssl-dev libyaml-dev
# Installe les dépendances de base pour faire tourner kolla-ansible dans un virtualenv :
# - python3-venv : permet de créer des environnements virtuels Python (python -m venv)
# - python3-dev  : headers Python pour compiler certains modules natifs
# - libffi-dev   : utilisé par des libs comme cryptography (gestion des FFI, Foreign Function Interface)
# - gcc          : compilateur C nécessaire pour compiler des modules Python natifs
# - libssl-dev   : headers OpenSSL, utilisés par cryptography, TLS, etc.
# - libyaml-dev  : pour PyYAML (lecture des fichiers YAML d'Ansible et de Kolla)
```

Créer un virtualenv dédié pour kolla-ansible :

```bash
python3 -m venv /root/kolla-openstack
# Crée un environnement virtuel Python isolé dans /root/kolla-openstack.
# Avantages :
# - tu figes les versions de ansible / kolla-ansible / cryptography
# - tu évites les conflits avec les paquets système Python

source /root/kolla-openstack/bin/activate
# Active le virtualenv : à partir de là, "python" et "pip" pointent vers l'env virtuel.
# Tout ce que tu installes via pip reste confiné dans /root/kolla-openstack.
```

Mettre à jour `pip`/`setuptools` pour éviter l’erreur `setuptools_rust` avec `cryptography` :

```bash
python -m pip install --upgrade "pip==21.3.1" "setuptools<60" "wheel"
# On force :
# - une version de pip raisonnablement récente (21.3.1)
# - setuptools < 60 pour éviter les dépendances à Rust sur d'anciennes versions de Python
# - wheel : permet d’installer des paquets Python précompilés (format .whl)
# Pourquoi ? Pour que cryptography < 3.5 puisse s’installer SANS Rust sur Ubuntu/Python ancien.
```

Installer une version de `cryptography` compatible Python 3.6 **sans Rust** :

```bash
pip install "cryptography==3.4.8"
# On fixe cryptography à 3.4.8, dernière version à bien fonctionner sans Rust sur Python ancien.
# Cela évite :
# - les erreurs du type "setuptools-rust required for building..."
# - les problèmes de compilation sur une VM un peu "légère".
```

Installer kolla-ansible + ansible dans ce venv :

```bash
pip install "ansible==2.9.27" "kolla-ansible==10.2.0"
# On installe des versions cohérentes avec Ussuri :
# - ansible 2.9.x : dernière branche supportée officiellement par kolla-ansible Ussuri/Train/Stein
# - kolla-ansible 10.2.0 : branche qui correspond à OpenStack Ussuri
# Tout cela reste DANS le venv : pas de pollution du système.
```

Vérifier :

```bash
kolla-ansible --version
# Vérifie que la commande kolla-ansible fonctionne et est bien celle du venv.

ansible --version
# Vérifie la version de Ansible utilisée par le venv (2.9.27 normalement).
```

> 🔁 **À chaque fois que tu veux utiliser kolla-ansible** :
>
> ```bash
> sudo -i
> source /root/kolla-openstack/bin/activate
> ```
>
> Sinon tu risques d’appeler un ansible/kolla-ansible du système (mauvaise version).

---

# 🗂 1. Vérifier / préparer l’inventaire `all-in-one`

On va utiliser ton inventaire **AIO** (fichier `all-in-one`) et vérifier que Swift est bien mappé sur `localhost`.

```ini
[control]
localhost       ansible_connection=local
# Groupe "control" : nœud qui héberge les services de contrôle
# (Keystone, Glance, Nova-API, Neutron-server, Horizon, Swift proxy dans ton cas).
# Ici : tout tourne sur localhost → AIO (All-In-One).

[network]
localhost       ansible_connection=local
# Groupe "network" : nœud qui héberge les agents réseau (Neutron L3, DHCP, etc.).
# Toujours localhost en AIO.

[compute]
localhost       ansible_connection=local
# Groupe "compute" : nœud(s) qui hébergent les hyperviseurs Nova.
# Ici : Nova-compute tourne aussi sur localhost.

[storage]
localhost       ansible_connection=local
# Groupe "storage" : nœud(s) de stockage (Cinder, Swift, etc.).
# En AIO, on utilise aussi localhost.

[monitoring]
localhost       ansible_connection=local
# Groupe pour Prometheus, Grafana, etc. sur localhost.

[deployment]
localhost       ansible_connection=local
# Nœud qui exécute kolla-ansible. Dans un AIO, c'est aussi localhost.

# ...

[swift:children]
control
# Groupe "swift" = alias logique qui regroupe les nœuds concernés par Swift (proxy).
# Ici, il hérite des nœuds du groupe [control], donc localhost.

[swift-proxy-server:children]
swift
# Groupe pour les containers swift_proxy_server.
# Il utilise les hôtes du groupe [swift], donc les "control nodes".

[swift-account-server:children]
storage
# Containers swift_account_server déployés sur le groupe [storage]
# (dans un vraies archi prod : tu peux séparer control et storage).

[swift-container-server:children]
storage
# Containers swift_container_server également sur les nœuds de stockage.

[swift-object-server:children]
storage
# Containers swift_object_server (= data) sur les nœuds de stockage.
```

✅ Pour un AIO, ce mapping signifie :
**tout Swift (proxy + data) tourne sur la même VM**, mais **logiquement séparé** en rôles.

Juste pour le ranger proprement :

```bash
mkdir -p /etc/kolla
# Crée le répertoire standard de configuration de Kolla-Ansible.

cp /home/devops/all-in-one /etc/kolla/all-in-one
# Copie ton inventaire AIO dans /etc/kolla.
# Tu pourras lancer :
#   kolla-ansible -i /etc/kolla/all-in-one ...
# depuis n'importe où.
```

---

# 💽 2. Ajouter et préparer le disque Swift

## 2.1. Ajouter un disque dans VirtualBox

Là, c’est purement “infrastructure” : on ajoute un disque dédié au stockage Swift.

1. Éteindre la VM.
2. VirtualBox → **Paramètres → Stockage**.
3. Ajouter un nouveau disque VDI (20 Go, dynamique).
4. Redémarrer la VM, puis :

```bash
lsblk
# Liste tous les disques et partitions.
# Tu dois voir un nouveau disque sans partitions, par ex. "sdb" de ~20G.
```

---

## 2.2. Partitionner + formater en XFS avec label `SWIFT_DATA`

```bash
sudo parted /dev/sdb --script mklabel gpt
# Initialise le disque /dev/sdb avec un label GPT (table de partitions moderne).
# ATTENTION : cela efface tout contenu précédent sur /dev/sdb.

sudo parted /dev/sdb --script mkpart primary 0% 100%
# Crée une partition unique "primary" qui occupe 100% du disque.
# Résultat attendu : /dev/sdb1.
```

Formater avec un **label court (≤ 12 caractères)** :

```bash
sudo mkfs.xfs -f -L SWIFT_DATA /dev/sdb1
# Formate la partition /dev/sdb1 avec le système de fichiers XFS.
# - -f : force le formatage (même si un FS existait).
# - -L SWIFT_DATA : assigne un LABEL au FS (max 12 chars).
# Swift, avec "swift_devices_match_mode: strict", se base sur ce LABEL.
```

Vérifier :

```bash
lsblk -f
# -f affiche les infos de FS : type (xfs), LABEL, UUID.
# Tu dois voir sdb1 avec :
#   FSTYPE=xfs  LABEL=SWIFT_DATA
```

---

## 2.3. Monter le disque sur `/srv/node/sdb1`

```bash
sudo mkdir -p /srv/node/sdb1
# Répertoire de montage utilisé par Swift.
# Convention : /srv/node/<nom_device_logique>
```

```bash
echo 'LABEL=SWIFT_DATA /srv/node/sdb1 xfs defaults 0 0' | sudo tee -a /etc/fstab
# Ajoute une entrée dans /etc/fstab pour que le FS soit monté automatiquement au boot :
# - LABEL=SWIFT_DATA : on cible le FS par son label, pas par /dev/sdb1 (plus robuste)
# - /srv/node/sdb1   : point de montage
# - xfs              : type de FS
# - defaults         : options de montage standard
# - 0 0              : pas de dump, pas de fsck au boot
```

```bash
sudo mount -a
# Relit /etc/fstab et monte tous les systèmes de fichiers non encore montés.
```

```bash
df -h | grep /srv || echo "AUCUN_MONTAGE_SRV"
# Vérifie que /srv/node/sdb1 est bien monté :
# - df -h : liste les FS montés et leur utilisation
# - grep /srv : filtre ceux montés sous /srv
# Si rien ne ressort, le echo te dit qu'aucun montage /srv n'existe.
```

---

## 2.4. Permissions UID pour l’utilisateur `swift` (point clé)

Là on s’assure que **le FS sur l’hôte** appartient au même `uid:gid` que l’utilisateur `swift` **dans les containers**.
Sinon Swift va râler “permission denied” en écriture.

```bash
docker exec -it swift_account_server id swift
# On exécute "id swift" DANS un container Swift (swift_account_server ici).
# Pourquoi ?
# Parce que dans Kolla, les UID/GID sont fixés (42445, 42446, etc.)
# et peuvent ne pas correspondre à un utilisateur local de l’hôte.
#
# Ce qui nous intéresse, c’est l'UID NUMÉRIQUE de swift dans le container.
```

Tu verras quelque chose comme :

```text
uid=42445(swift) gid=42445(swift) groups=42445(swift)
```

C’est cet UID que tu dois utiliser sur l’hôte :

```bash
sudo chown -R 42445:42445 /srv/node/sdb1
# Change le propriétaire du FS monté pour qu'il appartienne à l'utilisateur "swift"
# tel qu'il est vu DANS le container (UID 42445).
# Sans ça, les containers Swift ne pourront pas écrire leurs données sur le disque.

sudo chmod -R 755 /srv/node/sdb1
# Donne les droits rx à tout le monde et w au propriétaire.
# Suffisant pour un lab (en prod on ferait plus fin, mais c'est OK).
```

Vérifier :

```bash
ls -lan /srv/node
ls -lan /srv/node/sdb1
# -l   : long listing
# -n   : affiche les UID/GID numériques au lieu des noms.
# Tu dois voir :
#   drwxr-xr-x  42445  42445  ... sdb1
# ce qui confirme que swift (UID 42445) est propriétaire.
```

---

# ⚙️ 3. Configuration Swift dans `globals.yml`

On active Swift et on indique à Kolla **comment trouver les disques**.

```yaml
# Swift - Object Storage Options
enable_swift: "yes"
# Active le déploiement de Swift dans Kolla-Ansible.
# Sans ça, même si ton disque est prêt, Swift ne sera pas déployé.

# Le disque est détecté par label XFS
swift_devices_match_mode: "strict"
# "strict" = Swift ne considèrera comme valide que les devices correspondant EXACTEMENT
# au critère donné (label ou nom).
# Ça évite qu'un mauvais disque se retrouve utilisé par erreur.

swift_devices_name: "SWIFT_DATA"
# Comme on a "match_mode: strict", Kolla va chercher un FS XFS dont le LABEL est "SWIFT_DATA".
# Ce LABEL est celui que tu as donné avec mkfs.xfs -L SWIFT_DATA.
# Du coup, Kolla sait que /srv/node/sdb1 correspond à ce device Swift.

# enable_swift_s3api: "no"
# Optionnel : permettrait d'exposer une API S3 compatible au-dessus de Swift.
# Tu pourras l'activer plus tard si tu veux un endpoint S3.
```

---

# 🧱 4. Installer les outils Swift *sur l’hôte* (pour créer les rings)

Ici, l’objectif est d’avoir sur l’hôte les commandes `swift-ring-builder` pour construire les rings.

```bash
apt update
apt install -y swift swift-account swift-container swift-object
# Installe les packages Swift côté hôte (hors containers) :
# - swift             : outils de base (swift, swift-ring-builder, etc.)
# - swift-account     : binaire pour gérer les comptes
# - swift-container   : idem pour les containers
# - swift-object      : idem pour les objets
#
# C'est JUSTE pour pouvoir créer les rings (*.builder, *.ring.gz) sur l'hôte, 
# dans /etc/kolla/config/swift. Kolla les copiera dans les containers.
```

Si problème DNS :

```bash
sudo bash -c 'echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" > /etc/resolv.conf'
# Remplace le contenu de /etc/resolv.conf par des DNS publics (Google et Cloudflare).
# Utile si ton /etc/resolv.conf pointe vers un DNS local qui ne marche pas.
```

---

# 🔁 5. Créer les Swift rings dans `/etc/kolla/config/swift`

Les **rings** sont la “carte de routage” de Swift :
ils disent **quel device** (sdb1 sur telle IP, tel port) stocke **quelles partitions logiques**.

```bash
sudo mkdir -p /etc/kolla/config/swift
cd /etc/kolla/config/swift
# Répertoire où Kolla va chercher les fichiers *.builder et *.ring.gz.
# On crée et gère les rings ici côté hôte.
```

## 5.1. Account Ring

```bash
sudo swift-ring-builder account.builder create 10 1 1
# Crée le fichier "account.builder" avec ces paramètres :
# - 10 : "part_power" → nombre de partitions = 2^10 = 1024 partitions logiques
# - 1  : "replica_count" → 1 copie de chaque partition (lab simple, pas de HA)
# - 1  : "min_part_hours" → délai minimum en heures avant qu'une partition puisse
#        être déplacée à nouveau (rebalance trop fréquent protégé).
```

```bash
sudo swift-ring-builder account.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6001 \
  --device sdb1 --weight 100
# Ajoute un "device" dans le ring des ACCOUNT :
# - region 1 / zone 1 : structure logique du DC (tu peux en avoir plusieurs en prod)
# - ip 9.11.93.4      : IP de ton noeud de stockage (la VM AIO)
# - port 6001         : port Swift account-server
# - device sdb1       : nom logique du device (doit correspondre au device monté)
# - weight 100        : poids relatif pour la distribution des partitions
#
# En gros, on dit : "le service account de Swift est sur 9.11.93.4:6001 sur le disque sdb1".
```

```bash
sudo swift-ring-builder account.builder rebalance
# Calcule et écrit dans account.ring.gz la distribution des 1024 partitions
# sur les devices configurés.
# C'est le "compilateur" du ring : il génère le fichier binaire final utilisé en prod.
```

## 5.2. Container Ring

Même principe, mais pour les containers :

```bash
sudo swift-ring-builder container.builder create 10 1 1
# Crée un ring pour les CONTAINERS (même part_power, replicas, etc.)

sudo swift-ring-builder container.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6002 \
  --device sdb1 --weight 100
# Déclare que les metadata des containers seront sur :
# IP 9.11.93.4, port 6002 (container-server), disque sdb1.

sudo swift-ring-builder container.builder rebalance
# Génère container.ring.gz à partir du builder.
```

## 5.3. Object Ring

Et enfin pour les objets eux-mêmes :

```bash
sudo swift-ring-builder object.builder create 10 1 1
# Crée le ring pour les OBJECTS (données elles-mêmes).

sudo swift-ring-builder object.builder add \
  --region 1 --zone 1 \
  --ip 9.11.93.4 --port 6000 \
  --device sdb1 --weight 100
# Déclare que les objets seront stockés sur :
# IP 9.11.93.4, port 6000 (object-server), disque sdb1.

sudo swift-ring-builder object.builder rebalance
# Calcule la répartition des partitions d'objets → object.ring.gz.
```

Vérifier l’état des rings :

```bash
swift-ring-builder account.builder
swift-ring-builder container.builder
swift-ring-builder object.builder
# Affiche un résumé : nombre de partitions, répartition, poids, etc.
# Permet de vérifier qu'il n'y a pas de partitions "sans device".
```

Vérifier les fichiers `.ring.gz` :

```bash
ls -lh /etc/kolla/config/swift/*.ring.gz
# Vérifie que les trois fichiers binaires ont bien été générés :
# - account.ring.gz
# - container.ring.gz
# - object.ring.gz
# Ce sont ceux-là qui seront copiés DANS les containers Swift.
```

---

# 🚀 6. (Re)déployer Swift avec kolla-ansible

Toujours dans le **virtualenv** :

```bash
sudo -i
source /root/kolla-openstack/bin/activate
cd /etc/kolla
# On se place dans le répertoire où se trouvent globals.yml + all-in-one.
```

### 6.1. Préchecks

```bash
kolla-ansible -i ./all-in-one prechecks --tags swift
# Lancement des pré-vérifications Kolla pour les services marqués "swift".
# Vérifie :
# - que les hosts sont accessibles
# - que la config est cohérente
# - que les rings existent là où ils doivent
# Si ça échoue ici, ça t'évite un "deploy" qui part en vrille.
```

### 6.2. Déploiement Swift uniquement

```bash
kolla-ansible -i ./all-in-one deploy --tags swift
# Déploie / reconfigure uniquement les services liés à Swift :
# - swift_proxy_server
# - swift_account_server
# - swift_container_server
# - swift_object_server
# - et leurs workers (auditor, replicator, updater, etc.)
# Utilise :
# - /etc/kolla/globals.yml pour la config globale
# - /etc/kolla/config/swift/*.ring.gz pour les rings
```

### 6.3. Post-deploy (si pas déjà fait)

```bash
kolla-ansible post-deploy
# Étape standard Kolla :
# - crée /etc/kolla/admin-openrc.sh
# - configure quelques scripts de post-install
# - met en place des fichiers utilitaires
# À faire au moins une fois après un déploiement global.
```

### 6.4. Vérifier les containers Swift

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep swift
# Liste les containers dont le nom contient "swift" avec leur statut.
# Tu dois voir :
#   swift_proxy_server, swift_account_server, swift_container_server,
#   swift_object_server, leurs workers (auditor, replicator, updater, expirer...)
# en statut "Up".
# Un container en "Restarting" = problème dans les logs à inspecter.
```

---

# 🔍 7. Vérifier que les rings sont bien dans les containers

```bash
docker exec -it swift_proxy_server   ls -l /etc/swift/*.ring.gz
docker exec -it swift_account_server ls -l /etc/swift/account.ring.gz
docker exec -it swift_container_server ls -l /etc/swift/container.ring.gz
docker exec -it swift_object_server    ls -l /etc/swift/object.ring.gz
# On vérifie DANS les containers :
# - que les fichiers *.ring.gz ont bien été copiés depuis /etc/kolla/config/swift
# - qu'ils appartiennent à l'utilisateur swift:swift
# Sans ces rings, les daemons Swift ne savent pas sur quels devices écrire/lire.
```

---

# 🧪 8. Tests côté OpenStack (CLI)

```bash
source /etc/kolla/admin-openrc.sh
# Charge les variables d'environnement pour le client OpenStack :
# - OS_AUTH_URL, OS_USERNAME, OS_PASSWORD, OS_PROJECT_NAME, etc.
# Sans ça, la commande "openstack" ne sait pas sur quel endpoint parler ni avec quel token.
```

```bash
openstack service list | grep -i object
# Vérifie que le service "object-store" existe dans Keystone.
# C'est l'enregistrement du service Swift dans le catalogue.
```

```bash
openstack endpoint list | grep -i object
# Vérifie que des endpoints publics/internal/admin existent pour "object-store".
# S'il n'y a pas d'endpoint, Horizon/CLI ne pourront pas accéder à Swift.
```

```bash
openstack container create demo
# Crée un container Swift nommé "demo" dans ton projet courant.
# (équivalent d'un "bucket" dans S3).
```

```bash
openstack object create demo /etc/hosts
# Uploade le fichier /etc/hosts dans le container "demo".
# Ça déclenche :
# - un appel au Swift proxy
# - qui consulte les rings
# - qui envoie la requête vers object-server/container-server/account-server
#   sur ton disque sdb1.
```

```bash
openstack object list demo
# Liste les objets présents dans le container "demo".
# Tu dois voir /etc/hosts (le nom exact dépend de la commande précédente).
```

```bash
openstack object save demo /etc/hosts --file /tmp/hosts-downloaded
# Télécharge l'objet stocké dans "demo" sous le nom /etc/hosts
# et le sauvegarde localement dans /tmp/hosts-downloaded.
```

```bash
diff /etc/hosts /tmp/hosts-downloaded
# Compare le fichier original et celui téléchargé.
# Pas de différence => le cycle upload / stockage / download fonctionne correctement.
```

En cas d’erreur 503 ou autre :

```bash
docker logs swift_proxy_server --tail 50
docker logs swift_account_server --tail 50
docker logs swift_container_server --tail 50
docker logs swift_object_server --tail 50
# On regarde les logs des différents services Swift pour voir :
# - erreurs de permission (UID / chown)
# - erreurs de montage (/srv/node/sdb1 non monté)
# - erreurs de ring manquant (pas de *.ring.gz)
```

---

# 🌐 9. Tests dans Horizon

1. Aller sur Horizon (`http://9.11.93.4` ou IP de ton VIP).
2. Se connecter en `admin` (ou un autre projet).
3. Menu **Project → Object Store → Containers**.
4. Créer un container `demo`.
5. Uploader un fichier.

Derrière cette interface graphique, c’est **exactement** les mêmes mécanismes :

* Horizon → appelle l’API OpenStack Swift (via Keystone).
* Swift Proxy → lit les rings (`*.ring.gz`).
* Swift Proxy → envoie la requête aux bons *account/container/object-server* sur ton disque.

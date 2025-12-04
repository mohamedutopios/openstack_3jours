# Swift dans OpenStack - Architecture Complète

## Vue d'Ensemble

Swift est le service de **stockage objet** d'OpenStack, conçu pour stocker et récupérer des quantités massives de données non structurées avec haute disponibilité et durabilité.

---

## 1. LES RINGS (Anneaux)

Les rings sont des **structures de mapping** qui définissent où les données sont stockées dans le cluster Swift.

### Les 3 Types de Rings

```bash
# Les fichiers des rings se trouvent dans /etc/swift/

account.ring.gz       # Gère les comptes
container.ring.gz     # Gère les conteneurs
object.ring.gz        # Gère les objets (données)
```

### Rôle des Rings

**Le ring détermine :**
- Sur quel(s) serveur(s) stocker les données
- Sur quel(s) disque(s) précis
- Combien de réplicas créer (généralement 3)
- Comment redistribuer les données lors d'ajout/retrait de serveurs

**Structure d'un Ring :**
```
Ring = Zones + Devices + Partitions + Replicas

- Partitions : Le ring divise l'espace en partitions (ex: 2^18 = 262 144 partitions)
- Zones : Groupes logiques de serveurs (datacenter, rack, etc.)
- Devices : Disques physiques
- Replicas : Nombre de copies (généralement 3)
```

### Comment ça Fonctionne

```
Quand tu uploades un fichier "photo.jpg" :

1. Swift calcule un hash MD5 du chemin : /account/container/photo.jpg
2. Le hash est mappé à une partition (ex: partition 42)
3. Le ring lookup trouve où est la partition 42 :
   - Replica 1 : server1, disk sdb, zone 1
   - Replica 2 : server2, disk sdc, zone 2
   - Replica 3 : server3, disk sdd, zone 3
4. Swift écrit les 3 copies sur ces 3 emplacements
```

---

## 2. LES SERVEURS SWIFT

Swift utilise plusieurs types de serveurs avec des rôles distincts :

### A. PROXY SERVERS (Serveurs Proxy)

**Rôle** : Point d'entrée API pour toutes les requêtes

```
Client → Proxy Server → Storage Servers
```

**Responsabilités :**
- Recevoir les requêtes HTTP/HTTPS des clients
- Authentifier via Keystone
- Consulter les rings pour localiser les données
- Router les requêtes vers les bons storage servers
- Agréger les réponses
- Gérer les échecs (si un storage server est down)

**Processus :**
```bash
# Voir les processus proxy
ps aux | grep swift-proxy-server

# Configuration
/etc/swift/proxy-server.conf
```

**Exemple de flux :**
```
GET /v1/account/container/object
↓
Proxy consulte object.ring.gz
↓
Trouve : partition 42 sur server1, server2, server3
↓
Envoie GET à server1 (le plus rapide à répondre)
↓
Retourne l'objet au client
```

### B. STORAGE SERVERS (Serveurs de Stockage)

Il y a **3 types de storage servers** correspondant aux 3 rings :

#### 1. Account Servers

**Rôle** : Gérer les comptes Swift

```bash
# Processus
swift-account-server

# Base de données SQLite par compte
/srv/node/sdb1/accounts/<hash>/account.db
```

**Contient :**
- Liste des conteneurs dans un compte
- Métadonnées du compte
- Statistiques (nombre de conteneurs, objets, octets)

#### 2. Container Servers

**Rôle** : Gérer les conteneurs (équivalent de "buckets" en S3)

```bash
# Processus
swift-container-server

# Base de données SQLite par conteneur
/srv/node/sdb1/containers/<hash>/container.db
```

**Contient :**
- Liste des objets dans un conteneur
- Métadonnées du conteneur
- Statistiques (nombre d'objets, taille totale)

#### 3. Object Servers

**Rôle** : Stocker les données réelles (fichiers)

```bash
# Processus
swift-object-server

# Stockage des fichiers
/srv/node/sdb1/objects/<partition>/<hash>/<timestamp>.data
```

**Contient :**
- Les données binaires des objets
- Les métadonnées (headers HTTP)
- Extended attributes (xattrs)

---

## 3. LES PROCESSUS DE FOND (Background Processes)

### A. Replicators

**Rôle** : Assurer que les 3 réplicas existent toujours

```bash
swift-account-replicator
swift-container-replicator
swift-object-replicator
```

**Fonctionnement :**
- Parcourt régulièrement les partitions locales
- Compare avec les autres réplicas
- Copie les données manquantes
- Supprime les données obsolètes

### B. Auditors

**Rôle** : Vérifier l'intégrité des données

```bash
swift-account-auditor
swift-container-auditor
swift-object-auditor
```

**Fonctionnement :**
- Vérifie les checksums MD5
- Détecte la corruption de données
- Marque les objets corrompus pour suppression

### C. Updaters

**Rôle** : Mettre à jour les statistiques

```bash
swift-account-updater
swift-container-updater
swift-object-updater
```

**Fonctionnement :**
- Propage les changements vers le haut
- Met à jour les compteurs (nombre d'objets, taille)
- Retente les opérations échouées

### D. Other Processes

```bash
swift-container-sync        # Synchronisation entre clusters
swift-object-expirer        # Suppression des objets expirés
swift-container-reconciler  # Résolution des conflits
```

---

## 4. ARCHITECTURE COMPLÈTE

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────▼─────┐    ┌────▼─────┐    ┌────▼─────┐
      │  Proxy 1  │    │ Proxy 2  │    │ Proxy 3  │
      └─────┬─────┘    └────┬─────┘    └────┬─────┘
            │               │               │
            └───────────────┼───────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
    ┌─────▼─────┐     ┌─────▼─────┐    ┌─────▼─────┐
    │ Storage 1 │     │ Storage 2 │    │ Storage 3 │
    │  Zone 1   │     │  Zone 2   │    │  Zone 3   │
    │           │     │           │    │           │
    │ Account   │     │ Account   │    │ Account   │
    │ Container │     │ Container │    │ Container │
    │ Object    │     │ Object    │    │ Object    │
    │           │     │           │    │           │
    │ /dev/sdb  │     │ /dev/sdb  │    │ /dev/sdb  │
    │ /dev/sdc  │     │ /dev/sdc  │    │ /dev/sdc  │
    │ /dev/sdd  │     │ /dev/sdd  │    │ /dev/sdd  │
    └───────────┘     └───────────┘    └───────────┘
```

---

## 5. EXEMPLE DE FLUX COMPLET

### Upload d'un Objet

```
1. Client envoie : PUT /v1/AUTH_account/photos/cat.jpg
                   ↓
2. Proxy Server reçoit la requête
                   ↓
3. Authentification via Keystone
                   ↓
4. Calcul du hash : MD5(/AUTH_account/photos/cat.jpg) = abc123
                   ↓
5. Consultation object.ring.gz : partition 42
                   ↓
6. Ring lookup trouve 3 emplacements :
   - server1:/srv/node/sdb1/objects/42/abc/123.data
   - server2:/srv/node/sdc1/objects/42/abc/123.data
   - server3:/srv/node/sdd1/objects/42/abc/123.data
                   ↓
7. Proxy écrit en parallèle sur les 3 servers
                   ↓
8. Attendre 2 succès sur 3 (quorum)
                   ↓
9. Object-updater met à jour container.db
                   ↓
10. Container-updater met à jour account.db
                   ↓
11. Retour 201 Created au client
```

### Download d'un Objet

```
1. Client envoie : GET /v1/AUTH_account/photos/cat.jpg
                   ↓
2. Proxy consulte object.ring.gz
                   ↓
3. Trouve les 3 réplicas
                   ↓
4. Envoie GET au premier qui répond
                   ↓
5. Stream les données au client
                   ↓
6. Si échec, essaie le replica suivant
```

---

## 6. COMMANDES DE GESTION DES RINGS

```bash
# Créer un ring
swift-ring-builder object.builder create 18 3 1
# 18 = 2^18 partitions
# 3 = 3 réplicas
# 1 = 1 heure avant rebalance

# Ajouter un device
swift-ring-builder object.builder add \
  --region 1 --zone 1 --ip 10.0.0.1 --port 6200 \
  --device sdb1 --weight 100

# Rebalancer le ring
swift-ring-builder object.builder rebalance

# Voir le ring
swift-ring-builder object.builder

# Distribuer le ring
scp object.ring.gz root@proxy1:/etc/swift/
scp object.ring.gz root@storage1:/etc/swift/
```

---

## 7. COMMANDES DE DIAGNOSTIC

```bash
# Voir les services Swift
ps aux | grep swift

# Vérifier un ring
swift-ring-builder /etc/swift/object.builder

# Voir les disques montés
df -h | grep srv

# Vérifier la réplication
swift-recon --replication

# Statistiques du cluster
swift-recon --all

# Voir les objets sur un disque
ls -lah /srv/node/sdb1/objects/

# Logs Swift
tail -f /var/log/swift/proxy.log
tail -f /var/log/swift/object.log
```

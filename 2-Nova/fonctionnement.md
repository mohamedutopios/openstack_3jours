1. **Le rôle de Nova**
2. **Architecture interne**
3. **Les composants Nova et leur rôle exact**
4. **Ce qui se passe quand tu crées une VM** (workflow complet + détail des messages)
5. **Comment Nova parle à Neutron / Cinder / Glance**
6. **Gestion de l’hyperviseur (KVM / QEMU / libvirt)**
7. **Le scheduler en détail**

C’est la version que je donne en formation avancée OpenStack.

---

# 1️⃣ Nova : le service Compute d’OpenStack

Nova est responsable de :

* la **création**, **exécution**, **arrêt**, **pause**, **migration** des VM
* la gestion de l’hyperviseur (KVM le plus souvent)
* la gestion de l’état et du cycle de vie des instances
* l’orchestration du réseau (en coopération avec Neutron)
* l’allocation du stockage éphémère
* la communication entre contrôleurs et compute nodes

Nova seul **ne fait ni réseau**, ni **stockage**, ni **images** :
Il délègue à :

* **Neutron** pour le réseau
* **Cinder** pour les volumes
* **Glance** pour les images
* **Keystone** pour l’authentification

---

# 2️⃣ Architecture interne de Nova (haute précision)

Nova se compose de plusieurs services :

| Composant Nova                        | Fonction                                                                                |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| **nova-api**                          | Réception des requêtes REST (création VM, arrêt, reboot...)                             |
| **nova-scheduler**                    | Décide sur quel hyperviseur placer la VM                                                |
| **nova-conductor**                    | Passe les commandes internes entre API / DB / Compute (évite que compute parle à la DB) |
| **nova-compute**                      | Le service présent sur chaque hyperviseur (KVM) qui crée réellement la VM               |
| **nova-novncproxy / spicehtml5proxy** | Console distante                                                                        |
| **Placement API**                     | Vérifie les ressources disponibles (CPU, RAM, disque)                                   |
| **base de données Nova**              | Stocke l’état complet des instances, migrations, ressources                             |
| **message queue (RabbitMQ)**          | Bus de communication entre les services                                                 |

Tous ces services travaillent ensemble.

---

# 3️⃣ Les composants Nova en détail

## 🟩 **3.1 nova-api**

* reçoit les commandes REST des utilisateurs
* vérifie les droits auprès de Keystone
* traduit les demandes en messages pour RabbitMQ
  (ex : "scheduler, trouve-moi un compute" / "compute, crée la VM")

## 🟦 **3.2 nova-scheduler**

* lit la base placement pour savoir quels compute sont disponibles
* applique des **filtres** et **pénalités** (weighters)
* sélectionne *un* hyperviseur final
* envoie l’ordre à cet hyperviseur

## 🟩 **3.3 nova-conductor**

* sert d’intermédiaire entre :

  * nova-api
  * nova-compute
  * la base de données
* protège la DB (les compute ne s'y connectent jamais directement)

## 🟦 **3.4 nova-compute**

C’est le cœur du système.

* installé sur chaque hyperviseur
* contrôle **libvirt + QEMU + KVM**
* crée, détruit, migre les VM
* attache les interfaces réseau (via Neutron)
* attache les volumes (via Cinder)
* réalise le *spawn* (création) de la VM

## 🟪 **3.5 Placement Engine**

Service séparé depuis Pike.

* garde une vision exacte des ressources CPU/RAM/Disk
* permet le scheduling intelligent
* évite la sur-allocation non contrôlée

---

# 4️⃣ **Ce qui se passe quand tu crées une VM**

Workflow ultra détaillé :

Lorsque tu fais :

```
openstack server create ...
```

### 🟦 1. nova-api reçoit la requête

* vérifie les droits (Keystone)
* vérifie l’image (Glance)
* vérifie le réseau (Neutron)
* enregistre la demande dans DB
* envoie un message au scheduler via RabbitMQ

### 🟩 2. nova-scheduler choisit un hyperviseur

* interroge Placement pour voir où il reste des ressources
* applique ses filtres :

  * RamFilter
  * CpuFilter
  * DiskFilter
  * ImagePropertiesFilter
  * AggregateFilter
  * AffinityFilter
* décide un hôte
* envoie un message au **nova-compute de cet hôte**

### 🟦 3. nova-compute commence le “spawn”

Nova-compute fait :

1. **Téléchargement de l’image depuis Glance**

   * via `image_cache`
   * stockée sous `/var/lib/nova/instances/<instance_id>/disk`

2. **Création du volume éphémère**

   * disque root = image
   * swap = optionnel
   * ephemeral disk = optionnel

3. **Création du XML libvirt pour la VM**
   Nova génère un fichier XML qui décrit :

   * CPU
   * RAM
   * Disk
   * NIC
   * VNC
   * PCI passthrough si besoin
   * NUMA si utilisé

4. **Libvirt démarre QEMU/KVM**

### 🟩 4. Neutron configure le réseau

Pour chaque NIC :

* Neutron-Server génère un port
* DHCP agent ajoute une entrée
* OVS/OVN crée un port virtuel
* le tap interface est branché dans le bridge
* l’IP est attribuée

### 🟦 5. Mise à jour de l’état

* nova-compute envoie l’état à nova-conductor
* conductor met à jour la DB
* la VM passe à l’état **ACTIVE**

---

# 5️⃣ Comment Nova interagit avec les autres services

## 🟦 Avec Glance (images)

* nova-compute télécharge l’image sur l’hôte
* Nova utilise `qemu-img convert` pour convertir au besoin
* Mise en cache locale pour accélérer les futurs boots

## 🟦 Avec Neutron (réseau)

* Nova demande des ports
* Neutron crée les interfaces virtuelles
* Nova les branche dans la VM via libvirt

## 🟦 Avec Cinder (volumes)

* Nova demande l’attachement
* Cinder attache le volume sur l’hôte compute (iSCSI ou RBD)
* libvirt devient responsable du mapping

## 🟦 Avec Placement

* Suivi fin des ressources de chaque hyperviseur
* Empêche le scheduling sur des hôtes saturés

---

# 6️⃣ Hyperviseur : comment Nova pilote KVM/QEMU

Nova ne contrôle pas QEMU directement.
Il passe par :

### ➤ **libvirt**

* API standard
* pilote KVM/QEMU
* Nova lui envoie un XML
* libvirt lance réellement la VM

### ➤ **VNC / SPICE**

* nova-novncproxy expose la console web

### ➤ **cgroups**

* contrôle CPU / RAM
* limite les ressources

### ➤ **numactl** (si NUMA)

* placement des vCPU
* affinités

### ➤ **hugepages**

* support si activé

---

# 7️⃣ Le Scheduler dans le détail

Nova utilise une architecture en **filtres + score** :

## 🟦 Filtres

Exemples :

* **RamFilter** → il reste suffisamment de RAM ?
* **CpuFilter** → assez de vCPU disponibles ?
* **ImagePropertiesFilter** → l’image nécessite un accélérateur ?
* **AggregateFilter** → l’utilisateur est autorisé sur cet hôte ?

## 🟩 Weighters

On calcule un score :

* CPU free × coefficient
* RAM free × coefficient
* random spread
* metrics weighter

Puis Nova prend l’hôte **avec le plus grand score**.
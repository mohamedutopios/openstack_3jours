Très bonne question Mohamed 👌
Nova est le **service de calcul d’OpenStack** : c’est lui qui orchestre la création, le cycle de vie et l’administration des machines virtuelles (instances).

Je vais t’expliquer de manière détaillée :

---

# 🔎 Vue d’ensemble

* **Nom complet** : OpenStack Compute (code = Nova)
* **Rôle** : Gestion des instances (VM, conteneurs, parfois bare metal si couplé à Ironic).
* **Architecture** : distribuée → plusieurs composants qui communiquent via **RabbitMQ/OSLO.messaging** et une base de données **MariaDB/Galera**.
* **Interopérabilité** : Nova travaille avec **Glance (images)**, **Neutron (réseau)**, **Cinder (volumes)**, **Keystone (auth)**.

---

# 🧩 Composants principaux de Nova

## 1. **nova-api**

* Sert d’interface **REST** aux utilisateurs et aux autres services.
* Reçoit les requêtes (via Horizon, CLI `openstack server create`, Terraform, etc.).
* Vérifie les droits avec **Keystone**.
* Place les messages dans la file RabbitMQ pour traitement par les autres services.
  👉 Exemple : `POST /servers` (création d’une VM).

---

## 2. **nova-scheduler**

* Rôle : choisir **sur quel nœud de calcul** déployer une instance.
* Fonctionne par **filtres et pondération** :

  * Filtres (RAM, CPU, stockage, réseau, affinité/anti-affinité).
  * Weighers (priorisation → par ex. nœud le moins chargé).
* Après décision, envoie la demande au **compute node choisi** (via RabbitMQ).

---

## 3. **nova-conductor**

* Sert d’intermédiaire sécurisé entre **nova-compute** et la **base de données**.
* Les compute nodes n’accèdent **jamais directement à la DB** → passent par le conductor.
* Rôle critique pour la **scalabilité** et la **sécurité**.

---

## 4. **nova-compute**

* Déployé sur chaque **compute node**.
* Agent qui orchestre l’hyperviseur (via **drivers**).
* Supporte :

  * **KVM/QEMU** (le plus courant).
  * VMware vCenter.
  * Hyper-V.
  * Xen, LXC, etc.
* Reçoit les ordres du scheduler, et lance les opérations via **libvirt** (pour KVM) → création VM, attachement disque, config réseau.
* Surveille l’état des instances et remonte les infos.

---

## 5. **nova-placement-api**

* Introduit dans Pike (2017) pour séparer la logique de placement des ressources.
* Sert à modéliser les **Resource Providers** (CPU, RAM, GPU, SR-IOV, NUMA).
* Le scheduler interroge Placement pour savoir où il y a des ressources dispo.

---

## 6. **nova-consoleauth / nova-novncproxy / nova-spicehtml5proxy**

* Fournissent l’accès console aux instances :

  * **VNC** (par défaut via noVNC proxy).
  * **SPICE** ou **Serial console**.
* Exemple : dans Horizon → bouton *Console* ouvre noVNC via `nova-novncproxy`.

---

## 7. **nova-cert** (ancien, déprécié)

* Utilisé pour signer les certificats pour le service EC2 (héritage AWS).
* Supprimé depuis Stein.

---

# 🔗 Interactions Nova ↔ autres services

* **Keystone** → Authentification des API calls.
* **Glance** → Récupération de l’image pour créer la VM.
* **Neutron** → Provisionne les ports, attaches réseau à l’instance.
* **Cinder** → Attache des volumes block persistants aux instances.
* **Placement** → Informe sur les ressources disponibles.

---

# 🔄 Cycle de vie d’une VM dans Nova

1. **Demande utilisateur** : `openstack server create` ou Horizon → passe par `nova-api`.
2. **Auth Keystone** : valide le token.
3. **Placement** : nova-api → placement → vérifie ressources.
4. **Scheduling** : nova-scheduler choisit un hyperviseur.
5. **Orchestration** : nova-conductor → passe les infos.
6. **Création VM** : nova-compute du nœud sélectionné :

   * Télécharge l’image depuis Glance.
   * Crée les disques (ephemeral, Cinder si attaché).
   * Configure le réseau (via Neutron + OVS/OVN).
   * Lance la VM via **libvirt/KVM**.
7. **Mise à jour état** : compute → conductor → DB → visible dans Horizon/CLI.

---

# 📊 Base de données Nova

* Stocke :

  * Les instances (état, metadata, mapping).
  * Les quotas.
  * Les migrations.
  * Les infos de ressources.
* Utilise MySQL/MariaDB (Galera en prod).

---

# 📌 Résumé

Nova = un **orchestrateur de compute** composé de plusieurs services coopérant via RabbitMQ et une base SQL :

* **nova-api** → reçoit requêtes REST.
* **nova-scheduler** → choisit l’hôte.
* **nova-conductor** → interface DB sécurisée.
* **nova-compute** → exécute sur l’hyperviseur.
* **placement** → suivi des ressources.
* **console services** → accès console VNC/SPICE.

---

👉 Veux-tu que je te fasse un **schéma ASCII clair** de l’architecture Nova (API → Scheduler → Conductor → Compute → Hyperviseur), pour bien visualiser le flux quand on lance une VM ?

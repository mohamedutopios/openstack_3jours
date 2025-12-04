## 1. **Overview (Vue d’ensemble)**

👉 Cette partie présente ce qu’est **OpenStack-Ansible** :

* Un projet officiel OpenStack qui permet de déployer OpenStack avec **Ansible**.
* Il s’appuie sur des **conteneurs LXC** pour isoler les services (Keystone, Nova, Neutron, etc.).
* L’architecture proposée par OSA comprend :

  * Un **deployment host** (machine qui lance Ansible).
  * Un ou plusieurs **target hosts** (machines qui vont exécuter les services OpenStack).
* La doc donne aussi les **prérequis matériels** (RAM, CPU, disques) et logiciels (Ubuntu, Python, dépendances).

---

## 2. **Prepare the deployment host**

👉 Ici on configure **la machine d’où Ansible sera lancé**.
Typiquement :

* Installer Ubuntu LTS (souvent **22.04** en 2025).
* Ajouter les paquets nécessaires (`python3-venv`, `git`, `bridge-utils`, `curl`, etc.).
* Cloner le dépôt `openstack-ansible` depuis GitHub.
* Créer l’arborescence `/etc/openstack_deploy/`.

But : cette machine sert de **chef d’orchestre** pour piloter l’installation.

---

## 3. **Prepare the target hosts**

👉 Ce sont les machines qui **hébergeront OpenStack**.

* Tu définis leur rôle (contrôleur, compute, storage, etc.).
* Tu prépares les interfaces réseau (bridges, VLANs, MTU correct, etc.).
* Tu actives SSH sans mot de passe depuis le déploiement host → target hosts.
* Tu appliques quelques durcissements (désactiver `ufw`, configurer `sysctl`, etc.).

But : s’assurer que les machines qui recevront OpenStack sont **propres et prêtes**.

---

## 4. **Configure the deployment**

👉 Ici tu **personnalises les fichiers de configuration d’OSA** :

* Fichier principal : `/etc/openstack_deploy/openstack_user_config.yml`
  → décrit l’inventaire des hôtes (quelle IP pour quel service).
* Variables globales : `/etc/openstack_deploy/user_variables.yml`
  → exemple : choisir **Cinder avec LVM ou Ceph**, backend Neutron (OVS/OVN).
* Paramètres réseau : bridges, sous-réseaux (management, storage, external).

But : adapter OSA à **ton environnement** (réseaux, stockage, nombre de nœuds).

---

## 5. **Run playbooks**

👉 Tu exécutes les **playbooks Ansible fournis** par OSA, mais par étapes :

* `openstack-ansible setup-hosts.yml` → prépare les target hosts (OS de base, packages).
* `openstack-ansible setup-infrastructure.yml` → déploie les services de base (MariaDB, RabbitMQ, Memcached, etc.).
* `openstack-ansible setup-openstack.yml` → déploie les services OpenStack (Keystone, Glance, Nova, Neutron, Cinder, Horizon…).

But : transformer tes machines en **nœuds OpenStack prêts à l’emploi**.

---

## 6. **Checking the integrity of the configuration files**

👉 Vérification automatique des fichiers YAML :

* S’assurer que les fichiers dans `/etc/openstack_deploy/` n’ont pas de **syntaxe incorrecte**.
* Vérifier que l’inventaire est cohérent (noms d’hôtes, IP, rôles).
* OSA fournit un script :

  ```bash
  openstack-ansible /usr/local/bin/openstack-ansible rc-file-check.yml
  ```

But : éviter de lancer une installation qui **échouera à cause d’une simple faute de config**.

---

## 7. **Run the playbooks to install OpenStack**

👉 Ici tu lances le **déploiement complet** :

* `openstack-ansible setup-openstack.yml`
* Chaque service est déployé dans son conteneur LXC.
* Les dépendances (RabbitMQ, MariaDB, etc.) sont configurées.
* Les endpoints (Keystone API, Glance API, etc.) sont enregistrés automatiquement.

But : à la fin, tu as un **cloud OpenStack opérationnel**.

---

## 8. **Verifying OpenStack operation**

👉 Dernière étape : tu valides que ton OpenStack fonctionne.

* Charger les variables admin :

  ```bash
  source /root/openrc
  ```
* Vérifier les services Keystone :

  ```bash
  openstack service list
  ```
* Créer un réseau, une VM de test, attribuer une Floating IP.
* Vérifier que Horizon (dashboard web) est accessible.

But : s’assurer que l’installation est **réussie et exploitable**.

---

👉 En résumé :

* **Overview** = ce qu’on installe.
* **Prepare deployment host** = configurer la machine de déploiement.
* **Prepare target hosts** = préparer les serveurs cibles.
* **Configure** = adapter la conf OpenStack-Ansible.
* **Run playbooks** = appliquer les étapes Ansible.
* **Check configs** = valider les fichiers YAML.
* **Install OpenStack** = lancer le déploiement.
* **Verify** = tester que ça marche.



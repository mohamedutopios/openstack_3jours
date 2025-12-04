# 📂 Fichiers principaux

### `globals.yml`

* Ton fichier **maître de configuration** (qu’on a vu ensemble).
* Détermine : services activés, réseaux, interfaces, options Cinder, TLS, etc.

### `passwords.yml`

* Tous les **mots de passe, clés Fernet et secrets** générés par `kolla-genpwd`.
* Utilisé pour initialiser Keystone, MariaDB, RabbitMQ, etc.
  ⚠️ **Ne jamais perdre** si tu veux redéployer identique.

### `admin-openrc.sh`

* Script généré après `kolla-ansible post-deploy`.
* Contient les variables d’environnement pour utiliser les **CLI OpenStack** (`openstack server list`, etc.).
  Exemple :

```bash
export OS_USERNAME=admin
export OS_PASSWORD=xxxxxxxx
export OS_PROJECT_NAME=admin
export OS_AUTH_URL=http://192.168.56.11:5000/v3
```

---

# 📂 Répertoires de services OpenStack

Ces répertoires contiennent les **configs spécifiques** de chaque service, injectées dans les conteneurs.
Exemple : `/etc/kolla/nova-compute/nova.conf` → monté dans le conteneur `nova_compute`.

* **`glance-api/`** : config du service Glance (images).
* **`heat-api/`, `heat-api-cfn/`, `heat-engine/`** : orchestration (Heat).
* **`horizon/`** : config du tableau de bord Horizon (fichiers Apache, local_settings.py).
* **`keystone/`** : config de Keystone (authentification).
* **`keystone-fernet/`** : clés Fernet pour tokens.
* **`keystone-ssh/`** : config SSH pour synchronisation des clés Fernet.
* **`memcached/`** : config du cache distribué (sessions Keystone/Horizon).
* **`mariadb/`** : config du cluster MariaDB (bases OpenStack).
* **`neutron-dhcp-agent/`** : gère le DHCP pour les réseaux privés OpenStack.
* **`neutron-l3-agent/`** : gère le routage et les floating IP.
* **`neutron-metadata-agent/`** : fournit la metadata (ex : user-data) aux VMs.
* **`neutron-openvswitch-agent/`** : connecte Neutron avec OVS pour la gestion réseau.
* **`neutron-server/`** : API réseau OpenStack (Neutron).
* **`nova-api/`** : API Nova (compute).
* **`nova-api-bootstrap/`** : initialise la DB Nova API.
* **`nova-cell-bootstrap/`** : initialise les cellules Nova (cell0, cell1).
* **`nova-compute/`** : agent compute local (gère libvirt/KVM).
* **`nova-conductor/`** : service Nova pour orchestrer DB <-> compute nodes.
* **`nova-libvirt/`** : config de libvirt (backend hyperviseur).
* **`nova-novncproxy/`** : proxy pour la console web des VMs.
* **`nova-scheduler/`** : planificateur d’instances sur les compute nodes.
* **`nova-ssh/`** : clés SSH internes utilisées par Nova.
* **`placement-api/`** : service Placement (gestion des ressources compute).

---

# 📂 Répertoires annexes (infrastructures support)

* **`chrony/`** : config NTP (synchronisation horloge).
* **`cron/`** : tâches planifiées système pour OpenStack.
* **`fluentd/`** : collecte et centralisation des logs.
* **`kolla-toolbox/`** : outils Ansible/Docker (utilisés par kolla_ansible).
* **`openvswitch-db-server/`** : base de données OVSDB (réseau).
* **`openvswitch-vswitchd/`** : service dataplane OVS (switch virtuel).
* **`rabbitmq/`** : bus de messages pour communication inter-services.

---

# 🚀 Récapitulatif clair

| Élément                                      | Rôle                                 |
| -------------------------------------------- | ------------------------------------ |
| `globals.yml`                                | Configuration globale OpenStack      |
| `passwords.yml`                              | Secrets et mots de passe             |
| `admin-openrc.sh`                            | Fichier d’environnement pour CLI     |
| `*/` (nova, neutron, keystone, glance, etc.) | Configs montées dans les conteneurs  |
| `mariadb/`                                   | Base de données (services OpenStack) |
| `rabbitmq/`                                  | Bus de messages                      |
| `memcached/`                                 | Cache distribué                      |
| `fluentd/`                                   | Logs                                 |
| `chrony/`                                    | NTP                                  |
| `openvswitch-*`                              | Réseau virtuel (OVS)                 |



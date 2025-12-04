# 📂 Emplacement des playbooks Kolla-Ansible

Quand tu installes Kolla-Ansible (via pip), les playbooks se trouvent ici (dans ton venv ou ton système) :

```
/opt/kolla-venv/share/kolla-ansible/ansible/
```

Fichiers principaux :

* `site.yml` → déploiement complet
* `bootstrap-servers.yml`
* `prechecks.yml`
* `deploy.yml`
* `destroy.yml`
* `post-deploy.yml`
* `upgrade.yml`
* `reconfigure.yml`
* `pull.yml`

---

# 📑 Contenu des playbooks (vue d’ensemble)

## 1. **bootstrap-servers.yml**

Prépare les hôtes avant OpenStack :

* Installe dépendances système (python, pip, iproute2, etc.)
* Configure Docker & Docker registry
* Configure sysctl (IP forwarding, bridge-nf-call-iptables…)
* Crée les utilisateurs/permissions nécessaires

👉 Objectif : rendre l’hôte prêt à recevoir des conteneurs OpenStack.

---

## 2. **prechecks.yml**

* Vérifie la connectivité Ansible
* Vérifie les interfaces réseaux (management, external, etc.)
* Vérifie que Docker est actif
* Vérifie que les mots de passe (`passwords.yml`) sont valides
* Vérifie la configuration dans `globals.yml`

👉 Objectif : s’assurer que tout est correct **avant** de lancer le déploiement.

---

## 3. **deploy.yml** (inclus dans `site.yml`)

C’est le **playbook central** : il déploie tous les services OpenStack.
Il appelle en fait plusieurs rôles Ansible (dans `roles/`), chacun dédié à un service :

* **Keystone** : API d’identité
* **Glance** : service d’images
* **Nova** : compute (API, scheduler, conductor, compute)
* **Neutron** : réseau (server, agents L3/DHCP, OVS/OVN)
* **Cinder** : stockage bloc
* **Swift** : stockage objet
* **Horizon** : dashboard web
* **Heat** : orchestration
* etc.

Chaque rôle fait :

1. Télécharger l’image Docker du service
2. Générer les fichiers de config (dans `/etc/kolla/<service>`)
3. Créer/mettre à jour les conteneurs Docker
4. Vérifier l’état du service

👉 C’est l’étape la plus longue.

---

## 4. **destroy.yml**

* Arrête et supprime tous les conteneurs OpenStack
* Supprime les volumes liés
* Ne touche pas forcément aux données (à vérifier selon options)

---

## 5. **post-deploy.yml**

* Crée le fichier `/etc/kolla/admin-openrc.sh`
* Initialise Keystone (users, tenants, roles, endpoints)
* Initialise les services (Glance avec l’image Cirros, réseaux par défaut si activés)

👉 C’est ce qui permet d’avoir un cloud *utilisable* juste après `deploy`.

---

## 6. **upgrade.yml**

* Permet de faire un upgrade de version d’OpenStack
* Tire les nouvelles images Docker
* Reconfigure et redéploie service par service

---

## 7. **reconfigure.yml**

* Applique les changements de configuration (par ex. si tu modifies `globals.yml` ou `passwords.yml`)
* Redémarre uniquement les conteneurs concernés

---

## 8. **pull.yml**

* Télécharge toutes les images Docker nécessaires sans les déployer
* Très utile pour gagner du temps (pré-télécharger avant déploiement)

---

# 📂 Exemple : extrait simplifié de `deploy.yml`

```yaml
- name: Deploy all OpenStack services
  hosts: all
  roles:
    - role: keystone
    - role: glance
    - role: nova
    - role: neutron
    - role: cinder
    - role: horizon
    - role: heat
    - role: swift
```

Chaque rôle est un répertoire avec ses propres **tasks/main.yml**, **templates**, **handlers**.

---

# 📌 Résumé

* **bootstrap-servers.yml** → prépare l’hôte
* **prechecks.yml** → vérifie la conf et l’environnement
* **deploy.yml** → déploie tous les services (Docker + configs)
* **post-deploy.yml** → initialise Keystone et le cloud utilisable
* **destroy.yml** → supprime l’environnement
* **upgrade.yml / reconfigure.yml / pull.yml** → maintenance

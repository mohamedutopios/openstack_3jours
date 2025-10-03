Parfait 👍
Je vais te **commenter ton script étape par étape**, directement dans le code avec `#` pour que tu voies clairement **ce que fait chaque bloc**.

---

```bash
#!/bin/bash
set -e   # Arrête le script immédiatement si une commande retourne une erreur

# === [1/9] Mise à jour système et installation des paquets de base ===
echo "==== [1/9] Mise à jour système ===="
apt update && apt upgrade -y    # Met à jour les paquets existants
apt install -y git python3-dev libffi-dev gcc libssl-dev python3-venv curl \
    # git = nécessaire pour cloner des dépôts
    # python3-dev, libffi-dev, gcc, libssl-dev = dépendances pour compiler des libs Python
    # python3-venv = création d'environnements virtuels
    # curl = téléchargement d'outils/scripts

# === Ajout d'un swap pour éviter les erreurs OOM (Out Of Memory) ===
echo "==== Ajout de 2G de swap pour éviter OOM ===="
fallocate -l 2G /swapfile       # Crée un fichier de 2 Go
chmod 600 /swapfile             # Protège le fichier (accès root uniquement)
mkswap /swapfile                # Initialise le fichier comme swap
swapon /swapfile                # Active le swap
echo '/swapfile none swap sw 0 0' >> /etc/fstab   # Ajoute l’entrée pour persistance au reboot

# === [2/9] Installation de Docker ===
echo "==== [2/9] Installation Docker ===="
curl -fsSL https://get.docker.com | sh   # Installe Docker via script officiel
systemctl enable docker   # Active Docker au démarrage
systemctl start docker    # Démarre le service Docker

# === [3/9] Installation plugin Docker Compose ===
echo "==== [3/9] Installation Docker Compose plugin ===="
apt install -y docker-compose-plugin   # Installe Compose (nouveau format plugin docker)

# === [4/9] Création d’un environnement virtuel Python ===
echo "==== [4/9] Création du venv Python ===="
python3 -m venv /opt/kolla-venv       # Crée un venv pour isoler Kolla-Ansible
source /opt/kolla-venv/bin/activate   # Active le venv
pip install -U pip wheel setuptools   # Met à jour outils de base Python

# === [5/9] Installation de Kolla-Ansible (version 2025.1 Epoxy) ===
echo "==== [5/9] Installation Kolla-Ansible (Epoxy / 2025.1) ===="
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2025.1

# === [6/9] Installation dépendances système et Python ===
echo "==== [6/9] Installation dépendances Python et système ===="
apt install -y libdbus-1-dev libdbus-glib-1-dev pkg-config   # Librairies DBus requises pour certains modules

# Librairies Python additionnelles
pip install "docker==5.0.3" "requests==2.31.0" "requests-unixsocket==0.3.0" \
    # docker SDK pour Python
    # requests pour HTTP
    # requests-unixsocket pour API Docker via sockets Unix

# Version spécifique d’Ansible supportée par Kolla
pip install ansible-core==2.17.9 ansible==10.1.0

# Clients OpenStack + DBus
pip install python-openstackclient dbus-python

# === [7/9] Préparation des fichiers de configuration ===
echo "==== [7/9] Préparation fichiers de config ===="

kolla-ansible install-deps   # Installe dépendances Ansible pour Kolla

# Création du répertoire config Kolla
mkdir -p /etc/kolla
cp -r /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/   # Copie fichiers exemple de conf
cp /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one /home/vagrant/  # Copie inventaire AIO

# Génération automatique des mots de passe
kolla-genpwd

# Copie du globals.yml personnalisé fourni par l’hôte
cp /kolla-ansible/globals.yml /etc/kolla/globals.yml

# Configuration d’Ansible
mkdir -p /etc/ansible
cat <<EOF >/etc/ansible/ansible.cfg
[defaults]
roles_path = /opt/kolla-venv/share/kolla-ansible/ansible/roles
collections_paths = /root/.ansible/collections:/usr/share/ansible/collections:/etc/ansible/collections
host_key_checking = False   # Évite la vérification d’empreinte SSH
pipelining = True           # Améliore perf Ansible
forks = 100                 # Concurrence pour accélérer playbooks
EOF

# === [8/9] Déploiement d’OpenStack en mode AIO ===
echo "==== [8/9] Déploiement OpenStack AIO ===="
kolla-ansible bootstrap-servers -i /home/vagrant/all-in-one   # Prépare le serveur (packages, docker, etc.)
kolla-ansible prechecks -i /home/vagrant/all-in-one           # Vérifie la config avant déploiement
kolla-ansible deploy -i /home/vagrant/all-in-one              # Déploie tous les services OpenStack
kolla-ansible post-deploy                                     # Configure fichiers openrc, vérifie l’installation

# Charge automatiquement l’environnement admin pour l’utilisateur vagrant
echo "source /etc/kolla/admin-openrc.sh" >> /home/vagrant/.bashrc

# === [9/9] Fin du déploiement ===
echo "==== ✅ Déploiement terminé ! Connecte-toi et lance 'openstack server list' pour tester ===="
```

---

✅ Donc ton script :

1. Met à jour la VM + installe dépendances.
2. Ajoute un swap pour éviter les plantages mémoire.
3. Installe Docker + Compose.
4. Prépare un **venv Python** et installe Kolla-Ansible (version stable 2025.1).
5. Prépare la conf (`globals.yml`, `all-in-one`, `passwords.yml`).
6. Déploie OpenStack AIO (tout sur une seule VM).
7. Ajoute l’`admin-openrc` automatiquement à `.bashrc` pour que la CLI OpenStack fonctionne dès login.

---

Veux-tu que je t’en fasse une **version allégée (avec juste les étapes essentielles)** pour un usage rapide en formation/lab ?

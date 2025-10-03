#!/bin/bash
set -e

echo "==== [1/9] Mise à jour système ===="
apt update && apt upgrade -y
apt install -y git python3-dev libffi-dev gcc libssl-dev python3-venv curl


echo "==== Ajout de 2G de swap pour éviter OOM ===="
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab


echo "==== [2/9] Installation Docker ===="
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

echo "==== [3/9] Installation Docker Compose plugin ===="
apt install -y docker-compose-plugin

echo "==== [4/9] Création du venv Python ===="
python3 -m venv /opt/kolla-venv
source /opt/kolla-venv/bin/activate
pip install -U pip wheel setuptools

echo "==== [5/9] Installation Kolla-Ansible (Epoxy / 2025.1) ===="
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2025.1

echo "==== [6/9] Installation dépendances Python et système ===="
apt install -y libdbus-1-dev libdbus-glib-1-dev pkg-config

# Libs Python
pip install "docker==5.0.3" "requests==2.31.0" "requests-unixsocket==0.3.0"


pip install ansible-core==2.17.9 ansible==10.1.0

pip install python-openstackclient dbus-python

echo "==== [7/9] Préparation fichiers de config ===="

kolla-ansible install-deps

# Config Kolla
mkdir -p /etc/kolla
cp -r /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp /opt/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one /home/vagrant/

# Génération mots de passe
kolla-genpwd

# Copier globals.yml fourni par Host
cp /kolla-ansible/globals.yml /etc/kolla/globals.yml

# Config ansible.cfg
mkdir -p /etc/ansible
cat <<EOF >/etc/ansible/ansible.cfg
[defaults]
roles_path = /opt/kolla-venv/share/kolla-ansible/ansible/roles
collections_paths = /root/.ansible/collections:/usr/share/ansible/collections:/etc/ansible/collections
host_key_checking = False
pipelining = True
forks = 100
EOF

echo "==== [8/9] Déploiement OpenStack AIO ===="
kolla-ansible bootstrap-servers -i /home/vagrant/all-in-one
kolla-ansible prechecks -i /home/vagrant/all-in-one
kolla-ansible deploy -i /home/vagrant/all-in-one
kolla-ansible post-deploy

# Charger automatiquement l'environnement admin dans bash
echo "source /etc/kolla/admin-openrc.sh" >> /home/vagrant/.bashrc

echo "==== ✅ Déploiement terminé ! Connecte-toi et lance 'openstack server list' pour tester ===="

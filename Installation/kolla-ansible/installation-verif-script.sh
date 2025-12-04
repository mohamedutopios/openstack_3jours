#!/usr/bin/env bash
set -euo pipefail

#############################################
# 0. VÉRIFICATION : DOIT ÊTRE ROOT
#############################################
if [ "$EUID" -ne 0 ]; then
  echo "[ERREUR] Ce script doit être exécuté en root."
  echo "         Lance-le avec : sudo $0"
  exit 1
fi

#############################################
# CONFIG DE BASE
#############################################
KOLLA_VENV_DIR="/root/kolla-openstack"
KOLLA_RELEASE="stable/2024.1"    # OpenStack Caracal (18.x)
CINDER_LOOP_FILE="/var/lib/cinder.img"
CINDER_LOOP_SIZE_GB=20          # taille du fichier pour Cinder (en Go)
CINDER_VG_NAME="cinder-volumes"

PRIMARY_IF=""
HOST_IP=""

#############################################
# 1. CONFIG RÉSEAU HOST-ONLY (enp0s8)
#############################################
echo "[INFO] Vérification de l'interface enp0s8 (host-only VirtualBox)..."

if ip link show enp0s8 >/dev/null 2>&1; then
  IP_ENP0S8=$(ip -4 addr show enp0s8 | awk '/inet / {print $2}' | cut -d/ -f1 || true)

  if [ -z "$IP_ENP0S8" ]; then
    echo "[INFO] enp0s8 n'a pas d'IP -> configuration statique 192.168.56.10/24..."
    ip addr add 192.168.56.10/24 dev enp0s8 || true
    ip link set enp0s8 up || true
    IP_ENP0S8="192.168.56.10"
  fi

  PRIMARY_IF="enp0s8"
  HOST_IP="$IP_ENP0S8"
  echo "[INFO] enp0s8 utilisera l'IP : $HOST_IP"
else
  echo "[ERREUR] L'interface enp0s8 n'existe pas."
  echo "         -> Ajoute un 'Host-only Adapter' dans VirtualBox (vboxnet0)"
  echo "         -> Redémarre la VM, puis relance ce script."
  exit 1
fi

#############################################
# 2. VÉRIFICATION ANTI-NAT
#############################################
if echo "$HOST_IP" | grep -q '^10\.0\.2\.'; then
  echo "[ERREUR] L'IP détectée est $HOST_IP (NAT 10.0.2.x)."
  echo "         Ce réseau NAT VirtualBox n'est pas adapté pour OpenStack."
  echo "         -> Assure-toi que enp0s8 est bien en Host-only (192.168.56.x)"
  echo "         -> Puis relance ce script."
  exit 1
fi

echo "[INFO] Interface principale retenue pour OpenStack : $PRIMARY_IF"
echo "[INFO] Adresse IP utilisée pour Horizon / VIP      : $HOST_IP"

#############################################
# 3. PRÉREQUIS SYSTÈME
#############################################
echo "[STEP] Mise à jour du système et installation des paquets nécessaires..."

apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

apt install -y \
  git python3-dev libffi-dev python3-venv gcc libssl-dev \
  python3-pip python3-full \
  lvm2 thin-provisioning-tools \
  jq \
  python3-docker \
  pkg-config cmake \
  libdbus-1-dev libglib2.0-dev

#############################################
# 4. CRÉATION DU VENV POUR KOLLA-ANSIBLE
#############################################
echo "[STEP] Vérification / création du virtualenv Kolla-Ansible..."

if [ ! -d "$KOLLA_VENV_DIR" ]; then
  echo "[INFO] Création du venv $KOLLA_VENV_DIR..."
  python3 -m venv "$KOLLA_VENV_DIR"
fi

# shellcheck disable=SC1090
source "$KOLLA_VENV_DIR/bin/activate"

pip install -U pip

# Ansible peut déjà être présent, on ré-assure la version
pip install "ansible>=8,<9"

#############################################
# 5. INSTALLATION DE KOLLA-ANSIBLE
#############################################
echo "[STEP] Installation / vérification de Kolla-Ansible..."

if ! python -c "import kolla_ansible" 2>/dev/null; then
  echo "[INFO] kolla-ansible non détecté dans le venv -> installation..."
  # Tu peux basculer sur un pin précis si tu veux, ex: kolla-ansible==18.8.1
  pip install "git+https://opendev.org/openstack/kolla-ansible@$KOLLA_RELEASE"
else
  echo "[INFO] kolla-ansible déjà présent dans le venv, on ne réinstalle pas."
fi

mkdir -p /etc/kolla
chown "$(id -un)":"$(id -gn)" /etc/kolla

# Copier les fichiers d'exemple uniquement si pas déjà présents
if [ ! -f /etc/kolla/globals.yml ]; then
  echo "[INFO] Copie des fichiers d'exemple Kolla dans /etc/kolla..."
  cp "$KOLLA_VENV_DIR/share/kolla-ansible/etc_examples/kolla/"* /etc/kolla/
fi

# Copier l'inventaire all-in-one dans /root s'il n'existe pas
if [ ! -f /root/all-in-one ]; then
  echo "[INFO] Copie de l'inventaire all-in-one dans /root..."
  cp "$KOLLA_VENV_DIR/share/kolla-ansible/ansible/inventory/all-in-one" /root/
fi

#############################################
# 6. FICHIER ansible.cfg
#############################################
echo "[STEP] Création / mise à jour de /root/ansible.cfg..."

cat >/root/ansible.cfg <<EOF
[defaults]
host_key_checking = False
pipelining = True
forks = 100
EOF

export ANSIBLE_CONFIG=/root/ansible.cfg

#############################################
# 7. PRÉPARATION CINDER (VG LVM SUR FICHIER)
#############################################
echo "[STEP] Préparation du volume group LVM pour Cinder..."

if vgs "$CINDER_VG_NAME" >/dev/null 2>&1; then
  echo "[INFO] VG $CINDER_VG_NAME déjà présent, on ne recrée pas."
else
  echo "[INFO] Création du fichier loop pour Cinder : ${CINDER_LOOP_SIZE_GB}G à $CINDER_LOOP_FILE..."
  mkdir -p "$(dirname "$CINDER_LOOP_FILE")"
  if [ ! -f "$CINDER_LOOP_FILE" ]; then
    dd if=/dev/zero of="$CINDER_LOOP_FILE" bs=1G count="$CINDER_LOOP_SIZE_GB"
  fi

  echo "[INFO] Association du loop device..."
  LOOP_DEV=$(losetup -f --show "$CINDER_LOOP_FILE")
  echo "[INFO] Loop device utilisé : $LOOP_DEV"

  pvcreate "$LOOP_DEV"
  vgcreate "$CINDER_VG_NAME" "$LOOP_DEV"
fi

#############################################
# 8. CONFIGURATION /etc/kolla/globals.yml
#############################################
echo "[STEP] Configuration (override) de /etc/kolla/globals.yml..."

cat >/etc/kolla/globals.yml <<EOF
---
###################
# Ansible options
###################
workaround_ansible_issue_8743: yes

###############
# Kolla options
###############
config_strategy: "COPY_ALWAYS"
kolla_base_distro: "ubuntu"
openstack_release: "2024.1"

kolla_internal_vip_address: "$HOST_IP"
kolla_internal_fqdn: "{{ kolla_internal_vip_address }}"
kolla_external_vip_address: "{{ kolla_internal_vip_address }}"
kolla_external_fqdn: "{{ kolla_external_vip_address }}"

##################
# Container engine
##################
# [ docker, podman ]
kolla_container_engine: docker

##############################
# Networking - VirtualBox lab
##############################
network_interface: "$PRIMARY_IF"
api_interface: "$PRIMARY_IF"
kolla_external_vip_interface: "$PRIMARY_IF"
neutron_external_interface: "$PRIMARY_IF"
neutron_plugin_agent: "openvswitch"

###################
# OpenStack options
###################
enable_openstack_core: "yes"

# Services de base demandés
enable_keystone: "{{ enable_openstack_core | bool }}"
enable_glance: "{{ enable_openstack_core | bool }}"
enable_neutron: "{{ enable_openstack_core | bool }}"
enable_nova: "{{ enable_openstack_core | bool }}"
enable_horizon: "{{ enable_openstack_core | bool }}"
enable_swift: "no"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"

# Services infra
enable_mariadb: "yes"
enable_memcached: "yes"
enable_rabbitmq: "yes"

# Pas de HAProxy/HA pour un AIO simple
enable_haproxy: "no"
enable_hacluster: "no"

################################
# Cinder - Block Storage Options
################################
cinder_volume_group: "$CINDER_VG_NAME"

EOF

echo "[INFO] globals.yml configuré avec :"
echo "       - IP interne/externe : $HOST_IP"
echo "       - Interface réseau    : $PRIMARY_IF"
echo "       - Cinder VG           : $CINDER_VG_NAME"
echo "       - Swift               : désactivé"

#############################################
# 9. GÉNÉRATION DES MOTS DE PASSE
#############################################
echo "[STEP] Vérification / génération de /etc/kolla/passwords.yml..."

if [ ! -f /etc/kolla/passwords.yml ]; then
  echo "[INFO] passwords.yml absent -> génération avec kolla-genpwd..."
  kolla-genpwd
else
  echo "[INFO] passwords.yml déjà présent -> on ne régénère pas (pour ne pas casser les mots de passe existants)."
fi

#############################################
# 10. INSTALLATION DES ROLES GALAXY
#############################################
echo "[STEP] Installation des dépendances Ansible Galaxy..."
kolla-ansible install-deps

#############################################
# 11. BOOTSTRAP DU NŒUD
#############################################
echo "[STEP] Bootstrap du nœud (install Docker, etc.)..."
cd /root
kolla-ansible -i all-in-one bootstrap-servers

#############################################
# 12. PRÉCHECKS
#############################################
echo "[STEP] Exécution des préchecks..."
kolla-ansible -i all-in-one prechecks

#############################################
# 13. DÉPLOIEMENT OPENSTACK
#############################################
echo "[STEP] Déploiement OpenStack (cela peut être long)..."
kolla-ansible -i all-in-one deploy

#############################################
# 14. POST-DEPLOY
#############################################
echo "[STEP] Post-deploy (création admin-openrc, etc.)..."
kolla-ansible post-deploy

echo
echo "==========================================================="
echo "[OK] Déploiement Kolla-Ansible AIO terminé (sans Swift)."
echo " - IP Horizon (non TLS) : http://$HOST_IP/"
echo " - Fichier admin-openrc : /etc/kolla/admin-openrc.sh"
echo "Pour utiliser la CLI :"
echo "  source /etc/kolla/admin-openrc.sh"
echo "==========================================================="

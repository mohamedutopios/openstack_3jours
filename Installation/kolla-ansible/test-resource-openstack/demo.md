Voici un script Bash complet qui va :

* vérifier que le CLI OpenStack est dispo et que tu es authentifié
* créer réseau + sous-réseau + routeur
* créer une image Ubuntu cloud si besoin
* créer un security group qui ouvre **SSH (22)** et **HTTP (80)**
* créer une VM avec **cloud-init** qui installe et démarre **nginx**
* lui associer une **IP flottante** sur le réseau externe
* t’afficher l’URL à ouvrir dans le navigateur de ta VM Ubuntu (celle qui héberge OpenStack)

---

## 1. Le script `deploy_nginx_vm.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

#############################################
# CONFIGURATION (à adapter au besoin)
#############################################

# Nom du réseau interne et du sous-réseau
INT_NET_NAME="demo-net"
INT_SUBNET_NAME="demo-subnet"
INT_SUBNET_CIDR="10.10.10.0/24"
INT_SUBNET_GW="10.10.10.1"
INT_DNS="8.8.8.8"

# Routeur
ROUTER_NAME="demo-router"

# Image pour la VM
IMAGE_NAME="ubuntu-22.04-cloud"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"

# Flavor (doit exister dans ton OpenStack)
FLAVOR_NAME="m1.small"

# Clé SSH (fichier public existant sur ta VM Ubuntu)
SSH_PUBKEY="${HOME}/.ssh/id_rsa.pub"
KEYPAIR_NAME="demo-key"

# Security group pour HTTP + SSH
SEC_GROUP_NAME="web-secgroup"

# Nom de la VM
SERVER_NAME="web-nginx-1"

#############################################
# 0. VÉRIFICATIONS DE BASE
#############################################

if ! command -v openstack >/dev/null 2>&1; then
  echo "[ERREUR] La commande 'openstack' n'est pas disponible."
  echo "         Installe le client : sudo apt install python3-openstackclient"
  exit 1
fi

if [ -z "${OS_AUTH_URL:-}" ]; then
  echo "[ERREUR] Les variables d'environnement OpenStack ne sont pas chargées."
  echo "         Fais par exemple : source /etc/kolla/admin-openrc.sh"
  exit 1
fi

if [ ! -f "$SSH_PUBKEY" ]; then
  echo "[ERREUR] Clé publique SSH introuvable : $SSH_PUBKEY"
  echo "         Génère-en une avec : ssh-keygen -t rsa -b 4096"
  exit 1
fi

echo "✅ Client OpenStack et variables d'env OK."

#############################################
# 1. RÉSEAU EXTERNE EXISTANT
#############################################
# On tente de détecter le premier réseau marqué --external

EXTERNAL_NET_NAME="${EXTERNAL_NET_NAME:-$(openstack network list --external -f value -c Name | head -n1 || true)}"

if [ -z "$EXTERNAL_NET_NAME" ]; then
  echo "[ERREUR] Aucun réseau externe trouvé (openstack network list --external)."
  echo "         Tu dois déjà avoir un réseau externe (br-ex) configuré via Kolla."
  exit 1
fi

echo "🌐 Réseau externe détecté : $EXTERNAL_NET_NAME"

#############################################
# 2. RÉSEAU INTERNE + SOUS-RÉSEAU
#############################################

if ! openstack network show "$INT_NET_NAME" >/dev/null 2>&1; then
  echo "➡️  Création du réseau interne : $INT_NET_NAME"
  openstack network create "$INT_NET_NAME"
else
  echo "ℹ️  Réseau interne déjà existant : $INT_NET_NAME"
fi

if ! openstack subnet show "$INT_SUBNET_NAME" >/dev/null 2>&1; then
  echo "➡️  Création du sous-réseau : $INT_SUBNET_NAME"
  openstack subnet create "$INT_SUBNET_NAME" \
    --network "$INT_NET_NAME" \
    --subnet-range "$INT_SUBNET_CIDR" \
    --gateway "$INT_SUBNET_GW" \
    --dns-nameserver "$INT_DNS"
else
  echo "ℹ️  Sous-réseau déjà existant : $INT_SUBNET_NAME"
fi

#############################################
# 3. ROUTEUR ET GATEWAY
#############################################

if ! openstack router show "$ROUTER_NAME" >/dev/null 2>&1; then
  echo "➡️  Création du routeur : $ROUTER_NAME"
  openstack router create "$ROUTER_NAME"
else
  echo "ℹ️  Routeur déjà existant : $ROUTER_NAME"
fi

# Définir le réseau externe comme gateway du routeur
echo "➡️  Configuration de la gateway externe sur le routeur"
openstack router set "$ROUTER_NAME" --external-gateway "$EXTERNAL_NET_NAME"

# Attacher le sous-réseau interne au routeur
if ! openstack router show "$ROUTER_NAME" -f json | grep -q "$INT_SUBNET_NAME"; then
  echo "➡️  Attache du sous-réseau $INT_SUBNET_NAME au routeur $ROUTER_NAME"
  openstack router add subnet "$ROUTER_NAME" "$INT_SUBNET_NAME" || true
else
  echo "ℹ️  Le sous-réseau est déjà attaché au routeur."
fi

#############################################
# 4. IMAGE UBUNTU CLOUD (pour cloud-init)
#############################################

if ! openstack image show "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "➡️  Téléchargement de l'image Ubuntu (ça peut prendre un moment)..."
  TMP_IMG="/tmp/${IMAGE_NAME}.qcow2"
  wget -O "$TMP_IMG" "$IMAGE_URL"

  echo "➡️  Import de l'image dans Glance : $IMAGE_NAME"
  openstack image create "$IMAGE_NAME" \
    --disk-format qcow2 \
    --container-format bare \
    --file "$TMP_IMG" \
    --private
else
  echo "ℹ️  Image déjà existante : $IMAGE_NAME"
fi

#############################################
# 5. CLÉ SSH (KEYPAIR)
#############################################

if ! openstack keypair show "$KEYPAIR_NAME" >/dev/null 2>&1; then
  echo "➡️  Création du keypair OpenStack : $KEYPAIR_NAME"
  openstack keypair create "$KEYPAIR_NAME" --public-key "$SSH_PUBKEY"
else
  echo "ℹ️  Keypair déjà existant : $KEYPAIR_NAME"
fi

#############################################
# 6. SECURITY GROUP HTTP + SSH
#############################################

# On ne touche pas au "default" : on en crée un spécifique
if ! openstack security group show "$SEC_GROUP_NAME" >/dev/null 2>&1; then
  echo "➡️  Création du security group : $SEC_GROUP_NAME"
  openstack security group create "$SEC_GROUP_NAME" \
    --description "SSH + HTTP pour serveur web"
else
  echo "ℹ️  Security group déjà existant : $SEC_GROUP_NAME"
fi

# Règle SSH (22/tcp) si absente
if ! openstack security group rule list "$SEC_GROUP_NAME" -f value -c "Port Range" | grep -q "22:22"; then
  echo "➡️  Ajout de la règle SSH (22/tcp)"
  openstack security group rule create "$SEC_GROUP_NAME" \
    --protocol tcp --dst-port 22:22 --ingress --ethertype IPv4
fi

# Règle HTTP (80/tcp) si absente
if ! openstack security group rule list "$SEC_GROUP_NAME" -f value -c "Port Range" | grep -q "80:80"; then
  echo "➡️  Ajout de la règle HTTP (80/tcp)"
  openstack security group rule create "$SEC_GROUP_NAME" \
    --protocol tcp --dst-port 80:80 --ingress --ethertype IPv4
fi

#############################################
# 7. CLOUD-INIT POUR INSTALLER NGINX
#############################################

USER_DATA_FILE="$(pwd)/cloud-init-nginx.yaml"

cat > "$USER_DATA_FILE" <<'EOF'
#cloud-config
packages:
  - nginx

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - bash -c 'echo "<h1>Serveur NGINX OpenStack OK</h1>" > /var/www/html/index.html || echo "<h1>NGINX par défaut</h1>" > /var/www/html/index.nginx-debian.html'
EOF

echo "ℹ️  Fichier cloud-init généré : $USER_DATA_FILE"

#############################################
# 8. CRÉATION DE LA VM
#############################################

if openstack server show "$SERVER_NAME" >/dev/null 2>&1; then
  echo "ℹ️  La VM $SERVER_NAME existe déjà, on ne la recrée pas."
else
  echo "➡️  Création de la VM : $SERVER_NAME"

  NET_ID=$(openstack network show "$INT_NET_NAME" -f value -c id)

  openstack server create "$SERVER_NAME" \
    --flavor "$FLAVOR_NAME" \
    --image "$IMAGE_NAME" \
    --nic net-id="$NET_ID" \
    --security-group "$SEC_GROUP_NAME" \
    --key-name "$KEYPAIR_NAME" \
    --user-data "$USER_DATA_FILE"

  echo "⏳ Attente que la VM soit ACTIVE..."
  while true; do
    STATUS=$(openstack server show "$SERVER_NAME" -f value -c status)
    echo "   -> Statut actuel : $STATUS"
    if [ "$STATUS" = "ACTIVE" ]; then
      break
    elif [ "$STATUS" = "ERROR" ]; then
      echo "[ERREUR] La VM est en état ERROR. Vérifie 'openstack server show $SERVER_NAME'."
      exit 1
    fi
    sleep 5
  done
fi

#############################################
# 9. IP FLOTTANTE ET ASSOCIATION
#############################################

# On vérifie si la VM a déjà une floating IP
EXISTING_FIP=$(openstack server show "$SERVER_NAME" -f json | \
  python3 - "$SERVER_NAME" <<'PYCODE'
import json, sys
data = json.load(sys.stdin)
addresses = data.get("addresses", "")
# format: "demo-net=10.10.10.5; 203.0.113.10"
fip = None
for part in addresses.split(","):
    if "=" not in part:
        continue
    _, addrs = part.split("=", 1)
    for addr in addrs.split():
        if ";" in addr:
            ip = addr.split(";", 1)[1]
            if ip.count(".") == 3:
                fip = ip
                break
    if fip:
        break
if fip:
    print(fip)
PYCODE
) || true

if [ -n "${EXISTING_FIP:-}" ]; then
  FLOATING_IP="$EXISTING_FIP"
  echo "ℹ️  La VM a déjà une floating IP : $FLOATING_IP"
else
  echo "➡️  Création d'une nouvelle floating IP sur $EXTERNAL_NET_NAME"
  FLOATING_IP=$(openstack floating ip create "$EXTERNAL_NET_NAME" -f value -c floating_ip_address)
  echo "➡️  Association de la floating IP $FLOATING_IP à la VM $SERVER_NAME"
  openstack server add floating ip "$SERVER_NAME" "$FLOATING_IP"
fi

#############################################
# 10. RÉSUMÉ
#############################################

echo "============================================================"
echo "✅ Déploiement terminé."
echo "VM            : $SERVER_NAME"
echo "Réseau interne: $INT_NET_NAME ($INT_SUBNET_CIDR)"
echo "Routeur       : $ROUTER_NAME (gateway -> $EXTERNAL_NET_NAME)"
echo "Security group: $SEC_GROUP_NAME (SSH + HTTP)"
echo "Floating IP   : $FLOATING_IP"
echo "------------------------------------------------------------"
echo "Sur ta VM Ubuntu (celle où tu as installé OpenStack) :"
echo "  -> Ouvre un navigateur et va sur : http://$FLOATING_IP"
echo "Tu devrais voir la page Nginx."
echo "============================================================"
```

---

## 2. Comment l’utiliser

1. Sauvegarde le script sur ta VM Ubuntu (celle qui héberge Kolla/OpenStack) :

```bash
nano deploy_nginx_vm.sh
# colle le script, puis enregistre
chmod +x deploy_nginx_vm.sh
```

2. Charge les variables OpenStack (avec Kolla, en root en général) :

```bash
sudo -i
source /etc/kolla/admin-openrc.sh
```

3. Lance le script :

```bash
./deploy_nginx_vm.sh
```

4. À la fin, il t’affichera une ligne du type :

```text
Floating IP   : 192.168.56.123
Sur ta VM Ubuntu :
  -> Ouvre un navigateur et va sur : http://192.168.56.123
```

Depuis **le navigateur de ta VM Ubuntu**, tu vas sur cette URL → tu dois voir Nginx.
Si ça ne répond pas, dis-moi ce que donne :

```bash
openstack server list
openstack floating ip list
openstack network list
```

et on debug ensemble.

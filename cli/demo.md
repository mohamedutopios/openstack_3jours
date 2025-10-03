Parfait 👍 tu veux une **série de commandes OpenStack CLI** pour gérer les ressources principales (réseaux, VM, volumes, images, sécurité).
Je vais te donner une **boîte à outils complète** : les commandes de base + quelques options utiles, avec une explication rapide à chaque fois.

---

# 🚀 Commandes OpenStack CLI (gestion des ressources)

---

## 🔹 1. Authentification & projets

```bash
# Vérifier la connexion (token valide)
openstack token issue

# Voir les projets
openstack project list

# Changer de projet (si plusieurs)
export OS_PROJECT_NAME=myproject
```

---

## 🔹 2. Images (Glance)

```bash
# Lister les images disponibles
openstack image list

# Ajouter une image (ex: cirros)
openstack image create "cirros2" \
  --disk-format qcow2 --container-format bare \
  --public --file cirros-0.4.0-x86_64-disk.img

# Supprimer une image
openstack image delete cirros2
```

---

## 🔹 3. Flavors (tailles de VM)

```bash
# Lister les flavors
openstack flavor list

# Créer un flavor (1 vCPU, 512 MB RAM, 5 GB disque)
openstack flavor create m1.tiny --ram 512 --disk 5 --vcpus 1

# Supprimer un flavor
openstack flavor delete m1.tiny
```

---

## 🔹 4. Réseaux & sous-réseaux (Neutron)

```bash
# Lister les réseaux
openstack network list

# Créer un réseau privé
openstack network create net-a

# Créer un sous-réseau
openstack subnet create --network net-a --subnet-range 10.20.0.0/24 subnet-a

# Lister les sous-réseaux
openstack subnet list

# Supprimer un réseau
openstack network delete net-a
```

---

## 🔹 5. Routeurs (L3 agent)

```bash
# Créer un routeur
openstack router create router1

# Attacher un subnet au routeur
openstack router add subnet router1 subnet-a

# Attacher une gateway externe
openstack router set router1 --external-gateway public-net

# Supprimer un routeur
openstack router delete router1
```

---

## 🔹 6. Security Groups & règles

```bash
# Lister les groupes de sécurité
openstack security group list

# Créer un groupe
openstack security group create sg-demo

# Ajouter une règle ICMP (ping)
openstack security group rule create --proto icmp sg-demo

# Ajouter une règle SSH
openstack security group rule create --proto tcp --dst-port 22 sg-demo

# Supprimer un groupe
openstack security group delete sg-demo
```

---

## 🔹 7. VM (Nova)

```bash
# Lister les VM
openstack server list

# Créer une VM
openstack server create --flavor m1.small --image cirros \
  --network net-a --security-group sg-demo --key-name mykey vm1

# Afficher les détails
openstack server show vm1

# Démarrer / arrêter une VM
openstack server stop vm1
openstack server start vm1

# Supprimer une VM
openstack server delete vm1
```

---

## 🔹 8. Volumes (Cinder)

```bash
# Lister les volumes
openstack volume list

# Créer un volume de 1 Go
openstack volume create --size 1 vol1

# Attacher un volume à une VM
openstack server add volume vm1 vol1

# Détacher un volume
openstack server remove volume vm1 vol1

# Supprimer un volume
openstack volume delete vol1
```

---

## 🔹 9. Floating IP

```bash
# Créer une floating IP dans le réseau externe
openstack floating ip create public-net

# Associer à une VM
openstack server add floating ip vm1 192.168.1.101

# Supprimer une floating IP
openstack floating ip delete 192.168.1.101
```

---

## 🔹 10. Stack (Heat, orchestration)

```bash
# Lister les stacks
openstack stack list

# Créer une stack à partir d’un template
openstack stack create -t mytemplate.yaml mystack

# Supprimer une stack
openstack stack delete mystack
```

---

# ✅ Résumé

Avec ça tu peux gérer :

* **Images** (Glance)
* **Flavors** (Nova)
* **Réseaux, subnets, routeurs** (Neutron)
* **Security groups & règles**
* **VM** (lifecycle complet)
* **Volumes** (Cinder)
* **Floating IP**
* **Stacks** (Heat)



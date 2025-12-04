# 🟥 1. COMMENT OPENSTACK ATTRIBUE DES PERMISSIONS AUX RÔLES

Chaque service OpenStack → possède un fichier :

```
/etc/<service>/<service>-policy.yaml
# parfois policy.json (anciennes versions)
```

Exemples :

* Keystone → policy.yaml
* Nova → policy.yaml
* Neutron → policy.yaml
* Swift → proxy-server.conf + ACL
* Cinder → policy.yaml
* Glance → policy.yaml

Ces fichiers contiennent des règles du type :

```yaml
"compute:get": "role:admin or role:member"
```

Tu peux ajouter :

```yaml
"compute:get": "role:analyst"
```

➡️ Si un rôle est listé, il a le droit
➡️ S'il n'est pas listé, le service bloque (403 Forbidden)

---

# 🟦 2. OBJECTIF : DÉFINIR UN RÔLE *ANALYST*

Nous allons créer un rôle analyst avec les capacités suivantes :

| Fonction               | Analyst peut ? |
| ---------------------- | -------------- |
| Voir les VMs (listing) | ✔ oui          |
| Voir les flavors       | ✔ oui          |
| Voir les images        | ✔ oui          |
| Lire dans Swift        | ✔ oui          |
| Écrire dans Swift      | ❌ non          |
| Créer / supprimer VM   | ❌ non          |
| Modifier réseau        | ❌ non          |
| Créer volumes          | ❌ non          |
| Attacher volumes       | ❌ non          |

C’est un rôle **lecture seule + accès aux données**.

**Très adapté pour une équipe Data (DataTeam).**

---

# 🟩 3. CONFIGURATION EXACTE DES POLICIES POUR LE RÔLE ANALYST

---

# 🟦 A. Nova (Compute) — autoriser la lecture seule

Fichier :

```
/etc/nova/policy.yaml
```

Ajouter ou modifier :

```yaml
"os_compute_api:servers:index": "role:admin or role:member or role:analyst"
"os_compute_api:servers:detail": "role:admin or role:member or role:analyst"
"os_compute_api:servers:show": "role:admin or role:member or role:analyst"

# Interdire les actions dangereuses
"os_compute_api:servers:create": "role:admin or role:member"
"os_compute_api:servers:delete": "role:admin or role:member"
```

➡️ Analyst peut VOIR les VMs du projet
➡️ mais PAS en créer/supprimer

---

# 🟦 B. Glance (Images)

Fichier :

```
/etc/glance/policy.yaml
```

Ajouter :

```yaml
"get_images": "role:admin or role:member or role:analyst"
"get_image": "role:admin or role:member or role:analyst"
```

Interdire modifications :

```yaml
"add_image": "role:admin or role:member"
"modify_image": "role:admin"
```

➡️ Analyst peut VOIR les images
➡️ mais pas en importer

---

# 🟦 C. Swift (Object Storage) — clé pour un rôle analyst

Swift utilise un fichier différent :

```
/etc/swift/proxy-server.conf
```

Ajouter dans la section ACLs :

```ini
read_only_roles = analyst
```

Ou dans les politiques :

```ini
operator_roles = admin, member
read_roles = analyst
```

Ensuite tu peux restreindre l’écriture :

```
"object:put": "role:admin or role:member"
"object:get": "role:admin or role:member or role:analyst"
```

➡️ Analyst peut LIRE mais pas ÉCRIRE dans Swift.

---

# 🟦 D. Cinder (Volumes)

Fichier :

```
/etc/cinder/policy.yaml
```

Lecture seule :

```yaml
"volume:get_all": "role:admin or role:analyst"
"volume:get": "role:admin or role:analyst"
```

Mais pas d'écriture :

```yaml
"volume:create": "role:admin or role:member"
"volume:delete": "role:admin or role:member"
```

---

# 🟦 E. Neutron (Network)

Fichier :

```
/etc/neutron/policy.yaml
```

Autoriser la lecture :

```yaml
"get_network": "role:admin or role:member or role:analyst"
"get_subnet": "role:admin or role:member or role:analyst"
"get_port": "role:admin or role:member or role:analyst"
```

Interdire modifications :

```yaml
"create_network": "role:admin or role:member"
```

---

# 🟩 4. RECHARGER LES SERVICES

⚠️ Important : chaque service doit recharger sa policy.

```
sudo systemctl restart nova-api
sudo systemctl restart glance-api
sudo systemctl restart neutron-server
sudo systemctl restart cinder-api
sudo systemctl restart apache2   # pour Keystone
sudo docker restart swift_proxy  # pour Swift sous Kolla
```

---

# 🟥 5. TESTER LE RÔLE ANALYST

### A. Test listage des serveurs (NOVACOMPUTE)

```
openstack --os-username charlie --os-password Charlie123 \
 --os-project-name DataProject server list
```

Attendu :
✔ ça liste les serveurs
❌ mais pas de création possible

Test de création, cela doit échouer :

```
openstack --os-username charlie --os-password Charlie123 \
 --os-project-name DataProject server create ...
```

Attendu → `403 Forbidden`

---

### B. Test Swift (READ OK, WRITE KO)

```
openstack object list mybucket
```

Tester l’écriture :

```
openstack object create mybucket file.txt
```

Attendu → `403 Forbidden`

---

### C. Test Réseau (lecture ok)

```
openstack network list
```

---

### D. Test quotas (lecture OK)

```
openstack quota show DataProject
```

---

# 🟦 6. RÉSUMÉ DU RÔLE ANALYST (propre à ton entreprise)

| Service | Droit analyst | Effet |
| ------- | ------------- | ----- |
| Nova    | Voir VMs      | ✔     |
| Nova    | Créer VMs     | ❌     |
| Glance  | Voir images   | ✔     |
| Swift   | Lire objets   | ✔     |
| Swift   | Écrire objets | ❌     |
| Neutron | Voir réseaux  | ✔     |
| Cinder  | Voir volumes  | ✔     |
| Cinder  | Créer volumes | ❌     |


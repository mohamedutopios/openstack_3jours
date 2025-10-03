Parfait 👍 je vais te donner le **workflow complet en commandes `openstack`** pour :

1. Créer une VM.
2. Créer un volume NFS.
3. Attacher ce volume à la VM.

---

## 🚀 Étapes

### 1. Créer une VM

Exemple avec une image **cirros** et un flavor **m1.small** :

```bash
openstack server create \
  --image cirros \
  --flavor m1.small \
  --network demo-net \
  --security-group default \
  --key-name mykey \
  test-vm
```

➡️ Cela crée une VM appelée `test-vm`.

---

### 2. Créer un volume

Créer un volume de 1 Go :

```bash
openstack volume create --size 1 test-nfs
```

Vérifie qu’il est **available** :

```bash
openstack volume list
```

---

### 3. Attacher le volume à la VM

Rattacher le volume `test-nfs` à la VM `test-vm` :

```bash
openstack server add volume test-vm test-nfs
```

---

### 4. Vérifier l’attachement

```bash
openstack server show test-vm -f value -c volumes_attached
```

---


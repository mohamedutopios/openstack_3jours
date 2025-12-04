# 🚀 Exemple : Cinder avec backend **NFS**

## 1. Préparer un répertoire NFS sur ton hôte (Ubuntu)

Installe le serveur NFS :

```bash
sudo apt update
sudo apt install nfs-kernel-server -y
```

Crée un dossier pour les volumes Cinder :

```bash
sudo mkdir -p /var/lib/cinder-nfs
sudo chown -R nobody:nogroup /var/lib/cinder-nfs
sudo chmod 777 /var/lib/cinder-nfs
```

Configure l’export NFS :

```bash
echo "/var/lib/cinder-nfs *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
```

Vérifie :

```bash
showmount -e localhost
```

➡️ Doit montrer `/var/lib/cinder-nfs`.

---
## 2. Configurer Cinder pour NFS (dans Kolla-Ansible)

Édite `/etc/kolla/globals.yml` :

```yaml
enable_cinder: "yes"
enable_cinder_backend_lvm: "no"
enable_cinder_backend_nfs: "yes"

cinder_nfs_servers: "localhost:/var/lib/cinder-nfs"
```

1. **Créer le fichier attendu**
   Par défaut, Kolla-Ansible va chercher dans :

```
/etc/kolla/config/cinder/nfs_shares
```

Donc crée-le avec :

```bash
sudo mkdir -p /etc/kolla/config/cinder
echo "localhost:/var/lib/cinder-nfs" | sudo tee /etc/kolla/config/cinder/nfs_shares
```

2. **Vérifier les droits**
   Le fichier doit être lisible par Ansible (root) :

```bash
sudo chmod 644 /etc/kolla/config/cinder/nfs_shares
```

3. **Re-déployer uniquement Cinder**

```bash
kolla-ansible -i /etc/kolla/all-in-one reconfigure -t cinder
```

4. **Vérifier**

```bash
openstack volume service list
```

Tu dois voir ton backend NFS (`opk@nfs-1`) **up**.

---


## 5. Tester un volume

Créer un volume :

```bash
openstack volume create --size 1 test-nfs
```

Vérifie :

```bash
openstack volume list
```

➡️ Le volume doit être **available**.

Attache à une VM :

```bash
openstack server add volume <ID_VM> test-nfs
```



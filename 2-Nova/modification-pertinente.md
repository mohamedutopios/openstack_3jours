1. **Base obligatoire** (pour que ça marche)
2. **Performance / tuning**
3. **Fonctionnalités avancées (NUMA, SR-IOV, GPU, quotas, etc.)**
4. **Sécurité et observabilité**

---

# 1) Modifs de base obligatoires

Ces sections sont quasi toujours à revoir :

### `[DEFAULT]`

* `my_ip = <IP locale du node>` → IP de la carte de gestion (ex : `10.0.0.x`).
* `transport_url = rabbit://openstack:PASS@controller` → adresse du RabbitMQ.
* `use_neutron = true` → Nova doit déléguer le réseau à Neutron.
* `enabled_apis = osapi_compute,metadata` → n’expose que les APIs nécessaires.

### `[keystone_authtoken]`

* Doit être ajustée avec les bons **URL Keystone** et **mots de passe** (sinon Nova API ne s’authentifie pas).

### `[placement]`

* Obligatoire depuis Pike → indique les identifiants Placement.

### `[glance]`

* URL du service Glance (`http://controller:9292`).

---

# 2) Modifs de performance / tuning

### `[libvirt]`

* `virt_type = kvm` (par défaut, mais peut être `qemu` si pas de virtualisation hardware).
* `cpu_mode = host-model` (ou `host-passthrough` si tu veux de la perf pure → mais attention aux migrations live).
* `live_migration_uri = qemu+tcp://%s/system` (ou TLS si sécurité).
* `images_type = rbd` si tu utilises **Ceph** (meilleur pour perf et migration live).
* `disk_cachemodes = writeback` (optimisation IO).

### `[scheduler]`

* `discover_hosts_in_cells_interval = 300` → Nova découvre automatiquement les nouveaux compute hosts.
* `workers = <nb_coeurs>` → ajuster le nombre de workers du scheduler/api pour mieux paralléliser.

---

# 3) Fonctions avancées (selon besoins)

### CPU / NUMA

* Dans `nova.conf` :

  ```ini
  [compute]
  cpu_dedicated_set = 2-15
  cpu_shared_set = 0,1
  reserved_host_memory_mb = 2048
  ```

  → Permet le **CPU pinning** (VM avec CPU dédiés), et réserve 2 Go de RAM à l’hyperviseur.

### Hugepages

```ini
[libvirt]
hugepages = True
```

→ si tu configures des pages énormes côté kernel.

### PCI passthrough / SR-IOV

```ini
[pci]
passthrough_whitelist = [{"address": "0000:05:00.0", "physical_network": "physnet1"}]
alias = {"name": "gpu", "product_id": "1db6", "vendor_id": "10de", "device_type": "type-PCI"}
```

→ pour exposer des GPUs/NICs SR-IOV aux VMs via les flavors.

### VGPU

* Déclaration des traits (Placement) + config `[devices]` pour vGPU NVIDIA/Intel.

---

# 4) Sécurité et observabilité

### `[vnc]` ou `[spice]`

* `server_listen = 0.0.0.0`
* `novncproxy_base_url = http://controller:6080/vnc_auto.html`
  ⚠️ En prod, restreindre l’accès VNC/Spice derrière un proxy sécurisé.

### `[oslo_concurrency]`

```ini
lock_path = /var/lib/nova/tmp
```

* Important pour éviter les races conditions sur les locks.

### `[quota]`

* Personnalisation des quotas projet :

  ```ini
  [quota]
  cores = 100
  instances = 50
  ram = 256000
  ```
* Permet d’ajuster en fonction de ton cloud.

### Logs et debug

```ini
[DEFAULT]
debug = true
log_dir = /var/log/nova
```

* Activer le `debug` temporairement quand tu débogues.

---

# 5) Autres fichiers utiles

* `/etc/nova/policy.yaml` → personnaliser les **règles RBAC** (ex : qui peut créer une VM, qui peut faire des migrations).
* `/etc/nova/api-paste.ini` → pipeline WSGI (tu peux activer/désactiver des middlewares, comme rate-limit).
* `/etc/nova/rootwrap.conf` → contrôle des commandes root autorisées.

---

# 👉 Bonnes pratiques

* Toujours séparer **conf de dev** (debug activé, `cpu_mode=host-passthrough`) et **conf de prod** (limites, sécurité).
* Vérifier après chaque modif avec :

  ```bash
  nova-status upgrade check
  openstack compute service list
  journalctl -u nova-compute -f
  ```
* Documenter les extra_specs/flavors liés aux changements (`hw:cpu_policy`, `trait:CUSTOM_GPU`, etc.).
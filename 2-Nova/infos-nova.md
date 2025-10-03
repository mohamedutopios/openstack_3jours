Super question 👍 — voici une vue “de bout-en-bout” d’OpenStack Nova, avec l’architecture, le cycle de vie d’une VM, la configuration (fichiers/sections clés), l’ordonnancement (scheduler + Placement), et les options avancées (NUMA, SR-IOV, migrations, etc.). Je te laisse un gabarit `nova.conf` minimal + des check-lists opérateurs.

# 1) Rôle et grands blocs de Nova

Nova est le service Compute d’OpenStack : il expose une API REST, orchestre l’ordonnancement (choix d’un hôte), délègue la création/gestion des machines virtuelles aux nœuds de calcul, et s’appuie sur d’autres services : **Glance** (images), **Neutron** (réseau), **Cinder/Manila** (volumes/fichiers), **Placement** (capacité/traits), **Keystone** (auth). Les composants clés :

* **nova-api** : entrée REST (wsgi), gère les microversions, la validation, et publie des requêtes sur le bus RPC. Fournit aussi l’API **metadata** (ou via `nova-api-metadata`), généralement proxifiée par `neutron-metadata-agent`. ([docs.openstack.org][1])
* **nova-conductor** : logique lourde côté contrôleur (DB touches, orchestration), pour décharger les computes. ([docs.openstack.org][1])
* **nova-scheduler** : choisit un hôte en consultant **Placement** (capacité, traits, agrégats/AZ) puis réserve (allocations). ([docs.openstack.org][2])
* **nova-compute** (sur chaque hôte) : dialogue avec l’hyperviseur (libvirt/KVM, etc.), attache les ports Neutron et volumes Cinder, crée/boote la VM. ([docs.openstack.org][3])
* **Placement** (service séparé) : inventorie les **resource providers** (nœuds, pools de stockage partagés…), publie inventaire/usage, gère **resource classes** (VCPU, MEMORY_MB…), **traits** (ex : `HW_CPU_X86_AVX2`), et renvoie au scheduler des **candidats d’allocation**. ([docs.openstack.org][4])
* **Cells v2** : sharding horizontal de Nova (chaque cell = DB + MQ par “groupe” de computes). **Toutes** les déploiements ont au moins `cell0` (échecs de scheduling) + `cell1`. ([docs.openstack.org][1])

# 2) Architecture logique (Cells v2 + Placement)

* **Topologie** : API “globales” (Keystone/Nova API) au dessus, puis routing vers la bonne **cell** où vivent `nova-conductor`/DB/MQ et les `nova-compute`. `cell0` sert de collecteur pour les requêtes impossibles à placer. ([docs.openstack.org][5])
* **Placement** : les computes publient leur inventaire (VCPU, mémoire, disque, PCI, vGPU, traits) vers Placement; le scheduler demande des “allocation candidates” filtrés (pré-filtres AZ/agrégats, traits requis, etc.) puis choisit/pondère. ([docs.openstack.org][6])

# 3) Cycle de vie d’une VM (chemin critique)

1. **API** : `openstack server create` (avec flavor, image/volume, ports Neutron, hints, server group…).
2. **Scheduler** : interroge **Placement** (ressources & traits requis), applique politiques (affinité/anti-affinité via server groups, agrégats/AZ, quotas), réserve (allocations). ([docs.openstack.org][2])
3. **Conductor → Compute** (RPC) : l’hôte choisi “claim” les ressources et spawn la VM via le *virt driver*.
4. **Neutron/Cinder** : plug des ports/attach des volumes, config-drive/metadata, puis boot.
5. **Reporting** : compute met à jour l’état, heartbeat, et publie usage vers Placement. ([docs.openstack.org][3])

# 4) Ordonnancement (scheduler) & Placement — ce que tu règles vraiment

* **AZ & agrégats** : map d’AZ vers agrégats Placement (`map_az_to_placement_aggregate`), utile pour scoper les hôtes par zone/fonction (SSD only, GPU only, etc.). ([docs.openstack.org][2])
* **Flavors & extra_specs** : définissent vCPU, RAM, disque, plus des besoins qualitatifs : NUMA/hugepages, CPU policy, PCI alias, **traits** requis (`trait:HW_CPU_X86_AVX2=require`), ressources personnalisées, etc. (nova → Placement). ([docs.openstack.org][6])
* **Server Groups** : `anti-affinity/affinity` au niveau hôtes (souvent par projet).
* **Host aggregates** : tags (métadonnées) côté hôtes ; couplés aux **extra_specs** pour filtrer (ex : `aggregate_instance_extra_specs`).
* **Traits & resource classes** : exposées par les computes (ex : `CUSTOM_NVME`, `HW_CPU_X86_VMX`), demandées par flavor/image/hints. ([Documentation Red Hat][7])

# 5) Composants sur disque & fichiers de conf

* **Fichiers** :

  * `/etc/nova/nova.conf` : la quasi-totalité de la conf (API, DB, MQ, libvirt, Placement, Neutron, Glance, Cinder, scheduler, pci/numa, consoles…). ([docs.openstack.org][8])
  * `/etc/nova/api-paste.ini` : pipeline WSGI (limiteurs, auth). ([docs.openstack.org][8])
  * **policy** : `/etc/nova/policy.yaml` pour surcharger RBAC.
  * Logs via Oslo : `/var/log/nova/*`.
* **Référence** : doc de conf + sample `nova.conf` officiel. (Les pages “Config Reference” listent les sections/options par thème.) ([docs.openstack.org][9])

# 6) Gabarit `nova.conf` (libvirt/KVM) — minimal “qui marche”

```ini
[DEFAULT]
transport_url = rabbit://openstack:SECRETRABBIT@ctrl:5672/
my_ip = 10.0.0.11
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
enabled_apis = osapi_compute,metadata
debug = false

[api_database]
connection = mysql+pymysql://nova:DBPASS@ctrl/nova_api

[database]
connection = mysql+pymysql://nova:DBPASS@ctrl/nova

[keystone_authtoken]
www_authenticate_uri = http://ctrl:5000
auth_url = http://ctrl:5000
memcached_servers = ctrl:11211
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = SERVICEPASS
auth_type = password

[glance]
api_servers = http://ctrl:9292

[neutron]
auth_url = http://ctrl:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = SERVICEPASS
service_metadata_proxy = true
metadata_proxy_shared_secret = METADATASECRET

[placement]
region_name = RegionOne
auth_type = password
auth_url = http://ctrl:5000
project_name = service
username = placement
password = SERVICEPASS
user_domain_name = Default
project_domain_name = Default

[libvirt]
virt_type = kvm
cpu_mode = host-model
video_type = virtio

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://ctrl:6080/vnc_auto.html

[scheduler]
discover_hosts_in_cells_interval = 300
# map_az_to_placement_aggregate = true   # utile si vous mappez AZ→agrégats

[oslo_concurrency]
lock_path = /var/lib/nova/tmp
```

> Adapte les hôtes/MDP/URLs à ton environnement. Si **Ceph RBD** pour les images éphémères : `images_type=rbd`, `images_rbd_pool=vms`, `images_rbd_ceph_conf=/etc/ceph/ceph.conf`. ([docs.openstack.org][9])

# 7) Procédures d’installation/initialisation (extraits utiles)

* **DB & cells v2** : `nova-manage api_db sync` → `nova-manage cell_v2 map_cell0` → `nova-manage cell_v2 create_cell --name cell1 --verbose` → `nova-manage db sync` → `nova-status upgrade check`. (Rappels dans les guides install/admin Nova 2025.1). ([docs.openstack.org][10])
* **Découverte d’hôtes** : `discover_hosts_in_cells_interval` ou `nova-manage cell_v2 discover_hosts`. ([docs.openstack.org][5])
* **Services** : `openstack compute service list`, `openstack hypervisor list`, `openstack resource provider list` (Placement), `openstack aggregate list`, `openstack server group list`. ([docs.openstack.org][6])

# 8) Hyperviseurs & virt-drivers

* **libvirt/KVM** est le plus courant (x86_64, ppc64le, aarch64). D’autres drivers existent (Ironic/bare metal, Xen, VMware via virt-driver dédié, etc.), mais les fonctionnalités varient. Les capacités (NUMA, hugepages, vGPU/PCI) dépendent du driver et du matériel. ([docs.openstack.org][3])

# 9) Stockage & images

* **Racine/éphémère/swap** : définis par flavor (ex : `--disk`, `--ephemeral`, `--swap`).
* **Backend des images éphémères** : fichiers locaux (`qcow2/raw`) ou **Ceph RBD** (performant & partagé).
* **Volumes Cinder** : attachés/détachés à chaud/froid; **Manila** (2025.1) autorise l’attachement direct de partages aux instances libvirt. ([specs.openstack.org][11])

# 10) Réseau & metadata

* **Neutron** crée/attribue les ports (binding vif), DHCP/L3, *security groups*.
* **Metadata** : en prod, `neutron-metadata-agent` proxifie vers l’API metadata de Nova avec `service_metadata_proxy=true` + `metadata_proxy_shared_secret` (Nova/Neutron). **Config-Drive** peut être forcé (`--config-drive true`). ([docs.openstack.org][8])

# 11) Fonctions avancées (production)

* **NUMA & CPU pinning** : `hw:cpu_policy=dedicated`, `hw:cpu_thread_policy=prefer/isolate`, `hw:numa_nodes`, `hw:mem_page_size=1GB` (image props ou extra_specs).
* **PCI passthrough & SR-IOV** : section `[pci]` (alias/whitelist), Neutron SR-IOV pour les NICs; possibilité de **vGPU** (traits/RC).
* **Traits & classes** : annonce côté compute, demande côté flavor/image (`trait:FOO=required`), filtrage en amont via Placement. ([Documentation Red Hat][7])
* **Consoles** : noVNC/Spice/serial (2025.1 ajoute *SPICE direct consoles* sous libvirt). ([specs.openstack.org][11])
* **Server Groups** : affinité/anti-affinité stricte ou “soft”.
* **Host aggregates/AZ** : regrouper des hôtes par caractéristiques (CPU AMD, NVMe, “GPU”) et mapper à des AZ. ([docs.openstack.org][2])

# 12) Opérations (migrations, taille, rebuild)

* **Live migration** (partagée/block-migration), vérifie compatibilité CPU, réseau, stockage; 2025.1 améliore la **live-migration de périphériques VFIO**. ([specs.openstack.org][11])
* **Cold migration / resize** : change de flavor et/ou d’hôte (confirm/revert).
* **Evacuate** : reprise après panne hôte (stockage partagé recommandé).
* **Rebuild** : réinstalle l’instance (même identité/ports).

# 13) Sécurité, quotas & politiques

* **RBAC** via `policy.yaml`.
* **Quotas** : passage aux **Unified Limits** (Keystone) accéléré; la 2025.1 (Epoxy) note une option de conf sur le comportement des limites non définies (upgrade notes). ([docs.openstack.org][12])

# 14) Observabilité & dépannage

* **Santé/état** : `openstack compute service list`, `openstack hypervisor stats show`.
* **Placement** : `openstack resource provider/inventory/usage`, corréler allocations ↔ VM. ([docs.openstack.org][6])
* **Vérifs d’upgrade** : `nova-status upgrade check`.
* **Logs** : `nova-api`, `nova-scheduler`, `nova-conductor`, `nova-compute` (rechercher ERROR/TRACE autour des requêtes d’allocations Placement/scheduler).

# 15) Bonnes pratiques d’architecture & conf

* **Toujours** déployer **Cells v2** correctement (au moins cell1 + cell0) et valider la découverte des hôtes. ([docs.openstack.org][5])
* **Converger via Placement** : exprimer les besoins en **traits/extra_specs** et utiliser **host aggregates** + **AZ** pour le contrôle logique. ([docs.openstack.org][2])
* **Séparer** DB/MQ par cell pour l’échelle; journalisation et métriques au niveau cell. ([docs.openstack.org][5])
* **Hyperviseur** : KVM + libvirt, `cpu_mode=host-model` (ou `host-passthrough` si tu maîtrises la compatibilité live-migration).
* **Stockage** : Ceph RBD pour images éphémères (partage + perf), Cinder/Manila suivant besoins. ([specs.openstack.org][11])
* **Réseau** : métadonnées via Neutron metadata-agent avec secret partagé; config-drive en fallback. ([docs.openstack.org][8])
* **Mises à jour** : lire les **release notes 2025.1 Epoxy** (SLURP : upgrade 2024.1→2025.1 possible en sautant 2024.2). ([docs.openstack.org][12])

---

## Check-lists opérateur (exécutables)

### A. Vérifier l’état global

```bash
openstack compute service list
openstack hypervisor list
openstack hypervisor stats show
openstack aggregate list && openstack availability zone list
openstack server group list
openstack resource provider list   # Placement
openstack limits show --project <id>
nova-status upgrade check
```

(Placement : `openstack resource provider inventory/usage/show <UUID>`). ([docs.openstack.org][6])

### B. Déboguer un échec de scheduling

1. Regarder `nova-scheduler.log` et la requête Placement (candidats 0 ?).
2. Confirmer **traits** et **extra_specs** du flavor / image.
3. Vérifier agrégats/AZ (`map_az_to_placement_aggregate`).
4. Inspecter inventaire/allocations du provider (Placement). ([docs.openstack.org][2])

### C. Activer options avancées (exemples de knobs)

* NUMA/CPU dedic. dans flavor (extra_specs) : `hw:cpu_policy=dedicated`, `hw:mem_page_size=1GB`, etc.
* PCI passthrough : `[pci] device_spec / alias`, et côté Neutron pour SR-IOV.
* vGPU : mapping traits/RC, agrégats “GPU”. ([Documentation Red Hat][7])

---

## Où trouver quoi (docs fiables et à jour)

* **Architecture & Cells v2** (admin) : schémas, bonnes pratiques. ([docs.openstack.org][1])
* **Scheduler & Placement** (admin) : pré-filtres, AZ→agrégats, fonctionnement concret. ([docs.openstack.org][2])
* **Placement API & concepts** : resource providers, traits, allocations, microversions. ([docs.openstack.org][6])
* **Configuration & sample `nova.conf`** : guide et référence par sections. ([docs.openstack.org][8])
* **Release notes 2025.1 (Epoxy)** : nouveautés (SPICE direct consoles, VFIO live-migration, Manila direct attach, OpenAPI schemas, unified limits…). ([docs.openstack.org][12])

---

Si tu veux, je peux te générer un **pack d’exemples de flavors/extra_specs** (NUMA, hugepages, GPU, SR-IOV), un `policy.yaml` de départ (RBAC restreint), et un **exemple d’agrégats/AZ** (CPU AMD vs Intel, NVMe vs HDD) adaptés à ton lab VirtualBox/Ubuntu 22.04.

[1]: https://docs.openstack.org/nova/latest/admin/architecture.html?utm_source=chatgpt.com "Nova System Architecture"
[2]: https://docs.openstack.org/nova/latest/admin/scheduling.html?utm_source=chatgpt.com "Compute schedulers — nova 32.1.0.dev11 documentation"
[3]: https://docs.openstack.org/nova/latest/install/get-started-compute.html?utm_source=chatgpt.com "Compute service overview — nova 32.1.0.dev11 ..."
[4]: https://docs.openstack.org/nova/queens/user/placement.html?utm_source=chatgpt.com "OpenStack Docs: Placement API"
[5]: https://docs.openstack.org/nova/latest/admin/cells.html?utm_source=chatgpt.com "Cells (v2) — nova 32.1.0.dev11 documentation"
[6]: https://docs.openstack.org/placement/latest/specs/index.html?utm_source=chatgpt.com "Placement Specifications"
[7]: https://docs.redhat.com/en/documentation/red_hat_openstack_platform/17.1/html/configuring_the_compute_service_for_instance_creation/assembly_configuring-instance-scheduling-and-placement_memory?utm_source=chatgpt.com "Chapter 7. Configuring instance scheduling and placement"
[8]: https://docs.openstack.org/nova/latest/admin/configuration/index.html?utm_source=chatgpt.com "Configuration — nova 31.1.0.dev372 documentation"
[9]: https://docs.openstack.org/nova/latest/configuration/index.html?utm_source=chatgpt.com "Configuration Guide - nova 32.1.0.dev11"
[10]: https://docs.openstack.org/2025.1/?utm_source=chatgpt.com "OpenStack Docs: 2025.1"
[11]: https://specs.openstack.org/openstack/nova-specs/specs/2025.1/index.html?utm_source=chatgpt.com "Nova 2025.1 Epoxy Specifications"
[12]: https://docs.openstack.org/releasenotes/nova/2025.1.html?utm_source=chatgpt.com "2025.1 Series Release Notes - nova"

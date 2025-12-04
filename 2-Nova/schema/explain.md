# 🖼️ **Analyse de l’image : Compute Hosts in User Plane**

## 🔶 Bloc de gauche : Services OpenStack de base

* **Keystone** → authentification et autorisation.
* **Neutron** → gestion des réseaux (ports, subnets, floating IPs).
* **Glance** → gestion des images (ISO, QCOW2, etc.).
* **Cinder** → stockage bloc (volumes persistants).

👉 Ces services sont utilisés à chaque création d’instance.

---

## 🟩 Bloc central : Services Nova

* **Nova API**

  * Reçoit la requête utilisateur :
    Exemple :

    ```bash
    $ openstack server create ...
    ```
  * Vérifie l’auth avec Keystone.
  * Demande l’image à Glance, le réseau à Neutron, les volumes à Cinder.
  * Transmet la requête au **scheduler**.

* **Nova Scheduler**

  * Choisit le compute node optimal pour l’instance.
  * Utilise le service Placement pour vérifier les ressources (RAM, CPU, GPU).

* **Nova Conductor**

  * Intermédiaire sécurisé entre le compute node et la DB.
  * Empêche les compute nodes d’accéder directement à la base.

---

## 🔷 En bas à gauche : les compute nodes Nova

* **nova-compute (KVM Host)**

  * VM gérées avec KVM/QEMU via libvirt.
* **nova-compute (ESX Host)**

  * Nova peut parler à VMware vCenter → gérer des VM sur ESXi.
  * Ici, plusieurs hôtes ESXi sont orchestrés via vCenter DRS (Distributed Resource Scheduler).

👉 Nova peut donc piloter à la fois des hyperviseurs open source (KVM) et propriétaires (VMware).

---

## 🟦 En bas au centre : Bare Metal avec Ironic

* **Ironic API & Ironic Conductor**

  * Extension d’OpenStack pour gérer du **bare metal** (pas de VM, du physique).
  * Nova envoie la requête à Ironic si on veut lancer un “instance” directement sur un serveur physique.
  * Exemple : provisionner un serveur pour une charge HPC.

---

## 🟪 À droite : Containers avec Zun

* **Zun API**

  * Service OpenStack pour orchestrer des conteneurs.
  * Permet de faire :

    ```bash
    $ openstack appcontainer run ...
    ```

* **Zun wsproxy**

  * Permet d’exposer la console/exec d’un conteneur.

* **zun-compute (Docker Host)**

  * Un compute node spécial qui parle à Docker Engine pour lancer des conteneurs.
  * Complémentaire à nova-compute (VM) et ironic (bare metal).

---

## 🔵 À droite : "Compute Host"

* Représente le fait que Nova peut piloter **plusieurs types de compute hosts** :

  * VM (KVM/VMware).
  * Bare metal (Ironic).
  * Containers (Zun).
  * … et potentiellement d’autres via des drivers.

---

# 🔄 Flux typique dans le schéma

1. Utilisateur tape une commande :

   * `openstack server create` → Nova API → Scheduler → Conductor → nova-compute → KVM/VMware.
   * `openstack appcontainer run` → Zun API → zun-compute → Docker.
   * Demande de **bare metal** → Nova API → Ironic API → Ironic Conductor → Bare Metal Host.

2. Les services Keystone, Neutron, Glance, Cinder sont consultés au passage.

3. Le résultat (VM, conteneur ou bare metal) tourne sur un compute host approprié.



# 🟦 **Installation complète de MicroStack**

---

## **1. Prérequis système**

* **OS** : Ubuntu 20.04, 22.04 ou supérieur (recommandé, fonctionne aussi sur d'autres distributions supportant Snap)
* **CPU** : Processeur avec virtualisation activée (VT-x, AMD-V)
* **RAM** : Minimum **8 Go** (16 Go recommandé)
* **Disque** : Au moins **40 Go** d’espace libre
* **Réseau** : Accès Internet pour télécharger les paquets/snaps

> **⚠️** Désactive tout hyperviseur (ex: VirtualBox sans nested virtualization), ou bien active la virtualisation dans le BIOS/UEFI si besoin.

---

## **2. Préparation de la machine**

```bash
# (Optionnel, mais recommandé) Mettre à jour le système
sudo apt update && sudo apt upgrade -y

# Installer snapd si ce n’est pas déjà fait
sudo apt install snapd -y

# Redémarrer le service snapd si besoin
sudo systemctl restart snapd
```

---

## **3. Installer MicroStack**

```bash
# Installer MicroStack en mode classic
sudo snap install microstack --classic
```

* Cette commande télécharge et installe tout le nécessaire (les services OpenStack empaquetés).

---

## **4. Initialiser MicroStack**

```bash
# Initialiser MicroStack (sur une machine "standalone" locale)
sudo microstack init --auto --control
```

* `--auto` : Pour répondre automatiquement aux questions par défaut
* `--control` : Installer le "control plane" sur la machine (par défaut pour un usage simple)
* Pour une configuration plus avancée (cluster, etc.), on peut utiliser d’autres options.

---

## **5. Vérifier le statut et les services**

```bash
# Voir le statut général de MicroStack
sudo microstack status

# Lister les services OpenStack lancés
sudo microstack.openstack service list
```

---

## **6. Accéder au dashboard Horizon**

* Après l’init, MicroStack affiche généralement l’adresse du dashboard web Horizon.
* Par défaut : http\://\<IP\_DE\_LA\_MACHINE>:80 ou [http://localhost](http://localhost)

Pour retrouver les infos d’accès :

```bash
sudo microstack.openstack dashboard list
# Ou simplement ouvre : http://<IP_DE_TA_MACHINE>
```

* **Identifiants par défaut :**

  * **Username** : `admin`
  * **Password** : (généré à l’init, visible à la fin de la commande `init` ou via la commande suivante)

Pour récupérer le mot de passe :

```bash
sudo snap get microstack config.credentials.keystone-password
```

---

## **7. (Optionnel) Configurer le réseau externe (NAT/Bridge)**

Par défaut, MicroStack crée un réseau privé et gère une passerelle NAT.
Si tu veux tester la connectivité vers/depuis l’extérieur :

* Vérifie la configuration réseau de ta VM/machine (bridge recommandé pour accéder aux instances OpenStack depuis ton LAN).
* Pour lister les réseaux :

```bash
sudo microstack.openstack network list
```

* Pour créer un réseau externe personnalisé :

```bash
sudo microstack.openstack network create external --external --provider-physical-network physnet1 --provider-network-type flat
```

(Tu n’es pas obligé de faire ça pour tester en local.)

---

## **8. (Optionnel) Utiliser la CLI OpenStack**

Pour utiliser la CLI OpenStack depuis MicroStack :

```bash
sudo microstack.openstack flavor list
sudo microstack.openstack image list
sudo microstack.openstack server list
```

(Toutes les commandes OpenStack fonctionnent avec le préfixe `sudo microstack.openstack`.)

---

## **9. Désinstaller MicroStack**

Pour tout nettoyer :

```bash
sudo snap remove microstack --purge
```

---

# **Résumé des étapes**

1. Met à jour ta machine, installe snapd
2. Installe MicroStack avec snap
3. Initialise MicroStack
4. Récupère l’URL et le mot de passe Horizon
5. Connecte-toi et profite de ton Cloud privé !

---

## **Documentation officielle**

* [https://microstack.run/docs/](https://microstack.run/docs/)
* [https://snapcraft.io/microstack](https://snapcraft.io/microstack)


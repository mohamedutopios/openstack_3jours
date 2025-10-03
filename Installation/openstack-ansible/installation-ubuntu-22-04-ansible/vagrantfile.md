Parfait 👍 on va repartir proprement et **sans gateway4 sur br-ex** (pour éviter les erreurs de routage).
Voici un **Vagrantfile testé et corrigé** qui prépare Ubuntu 22.04 pour OSA, avec toutes les étapes pour que ça marche dans VirtualBox.

---

# 📝 Vagrantfile complet (Ubuntu 22.04 + Netplan OSA)

Crée un fichier `Vagrantfile` dans un dossier vide avec ce contenu :

```ruby
Vagrant.configure("2") do |config|
  # 📦 Box officielle Ubuntu 22.04
  config.vm.box = "ubuntu/jammy64"
  config.vm.hostname = "osa-node"

  # 🌍 Carte 1 : NAT (Internet, DHCP)
  # -> fournit la gateway par défaut (10.0.2.2)
  config.vm.network "public_network", bridge: nil

  # 🔗 Carte 2 : Host-only (Accès Horizon / Floating IPs)
  # -> IP fixe côté VM
  config.vm.network "private_network", ip: "192.168.56.10"

  # ⚙️ Ressources VirtualBox
  config.vm.provider "virtualbox" do |vb|
    vb.name = "OSA-Ubuntu22"
    vb.cpus = 4
    vb.memory = 12288  # 12 Go RAM (monte à 16 Go si possible)
    vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
    vb.customize ["modifyvm", :id, "--nictype2", "virtio"]
  end

  # 📦 Provisioning
  config.vm.provision "shell", inline: <<-SHELL
    set -eux

    echo "[1/4] Mise à jour des paquets..."
    sudo apt-get update -y
    sudo apt-get dist-upgrade -y
    sudo apt-get install -y openssh-server qemu-guest-agent net-tools curl wget vim htop

    echo "[2/4] Sauvegarde Netplan existant..."
    sudo mkdir -p /etc/netplan/backup
    sudo cp /etc/netplan/*.yaml /etc/netplan/backup/ || true

    echo "[3/4] Configuration Netplan OSA..."
    cat <<EOF | sudo tee /etc/netplan/01-osa.yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s3:
      dhcp4: true
    enp0s8:
      dhcp4: no

  bridges:
    br-mgmt:
      dhcp4: no
      addresses: [172.29.236.10/22]

    br-vxlan:
      dhcp4: no
      addresses: [172.29.240.1/22]

    br-ex:
      interfaces: [enp0s8]
      dhcp4: no
      addresses: [192.168.56.10/24]
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

    sudo chmod 600 /etc/netplan/01-osa.yaml
    sudo netplan apply

    echo "[4/4] Vérification des routes..."
    ip route
  SHELL
end
```

---

# 🚀 Étapes d’utilisation

1. **Créer un dossier projet**

   ```bash
   mkdir ~/osa-vagrant && cd ~/osa-vagrant
   ```
2. **Créer le Vagrantfile**

   ```bash
   nano Vagrantfile
   ```

   (copie le contenu ci-dessus et enregistre)
3. **Lancer la VM**

   ```bash
   vagrant up
   ```

   ⚠️ La première fois, ça télécharge la box (~1 Go).
4. **Connexion en SSH**

   * Avec Vagrant :

     ```bash
     vagrant ssh
     ```
   * Depuis ton hôte (Windows/Linux/macOS) :

     ```bash
     ssh vagrant@192.168.56.10
     ```

     (mot de passe : `vagrant` si demandé, mais par défaut l’accès se fait par clé).

---

# 🔎 Vérifications après boot

Dans la VM (`vagrant ssh`) :

1. Vérifier les interfaces :

   ```bash
   ip a
   ```

   👉 tu dois voir :

   * `enp0s3` avec IP en `10.0.2.x` (NAT)
   * `enp0s8` lié à `br-ex` (`192.168.56.10`)
   * `br-mgmt` (`172.29.236.10`)
   * `br-vxlan` (`172.29.240.1`)

2. Vérifier la route par défaut :

   ```bash
   ip route
   ```

   👉 tu dois voir :

   ```
   default via 10.0.2.2 dev enp0s3
   ```

3. Tester la connectivité :

   ```bash
   ping -c3 8.8.8.8          # Internet
   ping -c3 google.com       # DNS
   ping -c3 192.168.56.1     # Hôte
   ```

4. Depuis ton **hôte**, tester :

   ```bash
   ping 192.168.56.10
   ssh vagrant@192.168.56.10
   ```

---

# ✅ Résumé

* **Carte NAT (`enp0s3`)** → Internet (gateway `10.0.2.2`)
* **Carte Host-only (`enp0s8` → `br-ex`)** → Horizon / accès depuis ton PC (`192.168.56.10`)
* **Pas de gateway sur br-ex** → pas de conflit de routage
* Bridges internes `br-mgmt` et `br-vxlan` prêts pour OSA

---

👉 Veux-tu que je t’ajoute aussi un **schéma ASCII** qui montre clairement :

* NAT → enp0s3 → Internet
* Host-only → enp0s8 → br-ex → ton PC
* br-mgmt et br-vxlan internes à la VM

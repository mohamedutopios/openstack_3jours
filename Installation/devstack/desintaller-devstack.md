Désinstaller **DevStack** n’est pas aussi simple qu’un `apt remove` parce que DevStack n’est pas un paquet, mais un ensemble de scripts qui installent et configurent OpenStack directement dans ton système.
La désinstallation dépend donc de ton objectif :

---

## 🔹 1. Si tu veux juste arrêter DevStack

Exécute depuis le dossier `devstack/` :

```bash
./unstack.sh
```

👉 Cela arrête tous les services OpenStack lancés par DevStack, mais ne supprime pas les fichiers ni les configurations.

---

## 🔹 2. Si tu veux nettoyer (supprimer services et fichiers créés)

Toujours dans le dossier `devstack/` :

```bash
./clean.sh
```

👉 Cela supprime les bases de données, les fichiers temporaires et une partie des configurations.
⚠️ Mais certains paquets et dépendances installés via `apt`/`pip` resteront sur ton système.

---

## 🔹 3. Si tu veux désinstaller complètement DevStack

Comme DevStack installe plein de dépendances (MySQL/MariaDB, RabbitMQ, services systemd, paquets Python, …), il faut nettoyer manuellement :

### Étapes :

1. **Supprimer les services et bases installés**

```bash
sudo systemctl stop apache2 rabbitmq-server mysql
sudo apt remove --purge -y mysql-server rabbitmq-server apache2 memcached etcd
```

2. **Supprimer les paquets Python** installés par pip :

```bash
sudo pip uninstall -y -r requirements.txt
```

(à lancer depuis le répertoire `devstack` si le fichier existe encore).

3. **Supprimer les fichiers et dossiers DevStack**

```bash
rm -rf ~/devstack
rm -rf /opt/stack
```

4. **Nettoyer les bases de données résiduelles**

```bash
sudo rm -rf /var/lib/mysql /var/log/mysql
sudo rm -rf /var/lib/rabbitmq
```

5. **Nettoyer les utilisateurs OpenStack créés**
   Certains scripts créent des utilisateurs système (`stack`, etc.)

```bash
sudo deluser stack --remove-home
```

6. **Vérifier les dépendances résiduelles**

```bash
sudo apt autoremove -y
sudo apt clean
```

---

## 🔹 4. Si tu veux repartir totalement propre

La méthode la plus simple reste de **supprimer ta VM** (ou refaire un snapshot avant installation).
👉 DevStack est prévu pour des environnements de test jetables, pas pour une désinstallation propre et réversible.

---

👉 Veux-tu que je te fasse un **script bash** qui automatise toutes ces étapes pour nettoyer DevStack proprement ?

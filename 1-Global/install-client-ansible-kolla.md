Très bon réflexe 👌
Si tu veux rester sur **Ubuntu 18.04 (Bionic, Python 3.6.9)**, tu ne peux pas utiliser les dernières versions de Kolla-Ansible (**Epoxy 2025.1**) car elles exigent **Python ≥ 3.8 + Ansible ≥ 2.13**.

👉 La solution est donc de déployer **une version plus ancienne d’OpenStack via Kolla-Ansible**, qui est **compatible Python 3.6 et Ansible 2.9/2.11**.

---

# 🟢 Compatibilité OpenStack / Ubuntu 18.04

* Ubuntu 18.04 est officiellement supporté jusqu’à **Victoria (2020.2)** et partiellement **Wallaby (2021.1)**.
* Au-delà → Ubuntu 20.04 ou 22.04 est requis.

| OpenStack release | Kolla-Ansible release | Ubuntu support                   |
| ----------------- | --------------------- | -------------------------------- |
| Train (2019.2)    | Kolla-Ansible 9.x     | Ubuntu 18.04 ✅                   |
| Ussuri (2020.1)   | Kolla-Ansible 10.x    | Ubuntu 18.04 ✅                   |
| Victoria (2020.2) | Kolla-Ansible 11.x    | Ubuntu 18.04 ✅                   |
| Wallaby (2021.1)  | Kolla-Ansible 12.x    | Ubuntu 18.04 (fin de support) ⚠️ |
| Xena (2021.2) →   | Kolla-Ansible 13+     | Ubuntu 20.04 requis ❌            |

---

# 🟢 Comment installer une version compatible de Kolla-Ansible

1. **Créer un venv Python 3.6**

```bash
python3 -m venv /opt/kolla-venv
source /opt/kolla-venv/bin/activate
```

2. **Installer Ansible 2.9.x** (dernière compatible Python 3.6)

```bash
pip install "ansible==2.9.*"
```

3. **Installer Kolla-Ansible version 11.x (Victoria)**

```bash
pip install "kolla-ansible==11.*"
```

4. **Copier les fichiers exemples**

```bash
mkdir -p /etc/kolla
cp -r /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

5. **Vérifier**

```bash
ansible --version
kolla-ansible --version
```

---

# 🟢 Avantages et limites

✅ Tu restes sur Ubuntu 18.04 sans upgrade.
✅ Tu peux déployer OpenStack **Victoria (2020.2)** qui est stable et bien supporté.
⚠️ Tu n’auras pas les toutes dernières features (Epoxy 2025.1).
⚠️ Certaines images Kolla Docker récentes risquent de ne pas builder → il faudra utiliser les images taggées `victoria`.

---

# 🚀 Résumé

* Sur Ubuntu 18.04 (Python 3.6) → **choisis Kolla-Ansible 11.x (Victoria)**.
* Utilise **Ansible 2.9.x** (le dernier supporté sur Python 3.6).
* Installe via :

  ```bash
  pip install "ansible==2.9.*"
  pip install "kolla-ansible==11.*"
  ```

---

👉 Veux-tu que je te prépare un **pas-à-pas complet** pour déployer OpenStack Victoria avec Kolla-Ansible sur Ubuntu 18.04 (AIO), y compris le `globals.yml` et le `all-in-one` adaptés ?

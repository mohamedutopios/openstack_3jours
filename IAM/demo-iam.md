# 🟥 **CONTEXTE DU SCÉNARIO*

Une entreprise fictive **TechCorp** utilise OpenStack pour héberger ses applications.

Elle possède 2 équipes :

| Équipe       | Activités                   | Besoins                        |
| ------------ | --------------------------- | ------------------------------ |
| **DevTeam**  | Développer des applications | Lancer beaucoup de petites VMs |
| **DataTeam** | Big Data & Analytics        | VMs puissantes, accès à Swift  |

Le département IT (admin OpenStack) doit :

1. Organiser l’infrastructure en **domaines** et **projets**
2. Créer les **utilisateurs**
3. Les regrouper en **groupes**
4. Leur attribuer les **rôles**
5. Appliquer des **quotas**
6. Tester les accès
7. Fournir une **clé API** (application credential)
8. Ajouter des **politiques avancées (RBAC)** pour Swift, Nova ou Neutron
9. Gérer un **cas d’escalation** (passage temporaire en admin)

---

# 🟦 **PHASE 1 — Création de l’organisation IAM (Domain + Projects)**

## 👉 Objectif pédagogique :

Comprendre la hiérarchie **Domaine → Projets → Rôles → Utilisateurs**.

### 1️⃣ Créer un domaine "TechCorp"

```
openstack domain create TechCorp
openstack domain list
```

### 2️⃣ Créer les projets (tenants)

```
openstack project create --domain TechCorp DevProject
openstack project create --domain TechCorp DataProject
openstack project list --domain TechCorp
```

📌 **Analyse pédagogique**

* Le **domaine** isole tous les projets d’une entreprise.
* Les ressources sont **compartimentées par projet** (réseaux, VMs, volumes).

---

# 🟦 **PHASE 2 — Création des utilisateurs**

## 3️⃣ DevTeam : Alice & Bob

```
openstack user create --domain TechCorp --password Alice123 alice
openstack user create --domain TechCorp --password Bob123   bob
```

## 4️⃣ DataTeam : Charlie & Diana

```
openstack user create --domain TechCorp --password Charlie123 charlie
openstack user create --domain TechCorp --password Diana123   diana
```

📌 **Analyse**

* Chaque utilisateur est créé dans le domaine TechCorp.
* Aucun utilisateur n’a encore de rôle → ils ne peuvent rien faire.

---

# 🟦 **PHASE 3 — Création des groupes**

### 5️⃣ Créer deux groupes liés aux équipes

```
openstack group create DevTeam --domain TechCorp

openstack group create DataTeam --domain TechCorp
```

### 6️⃣ Ajouter les membres dans les groupes

```
openstack group add user DevTeam alice
openstack group add user DevTeam bob

openstack group add user DataTeam charlie
openstack group add user DataTeam diana
```

📌 **Analyse**

* Un utilisateur peut appartenir à plusieurs groupes.
* Les rôles seront attachés au groupe = gestion simplifiée.

---

# 🟥 **PHASE 4 — Création / Attribution des rôles**

OpenStack vient avec :

* `reader`
* `member`
* `admin`

Tu peux créer un rôle personnalisé :

### 7️⃣ Créer un rôle “analyst”

```
openstack role create analyst
```

### 8️⃣ Assigner les rôles aux groupes

#### DevTeam → rôle **member**

```
openstack role add --group DevTeam --project DevProject member
```

#### DataTeam → rôle **analyst**

```
openstack role add --group DataTeam --project DataProject analyst
```

📌 **Analyse**

* DevTeam peut créer/modifier des VMs.
* DataTeam aura des droits spécialisés (que tu définiras plus tard).

---

# 🟧 **PHASE 5 — Mise en place des quotas (gestion des ressources)**

### 9️⃣ Limiter DevProject à de petites ressources

```
openstack quota set --instances 10 --cores 20 --ram 60000 DevProject
```

### 🔟 Limiter DataProject mais autoriser volumes importants

```
openstack quota set --instances 6 --cores 40 --ram 120000 --volumes 20 DataProject
```

📌 **Objectif pédagogique**

* Faire comprendre que OpenStack sépare l'accès (IAM) et les ressources (quotas).

---

# 🟦 **PHASE 6 — Test des accès**

## Test : Alice doit pouvoir se connecter au projet DevProject

```
openstack --os-username alice --os-password Alice123 \
  --os-project-name DevProject \
  server list
```

Résultat attendu :
→ command works but no servers yet.

Si Alice teste DataProject → accès refusé :

```
openstack --os-username alice --os-password Alice123 \
  --os-project-name DataProject \
  server list
```

Résultat attendu :
❌ `Forbidden (HTTP 403)`

---

# 🟦 **PHASE 7 — Création d’application credentials (clé API)**

## Pour permettre à un utilisateur d’automatiser Terraform / Ansible

### 11️⃣ Alice demande une clé API pour Terraform

```
openstack application credential create \
  --role member \
  --description "Terraform Key for Alice" \
  terraform-key
```

Résultat :

```
+-------------+------------------------------------+
| id          | XXXXX                               |
| secret      | YYYYY                               |
| project_id  | ...                                  |
| roles       | member                               |
+-------------+------------------------------------+
```

📌 Cette clé remplace totalement le mot de passe.

---

# 🟧 **PHASE 8 — RBAC avancé (policies)**

### 12️⃣ Exemple : autoriser data engineers à lire Swift mais pas à écrire

Modifier la policy Swift :

```
docker exec -it swift_proxy cat /etc/swift/policy.json
```

Ajouter :

```json
{
  "object:get": "role:analyst",
  "object:put": "rule:deny"
}
```

Redémarrer Swift Proxy.

📌 **Analyse**

* Tu montres aux apprenants comment contrôler les API d’un service.
* IAM + policies = vrai contrôle d’entreprise.

---

# 🟥 **PHASE 9 — Cas d’usage : montée en privilèges (delegation)**

Charlie (DataTeam) devient temporairement admin de DataProject.

### 13️⃣ Ajouter rôle admin

```
openstack role add --user charlie --project DataProject admin
```

Charlie peut maintenant :

```
openstack --os-username charlie --os-password Charlie123 \
  volume create test-volume --size 10
```

### 14️⃣ Retrait après intervention

```
openstack role remove --user charlie --project DataProject admin
```

---

# 🟩 **PHASE 10 — Suppression et audit**

### 15️⃣ Voir toutes les assignations IAM

```
openstack role assignment list
```

### 16️⃣ Supprimer un utilisateur parti de l’entreprise

```
openstack user delete bob
```

### 17️⃣ Supprimer un projet et ses droits

```
openstack project delete DevProject
```

---

# 🟦 RÉCAPITULATIF GLOBAL (TABLEAU)

| Phase | Action                  | Objectif pédagogique          |
| ----- | ----------------------- | ----------------------------- |
| 1     | Créer domaine           | Organisation multi-entreprise |
| 2     | Créer utilisateurs      | Base IAM                      |
| 3     | Créer groupes           | Gestion scalable              |
| 4     | Roles & RBAC            | Contrôle d’accès              |
| 5     | Quotas                  | Gouvernance des ressources    |
| 6     | Tests utilisateurs      | Validation IAM                |
| 7     | Application Credentials | Automatisation                |
| 8     | Policies avancées       | Sécurité fine                 |
| 9     | Escalation admin        | Process IT réel               |
| 10    | Audit & cleanup         | Cycle de vie complet          |

---


openstack \
  --os-auth-url http://controller:5000/v3 \
  --os-username alice \
  --os-password Alice123 \
  --os-user-domain-name TechCorp \
  --os-project-name DataProject \
  --os-project-domain-name TechCorp \
  server list
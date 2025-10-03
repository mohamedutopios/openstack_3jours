Yes 👌 là ton Terraform est presque bon :

Le **plan sort une erreur sur le `data "openstack_networking_network_v2" "ext"`** :

```
Error: Your query returned no results. Please change your search criteria and try again.
```

👉 Ça veut dire que Terraform n’a pas trouvé de **réseau externe** qui correspond à `var.external_network_name`.

Et dans ton `plan` tu avais saisi :

```
Enter a value: 9.12.93.4
```

⚠️ Mais **ce n’est pas le nom du réseau externe**, c’est une adresse IP.

---

## ✅ Ce qu’il faut mettre

L’argument `external_network_name` doit être **le nom du réseau externe dans OpenStack** (par ex. souvent `public`, `ext-net`, `external`, `provider`, etc.).

Pour savoir lequel utiliser :

### Commande OpenStack CLI

```bash
openstack network list --external
```

Exemple de sortie :

```
+--------------------------------------+----------+---------+
| ID                                   | Name     | Router  |
+--------------------------------------+----------+---------+
| 2eaa1d6a-ccaf-46c4-9316-111111111111 | public   | External|
+--------------------------------------+----------+---------+
```

Ici → le nom est `public`.

---

## 🔧 Correction dans ton `terraform plan`

Quand il te demande :

```
var.external_network_name
  Nom du réseau externe pour les Floating IPs

  Enter a value:
```

👉 Tu dois entrer **le nom** (ex : `public`), pas une IP.

---

## ⚡ Résumé

1. Vérifie ton réseau externe :

   ```bash
   openstack network list --external
   ```
2. Récupère le champ **Name** (ex. `public`).
3. Relance :

   ```bash
   terraform plan -var="external_network_name=public1"
   ```

---

👉 Veux-tu que je t’ajoute un `variables.tf` avec un `default = "public"` pour `external_network_name`, comme ça tu n’auras plus besoin de le saisir à chaque fois ?

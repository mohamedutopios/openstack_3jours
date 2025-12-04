# 🚀 Démo 2 : Automatisation avec l’API REST OpenStack

👉 **Message clé** : *L’API REST est la base → Horizon, CLI, SDK, Ansible, Terraform… ne sont que des clients.*

---

## 1. Authentification (Keystone API)

Avant tout, Horizon ou la CLI font un **login** auprès de Keystone pour obtenir un **token**.

```bash

curl -s -i \
  -H "Content-Type: application/json" \
  -d '{
        "auth": {
          "identity": {
            "methods": ["password"],
            "password": {
              "user": {
                "name": "admin",
                "domain": { "id": "default" },
                "password": "xMvLAtOwFyGnwVoT3V96mRZsxaMyxNE8HVQ4G8CJ"
              }
            }
          },
          "scope": {
            "project": {
              "name": "admin",
              "domain": { "id": "default" }
            }
          }
        }
      }' \
  http://9.11.93.4:5000/v3/auth/tokens
```

👉 La réponse contient un header :

```
X-Subject-Token: eyJhbGciOi...
```

➡️ Ce token est ensuite réutilisé dans toutes les requêtes REST (`-H "X-Auth-Token: ..."`)

---

## 2. Lister les instances (Nova API)

Equivalent à *"Instances → Onglet Horizon"* :

```bash
curl -s \
  -H "X-Auth-Token: $OS_TOKEN" \
  http://9.11.93.4:8774/v2.1/servers | jq .
```

Avec **httpie** (plus lisible) :

```bash
http GET http://9.11.93.4:8774/v2.1/servers \
  X-Auth-Token:$OS_TOKEN
```

👉 Tu obtiens exactement ce que Horizon affiche : nom, ID, statut, etc.

---

## 3. Créer une VM (Nova API)

Equivalent à *"Lancer une instance → Horizon"* :

```bash
curl -s -X POST \
  -H "X-Auth-Token: $OS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "server": {
          "name": "demo-vm",
          "imageRef": "a3343bc5-2944-4dca-b858-3c1eee0d2e5d",
          "flavorRef": "98b586a0-50ed-4a15-9815-e0569a3950d4",
          "networks": [{"uuid": "88d224b8-6d5d-41d1-b47e-c0920ff74f3b"}]
        }
      }' \
  http://9.11.93.4:8774/v2.1/servers | jq .
```

➡️ Le retour JSON contient l’`id` de la nouvelle instance.

---

## 4. Attacher un volume (Cinder API)

Equivalent à *"Volumes → Attacher à une instance"* :

```bash
curl -s -X POST \
  -H "X-Auth-Token: $OS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "volumeAttachment": {
          "volumeId": "ID_VOLUME",
          "device": "/dev/vdb"
        }
      }' \
  http://9.11.93.4:8774/v2.1/servers/<ID_VM>/os-volume_attachments | jq .
```

---

## 5. Créer un réseau (Neutron API)

Equivalent à *"Réseaux → Créer un réseau"* :

```bash
curl -s -X POST \
  -H "X-Auth-Token: $OS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "network": {
          "name": "demo-net",
          "admin_state_up": true
        }
      }' \
  http://9.11.93.4:9696/v2.0/networks | jq .
```

---

## 6. Lister les images (Glance API)

Equivalent à *"Images → Horizon"* :

```bash
curl -s \
  -H "X-Auth-Token: $OS_TOKEN" \
  http://9.11.93.4:9292/v2/images | jq .
```



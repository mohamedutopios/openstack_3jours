# 🟢 Étape 1 : Créer une VM simple

`main.tf`

```hcl
provider "openstack" {
  auth_url    = "http://controller:5000/v3"
  user_name   = "demo"
  password    = "secret"
  tenant_name = "demo"
  region      = "RegionOne"
}

resource "openstack_compute_instance_v2" "vm1" {
  name        = "vm1"
  image_name  = "Ubuntu-22.04"
  flavor_name = "m1.small"
  key_pair    = "mykey"

  network {
    name = "private-net"
  }
}
```

👉 La base : une VM reliée à un réseau existant.

---

# 🟢 Étape 2 : Ajouter un réseau et l’utiliser

```hcl
resource "openstack_networking_network_v2" "net" {
  name = "demo-net"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name       = "demo-subnet"
  network_id = openstack_networking_network_v2.net.id
  cidr       = "10.10.0.0/24"
  ip_version = 4
}

resource "openstack_compute_instance_v2" "vm2" {
  name        = "vm2"
  image_name  = "Ubuntu-22.04"
  flavor_name = "m1.small"
  key_pair    = "mykey"

  network {
    uuid = openstack_networking_network_v2.net.id
  }
}
```

👉 Ici on crée **réseau + subnet**, et la VM utilise ce réseau.

---

# 🟢 Étape 3 : Paramétrer avec des variables

`variables.tf`

```hcl
variable "image_name" {
  default = "Ubuntu-22.04"
}

variable "flavor_name" {
  default = "m1.small"
}

variable "vm_name" {
  default = "vm3"
}
```

`main.tf`

```hcl
resource "openstack_compute_instance_v2" "vm3" {
  name        = var.vm_name
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = "mykey"

  network {
    uuid = openstack_networking_network_v2.net.id
  }
}
```

👉 Maintenant on peut changer les noms/flavor via `terraform apply -var="vm_name=testvm"`.

---

# 🟢 Étape 4 : Ajouter des outputs

`outputs.tf`

```hcl
output "vm3_ip" {
  description = "Adresse IP de la VM"
  value       = openstack_compute_instance_v2.vm3.access_ip_v4
}
```

👉 Après `apply`, Terraform affiche directement l’IP publique/privée de la VM.

---

# 🟢 Étape 5 : Utiliser locals (préfixes, concaténations)

```hcl
locals {
  prefix = "demo"
}

resource "openstack_compute_instance_v2" "vm4" {
  name        = "${local.prefix}-vm4"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = "mykey"

  network {
    uuid = openstack_networking_network_v2.net.id
  }
}
```

👉 `vm4` sera créé avec un nom préfixé automatiquement (`demo-vm4`).

---

# 🟢 Étape 6 : Lien avec une ressource existante (data source)

Exemple : utiliser un réseau externe **déjà existant** pour attribuer une Floating IP.

```hcl
# Récupérer un réseau externe existant
data "openstack_networking_network_v2" "ext" {
  name = "public"
}

# Créer une Floating IP
resource "openstack_networking_floatingip_v2" "fip" {
  pool = data.openstack_networking_network_v2.ext.name
}

# Nouvelle VM
resource "openstack_compute_instance_v2" "vm5" {
  name        = "${local.prefix}-vm5"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = "mykey"

  network {
    uuid = openstack_networking_network_v2.net.id
  }
}

# Associer la Floating IP à la VM
resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.fip.address
  port_id     = openstack_compute_instance_v2.vm5.network[0].port
}

output "vm5_fip" {
  value = openstack_networking_floatingip_v2.fip.address
}
```


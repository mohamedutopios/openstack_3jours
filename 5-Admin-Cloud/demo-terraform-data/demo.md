Parfait ✅
On simplifie alors ton projet **Terraform + OpenStack** :
👉 Chaque VM installe directement **Docker + Compose**, et on déploie **un service unique par VM** :

* VM1 = **Kafka/Redpanda**
* VM2 = **Spark** (master + worker)
* VM3 = **PostgreSQL**

---

# 📂 Arborescence

```
openstack-pipeline-simple/
├─ providers.tf
├─ variables.tf
├─ main.tf
├─ outputs.tf
└─ cloud-init/
   ├─ kafka.yaml
   ├─ spark.yaml
   └─ postgres.yaml
```

---

# 🔧 providers.tf

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.54.0"
    }
  }
}

provider "openstack" {}
```

---

# 📌 variables.tf

```hcl
variable "external_network_name" {
  description = "Nom du réseau externe pour les Floating IPs"
  type        = string
}

variable "image_name"  { default = "Ubuntu-22.04" }
variable "flavor_name" { default = "m1.small" }

variable "ssh_keypair_name" {
  description = "Keypair existant"
  type        = string
  default     = ""
}

variable "public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "cidr" { default = "10.70.0.0/24" }
```

---

# ⚙️ main.tf (simplifié)

```hcl
locals {
  prefix = "dps" # data-pipeline-simple
}

# Keypair
resource "openstack_compute_keypair_v2" "kp" {
  count      = var.ssh_keypair_name == "" ? 1 : 0
  name       = "${local.prefix}-key"
  public_key = file(var.public_key_path)
}

locals {
  key_name = var.ssh_keypair_name != "" ? var.ssh_keypair_name : one(openstack_compute_keypair_v2.kp[*].name)
}

# Réseau privé
resource "openstack_networking_network_v2" "net" {
  name           = "${local.prefix}-net"
  admin_state_up = true
}
resource "openstack_networking_subnet_v2" "subnet" {
  name       = "${local.prefix}-subnet"
  network_id = openstack_networking_network_v2.net.id
  cidr       = var.cidr
  ip_version = 4
  dns_nameservers = ["1.1.1.1", "8.8.8.8"]
}

# Routeur vers externe
data "openstack_networking_network_v2" "ext" {
  name = var.external_network_name
}
resource "openstack_networking_router_v2" "rtr" {
  name                = "${local.prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext.id
}
resource "openstack_networking_router_interface_v2" "rtr_if" {
  router_id = openstack_networking_router_v2.rtr.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}

# Sécurité
resource "openstack_networking_secgroup_v2" "sg" {
  name = "${local.prefix}-sg"
}
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  security_group_id = openstack_networking_secgroup_v2.sg.id
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix = "0.0.0.0/0"
}

# Volumes
resource "openstack_blockstorage_volume_v3" "vol_kafka" {
  name = "${local.prefix}-vol-kafka"
  size = 20
}
resource "openstack_blockstorage_volume_v3" "vol_postgres" {
  name = "${local.prefix}-vol-postgres"
  size = 20
}

# VM Kafka
resource "openstack_compute_instance_v2" "kafka" {
  name            = "${local.prefix}-kafka"
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = local.key_name
  security_groups = [openstack_networking_secgroup_v2.sg.name]

  network { uuid = openstack_networking_network_v2.net.id }

  user_data = file("${path.module}/cloud-init/kafka.yaml")
}

resource "openstack_compute_volume_attach_v2" "attach_kafka" {
  instance_id = openstack_compute_instance_v2.kafka.id
  volume_id   = openstack_blockstorage_volume_v3.vol_kafka.id
  device      = "/dev/vdb"
}

# VM Spark
resource "openstack_compute_instance_v2" "spark" {
  name            = "${local.prefix}-spark"
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = local.key_name
  security_groups = [openstack_networking_secgroup_v2.sg.name]

  network { uuid = openstack_networking_network_v2.net.id }

  user_data = file("${path.module}/cloud-init/spark.yaml")
}

# VM Postgres
resource "openstack_compute_instance_v2" "postgres" {
  name            = "${local.prefix}-postgres"
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = local.key_name
  security_groups = [openstack_networking_secgroup_v2.sg.name]

  network { uuid = openstack_networking_network_v2.net.id }

  user_data = file("${path.module}/cloud-init/postgres.yaml")
}

resource "openstack_compute_volume_attach_v2" "attach_postgres" {
  instance_id = openstack_compute_instance_v2.postgres.id
  volume_id   = openstack_blockstorage_volume_v3.vol_postgres.id
  device      = "/dev/vdb"
}

# Floating IPs
resource "openstack_networking_floatingip_v2" "fip_kafka" { pool = data.openstack_networking_network_v2.ext.name }
resource "openstack_networking_floatingip_v2" "fip_spark" { pool = data.openstack_networking_network_v2.ext.name }
resource "openstack_networking_floatingip_v2" "fip_postgres" { pool = data.openstack_networking_network_v2.ext.name }

resource "openstack_networking_floatingip_associate_v2" "fip_assoc_kafka" {
  floating_ip = openstack_networking_floatingip_v2.fip_kafka.address
  instance_id = openstack_compute_instance_v2.kafka.id
}
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_spark" {
  floating_ip = openstack_networking_floatingip_v2.fip_spark.address
  instance_id = openstack_compute_instance_v2.spark.id
}
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_postgres" {
  floating_ip = openstack_networking_floatingip_v2.fip_postgres.address
  instance_id = openstack_compute_instance_v2.postgres.id
}
```

---

# 📤 outputs.tf

```hcl
output "fips" {
  value = {
    kafka    = openstack_networking_floatingip_v2.fip_kafka.address
    spark    = openstack_networking_floatingip_v2.fip_spark.address
    postgres = openstack_networking_floatingip_v2.fip_postgres.address
  }
}
```

---

# ☁️ cloud-init

### kafka.yaml

```yaml
#cloud-config
package_update: true
packages: [docker.io, docker-compose]
runcmd:
  - mkdir -p /opt/kafka
  - cat > /opt/kafka/docker-compose.yml <<'EOF'
version: "3.8"
services:
  redpanda:
    image: redpandadata/redpanda:latest
    command: redpanda start --overprovisioned --smp 1 --reserve-memory 0M --node-id 0 --check=false
    ports:
      - "9092:9092"
      - "9644:9644"
    volumes:
      - /var/lib/redpanda:/var/lib/redpanda/data
    restart: unless-stopped
  console:
    image: redpandadata/console:latest
    environment:
      - KAFKA_BROKERS=redpanda:9092
    ports: ["8080:8080"]
    depends_on: [redpanda]
EOF
  - systemctl enable docker
  - systemctl start docker
  - docker compose -f /opt/kafka/docker-compose.yml up -d
```

### spark.yaml

```yaml
#cloud-config
package_update: true
packages: [docker.io, docker-compose]
runcmd:
  - mkdir -p /opt/spark
  - cat > /opt/spark/docker-compose.yml <<'EOF'
version: "3.8"
services:
  spark-master:
    image: bitnami/spark:3.5
    environment:
      - SPARK_MODE=master
    ports:
      - "7077:7077"
      - "8080:8080"
  spark-worker:
    image: bitnami/spark:3.5
    environment:
      - SPARK_MODE=worker
      - SPARK_MASTER_URL=spark://spark-master:7077
    depends_on:
      - spark-master
    ports:
      - "8081:8081"
EOF
  - systemctl enable docker
  - systemctl start docker
  - docker compose -f /opt/spark/docker-compose.yml up -d
```

### postgres.yaml

```yaml
#cloud-config
package_update: true
packages: [docker.io, docker-compose]
runcmd:
  - mkdir -p /opt/postgres
  - cat > /opt/postgres/docker-compose.yml <<'EOF'
version: "3.8"
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: spark
      POSTGRES_PASSWORD: sparkpass
      POSTGRES_DB: pipeline
    ports:
      - "5432:5432"
    volumes:
      - /var/lib/postgresql/data:/var/lib/postgresql/data
EOF
  - systemctl enable docker
  - systemctl start docker
  - docker compose -f /opt/postgres/docker-compose.yml up -d
```

---

# 🚀 Résultat

* **Kafka/Redpanda** : console Web sur `http://<FIP_kafka>:8080`, broker `:9092`
* **Spark** : UI Master sur `http://<FIP_spark>:8080`, Worker sur `:8081`
* **PostgreSQL** : `<FIP_postgres>:5432` (`user=spark`, `pass=sparkpass`, `db=pipeline`)

---

👉 Ce projet fait exactement ce que tu veux :

* 3 VMs OpenStack
* Chaque VM déploie son service (Kafka, Spark, Postgres) automatiquement
* Pas de Swift ni MinIO, stockage basique sur Cinder volumes

---

Veux-tu que je t’ajoute aussi un **exemple de job PySpark** (Kafka → Spark → Postgres) prêt à lancer après déploiement ?

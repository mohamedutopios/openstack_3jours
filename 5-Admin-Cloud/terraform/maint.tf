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
  name            = "${local.prefix}-subnet"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.cidr
  ip_version      = 4
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
resource "openstack_networking_secgroup_v2" "pipeline_sg" {
  name        = "${local.prefix}-sg"
  description = "SG for Kafka <-> Spark <-> Postgres"
}

# Règles SSH / Kafka / Spark / Postgres
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  security_group_id = openstack_networking_secgroup_v2.pipeline_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "kafka" {
  security_group_id = openstack_networking_secgroup_v2.pipeline_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9092
  port_range_max    = 9092
  remote_group_id   = openstack_networking_secgroup_v2.pipeline_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "postgres" {
  security_group_id = openstack_networking_secgroup_v2.pipeline_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.pipeline_sg.id
}


# Autoriser ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  security_group_id = openstack_networking_secgroup_v2.pipeline_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  remote_group_id   = openstack_networking_secgroup_v2.pipeline_sg.id
}


# Ports réseau pour chaque VM
resource "openstack_networking_port_v2" "port_kafka" {
  name               = "${local.prefix}-p-kafka"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.pipeline_sg.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
}

resource "openstack_networking_port_v2" "port_spark" {
  name               = "${local.prefix}-p-spark"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.pipeline_sg.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
}

resource "openstack_networking_port_v2" "port_postgres" {
  name               = "${local.prefix}-p-postgres"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.pipeline_sg.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
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
  name       = "${local.prefix}-kafka"
  image_name = var.image_name
  flavor_name = var.flavor_name
  key_pair   = local.key_name

  network {
    port = openstack_networking_port_v2.port_kafka.id
  }

  user_data = file("${path.module}/cloud-init/kafka.yaml")
}

resource "openstack_compute_volume_attach_v2" "attach_kafka" {
  instance_id = openstack_compute_instance_v2.kafka.id
  volume_id   = openstack_blockstorage_volume_v3.vol_kafka.id
  device      = "/dev/vdb"
}

# VM Spark
resource "openstack_compute_instance_v2" "spark" {
  name        = "${local.prefix}-spark"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = local.key_name

  network {
    port = openstack_networking_port_v2.port_spark.id
  }

  user_data = file("${path.module}/cloud-init/spark.yaml")
}

# VM Postgres
resource "openstack_compute_instance_v2" "postgres" {
  name        = "${local.prefix}-postgres"
  image_name  = var.image_name
  flavor_name = var.flavor_name
  key_pair    = local.key_name

  network {
    port = openstack_networking_port_v2.port_postgres.id
  }

  user_data = file("${path.module}/cloud-init/postgres.yaml")
}

resource "openstack_compute_volume_attach_v2" "attach_postgres" {
  instance_id = openstack_compute_instance_v2.postgres.id
  volume_id   = openstack_blockstorage_volume_v3.vol_postgres.id
  device      = "/dev/vdb"
}

# Floating IPs
resource "openstack_networking_floatingip_v2" "fip_kafka" {
  pool = data.openstack_networking_network_v2.ext.name
}
resource "openstack_networking_floatingip_v2" "fip_spark" {
  pool = data.openstack_networking_network_v2.ext.name
}
resource "openstack_networking_floatingip_v2" "fip_postgres" {
  pool = data.openstack_networking_network_v2.ext.name
}

# Associations avec les ports (pas instance_id !)
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_kafka" {
  floating_ip = openstack_networking_floatingip_v2.fip_kafka.address
  port_id     = openstack_networking_port_v2.port_kafka.id
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc_spark" {
  floating_ip = openstack_networking_floatingip_v2.fip_spark.address
  port_id     = openstack_networking_port_v2.port_spark.id
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc_postgres" {
  floating_ip = openstack_networking_floatingip_v2.fip_postgres.address
  port_id     = openstack_networking_port_v2.port_postgres.id
}

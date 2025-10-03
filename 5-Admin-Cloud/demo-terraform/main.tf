provider "openstack" {
  auth_url    = "http://9.11.93.4:5000/v3"
  user_name   = "admin"
  password    = "xMvLAtOwFyGnwVoT3V96mRZsxaMyxNE8HVQ4G8CJ"
  tenant_name = "admin"
  domain_name = "Default"
  region      = "RegionOne"
}

# Crée une clé SSH dans OpenStack
resource "openstack_compute_keypair_v2" "mykey" {
  name       = "terraform-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# Crée une VM
resource "openstack_compute_instance_v2" "vm1" {
  name            = "test-vm"
  image_name      = "cirros"
  flavor_name     = "m1.demo"
  key_pair        = openstack_compute_keypair_v2.mykey.name
  security_groups = ["default"]

  network {
    uuid = "88d224b8-6d5d-41d1-b47e-c0920ff74f3b"
  }
}

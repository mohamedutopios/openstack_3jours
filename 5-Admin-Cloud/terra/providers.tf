terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.1"   
    }
  }
  required_version = ">= 1.5.0"
}

provider "openstack" {
  auth_url    = "http://9.11.93.4:5000/v3"
  user_name   = "admin"
  password    = "xMvLAtOwFyGnwVoT3V96mRZsxaMyxNE8HVQ4G8CJ"
  tenant_name = "admin"
  domain_name = "Default"
  region      = "RegionOne"
}

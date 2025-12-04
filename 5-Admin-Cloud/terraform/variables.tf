variable "external_network_name" {
  description = "Nom du réseau externe pour les Floating IPs"
  type        = string
}

variable "image_name"  { default = "cirros" }
variable "flavor_name" { default = "m1.tiny" }

variable "ssh_keypair_name" {
  description = "Keypair existant"
  type        = string
  default     = ""
}

variable "public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

variable "cidr" { default = "10.70.0.0/24" }
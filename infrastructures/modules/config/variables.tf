variable "project_id" {
  type    = string
  default = "kubernetes-with-k0s"
}

variable "default_region" {
  type    = string
  default = "us-central1"
}

variable "default_zone" {
  type    = string
  default = "us-central1-a"
}

variable "subnet_ip_cidr_range" {
  default = {
    node       = "10.240.0.0/24",
		# we are dividing the node subnet into two parts
		# one for controller and one for worker
    controller = "10.240.0.0/25",
    worker     = "10.240.0.128/25",
    pod        = "10.200.0.0/16"
  }
}

module "resource" {
  source = "./modules/resource"
}

module "config" {
  source = "./modules/config"
}

module "network" {
  source = "./modules/network"
}

module "controller" {
  source = "./modules/compute"
  instance = {
    count       = 3
    name_prefix = "controller"
    tags        = ["kubernetes-with-k0s", "controller"]
  }
  network = {
    name              = module.network.network.name
    subnet_name       = module.network.subnet.name
    subnet_cidr_range = module.config.subnet_ip_cidr_range.controller
  }
}

module "worker" {
  source = "./modules/compute"
	is_worker = true
  instance = {
    count       = 3
    name_prefix = "worker"
    tags        = ["kubernetes-with-k0s", "worker"]
  }
  network = {
    name              = module.network.network.name
    subnet_name       = module.network.subnet.name
    subnet_cidr_range = module.config.subnet_ip_cidr_range.worker
  }
}

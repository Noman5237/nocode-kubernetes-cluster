# import modules

module "config" {
  source = "../config"
}

# create three compute instances for hosting the kubernetes control plane
resource "google_compute_instance" "instance" {
  count        = var.instance.count
  name         = "${var.instance.name_prefix}-${count.index}"
  machine_type = var.instance.machine_type
  zone         = module.config.default_zone
  tags         = var.instance.tags

  boot_disk {
    auto_delete = true
    device_name = "${var.instance.name_prefix}-device-${count.index}"
    initialize_params {
      image = var.instance.boot_disk.image
      size  = var.instance.boot_disk.size
      type  = var.instance.boot_disk.type
    }
  }

  network_interface {
    subnetwork = var.network.subnet_name
    # we are reserving the first 10 IP addresses for unknown special purposes 
    network_ip = cidrhost(var.network.subnet_cidr_range, count.index + 10)
		access_config {
			network_tier = "STANDARD"
		}
  }
  can_ip_forward = true

  scheduling {
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  service_account {
    scopes = var.instance.scopes
  }

  // if is_worker is true, then add pod_cidr metadata
	// although its not a perfect solution, but it works for now
	// TODO: modularize the metadata
  metadata = var.is_worker ? {
    "pod-cidr" = cidrsubnet(module.config.subnet_ip_cidr_range.pod, 8, count.index)
  } : {}

  enable_display = false
}

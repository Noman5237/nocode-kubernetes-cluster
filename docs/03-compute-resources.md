# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster across a single [compute zone](https://cloud.google.com/compute/docs/regions-zones/regions-zones).

## Terraform Modules
We are declaring all the configurable variables in the config module. This module is used by all the other modules to get the values of the variables.

### Resource Module
We are creating a separate module for resources. This module will be used to enable the APIs required for the project.
	The problem of enabling APIs is that we need to enable the APIs before creating any other resources. So we are creating a separate module for enabling APIs. And this module will be planned and applied first.

> file: modules/resource/main.tf
```hcl
# enable the compute engine API
resource "google_project_service" "compute_engine_api" {
	service = "compute.googleapis.com"
}

# enable Cloud Resource Manager API
resource "google_project_service" "cloud_resource_manager_api" {
	service = "cloudresourcemanager.googleapis.com"
	# prevent deletion
	lifecycle {
		prevent_destroy = true
	}
}
```

### Config Module
> file: modules/config/variables.tf
```hcl
variable "project_id" {
  type    = string
  default = "kubernetes-the-hard-way-389513"
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
```

> file: modules/config/outputs.tf
```hcl
output "project_id" {
  value = var.project_id
}

output "default_region" {
  value = var.default_region
}

output "default_zone" {
  value = var.default_zone
}

output "subnet_ip_cidr_range" {
  value = var.subnet_ip_cidr_range
}
```

### Network Module
We first import the config module and use the variables from it. Then we create the infrastructure for the network.
> file: modules/network/main.tf
```hcl
# import modules

module "config" {
  source = "../config"
}
```

And then add the configurations given below to the network module.

### Top Level Module
> file: main.tf
```hcl
module "network" {
	source = "./modules/network"
}

module "config" {
	source = "./modules/config"
}

module "resource" {
	source = "./modules/resource"
}
```

> file: versions.tf
```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.68.0"
    }
  }
}
```

> file: providers.tf
```hcl
provider "google" {
	region = module.config.default_region
	zone = module.config.default_zone
	credentials = file("credentials/gcp-credentials.json")

	project = module.config.project_id
}
```

## Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model) assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

### Virtual Private Cloud Network

In this section a dedicated [Virtual Private Cloud](https://cloud.google.com/compute/docs/networks-and-firewalls#networks) (VPC) network will be setup to host the Kubernetes cluster.

Create the `kubernetes-the-hard-way` custom VPC network:

```hcl
resource "google_compute_network" "kubernetes-the-hard-way" {
	name = "kubernetes-the-hard-way"
	auto_create_subnetworks = false
}
```

A [subnet](https://cloud.google.com/compute/docs/vpc/#vpc_networks_and_subnets) must be provisioned with an IP address range large enough to assign a private IP address to each node in the Kubernetes cluster.

Create the `kubernetes` subnet in the `kubernetes-the-hard-way` VPC network:

```hcl
resource "google_compute_subnetwork" "kubernetes" {
	name = "kubernetes"
	ip_cidr_range = "10.240.0.0/24"
	network = google_compute_network.kubernetes-the-hard-way.name
}
```

> The `10.240.0.0/24` IP address range can host up to 254 compute instances.

### Firewall Rules

Create a firewall rule that allows internal communication across all protocols:

```hcl
resource "google_compute_firewall" "kubernetes-allow-internal" {
  name    = "kubernetes-allow-internal"
  project = module.config.project_id
  network = google_compute_network.kubernetes-the-hard-way.name
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  source_ranges = [
    module.config.subnet_ip_cidr_range.node,
    module.config.subnet_ip_cidr_range.pod
  ]
}
```

Create a firewall rule that allows external SSH, ICMP, and HTTPS:

```hcl
resource "google_compute_firewall" "kubernetes-allow-external" {
	name = "kubernetes-allow-external"
	network = google_compute_network.kubernetes-the-hard-way.name
	allow {
		protocol = "icmp"
	}
	allow {
		protocol = "tcp"
		ports = ["22", "6443"]
	}
	source_ranges = [
		# allow from any range for external access
		"0.0.0.0/0"
	]
}
```

> An [external load balancer](https://cloud.google.com/compute/docs/load-balancing/network/) will be used to expose the Kubernetes API Servers to remote clients.

### Kubernetes Public IP Address

Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:

```hcl
resource "google_compute_address" "kubernetes-the-hard-way" {
	name = "kubernetes-the-hard-way"
	region = module.config.default_region
}
```

Verify the `kubernetes-the-hard-way` static IP address was created in your default compute region using output produced after the Terraform apply

> file: modules/network/outputs.tf
```hcl
output "network" {
	value = google_compute_network.kubernetes-the-hard-way
}

output "subnet" {
	value = google_compute_subnetwork.kubernetes
}
```

### Executing Terraform Configuration
- Enabling the APIs
```bash
$ terraform apply --target=module.resource

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.resource.google_project_service.cloud_resource_manager_api will be created
  + resource "google_project_service" "cloud_resource_manager_api" {
      + disable_on_destroy = true
      + id                 = (known after apply)
      + project            = (known after apply)
      + service            = "cloudresourcemanager.googleapis.com"
    }

  # module.resource.google_project_service.compute_engine_api will be created
  + resource "google_project_service" "compute_engine_api" {
      + disable_on_destroy = true
      + id                 = (known after apply)
      + project            = (known after apply)
      + service            = "compute.googleapis.com"
    }

Plan: 2 to add, 0 to change, 0 to destroy.
╷
│ Warning: Resource targeting is in effect
│ 
│ You are creating a plan with the -target option, which means that the result of this plan may not represent all of the changes requested by the current configuration.
│ 
│ The -target option is not for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically suggests to use it as
│ part of an error message.
╵
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.resource.google_project_service.compute_engine_api: Creating...
module.resource.google_project_service.cloud_resource_manager_api: Creating...
module.resource.google_project_service.cloud_resource_manager_api: Creation complete after 5s [id=kubernetes-the-hard-way-389513/cloudresourcemanager.googleapis.com]
module.resource.google_project_service.compute_engine_api: Still creating... [10s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [20s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [30s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [40s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [50s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [1m0s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [1m10s elapsed]
module.resource.google_project_service.compute_engine_api: Still creating... [1m20s elapsed]
module.resource.google_project_service.compute_engine_api: Creation complete after 1m29s [id=kubernetes-the-hard-way-389513/compute.googleapis.com]
```
- Creating the network
```bash
$ terraform apply --target=module.network

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.network.google_compute_address.kubernetes-the-hard-way will be created
  + resource "google_compute_address" "kubernetes-the-hard-way" {
      + address            = (known after apply)
      + address_type       = "EXTERNAL"
      + creation_timestamp = (known after apply)
      + id                 = (known after apply)
      + name               = "kubernetes-the-hard-way"
      + network_tier       = (known after apply)
      + project            = (known after apply)
      + purpose            = (known after apply)
      + region             = "us-central1"
      + self_link          = (known after apply)
      + subnetwork         = (known after apply)
      + users              = (known after apply)
    }

  # module.network.google_compute_firewall.kubernetes-allow-external will be created
  + resource "google_compute_firewall" "kubernetes-allow-external" {
      + creation_timestamp = (known after apply)
      + destination_ranges = (known after apply)
      + direction          = (known after apply)
      + enable_logging     = (known after apply)
      + id                 = (known after apply)
      + name               = "kubernetes-allow-external"
      + network            = "kubernetes-the-hard-way"
      + priority           = 1000
      + project            = (known after apply)
      + self_link          = (known after apply)
      + source_ranges      = [
          + "0.0.0.0/0",
        ]

      + allow {
          + ports    = [
              + "22",
              + "6443",
            ]
          + protocol = "tcp"
        }
      + allow {
          + ports    = []
          + protocol = "icmp"
        }
    }

  # module.network.google_compute_firewall.kubernetes-allow-internal will be created
  + resource "google_compute_firewall" "kubernetes-allow-internal" {
      + creation_timestamp = (known after apply)
      + destination_ranges = (known after apply)
      + direction          = (known after apply)
      + enable_logging     = (known after apply)
      + id                 = (known after apply)
      + name               = "kubernetes-allow-internal"
      + network            = "kubernetes-the-hard-way"
      + priority           = 1000
      + project            = "kubernetes-the-hard-way-389513"
      + self_link          = (known after apply)
      + source_ranges      = [
          + "10.200.0.0/16",
          + "10.240.0.0/24",
        ]

      + allow {
          + ports    = [
              + "0-65535",
            ]
          + protocol = "tcp"
        }
      + allow {
          + ports    = [
              + "0-65535",
            ]
          + protocol = "udp"
        }
      + allow {
          + ports    = []
          + protocol = "icmp"
        }
    }

  # module.network.google_compute_network.kubernetes-the-hard-way will be created
  + resource "google_compute_network" "kubernetes-the-hard-way" {
      + auto_create_subnetworks                   = false
      + delete_default_routes_on_create           = false
      + gateway_ipv4                              = (known after apply)
      + id                                        = (known after apply)
      + internal_ipv6_range                       = (known after apply)
      + mtu                                       = (known after apply)
      + name                                      = "kubernetes-the-hard-way"
      + network_firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"
      + project                                   = (known after apply)
      + routing_mode                              = (known after apply)
      + self_link                                 = (known after apply)
    }

  # module.network.google_compute_subnetwork.kubernetes will be created
  + resource "google_compute_subnetwork" "kubernetes" {
      + creation_timestamp         = (known after apply)
      + external_ipv6_prefix       = (known after apply)
      + fingerprint                = (known after apply)
      + gateway_address            = (known after apply)
      + id                         = (known after apply)
      + ip_cidr_range              = "10.240.0.0/24"
      + ipv6_cidr_range            = (known after apply)
      + name                       = "kubernetes"
      + network                    = "kubernetes-the-hard-way"
      + private_ip_google_access   = (known after apply)
      + private_ipv6_google_access = (known after apply)
      + project                    = (known after apply)
      + purpose                    = (known after apply)
      + region                     = (known after apply)
      + secondary_ip_range         = (known after apply)
      + self_link                  = (known after apply)
      + stack_type                 = (known after apply)
    }

Plan: 5 to add, 0 to change, 0 to destroy.
╷
│ Warning: Resource targeting is in effect
│ 
│ You are creating a plan with the -target option, which means that the result of this plan may not represent all of the changes requested by the current configuration.
│ 
│ The -target option is not for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically suggests to use it as
│ part of an error message.
╵
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.network.google_compute_address.kubernetes-the-hard-way: Creating...
module.network.google_compute_network.kubernetes-the-hard-way: Creating...
module.network.google_compute_address.kubernetes-the-hard-way: Creation complete after 5s [id=projects/kubernetes-the-hard-way-389513/regions/us-central1/addresses/kubernetes-the-hard-way]
module.network.google_compute_network.kubernetes-the-hard-way: Still creating... [10s elapsed]
module.network.google_compute_network.kubernetes-the-hard-way: Creation complete after 14s [id=projects/kubernetes-the-hard-way-389513/global/networks/kubernetes-the-hard-way]
module.network.google_compute_subnetwork.kubernetes: Creating...
module.network.google_compute_firewall.kubernetes-allow-external: Creating...
module.network.google_compute_firewall.kubernetes-allow-internal: Creating...
module.network.google_compute_subnetwork.kubernetes: Still creating... [10s elapsed]
module.network.google_compute_firewall.kubernetes-allow-external: Still creating... [10s elapsed]
module.network.google_compute_firewall.kubernetes-allow-internal: Still creating... [10s elapsed]
module.network.google_compute_firewall.kubernetes-allow-external: Creation complete after 12s [id=projects/kubernetes-the-hard-way-389513/global/firewalls/kubernetes-allow-external]
module.network.google_compute_firewall.kubernetes-allow-internal: Creation complete after 12s [id=projects/kubernetes-the-hard-way-389513/global/firewalls/kubernetes-allow-internal]
module.network.google_compute_subnetwork.kubernetes: Creation complete after 15s [id=projects/kubernetes-the-hard-way-389513/regions/us-central1/subnetworks/kubernetes]
```

Verify all resources were created:

```bash
$ terraform show
NOTE: Output not included for security reasons.
```

## Compute Instances

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 20.04, which has good support for the [containerd container runtime](https://github.com/containerd/containerd). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.


Compute Instance Configurations
> file: modules/compute/variables.tf
```hcl
variable "instance" {
  type = object({
    count        = optional(number, 3)
    name_prefix  = optional(string)
    machine_type = optional(string, "e2-standard-2")
    boot_disk = optional(object({
      auto_delete = optional(bool, true)
      size        = optional(number, 10)
      type        = optional(string, "pd-balanced")
      image       = optional(string, "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64")
      }), {
      auto_delete = true
      size        = 10
      type        = "pd-balanced"
      image       = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
    })
    scopes = optional(list(string), [
      "compute-rw",
      "storage-ro",
      "service-management",
      "service-control",
      "logging-write",
      "monitoring"
    ])
    tags     = optional(list(string), ["kubernetes-the-hard-way"])
    metadata = optional(map(string), {})
  })

  default = {}
}

variable "network" {
  default = {
    name              = null
    subnet_name       = null
    subnet_cidr_range = null
  }
}

variable "is_worker" {
	default = false
}
```
Template for creating compute instances, worker nodes and control plane nodes

> file: modules/compute/main.tf
```hcl
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
```

### Kubernetes Controllers
> file: main.tf

```hcl
module "controller" {
  source = "./modules/compute"
  instance = {
    count       = 3
    name_prefix = "controller"
    tags        = ["kubernetes-the-hard-way", "controller"]
  }
  network = {
    name              = module.network.network.name
    subnet_name       = module.network.subnet.name
    subnet_cidr_range = module.config.subnet_ip_cidr_range.controller
  }
}
```

- Executing terraform apply will provision the three compute instances:

```bash
$ terraform apply -target=module.controller
module.network.google_compute_network.kubernetes-the-hard-way: Refreshing state... [id=projects/kubernetes-the-hard-way-389513/global/networks/kubernetes-the-hard-way]
module.network.google_compute_subnetwork.kubernetes: Refreshing state... [id=projects/kubernetes-the-hard-way-389513/regions/us-central1/subnetworks/kubernetes]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.controller.google_compute_instance.instance[0] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "controller-0"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "controller",
          + "kubernetes-the-hard-way",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "controller-device-0"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.10"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

  # module.controller.google_compute_instance.instance[1] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "controller-1"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "controller",
          + "kubernetes-the-hard-way",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "controller-device-1"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.11"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

  # module.controller.google_compute_instance.instance[2] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "controller-2"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "controller",
          + "kubernetes-the-hard-way",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "controller-device-2"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.12"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

Plan: 3 to add, 0 to change, 0 to destroy.
╷
│ Warning: Resource targeting is in effect
│ 
│ You are creating a plan with the -target option, which means that the result of this plan may not represent all of the changes requested by the current configuration.
│ 
│ The -target option is not for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically suggests to use it
│ as part of an error message.
╵

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.controller.google_compute_instance.instance[2]: Creating...
module.controller.google_compute_instance.instance[0]: Creating...
module.controller.google_compute_instance.instance[1]: Creating...
module.controller.google_compute_instance.instance[1]: Still creating... [10s elapsed]
module.controller.google_compute_instance.instance[0]: Still creating... [10s elapsed]
module.controller.google_compute_instance.instance[2]: Still creating... [10s elapsed]
module.controller.google_compute_instance.instance[2]: Creation complete after 18s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/controller-2]
module.controller.google_compute_instance.instance[1]: Creation complete after 19s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/controller-1]
module.controller.google_compute_instance.instance[0]: Creation complete after 19s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/controller-0]
╷
│ Warning: Applied changes may be incomplete
│ 
│ The plan was created with the -target option in effect, so some changes requested in the configuration may have been ignored and the output values may not be fully updated. Run the
│ following command to verify that no other changes are pending:
│     terraform plan
│ 
│ Note that the -target option is not suitable for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically
│ suggests to use it as part of an error message.
╵

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Kubernetes Workers

Each worker instance requires a pod subnet allocation from the Kubernetes cluster CIDR range. The pod subnet allocation will be used to configure container networking in a later exercise. The `pod-cidr` instance metadata will be used to expose pod subnet allocations to compute instances at runtime.

> The Kubernetes cluster CIDR range is defined by the Controller Manager's `--cluster-cidr` flag. In this tutorial the cluster CIDR range will be set to `10.200.0.0/16`, which supports 254 subnets.

Create three compute instances which will host the Kubernetes worker nodes:

> file: main.tf
```hcl
module "worker" {
  source = "./modules/compute"
  is_worker = true
  instance = {
    count       = 3
    name_prefix = "worker"
    tags        = ["kubernetes-the-hard-way", "worker"]
  }
  network = {
    name              = module.network.network.name
    subnet_name       = module.network.subnet.name
    subnet_cidr_range = module.config.subnet_ip_cidr_range.worker
  }
}
```

- Execute the terraform apply command to create three compute instances:

```bash
$ terraform apply -target=module.worker
module.network.google_compute_network.kubernetes-the-hard-way: Refreshing state... [id=projects/kubernetes-the-hard-way-389513/global/networks/kubernetes-the-hard-way]
module.network.google_compute_subnetwork.kubernetes: Refreshing state... [id=projects/kubernetes-the-hard-way-389513/regions/us-central1/subnetworks/kubernetes]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.worker.google_compute_instance.instance[0] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata             = {
          + "pod-cidr" = "10.200.0.0/24"
        }
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "worker-0"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "kubernetes-the-hard-way",
          + "worker",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "worker-device-0"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.138"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

  # module.worker.google_compute_instance.instance[1] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata             = {
          + "pod-cidr" = "10.200.1.0/24"
        }
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "worker-1"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "kubernetes-the-hard-way",
          + "worker",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "worker-device-1"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.139"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

  # module.worker.google_compute_instance.instance[2] will be created
  + resource "google_compute_instance" "instance" {
      + can_ip_forward       = true
      + cpu_platform         = (known after apply)
      + current_status       = (known after apply)
      + deletion_protection  = false
      + enable_display       = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "e2-standard-2"
      + metadata             = {
          + "pod-cidr" = "10.200.2.0/24"
        }
      + metadata_fingerprint = (known after apply)
      + min_cpu_platform     = (known after apply)
      + name                 = "worker-2"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags                 = [
          + "kubernetes-the-hard-way",
          + "worker",
        ]
      + tags_fingerprint     = (known after apply)
      + zone                 = "us-central1-a"

      + boot_disk {
          + auto_delete                = true
          + device_name                = "worker-device-2"
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "projects/fedora-coreos-cloud/global/images/fedora-coreos-38-20230722-3-0-gcp-x86-64"
              + labels = (known after apply)
              + size   = 10
              + type   = "pd-balanced"
            }
        }

      + network_interface {
          + ipv6_access_type   = (known after apply)
          + name               = (known after apply)
          + network            = (known after apply)
          + network_ip         = "10.240.0.140"
          + stack_type         = (known after apply)
          + subnetwork         = "kubernetes"
          + subnetwork_project = (known after apply)

          + access_config {
              + nat_ip       = (known after apply)
              + network_tier = "STANDARD"
            }
        }

      + scheduling {
          + automatic_restart   = true
          + on_host_maintenance = "MIGRATE"
          + preemptible         = false
          + provisioning_model  = "STANDARD"
        }

      + service_account {
          + email  = (known after apply)
          + scopes = [
              + "https://www.googleapis.com/auth/compute",
              + "https://www.googleapis.com/auth/devstorage.read_only",
              + "https://www.googleapis.com/auth/logging.write",
              + "https://www.googleapis.com/auth/monitoring",
              + "https://www.googleapis.com/auth/service.management.readonly",
              + "https://www.googleapis.com/auth/servicecontrol",
            ]
        }
    }

Plan: 3 to add, 0 to change, 0 to destroy.
╷
│ Warning: Resource targeting is in effect
│ 
│ You are creating a plan with the -target option, which means that the result of this plan may not represent all of the changes requested by the current configuration.
│ 
│ The -target option is not for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically suggests to use it
│ as part of an error message.
╵

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.worker.google_compute_instance.instance[0]: Creating...
module.worker.google_compute_instance.instance[1]: Creating...
module.worker.google_compute_instance.instance[2]: Creating...
module.worker.google_compute_instance.instance[0]: Still creating... [10s elapsed]
module.worker.google_compute_instance.instance[1]: Still creating... [10s elapsed]
module.worker.google_compute_instance.instance[2]: Still creating... [10s elapsed]
module.worker.google_compute_instance.instance[0]: Creation complete after 19s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/worker-0]
module.worker.google_compute_instance.instance[1]: Still creating... [20s elapsed]
module.worker.google_compute_instance.instance[2]: Still creating... [20s elapsed]
module.worker.google_compute_instance.instance[2]: Creation complete after 28s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/worker-2]
module.worker.google_compute_instance.instance[1]: Creation complete after 29s [id=projects/kubernetes-the-hard-way-389513/zones/us-central1-a/instances/worker-1]
╷
│ Warning: Applied changes may be incomplete
│ 
│ The plan was created with the -target option in effect, so some changes requested in the configuration may have been ignored and the output values may not be fully updated. Run the
│ following command to verify that no other changes are pending:
│     terraform plan
│ 
│ Note that the -target option is not suitable for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically
│ suggests to use it as part of an error message.
╵

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

### Verification

```bash
$ terraform show
NOTE: Output not included for security reasons.
```

## Configuring SSH Access

SSH will be used to configure the controller and worker instances.
We will use a project wide SSH key to provide access to all instances.
This SSH key will also be used by ansible to configure the instances.

### Generating an SSH Key Pair

```bash
$ ssh-keygen -t rsa -b 4096 -C "anonyman637" -f ~/.ssh/gcloud
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in ~/.ssh/gcloud
Your public key has been saved in ~/.ssh/gcloud.pub
...
...
...
```

### Adding the Public Key to GCP

```hcl
resource "google_compute_project_metadata" "my_ssh_key" {
  metadata = {
		"ssh-keys" = <<EOT
      anonyman637: ssh-rsa <public-ssh-key> anonyman637

    EOT
  }
}
```
- Executing terraform apply
```bash
$ terraform apply -target=module.resource

module.resource.google_project_service.compute_engine_api: Refreshing state... [id=kubernetes-the-hard-way-389513/compute.googleapis.com]
module.resource.google_project_service.cloud_resource_manager_api: Refreshing state... [id=kubernetes-the-hard-way-389513/cloudresourcemanager.googleapis.com]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.resource.google_compute_project_metadata.my_ssh_key will be created
  + resource "google_compute_project_metadata" "my_ssh_key" {
      + id       = (known after apply)
      + metadata = {
          + "ssh-keys" = <<-EOT
                anonyman637: ssh-rsa <public-ssh-key> anonyman637
            EOT
        }
      + project  = (known after apply)
    }

Plan: 1 to add, 0 to change, 0 to destroy.
╷
│ Warning: Resource targeting is in effect
│ 
│ You are creating a plan with the -target option, which means that the result of this plan may not represent all of the changes requested by the current configuration.
│ 
│ The -target option is not for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically suggests to use it
│ as part of an error message.
╵

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.resource.google_compute_project_metadata.my_ssh_key: Creating...
module.resource.google_compute_project_metadata.my_ssh_key: Still creating... [10s elapsed]
module.resource.google_compute_project_metadata.my_ssh_key: Creation complete after 13s [id=kubernetes-the-hard-way-389513]
╷
│ Warning: Applied changes may be incomplete
│ 
│ The plan was created with the -target option in effect, so some changes requested in the configuration may have been ignored and the output values may not be fully updated. Run the
│ following command to verify that no other changes are pending:
│     terraform plan
│ 
│ Note that the -target option is not suitable for routine use, and is provided only for exceptional situations such as recovering from errors or mistakes, or when Terraform specifically
│ suggests to use it as part of an error message.
╵

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

### SSH into the Controller Nodes
```bash
$ ssh -i ~/.ssh/gcloud core@<controller-0-external-ip>

Fedora CoreOS 38.20230722.3.0
Tracker: https://github.com/coreos/fedora-coreos-tracker
Discuss: https://discussion.fedoraproject.org/tag/coreos

core@controller-1:~$ exit
logout
Connection to <controller-0-external-ip> closed.
```

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)

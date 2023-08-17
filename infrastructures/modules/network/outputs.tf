output "network" {
	value = google_compute_network.kubernetes-with-k0s
}

output "subnet" {
	value = google_compute_subnetwork.kubernetes
}

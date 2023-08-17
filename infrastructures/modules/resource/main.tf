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

resource "google_compute_project_metadata" "my_ssh_key" {
  metadata = {
		"ssh-keys" = <<EOT
      anonyman637: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNHmHK00EIYLmPWMJRQ/bE2cHJnaMtjdKX/DirMlIa8RDugs/Rb7gS1yAtP+txx4jndzZFgRSp0ev9T/dsRy10o6qUbC33qgsZpdn72h/FRf3RPHNtt4fMjYoq7zYpXEZmz+rqyYDIH7eGRWb3GhztQRsHZY+pEFamJk1zpDsJQln+1Ok7xAaQGvLNKA0nM6pWOn54emCvxI5guQz1f03H4jbGpus+eoGc11NG8YvfwuS8BC59OenAIJFU2sQ7o5FviSDnmKhtdETt+nb50b9t1ut8BXNmOJ4XxT5cz3vqZ7E91GSlV1otlOvTXZTmqNgwcjnP1Cfxf8A2OTTYyqpEJJxTcB/uxRGYO47LHS1Gri5foAfdRAgCaqy5dlmU9v/+TznmG80WabfPJj4LJy50wThn8+fqivcNrpjR3bBp0wPKpPaoxU9AAAhcf/hHZNez0NazZURgbYXF/TNu1PNMgNRtvlFPy9CcmSviRPmtEMQEVF+u3r6F/dxbMru5rE4z2DNgi8T4TdCKDGpMntbYby+8pfjLemeIoW/Ar89EU/Xu9Tjc633DnXlnGv7/AbnGMeW200neFDsNWJ8t066305HWgL9w9jOBT0VYwLX8emVPyXSKI8ZFBMvrNYeSOdQ1Q92harBZ9J1QPDCNpLKaIsJHsZQSm2YFHWKunqWGZw== anonyman637

    EOT
  }
}

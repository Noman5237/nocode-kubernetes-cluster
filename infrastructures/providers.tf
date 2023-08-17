provider "google" {
	region = module.config.default_region
	zone = module.config.default_zone
	credentials = file("credentials/gcp-credentials.json")

	project = module.config.project_id
}

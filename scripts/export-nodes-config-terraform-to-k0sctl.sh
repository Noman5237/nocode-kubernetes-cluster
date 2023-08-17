cd $PROJECT_ROOT/infrastructures

output_controllers=$(
	terraform show -json |
		jq -r '[.values.root_module.child_modules[] 
	| select(.address == "module.controller")] 
	| .[].resources[].values 
	| {
			role: "controller",
			ssh: { 
				address: .network_interface[0].access_config[0].nat_ip, 
				port: 22,
				user: "core",
				keypath: "~/.ssh/gcloud",
			}
		}'
)

output_workers=$(
	terraform show -json |
		jq -r '[.values.root_module.child_modules[] 
	| select(.address == "module.worker")] 
	| .[].resources[].values 
	| {
			role: "worker",
			ssh: { 
				address: .network_interface[0].access_config[0].nat_ip,
				port: 22,
				user: "core",
				keypath: "~/.ssh/gcloud"
			}
		}'
)

merged_output=$(printf "%s\n%s" "$output_controllers" "$output_workers")

echo "$merged_output" |
	jq -s '[
  .[]
  | {
      "role": .role,
      "ssh": {
        "address": .ssh.address,
        "user": .ssh.user,
        "port": .ssh.port,
        "keyPath": .ssh.keypath
      }
    }
] | {
  "apiVersion": "k0sctl.k0sproject.io/v1beta1",
  "kind": "Cluster",
  "metadata": {
    "name": "k0s-cluster"
  },
  "spec": {
    "hosts": .,
    "k0s": {
      "version": "1.27.4+k0s.0",
      "dynamicConfig": false
    }
  }
}' |
	yq -P >$PROJECT_ROOT/k0sctl.yaml

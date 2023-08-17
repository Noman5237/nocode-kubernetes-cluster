cd $PROJECT_ROOT/infrastructures

mkdir -p $PROJECT_ROOT/automation/group_vars

terraform show -json | \
	jq -r '[.values.root_module.child_modules[] 
	| select(.address == "module.controller")] 
	| .[].resources[].values 
	| {
			(.name): {
				ip: { 
					internal: .network_interface[0].network_ip, 
					external: .network_interface[0].access_config[0].nat_ip
				},
				username: "core"
			}
		}' | \
	jq -s 'reduce .[] as $item ({}; . * $item) | { "control_plane": . }' | \
	awk '{ gsub("-", "_"); print }' | \
	yq -P > $PROJECT_ROOT/automation/group_vars/control_plane.yml

terraform show -json | \
	jq -r '[.values.root_module.child_modules[] 
	| select(.address == "module.worker")] 
	| .[].resources[].values 
	| {
			(.name): {
				ip: { 
					internal: .network_interface[0].network_ip, 
					external: .network_interface[0].access_config[0].nat_ip
				},
				username: "core"
			}
		}' | \
	jq -s 'reduce .[] as $item ({}; . * $item) | { "worker_plane": . }' | \
	awk '{ gsub("-", "_"); print }' | \
	yq -P > $PROJECT_ROOT/automation/group_vars/worker_plane.yml

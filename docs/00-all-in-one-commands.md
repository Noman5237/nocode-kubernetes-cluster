# All in One Commands

All the commands has to be executed from the root of the repository in order to work.

```
bash

################################################################
#                   ENVIRONMENT VARIABLES                      #
################################################################

export PROJECT_ROOT=$(pwd)

################################################################
#                        INFRASTRUCTURE                        #
################################################################
cd $PROJECT_ROOT/infrastructures
terraform init
terraform apply --target=module.resource
terraform apply --target=module.network
echo yes | terraform apply -target=module.controller
echo yes | terraform apply -target=module.worker
terraform show

# EXPORTING NODES CONFIGURATION TO ANSIBLE
################################################################
cd $PROJECT_ROOT
./scripts/export-nodes-config-terraform-to-ansible.sh

k0sctl init > k0sctl.yaml
k0sctl apply --config k0sctl.yaml
k0sctl kubeconfig > kubeconfig

```
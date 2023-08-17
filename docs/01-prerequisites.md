# Prerequisites

## Google Cloud Platform

This tutorial leverages the [Google Cloud Platform](https://cloud.google.com/) to streamline provisioning of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up. [Sign up](https://cloud.google.com/free/) for $300 in free credits.

### Create a Project
This tutorial uses a single [Google Cloud Project](https://cloud.google.com/resource-manager/docs/creating-managing-projects) to provision all of the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up. Create a new project and note the project id.

### Create a service account and download the private key
Create a new [service account](https://cloud.google.com/compute/docs/access/service-accounts#creatinganewserviceaccount) with the role *Owner* and download the JSON key file. We will use this key file to authenticate with the Google Cloud API from our local workstation.

### Estimated Cost
TODO

## Install Terraform

This tutorial uses [Terraform](https://developer.hashicorp.com/terraform) to provision the compute infrastructure required to bootstrap a Kubernetes cluster from the ground up.
Download the [Terraform binary](https://developer.hashicorp.com/terraform/downloads) and add it to your path.

## Running Commands in Parallel with Ansible

[Ansible](https://www.ansible.com/) can be used to run commands on multiple compute instances at the same time. Labs in this tutorial may require running the same commands across multiple compute instances, in those cases consider using ansible playbooks to speed up the provisioning process.

Next: [Installing the Client Tools](02-client-tools.md)

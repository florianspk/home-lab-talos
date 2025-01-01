# Talos Setup and Usage Guide

This document provides guidance on how to set up and manage Talos, including configuring extensions and using Terraform for deployment. Below are the steps and references you’ll need to achieve the same functionality previously encapsulated in the script.

---

## Prerequisites

- [Talos CLI](https://github.com/siderolabs/talos/releases) installed on your machine.
- Docker installed and running for building images.
- [Terraform](https://www.terraform.io/downloads) installed and configured.
- Access to the following GitHub repositories for extensions and images:
  - [QEMU Guest Agent](https://github.com/siderolabs/extensions/tree/main/guest-agents/qemu-guest-agent)
  - [DRBD](https://github.com/siderolabs/extensions/tree/main/storage/drbd)
  - [Spin](https://github.com/siderolabs/extensions/tree/main/container-runtime/spin)
  - [Piraeus Operator](https://github.com/piraeusdatastore/piraeus-operator/releases)

---

## Environment Variables

Set the following environment variables in your shell:

```bash
export CHECKPOINT_DISABLE='1'
export TF_LOG='DEBUG' # Options: TRACE, DEBUG, INFO, WARN, ERROR
export TF_LOG_PATH='terraform.log'

export TALOSCONFIG=~/.talos/config
export KUBECONFIG=~/.kube/config-talos

export TALOS_VERSION='<talos_version>'
export K8S_CLUSTER_NAME='<cluster_name>'
export K8S_NAMESPACE='<namespace>'
```

---

## Terraform Variables Reference

| Variable Name                                           | Type          | Default Value                     | Description                                                                                 |
|--------------------------------------------------------|---------------|-----------------------------------|---------------------------------------------------------------------------------------------|
| `proxmox_pve_node_name`                                | `list(string)`| `['pve01', 'pve02', 'pve03']`    | List of Proxmox node names.                                                                |
| `talos_version`                                        | `string`      | `1.8.3`                           | Version of Talos to deploy.                                                                |
| `kubernetes_version`                                   | `string`      | `1.31.3`                          | Version of Kubernetes to deploy.                                                           |
| `cluster_name`                                         | `string`      | `example`                         | Name for the Talos cluster.                                                                |
| `cluster_vip`                                          | `string`      | `172.31.1.10`                     | Virtual IP (VIP) address of the Kubernetes API server.                                      |
| `cluster_endpoint`                                     | `string`      | `https://172.31.1.10:6443`        | Endpoint for the Kubernetes API server.                                                    |
| `cluster_node_network_gateway`                        | `string`      | `172.31.1.1`                      | Gateway for cluster nodes' network.                                                        |
| `cluster_node_network`                                | `string`      | `172.31.1.0/24`                   | CIDR block of the cluster node network.                                                    |
| `cluster_node_network_first_controller_hostnum`       | `number`      | `40`                              | Host number for the first controller.                                                      |
| `cluster_node_network_first_worker_hostnum`           | `number`      | `50`                              | Host number for the first worker node.                                                     |
| `cluster_node_network_load_balancer_first_hostnum`    | `number`      | `70`                              | Host number for the first load balancer.                                                   |
| `cluster_node_network_load_balancer_last_hostnum`     | `number`      | `80`                              | Host number for the last load balancer.                                                    |
| `ingress_domain`                                       | `string`      | `example.test`                    | DNS domain for ingress resources.                                                          |
| `controller_count`                                     | `number`      | `1`                               | Number of control plane nodes. Must be at least 1.                                          |
| `worker_count`                                         | `number`      | `2`                               | Number of worker nodes. Must be at least 1.                                                |
| `prefix`                                               | `string`      | `vm-talos`                        | Prefix for VM names.                                                                       |
| `talos-iso-datastoreid`                                | `string`      | `isoShare`                        | Datastore ID for Talos ISO images.                                                         |
| `talos-datastoreid-suffix`                            | `string`      | `local-lvm`                       | Datastore suffix for Talos VMs.                                                            |
| `api_token`                                            | `string`      | `XXXXXXXXXXX`                     | Secret token for authenticating with Proxmox.                                              |

---

## Steps to Update Talos Extensions

### 1. Fetch Extension Tags
Use the [Talos Extensions documentation](https://github.com/siderolabs/extensions?tab=readme-ov-file#installing-extensions) to fetch and set the appropriate tags for:

- QEMU Guest Agent
- DRBD
- Spin

### 2. Update Extensions
Use `crane` (or an equivalent tool) to retrieve image tags and update your Talos extensions configuration. Follow the instructions in the Extensions README to install or update extensions.

---

## Build Talos Images

### References:
- [Talos Boot Assets Guide](https://www.talos.dev/v1.8/talos-guides/install/boot-assets/)
- [Talos Advanced Metal Network Configuration](https://www.talos.dev/v1.8/advanced/metal-network-configuration/)

### Steps:

1. Prepare a configuration file `talos-<version>.yml` based on your requirements.
2. Use the Talos Imager Docker image to build the Talos disk image:

```bash
docker run --rm -i \
  -v $PWD/tmp/talos:/secureboot:ro \
  -v $PWD/tmp/talos:/out \
  -v /dev:/dev \
  --privileged \
  "ghcr.io/siderolabs/imager:<talos_version_tag>" \
  - < "tmp/talos/talos-<version>.yml"
```
3. Convert the generated raw image to QCOW2 format for use with QEMU:

```bash
qemu-img convert -O qcow2 tmp/talos/nocloud-amd64.raw tmp/talos/talos-<version>.qcow2
qemu-img info tmp/talos/talos-<version>.qcow2
```

---

## Deploying with Terraform

### Steps:

1. Initialize Terraform:

```bash
terraform init
```

2. Plan the deployment:

```bash
terraform plan -out=tfplan -var-file=integration.tfvars
```

3. Apply the deployment:

```bash
terraform apply tfplan
```

4. Extract configuration files for Talos and Kubernetes:

```bash
terraform output -raw talosconfig > ~/.talos/config
terraform output -raw kubeconfig > ~/.kube/config-talos
```

---

## Installing Piraeus Operator

### References:
- [Piraeus Talos Guide](https://github.com/piraeusdatastore/piraeus-operator/blob/v2.7.1/docs/how-to/talos.md)
- [Piraeus Get Started Guide](https://github.com/piraeusdatastore/piraeus-operator/blob/v2.7.1/docs/tutorial/get-started.md)
- [LINBIT DRBD Documentation](https://linbit.com/drbd-user-guide/)

### Steps:

1. Install the operator:

```bash
kubectl apply --server-side -k "https://github.com/piraeusdatastore/piraeus-operator//config/default?ref=v<piraeus_operator_version>"
```

2. Wait for the operator to be ready:

```bash
kubectl wait pod --timeout=15m --for=condition=Ready -n piraeus-datastore -l app.kubernetes.io/component=piraeus-operator
```

3. Configure the Piraeus cluster and storage class:

Refer to the examples in the [Piraeus Talos Guide](https://github.com/piraeusdatastore/piraeus-operator/blob/v2.7.1/docs/how-to/talos.md).

---

## Health Checks and Info Retrieval

### Talos Health:

```bash
talosctl health --control-plane-nodes <controller_ips> --worker-nodes <worker_ips>
```

### Kubernetes Node Info:

```bash
kubectl get nodes -o wide
```

### Piraeus Storage Info:

```bash
kubectl linstor node list
kubectl linstor storage-pool list
kubectl linstor volume list
```

---

## Destroying the Deployment

To clean up all resources:

```bash
terraform destroy -auto-approve
```

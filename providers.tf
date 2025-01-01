# see https://github.com/hashicorp/terraform
terraform {
  required_version = ">1.10.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.5"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.68.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.6.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.1"
    }
    kustomizer = {
      source  = "rgl/kustomizer"
      version = "0.0.1"
    }
  }
}

provider "proxmox" {
  tmp_dir = "tmp"
  endpoint = "https://${var.proxmox_pve_node_name[0]}.wallaby-marlin.ts.net:8006"
  api_token = "${var.api_token}"
  ssh {
    agent= true
    username = "terraform"
    private_key = "${var.path_private_key}"
    dynamic "node" {
      for_each = var.proxmox_pve_node_name
      content {
        name    = node.value
        address = "${node.value}.${var.ingress_domain}"
      }
    }
  }
}

provider "talos" {
}

variable "proxmox_pve_node_name" {
  type    = list(string)
  default = ["pve01", "pve02", "pve03"]
}

variable "talos_version" {
  type    = string
  default = "1.8.3"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.talos_version))
    error_message = "Must be a version number."
  }
}

variable "kubernetes_version" {
  type = string
  # renovate: datasource=github-releases depName=siderolabs/kubelet
  default = "1.33.3"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.kubernetes_version))
    error_message = "Must be a version number."
  }
}

variable "cluster_name" {
  description = "A name to provide for the Talos cluster"
  type        = string
  default     = "example"
}

variable "cluster_vip" {
  description = "The virtual IP (VIP) address of the Kubernetes API server. Ensure it is synchronized with the 'cluster_endpoint' variable."
  type        = string
  default     = "172.31.1.10"
}

variable "cluster_endpoint" {
  description = "The virtual IP (VIP) endpoint of the Kubernetes API server. Ensure it is synchronized with the 'cluster_vip' variable."
  type        = string
  default     = "https://172.31.1.10:6443"
}

variable "cluster_node_network_gateway" {
  description = "The IP network gateway of the cluster nodes"
  type        = string
  default     = "172.31.1.1"
}

variable "cluster_node_network" {
  description = "The IP network of the cluster nodes"
  type        = string
  default     = "172.31.1.0/24"
}

variable "cluster_node_network_first_controller_hostnum" {
  description = "The hostnum of the first controller host"
  type        = number
  default     = 40
}

variable "cluster_node_network_first_worker_hostnum" {
  description = "The hostnum of the first worker host"
  type        = number
  default     = 50
}

variable "cluster_node_network_load_balancer_first_hostnum" {
  description = "The hostnum of the first load balancer host"
  type        = number
  default     = 70
}

variable "cluster_node_network_load_balancer_last_hostnum" {
  description = "The hostnum of the last load balancer host"
  type        = number
  default     = 80
}

variable "bootstrap_repo_url" {
  description = "the DNS domain of the ingress resources"
  type        = string
  default     = "https://github.com/florianspk/argocd-apps-homelab.git"
}

variable "ingress_domain" {
  description = "the DNS domain of the ingress resources"
  type        = string
  default     = "example.test"
}

variable "pve_domain" {
  description = "The DNS domaine of the pve"
  type        = string
}

variable "controller_count" {
  type    = number
  default = 1
  validation {
    condition     = var.controller_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "worker_count" {
  type    = number
  default = 2
  validation {
    condition     = var.worker_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "prefix" {
  type    = string
  default = "vm-talos"
}

variable "default-iso-datastoreid" {
  type    = string
  default = "local"
}
variable "default-datastoreid" {
  type    = string
  default = "local-lvm-1"
}

variable "datastore_per_node" {
  type = map(string)
  default = {
    #exemple : "pve01" = "ssd-storage"
    #         "pve02" = "local-lvm-2"
    #pas besoin d’ajouter un noeud ici s’il doit utiliser la valeur par défaut
  }
}

variable "api_token" {
  type        = string
  description = "secret to auth proxmox"
  default     = "XXXXXXXXXXX"
}

variable "path_private_key" {
  type        = string
  description = "path to the private key"
  default     = "~/.ssh/terraform_id_ed25519"
}

variable "tags" {
  type        = list(string)
  default     = ["talos", "terraform"]
  description = "values to tag the vm"
}

variable "argocd_enabled" {
  type        = bool
  default     = true
  description = "enable argocd"

}

variable "ntp_serveurs" {
  type    = list(string)
  default = ["pool.ntp.org"]
}

variable "dns_serveurs" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "extra_disks_per_node" {
  description = "Disques supplémentaires par nœud"
  type = map(list(object({
    size         = number
    datastore_id = string
    interface    = string
    ssd          = optional(bool, true)
    discard      = optional(string, "on")
    file_format  = optional(string, "raw")
    iothread     = optional(bool, true)
  })))
  default = {}
}

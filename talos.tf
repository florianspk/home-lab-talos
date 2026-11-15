locals {
  controller_nodes = [
    for i in range(var.controller_count) : {
      name    = "c${i}"
      address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_controller_hostnum + i)
    }
  ]
  worker_nodes = [
    for i in range(var.worker_count) : {
      name    = "w${i}"
      address = cidrhost(var.cluster_node_network, var.cluster_node_network_first_worker_hostnum + i)
    }
  ]
  common_machine_config = {
    machine = {
      features = {
        kubePrism = {
          enabled = true
          port    = 7445
        }
        hostDNS = {
          enabled              = true
          forwardKubeDNSToHost = true
        }
      }
      kernel = {
        modules = [
          {
            name = "drbd"
            parameters = [
              "usermode_helper=disabled",
            ]
          },
          {
            name = "drbd_transport_tcp"
          },
          {
            name = "dm_thin_pool"
          },
        ]
      }
    }
    cluster = {
      discovery = {
        enabled = true
        registries = {
          kubernetes = {
            disabled = false
          }
          service = {
            disabled = true
          }
        }
      }
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
  }
}

resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_config_contract_version}"
  lifecycle {
    # Filet de sécurité : un replace régénérerait toute la PKI du cluster
    prevent_destroy = true
  }
}

# Une machine config complète par nœud (patches inclus) : talos_machine ne prend pas de config_patches
data "talos_machine_configuration" "controller" {
  count              = var.controller_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "controlplane"
  talos_version      = "v${var.talos_config_contract_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
  config_patches     = local.controller_config_patches[count.index]
}

data "talos_machine_configuration" "worker" {
  count              = var.worker_count
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = talos_machine_secrets.talos.machine_secrets
  machine_type       = "worker"
  talos_version      = "v${var.talos_config_contract_version}"
  kubernetes_version = var.kubernetes_version
  examples           = false
  docs               = false
  config_patches     = local.worker_config_patches[count.index]
}

data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoints            = [for node in local.controller_nodes : node.address]
}

resource "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[0].address
  node                 = local.controller_nodes[0].address
  depends_on = [
    talos_machine.controller,
  ]
}

locals {
  # Patches identiques à ceux de l'ancien talos_machine_configuration_apply (même ordre) :
  # la config générée doit rester octet pour octet celle déjà appliquée sur les nœuds
  controller_config_patches = [
    for i in range(var.controller_count) : [
      yamlencode(local.common_machine_config),
      yamlencode({
        machine = {
          network = {
            hostname    = local.controller_nodes[i].name
            nameservers = var.dns_serveurs
            interfaces = [
              {
                interface = "ens18"
                vip = {
                  ip = var.cluster_vip
                }
              }
            ]
          }
          time = {
            servers = var.ntp_serveurs
          }
          install = {
            image = "factory.talos.dev/nocloud-installer/${var.talos_schematic_id}:v${var.talos_version}"
          }
        }
      }),
      i == 0 ? yamlencode({
        cluster = {
          # CoreDNS fourni par l'inlineManifest "coredns" (coredns.tf) pour garder le forward 1.1.1.1 / 8.8.8.8
          coreDNS = {
            disabled = true
          }
          inlineManifests = concat([
            {
              name     = "coredns"
              contents = local.coredns_manifest
            },
            {
              name     = "spin"
              contents = <<-EOF
              apiVersion: node.k8s.io/v1
              kind: RuntimeClass
              metadata:
                name: wasmtime-spin-v2
              handler: spin
              EOF
            },
            {
              name = "cilium"
              contents = join("---\n", [
                local.cilium_manifest,
                "# Source cilium.tf\n${local.cilium_external_lb_manifest}",
              ])
            },
            {
              name = "cert-manager"
              contents = join("---\n", [
                yamlencode({
                  apiVersion = "v1"
                  kind       = "Namespace"
                  metadata = {
                    name = "cert-manager"
                  }
                }),
                data.helm_template.cert_manager.manifest,
                "# Source cert-manager.tf\n${local.cert_manager_ingress_ca_manifest}",
              ])
            },
            {
              name     = "trust-manager"
              contents = data.helm_template.trust_manager.manifest
            },
            {
              name     = "reloader"
              contents = data.helm_template.reloader.manifest
            }
            ], var.argocd_enabled ? [
            {
              name = "argocd"
              contents = join("---\n", [
                yamlencode({
                  apiVersion = "v1"
                  kind       = "Namespace"
                  metadata = {
                    name = local.argocd_namespace
                  }
                }),
                data.helm_template.argocd.manifest,
                "# Source argocd.tf\n${local.argocd_manifest}",
              ])
            }
          ] : [])
        }
      }) : yamlencode({})
    ]
  ]
  worker_config_patches = [
    for i in range(var.worker_count) : [
      yamlencode(local.common_machine_config),
      yamlencode({
        machine = {
          network = {
            hostname    = local.worker_nodes[i].name
            nameservers = var.dns_serveurs
            interfaces = [
              {
                interface = "ens18"
                addresses = ["${local.worker_nodes[i].address}/${split("/", var.cluster_node_network)[1]}"]
                routes = [
                  {
                    network = "0.0.0.0/0"
                    gateway = var.cluster_node_network_gateway
                  }
                ]
              }
            ]
          }
          time = {
            servers = var.ntp_serveurs
          }
          install = {
            image = "factory.talos.dev/installer/${var.talos_schematic_id}:v${var.talos_version}"
          }
          sysctls = {
            "net.ipv6.conf.all.disable_ipv6"     = "1"
            "net.ipv6.conf.default.disable_ipv6" = "1"
            "net.ipv6.conf.lo.disable_ipv6"      = "1"
          }
        }
      }),
    ]
  ]
}

# Config + version de l'OS de chaque nœud.
# Monter var.talos_version change `image` => upgrade Talos (reboot). Un changement de la chaîne image,
# même à version égale (registry, plateforme, digest), déclenche aussi un upgrade.
# Upgrades OS : c0 d'abord, puis les workers ; lancer l'apply avec -parallelism=1 pour les faire un par un.
resource "talos_machine" "controller" {
  count                = var.controller_count
  client_configuration = talos_machine_secrets.talos.client_configuration
  endpoint             = local.controller_nodes[count.index].address
  node                 = local.controller_nodes[count.index].address
  # nocloud obligatoire sur le CP : son IP vient du cidata nocloud
  image                 = "factory.talos.dev/nocloud-installer/${var.talos_schematic_id}:v${var.talos_version}"
  machine_configuration = data.talos_machine_configuration.controller[count.index].machine_configuration
  # CP unique : l'API Kubernetes disparaît pendant son propre reboot, pas de drain via le provider
  drain_on_upgrade = false
  # Les tags d'images Kubernetes sont gérés par upgrade-k8s, pas par ce resource (pas de ré-apply quand kubernetes_version suit)
  ignore_kubernetes_upgrade_drift = true
  depends_on = [
    proxmox_virtual_environment_vm.controller,
  ]
}

resource "talos_machine" "worker" {
  count                 = var.worker_count
  client_configuration  = talos_machine_secrets.talos.client_configuration
  endpoint              = local.worker_nodes[count.index].address
  node                  = local.worker_nodes[count.index].address
  image                 = "factory.talos.dev/installer/${var.talos_schematic_id}:v${var.talos_version}"
  machine_configuration = data.talos_machine_configuration.worker[count.index].machine_configuration
  # Cordon + drain via l'API Kubernetes avant le reboot, uncordon après (doc provider : défaut recommandé).
  # kubeconfig en write-only : pas stocké dans ce resource, pas de diff quand le certificat est renouvelé
  drain_on_upgrade                = true
  kubeconfig_wo                   = talos_cluster_kubeconfig.talos.kubeconfig_raw
  ignore_kubernetes_upgrade_drift = true
  depends_on = [
    proxmox_virtual_environment_vm.worker,
    talos_machine.controller,
  ]
}

# Upgrade Kubernetes piloté par Terraform : quand kubernetes_version change, talos_cluster lance la
# procédure upgrade-k8s de Talos (pré-pull des images, apiserver -> controller-manager -> scheduler,
# kube-proxy, puis kubelet nœud par nœud avec health checks, puis ré-application des inlineManifests).
# Les talos_machine ont ignore_kubernetes_upgrade_drift = true : ils ne touchent jamais aux tags d'images k8s.
# Création sur un cluster existant : le Bootstrap RPC renvoie AlreadyExists (etcd déjà initialisé),
# traité comme un succès par le provider ; aucun upgrade n'est lancé à la création, seulement sur update.
# depends_on : si talos_version et kubernetes_version changent dans le même apply, l'OS passe d'abord.
resource "talos_cluster" "talos" {
  client_configuration = talos_machine_secrets.talos.client_configuration
  node                 = local.controller_nodes[0].address
  control_plane_nodes  = [for node in local.controller_nodes : node.address]
  kubernetes_version   = "v${var.kubernetes_version}"
  timeouts = {
    create = "20m"
    update = "60m"
  }
  depends_on = [
    talos_machine.controller,
    talos_machine.worker,
  ]
}

# Migration provider 0.12.0 : les anciennes ressources sortent du state sans être détruites
# (pas de moved/import possible en 0.12.0 vers talos_machine / talos_cluster)
removed {
  from = talos_machine_configuration_apply.controller
  lifecycle {
    destroy = false
  }
}

removed {
  from = talos_machine_configuration_apply.worker
  lifecycle {
    destroy = false
  }
}

removed {
  from = talos_machine_bootstrap.talos
  lifecycle {
    destroy = false
  }
}

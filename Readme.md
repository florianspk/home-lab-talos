<div align="center">

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="16" height="16"> Mon Homelab Kubernetes <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f6a7/512.gif" alt="🚧" width="16" height="16">

_... géré avec Terraform, ArgoCD, et Talos Linux_ <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.gif" alt="🤖" width="16" height="16">

</div>

<div align="center">

[![Talos](https://img.shields.io/badge/Talos-Linux-blue?style=for-the-badge&logo=talos&logoColor=white)](https://talos.dev)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-blue?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io)&nbsp;&nbsp;
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-blue?style=for-the-badge&logo=argo&logoColor=white)](https://argo-cd.readthedocs.io)&nbsp;&nbsp;
[![Terraform](https://img.shields.io/badge/Terraform-IaC-blue?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)

</div>

<div align="center">

[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-brightgreen?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com)&nbsp;&nbsp;
[![Cloudflare](https://img.shields.io/badge/Cloudflare-ZeroTrust-brightgreen?style=for-the-badge&logo=cloudflare&logoColor=white)](https://www.cloudflare.com)&nbsp;&nbsp;
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-brightgreen?style=for-the-badge&logo=proxmox&logoColor=white)](https://proxmox.com)

</div>

<div align="center">

[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://kromgo.wheezy.fr)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://kromgo.wheezy.fr)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_nodes_ready)](https://kromgo.wheezy.fr)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_pods_running)](https://kromgo.wheezy.fr)&nbsp;&nbsp;
</div>

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a1/512.gif" alt="💡" width="20" height="20"> Vue d'ensemble

Ce repository contient l'infrastructure complète de mon homelab Kubernetes. J'applique les principes d'Infrastructure as Code (IaC) et GitOps en utilisant [Terraform](https://www.terraform.io/) pour le provisioning, [Talos Linux](https://www.talos.dev/) comme OS des nœuds, et [ArgoCD](https://argo-cd.readthedocs.io/) pour le déploiement des applications.

L'infrastructure est hébergée sur [Proxmox VE](https://proxmox.com/) et utilise [Tailscale](https://tailscale.com/) pour l'accès privé sécurisé ainsi que [Cloudflare Zero Trust](https://www.cloudflare.com/) pour l'exposition publique des services.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f331/512.gif" alt="🌱" width="20" height="20"> Kubernetes

Mon cluster Kubernetes est déployé avec [Talos Linux](https://www.talos.dev/) sur deux serveurs physiques sous Proxmox VE. Le cluster utilise un stockage distribué avec [Linstor](https://linbit.com/linstor/) pour la persistance des données.

Le repository des applications ArgoCD se trouve ici : [argocd-apps-homelab](https://github.com/florianspk/argocd-apps-homelab)

### Composants principaux

- **[talos](https://www.talos.dev/)** : OS minimal et sécurisé pour Kubernetes
- **[cilium](https://github.com/cilium/cilium)** : CNI basé sur eBPF avec ingress controller intégré
- **[argocd](https://argo-cd.readthedocs.io/)** : Déploiement GitOps des applications
- **[cert-manager](https://github.com/cert-manager/cert-manager)** : Gestion automatique des certificats SSL/TLS
- **[trust-manager](https://github.com/cert-manager/trust-manager)** : Distribution des CA pour les DNS privés
- **[linstor](https://linbit.com/linstor/)** : Stockage distribué haute disponibilité
- **[external-dns](https://github.com/kubernetes-sigs/external-dns)** : Synchronisation automatique des enregistrements DNS

### GitOps avec ArgoCD

[ArgoCD](https://argo-cd.readthedocs.io/) surveille le repository [argocd-apps-homelab](https://github.com/florianspk/argocd-apps-homelab) et synchronise automatiquement l'état désiré des applications avec le cluster Kubernetes.

Les applications sont organisées par namespace et environnement, permettant une gestion granulaire des déploiements et des mises à jour.

### Structure des répertoires

```sh
📁 homelab-infrastructure
├── 📁 terraform          # Configuration Terraform pour Proxmox
├── 📁 talos              # Configuration Talos Linux
├── 📁 hack               # Scripts Linstor et utilitaires
└── 📁 docs               # Documentation
```

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f30e/512.gif" alt="🌎" width="20" height="20"> Réseau

### DNS et accès sécurisé

Le cluster utilise une approche hybride pour la gestion DNS et l'accès réseau :

- **DNS privé** : Intégration avec le DNS interne du cluster via cert-manager et une CA privée
- **Tailscale** : VPN mesh pour l'accès administratif aux interfaces (pfSense, Proxmox)
- **Split DNS** : Configuration sur Tailscale pour résoudre les services internes
- **Cloudflare Zero Trust** : Exposition sécurisée des services publics

### Ingress et Load Balancing

Cilium assure à la fois les fonctions de CNI et d'ingress controller, offrant :
- Load balancing L4/L7 natif
- Politique réseau fine avec eBPF
- Observabilité réseau avancée
- Intégration native avec les services Kubernetes

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2699_fe0f/512.gif" alt="⚙" width="20" height="20"> Infrastructure

### Matériel

| Serveur | CPU | RAM | Stockage | Rôle | Spécificités |
|---------|-----|-----|----------|------|-------------|
| pve01 | Intel i5 5ème gen | 32GB | SSD NVMe | Kubernetes Master/Worker | NVIDIA GTX 1060 |
| pve02 | Intel i5 5ème gen | 32GB | SSD NVMe | Kubernetes Worker | - |

### Hyperviseur

- **[Proxmox VE](https://proxmox.com/)** : Plateforme de virtualisation pour héberger les VMs Talos
- **Terraform Provider** : Automatisation du provisioning des ressources Proxmox

### Stockage

- **[Linstor](https://linbit.com/linstor/)** : Stockage distribué DRBD pour la haute disponibilité
- **Configuration manuelle** : Scripts de déploiement dans le dossier `hack/`
- **Réplication** : Données répliquées entre les deux nœuds

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f636_200d_1f32b_fe0f/512.gif" alt="😶" width="20" height="20"> Services Cloud

Bien que la majorité de l'infrastructure soit auto-hébergée, je m'appuie sur quelques services cloud pour les besoins critiques :

| Service | Utilisation | Coût |
|---------|-------------|------|
| [Tailscale](https://tailscale.com/) | VPN mesh et accès administratif | ~$5/mois |
| [Cloudflare](https://www.cloudflare.com/) | Zero Trust et DNS public | ~$0/mois |
| [GitHub](https://github.com/) | Hébergement des repositories et CI/CD | Gratuit |

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="20" height="20"> Déploiement

### Prérequis

- Proxmox VE configuré avec les VMs
- Terraform installé
- Talosctl installé
- Accès aux credentials Proxmox

### Étapes de déploiement

1. **Provisioning Terraform**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Bootstrap Talos**
   ```bash
   cd talos
   talosctl bootstrap --nodes <node-ip>
   talosctl kubeconfig
   ```

3. **Déploiement Linstor**
   ```bash
   cd hack
   ./deploy-linstor.sh
   ```

4. **Configuration ArgoCD**
   - ArgoCD se déploie automatiquement
   - Configurer le repository [argocd-apps-homelab](https://github.com/florianspk/argocd-apps-homelab)

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f64f/512.gif" alt="🙏" width="20" height="20"> Remerciements

Merci à la communauté open-source et aux projets qui rendent ce homelab possible :
- [Talos Linux](https://www.talos.dev/) pour l'OS Kubernetes sécurisé
- [ArgoCD](https://argo-cd.readthedocs.io/) pour le GitOps
- [Cilium](https://cilium.io/) pour le networking eBPF
- [Linstor](https://linbit.com/linstor/) pour le stockage distribué

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4dd/512.gif" alt="📝" width="20" height="20"> Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

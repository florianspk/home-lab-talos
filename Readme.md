

<div align="center">

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="16" height="16"> Mon Homelab Kubernetes <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f6a7/512.gif" alt="🚧" width="16" height="16">

<img src="assets/wheezy_logo.png" align="center"  height="250px"/>


_... géré avec Terraform, ArgoCD, et Talos Linux_ <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.gif" alt="🤖" width="16" height="16">

</div>

<div align="center">

[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Ftalos_version&style=for-the-badge&logo=talos&logoColor=white&label=Talos&color=blue)](https://talos.dev)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fkubelet_version&style=for-the-badge&logo=kubernetes&logoColor=white&label=Kubernetes&color=blue)](https://kubernetes.io)&nbsp;&nbsp;
[![ArgoCD](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fargocd_version&style=for-the-badge&logo=argo&logoColor=white&label=ArgoCD&color=blue)](https://argo-cd.readthedocs.io)&nbsp;&nbsp;
[![Terraform](https://img.shields.io/badge/Terraform-IaC-blue?style=for-the-badge&logo=terraform&logoColor=white)](https://terraform.io)

</div>

<div align="center">

[![Tailscale](https://img.shields.io/badge/Tailscale-VPN-brightgreen?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com)&nbsp;&nbsp;
[![Cloudflare](https://img.shields.io/badge/Cloudflare-ZeroTrust-brightgreen?style=for-the-badge&logo=cloudflare&logoColor=white)](https://www.cloudflare.com)&nbsp;&nbsp;
[![Proxmox](https://img.shields.io/badge/Proxmox-VE-brightgreen?style=for-the-badge&logo=proxmox&logoColor=white)](https://proxmox.com)

</div>

<div align="center">

[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_cpu_usage&style=flat-square&label=CPU)]("")&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_memory_usage&style=flat-square&label=Memory)]("")&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_nodes_ready)]("")&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.wheezy.fr%2Fcluster_pods_running)]("")&nbsp;&nbsp;
</div>

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a1/512.gif" alt="💡" width="20" height="20"> Vue d'ensemble

Ce repository contient l'infrastructure complète de mon homelab Kubernetes. J'applique les principes d'Infrastructure as Code (IaC) et GitOps en utilisant [Terraform](https://www.terraform.io/) pour le provisioning, [Talos Linux](https://www.talos.dev/) comme OS des nœuds, et [ArgoCD](https://argo-cd.readthedocs.io/) pour le déploiement des applications.

L'infrastructure est hébergée sur [Proxmox VE](https://proxmox.com/) et j'utilise [Tailscale](https://tailscale.com/) pour l'accès privé sécurisé ainsi que [Cloudflare Zero Trust](https://www.cloudflare.com/) pour l'exposition publique des services.

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

### GitOps avec ArgoCD

[ArgoCD](https://argo-cd.readthedocs.io/) surveille le repository [argocd-apps-homelab](https://github.com/florianspk/argocd-apps-homelab) et synchronise automatiquement l'état désiré des applications avec le cluster Kubernetes.

Les applications sont organisées par famille et par cluster, permettant une gestion granulaire des déploiements et des mises à jour.

### Structure des répertoires

```sh
📁 argocd-apps-homelab
├── 📁 apps
│     ├── 📁 apps-ops
│     ├── 📁 apps-monitoring
│         ├── 📁 kube-prometheus-stack
│         │    ├── 📁 extras
│         │    ├── 📄 prd.json
│         │    ├── 📄 dev.json
│         │    └── 📄 staging.json
│         └── 📁 apps-ops
│
├── 📁 bootstrap
├── 📁 projects
└── 📄 renovate.json
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
| pve01 | Intel i5 5ème gen | 32GB | 4 To SSD | Kubernetes Master/Worker | NVIDIA GTX 1060 |
| pve02 | Intel i5 5ème gen | 32GB | 1 To SSD | Kubernetes Worker | - |

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
| [Tailscale](https://tailscale.com/) | VPN mesh et accès administratif | Gratuit |
| [Cloudflare](https://www.cloudflare.com/) | Zero Trust et DNS public | Gratuit|
| [GitHub](https://github.com/) | Hébergement des repositories et CI/CD | Gratuit |

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="20" height="20"> Déploiement

### Prérequis

- Proxmox VE configuré avec les VMs
- Terraform installé
- Talosctl installé
- Accès aux credentials Proxmox

### Étapes de déploiement

1. **Build custom talos image**
   ```bash
   chmod +x ./hack/build_talos_image.sh
   ./hack/build_talos_image.sh
   ```

2. **Provisioning Terraform**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```


3. **Déploiement Linstor**
   ```bash
   chmod +x ./hack/configure_linstor.sh
   ./hack/configure_linstor.sh
   ```

4. **Configuration ArgoCD**
   - ArgoCD se déploie automatiquement
   - Fork le repo  [argocd-apps-homelab](https://github.com/florianspk/argocd-apps-homelab) et modifier bootstrap_repo_url

### Upgrades (provider talos ≥ 0.12.0)

Les nœuds sont gérés par `talos_machine` (config + version de Talos).

**Avant chaque upgrade** : backup du state, snapshot etcd (`talosctl -n <c0> etcd snapshot`), `terraform plan` relu.

1. **Talos OS** (une mineure à la fois, ex. 1.13.x → 1.14.x) :
   - Vérifier que le schematic existe pour la version cible (Image Factory) et que le cluster est sain (NFS, CNPG, `linstor r l`), puis monter `talos_version`.
   - Nœud par nœud, c0 puis `worker[0..3]` : `terraform plan -target='talos_machine.<nœud>' -out=n.tfplan`, vérifier que seule l'`image` change, puis `terraform apply n.tfplan`.
   - Entre chaque nœud, attendre que tout soit sain (nodes Ready, DRBD sans resync, CNPG healthy) ; à la fin, `terraform plan` doit être vide.
   - Si un réplica CNPG reste bloqué en recovery, lancer `checkpoint` + `select pg_switch_wal()` sur le primaire. Si l'upgrade bloque au démontage, c'est le NFS (montage `hard`).
2. **Kubernetes** : une fois tous les nœuds upgradés, `talosctl -n <c0> upgrade-k8s --to <version>` (une mineure à la fois),
   puis aligner `kubernetes_version` et vérifier que `terraform plan` est vide.
   Utiliser un `talosctl` de la même version que Talos, toujours avec `--to`, plus `--with-docs=false --with-examples=false` ; lancer d'abord `--dry-run` et relire le diff des manifests.
   Garder les values `helm/*` alignées sur argocd-apps-homelab (sinon `upgrade-k8s` écrase le live), et aligner `kubernetes_version` juste après l'upgrade.
   `upgrade-k8s` resynchronise aussi les `inlineManifests` (cilium, cert-manager, argocd...) : vérifier les versions des charts avant.
   (`talos_cluster` n'est pas utilisé : ses health checks ne fonctionnent pas avec le provider 0.12.0 sur Talos 1.12, voir `talos.tf`.)

À ne pas faire :
- changer la chaîne `image` sans changer de version (registry, `installer` ↔ `nocloud-installer`, digest) : ça déclenche un upgrade avec reboot ;
- retirer `talos_schematic_id` ou passer c0 sur l'image `installer` (metal) : c0 doit rester en `nocloud-installer` ;
- descendre `talos_config_contract_version`.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4dd/512.gif" alt="📝" width="20" height="20"> Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

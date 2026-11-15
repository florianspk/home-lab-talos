#!/usr/bin/env python3
"""Résumé d'un plan Terraform SANS aucune valeur (repo public : les logs et commentaires sont visibles).

Usage : terraform show -json plan.tfplan | tf_plan_summary.py summary.md
Écrit le markdown dans summary.md et dans $GITHUB_OUTPUT :
  fingerprint  hash des (adresse, actions) : l'apply refuse si son plan diffère de celui validé
  changes      nombre de ressources modifiées
  destroy      true si une ressource est détruite ou remplacée
  k8s_to       version Kubernetes cible si talos_cluster change kubernetes_version, sinon vide
  talos_to     version Talos cible si l'image d'un talos_machine change, sinon vide
"""
import hashlib
import json
import os
import re
import sys

plan = json.load(sys.stdin)
out_md = sys.argv[1]

rows, fp, destroy = [], [], False
k8s_to = talos_to = ""

for rc in plan.get("resource_changes", []):
    actions = rc["change"]["actions"]
    if actions in (["no-op"], ["read"]):
        continue
    addr = rc["address"]
    fp.append(f"{addr} {','.join(actions)}")
    if "delete" in actions:
        destroy = True

    before = rc["change"].get("before") or {}
    after = rc["change"].get("after") or {}
    unknown = rc["change"].get("after_unknown") or {}
    # Noms d'attributs uniquement, jamais les valeurs
    attrs = sorted(k for k in set(before) | set(after) | set(unknown)
                   if before.get(k) != after.get(k) or unknown.get(k) is True)

    if rc["type"] == "talos_cluster" and before.get("kubernetes_version") != after.get("kubernetes_version"):
        k8s_to = str(after.get("kubernetes_version") or "").lstrip("v")
    if rc["type"] == "talos_machine" and before.get("image") != after.get("image"):
        m = re.search(r":v([0-9][^@]*)$", str(after.get("image") or ""))
        talos_to = m.group(1) if m else "?"

    rows.append((addr, "/".join(actions), ", ".join(f"`{a}`" for a in attrs[:8]) + (" …" if len(attrs) > 8 else "")))

fingerprint = hashlib.sha256("\n".join(sorted(fp)).encode()).hexdigest()[:16]

md = ["<!-- terraform-plan -->", "### Terraform plan (prod)", ""]
if not rows:
    md.append("**No changes.**")
else:
    md += [f"**{len(rows)} ressource(s) modifiée(s)**, empreinte `{fingerprint}`", ""]
    if destroy:
        md += ["> [!CAUTION]", "> Destruction ou remplacement : l'apply CI refuse, à faire en local.", ""]
    if talos_to:
        md += ["> [!WARNING]", f"> Upgrade **Talos → {talos_to}** : reboot de chaque nœud (apply `-parallelism=1`).", ""]
    if k8s_to:
        md += ["> [!WARNING]", f"> Upgrade **Kubernetes → {k8s_to}** via `talos_cluster` (upgrade-k8s).", ""]
    md += ["| Ressource | Action | Attributs |", "|---|---|---|"]
    md += [f"| `{a}` | {act} | {at} |" for a, act, at in rows]
md += ["", "_Valeurs masquées (repo public). Détail : `terraform plan` en local._"]

with open(out_md, "w") as f:
    f.write("\n".join(md) + "\n")

with open(os.environ.get("GITHUB_OUTPUT", os.devnull), "a") as f:
    f.write(f"fingerprint={fingerprint}\nchanges={len(rows)}\ndestroy={str(destroy).lower()}\n"
            f"k8s_to={k8s_to}\ntalos_to={talos_to}\n")

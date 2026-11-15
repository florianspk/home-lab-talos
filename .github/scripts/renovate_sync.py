#!/usr/bin/env python3
"""Synchronise les charts Helm partagés entre argocd-apps-homelab et home-lab-talos.

argocd-apps-homelab (ArgoCD) est la source de vérité des versions réellement
déployées. home-lab-talos ne fait que bootstrapper le cluster via les
inlineManifests Talos (data "helm_template"). Ce script garde les deux repos
alignés, sans jamais rien appliquer (aucun terraform / talosctl / kubectl) :

  guard      -> check "sync-guard" sur chaque PR (requis par la protection de main) :
                 * toute version de chart partagé modifiée par la PR doit être égale
                   à celle présente sur main dans argocd-apps-homelab ;
                 * une PR qui touche Talos / Kubernetes / provider talos ne doit
                   JAMAIS avoir l'auto-merge activé.
  reconcile  -> état désiré = versions sur main d'argocd-apps-homelab :
                 * auto-merge des PR Renovate (ou renovate-sync) éligibles ;
                 * création d'une PR renovate-sync/<chart>-<version> si aucune PR
                   ne porte la version attendue ;
                 * relance du check sync-guard des PR qui sont devenues conformes ;
                 * fermeture des PR renovate-sync obsolètes.
  check-renovate-config -> garde-fou : renovate.json ne doit activer aucun automerge.

Seuls les charts de SHARED_CHARTS (liste blanche explicite) sont concernés.
Les appels GitHub passent par `gh api` (arguments en liste, pas de shell).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass, field

TARGET_REPO = os.environ.get("GITHUB_REPOSITORY", "florianspk/home-lab-talos")
SOURCE_REPO = os.environ.get("SYNC_SOURCE_REPO", "florianspk/argocd-apps-homelab")
SOURCE_REF = "main"
BASE_BRANCH = "main"
WORKFLOW_FILE = "renovate-sync.yml"
GUARD_JOB_NAME = "sync-guard"
SYNC_BRANCH_PREFIX = "renovate-sync/"
RENOVATE_BRANCH_PREFIX = "renovate/"
RENOVATE_LOGINS = {"renovate[bot]"}
IGNORE_LABEL = "renovate-sync:ignore"
MERGE_METHOD = "squash"

# Liste blanche : seuls ces charts peuvent être synchronisés / auto-mergés.
SHARED_CHARTS: dict[str, dict[str, str]] = {
    "cilium": {
        "tf": "cilium.tf",
        "source": "bootstrap/core/cilium/prd.json",
        "registry": "https://helm.cilium.io",
    },
    "cert-manager": {
        "tf": "cert-manager.tf",
        "source": "bootstrap/core/cert-manager/prd.json",
        "registry": "https://charts.jetstack.io",
    },
    "trust-manager": {
        "tf": "trust-manager.tf",
        "source": "bootstrap/core/trust-manager/prd.json",
        "registry": "https://charts.jetstack.io",
    },
    "argo-cd": {
        "tf": "argocd.tf",
        "source": "bootstrap/core/argocd/prd.json",
        "registry": "https://argoproj.github.io/argo-helm",
    },
    "reloader": {
        "tf": "reloader.tf",
        "source": "bootstrap/core/reloader/prd.json",
        "registry": "https://stakater.github.io/stakater-charts",
    },
}
TF_FILE_TO_CHART = {cfg["tf"]: dep for dep, cfg in SHARED_CHARTS.items()}

# Fichiers portant talos_version, kubernetes_version, talos_config_contract_version,
# talos_image_version, le provider siderolabs/talos ou l'image Talos : une PR qui les
# touche n'est jamais auto-mergée (refus par reconcile ET échec de sync-guard si
# l'auto-merge est activé dessus).
PROTECTED_FILES = {
    "variables.tf",
    "providers.tf",
    "talos.tf",
    "proxmox.tf",
    ".terraform.lock.hcl",
    "hack/build_talos_image.sh",
}

VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+){0,3})$")

DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"


# --------------------------------------------------------------------------- utils
class GhError(RuntimeError):
    def __init__(self, msg: str, stderr: str):
        super().__init__(msg)
        self.stderr = stderr


def log(msg: str) -> None:
    print(msg, flush=True)


def notice(msg: str) -> None:
    print(f"::notice::{msg}", flush=True)


def warning(msg: str) -> None:
    print(f"::warning::{msg}", flush=True)


def error(msg: str) -> None:
    print(f"::error::{msg}", flush=True)


def gh(args: list[str], *, token_env: str | None = None, input_data: str | None = None) -> str:
    env = dict(os.environ)
    if token_env:
        env["GH_TOKEN"] = os.environ.get(token_env, "")
    proc = subprocess.run(
        ["gh", *args], input=input_data, capture_output=True, text=True, env=env, check=False
    )
    if proc.returncode != 0:
        raise GhError(f"gh {' '.join(args[:3])} ... a échoué", proc.stderr.strip())
    return proc.stdout


def api(path: str, *, method: str = "GET", body: dict | None = None,
        token_env: str | None = None, paginate: bool = False):
    args = ["api", "-X", method, "-H", "Accept: application/vnd.github+json", path]
    if paginate:
        args += ["--paginate", "--slurp"]
    data = None
    if body is not None:
        args += ["--input", "-"]
        data = json.dumps(body)
    out = gh(args, token_env=token_env, input_data=data)
    if not out.strip():
        return None
    res = json.loads(out)
    if paginate:
        merged: list = []
        for page in res:
            merged.extend(page if isinstance(page, list) else [page])
        return merged
    return res


def is_not_found(exc: GhError) -> bool:
    return "HTTP 404" in exc.stderr or "Not Found" in exc.stderr


def q(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def get_file(repo: str, path: str, ref: str) -> tuple[str, str] | None:
    """Retourne (contenu, blob_sha) ou None si absent."""
    try:
        data = api(f"repos/{repo}/contents/{urllib.parse.quote(path)}?ref={q(ref)}")
    except GhError as exc:
        if is_not_found(exc):
            return None
        raise
    return base64.b64decode(data["content"]).decode("utf-8"), data["sha"]


def norm(version: str | None) -> tuple[int, ...] | None:
    if version is None:
        return None
    m = VERSION_RE.match(version.strip())
    if not m:
        return None
    return tuple(int(p) for p in m.group(1).split("."))


def norm_str(version: str | None) -> str | None:
    n = norm(version)
    return ".".join(str(p) for p in n) if n is not None else None


# ------------------------------------------------------------------ fichiers .tf
def tf_pattern(dep: str) -> re.Pattern[str]:
    registry = re.escape(SHARED_CHARTS[dep]["registry"])
    return re.compile(
        r"(?m)^(?P<prefix>[ \t]*#[ \t]*renovate:[ \t]*datasource=helm[ \t]+depName="
        + re.escape(dep)
        + r"[ \t]+registryUrl="
        + registry
        + r"/?[ \t]*\r?\n[ \t]*version[ \t]*=[ \t]*\")(?P<value>[^\"\n]+)(?P<suffix>\")"
    )


def tf_get_version(content: str, dep: str) -> str | None:
    matches = list(tf_pattern(dep).finditer(content))
    if len(matches) != 1:
        return None
    return matches[0].group("value")


def tf_set_version(content: str, dep: str, version: str) -> str:
    pattern = tf_pattern(dep)
    matches = list(pattern.finditer(content))
    if len(matches) != 1:
        raise ValueError(f"{dep}: {len(matches)} ligne(s) version trouvée(s), 1 attendue")
    current = matches[0].group("value")
    value = norm_str(version)
    if value is None:
        raise ValueError(f"{dep}: version invalide {version!r}")
    if current.startswith("v"):
        value = "v" + value
    return pattern.sub(lambda m: m.group("prefix") + value + m.group("suffix"), content, count=1)


# -------------------------------------------------------------- argocd (source)
def source_versions() -> dict[str, str | None]:
    """Versions sur main d'argocd-apps-homelab (repo public, lecture seule)."""
    ref = api(f"repos/{SOURCE_REPO}/commits/{SOURCE_REF}")["sha"]
    log(f"Source {SOURCE_REPO}@{SOURCE_REF} = {ref}")
    result: dict[str, str | None] = {}
    for dep, cfg in SHARED_CHARTS.items():
        found = get_file(SOURCE_REPO, cfg["source"], ref)
        if found is None:
            warning(f"{dep}: {cfg['source']} absent de {SOURCE_REPO}, chart ignoré")
            result[dep] = None
            continue
        try:
            data = json.loads(found[0])
        except json.JSONDecodeError:
            warning(f"{dep}: {cfg['source']} n'est pas du JSON valide, chart ignoré")
            result[dep] = None
            continue
        chart = data.get("chart")
        repo_url = str(data.get("chartRepoURL", "")).rstrip("/")
        version = data.get("chartVersion")
        if chart != dep or repo_url != cfg["registry"].rstrip("/"):
            warning(
                f"{dep}: chart/dépôt divergent dans {SOURCE_REPO} "
                f"({chart!r} @ {repo_url!r}), chart ignoré"
            )
            result[dep] = None
            continue
        if norm(version) is None:
            warning(f"{dep}: version source non supportée {version!r}, chart ignoré")
            result[dep] = None
            continue
        result[dep] = norm_str(version)
    return result


# ------------------------------------------------------------- analyse d'une PR
@dataclass
class PrEval:
    number: int
    head_sha: str
    head_ref: str
    author: str
    same_repo: bool
    draft: bool
    labels: set[str]
    auto_merge: bool
    files: list[str] = field(default_factory=list)
    changed: dict[str, tuple[str | None, str | None]] = field(default_factory=dict)
    protected_touched: list[str] = field(default_factory=list)
    only_version_lines: bool = True
    guard_errors: list[str] = field(default_factory=list)
    guard_notes: list[str] = field(default_factory=list)

    @property
    def guard_ok(self) -> bool:
        return not self.guard_errors


def evaluate_pr(pr: dict, src: dict[str, str | None]) -> PrEval:
    head_repo = (pr.get("head") or {}).get("repo") or {}
    ev = PrEval(
        number=pr["number"],
        head_sha=pr["head"]["sha"],
        head_ref=pr["head"]["ref"],
        author=(pr.get("user") or {}).get("login", ""),
        same_repo=head_repo.get("full_name") == TARGET_REPO,
        draft=bool(pr.get("draft")),
        labels={lbl["name"] for lbl in pr.get("labels", [])},
        auto_merge=pr.get("auto_merge") is not None,
    )
    head_full = head_repo.get("full_name") or TARGET_REPO
    ignored = IGNORE_LABEL in ev.labels
    problems: list[str] = []
    files = api(f"repos/{TARGET_REPO}/pulls/{ev.number}/files?per_page=100", paginate=True)
    names: set[str] = set()
    for f in files:
        names.add(f["filename"])
        if f.get("previous_filename"):
            names.add(f["previous_filename"])
    ev.files = sorted(names)
    ev.protected_touched = sorted(n for n in names if n in PROTECTED_FILES)

    merge_base = api(
        f"repos/{TARGET_REPO}/compare/{q(pr['base']['sha'])}...{q(ev.head_sha)}"
    )["merge_base_commit"]["sha"]

    for name in ev.files:
        dep = TF_FILE_TO_CHART.get(name)
        if dep is None:
            ev.only_version_lines = False
            continue
        base = get_file(TARGET_REPO, name, merge_base)
        head = get_file(head_full, name, ev.head_sha)
        if base is None or head is None:
            ev.only_version_lines = False
            problems.append(f"{name} ajouté/supprimé : vérification impossible")
            continue
        base_v, head_v = tf_get_version(base[0], dep), tf_get_version(head[0], dep)
        if head_v is None:
            ev.only_version_lines = False
            problems.append(
                f"{name}: commentaire '# renovate: datasource=helm depName={dep} "
                f"registryUrl={SHARED_CHARTS[dep]['registry']}' + ligne version introuvable"
            )
            continue
        if base_v is not None and norm_str(base_v) != norm_str(head_v):
            ev.changed[dep] = (base_v, head_v)
        try:
            expected = tf_set_version(base[0], dep, head_v) if base_v is not None else None
        except ValueError:
            expected = None
        if expected != head[0]:
            ev.only_version_lines = False

    for msg in problems:
        (ev.guard_notes if ignored else ev.guard_errors).append(msg)
    for dep, (base_v, head_v) in ev.changed.items():
        target = src.get(dep)
        if ignored:
            ev.guard_notes.append(f"{dep} {base_v} -> {head_v} : label {IGNORE_LABEL}, parité non vérifiée")
        elif target is None:
            ev.guard_errors.append(f"{dep} {base_v} -> {head_v} : version argocd-apps-homelab inconnue")
        elif norm_str(head_v) != target:
            ev.guard_errors.append(
                f"{dep} {base_v} -> {head_v} : {SOURCE_REPO}@{SOURCE_REF} est en {target} "
                "(la PR sera auto-mergée quand la même version y sera mergée)"
            )
        else:
            ev.guard_notes.append(f"{dep} {base_v} -> {head_v} : identique à {SOURCE_REPO}")

    if ev.protected_touched and ev.auto_merge:
        ev.guard_errors.append(
            "auto-merge activé sur une PR qui touche Talos/Kubernetes/provider talos "
            f"({', '.join(ev.protected_touched)}) : interdit, désactiver l'auto-merge"
        )
    return ev


def is_sync_candidate(ev: PrEval, pr: dict, bot_login: str | None) -> tuple[bool, str]:
    """PR auto-mergeable par reconcile ? (en plus de guard_ok)."""
    if not ev.same_repo:
        return False, "branche hors dépôt"
    if ev.draft:
        return False, "brouillon"
    if IGNORE_LABEL in ev.labels:
        return False, f"label {IGNORE_LABEL}"
    from_renovate = ev.author in RENOVATE_LOGINS and ev.head_ref.startswith(RENOVATE_BRANCH_PREFIX)
    from_sync = ev.head_ref.startswith(SYNC_BRANCH_PREFIX) and bot_login is not None and ev.author == bot_login
    if not (from_renovate or from_sync):
        return False, "ni Renovate ni renovate-sync"
    if pr["base"]["ref"] != BASE_BRANCH:
        return False, "base différente de main"
    if ev.protected_touched:
        return False, "touche des fichiers protégés"
    if not ev.changed:
        return False, "aucune version de chart partagé modifiée"
    if not ev.only_version_lines:
        return False, "modifie autre chose que les lignes version des charts partagés"
    if not ev.guard_ok:
        return False, "; ".join(ev.guard_errors)
    return True, "ok"


# --------------------------------------------------------------------- commandes
def cmd_guard(pr_number: int) -> int:
    pr = api(f"repos/{TARGET_REPO}/pulls/{pr_number}")
    src = source_versions()
    ev = evaluate_pr(pr, src)
    for n in ev.guard_notes:
        notice(n)
    if ev.protected_touched:
        notice(f"PR touchant des fichiers protégés ({', '.join(ev.protected_touched)}) : jamais auto-mergée")
    if not ev.changed:
        log("Aucune version de chart partagé modifiée.")
    for e in ev.guard_errors:
        error(e)
    log("sync-guard: " + ("OK" if ev.guard_ok else "ECHEC"))
    return 0 if ev.guard_ok else 1


def mutate(desc: str) -> bool:
    if DRY_RUN:
        log(f"[dry-run] {desc}")
        return False
    log(desc)
    return True


def checks_all_green(sha: str) -> bool:
    pages = api(f"repos/{TARGET_REPO}/commits/{q(sha)}/check-runs?per_page=100", paginate=True)
    check_runs = [r for page in pages or [] for r in page.get("check_runs", [])]
    if not any(r["name"] == GUARD_JOB_NAME and r.get("conclusion") == "success" for r in check_runs):
        return False
    bad = {"failure", "cancelled", "timed_out", "action_required", "stale", None}
    return all(r.get("conclusion") not in bad for r in check_runs if r["name"] != "reconcile")


def ensure_merge(ev: PrEval) -> None:
    info = json.loads(gh([
        "pr", "view", str(ev.number), "-R", TARGET_REPO,
        "--json", "mergeStateStatus,autoMergeRequest,headRefOid,isDraft,state",
    ]))
    if info["state"] != "OPEN" or info["headRefOid"] != ev.head_sha:
        log(f"#{ev.number}: état changé pendant l'analyse, prochain passage")
        return
    if info.get("autoMergeRequest"):
        log(f"#{ev.number}: auto-merge déjà activé")
        return
    status = info["mergeStateStatus"]
    base = ["pr", "merge", str(ev.number), "-R", TARGET_REPO, f"--{MERGE_METHOD}",
            "--match-head-commit", ev.head_sha]
    try:
        if status == "CLEAN":
            if not checks_all_green(ev.head_sha):
                log(f"#{ev.number}: CLEAN mais checks incomplets, prochain passage")
                return
            if mutate(f"#{ev.number}: merge direct ({MERGE_METHOD})"):
                gh(base)
        elif status == "DIRTY":
            warning(f"#{ev.number}: conflits, en attente d'un rebase Renovate")
        else:
            if mutate(f"#{ev.number}: activation de l'auto-merge ({status})"):
                gh(base + ["--auto"])
    except GhError as exc:
        warning(f"#{ev.number}: merge/auto-merge impossible pour l'instant : {exc.stderr[:300]}")


def rerun_guard_if_failed(ev: PrEval) -> None:
    if not os.environ.get("GH_ACTIONS_TOKEN"):
        return
    runs = api(
        f"repos/{TARGET_REPO}/actions/workflows/{WORKFLOW_FILE}/runs"
        f"?event=pull_request&head_sha={q(ev.head_sha)}&per_page=10",
        token_env="GH_ACTIONS_TOKEN",
    ).get("workflow_runs", [])
    if not runs:
        warning(f"#{ev.number}: aucun run {GUARD_JOB_NAME} pour {ev.head_sha[:7]} (PR antérieure au workflow ?)")
        return
    latest = max(runs, key=lambda r: r["created_at"])
    if latest["status"] != "completed" or latest["conclusion"] == "success":
        return
    jobs = api(f"repos/{TARGET_REPO}/actions/runs/{latest['id']}/jobs", token_env="GH_ACTIONS_TOKEN")
    if any(j["name"] == GUARD_JOB_NAME and j.get("conclusion") == "failure" for j in jobs.get("jobs", [])):
        if mutate(f"#{ev.number}: relance de {GUARD_JOB_NAME} (run {latest['id']})"):
            api(f"repos/{TARGET_REPO}/actions/runs/{latest['id']}/rerun-failed-jobs",
                method="POST", token_env="GH_ACTIONS_TOKEN")


def close_pr(number: int, branch: str, reason: str) -> None:
    if not mutate(f"#{number}: fermeture ({reason}) et suppression de {branch}"):
        return
    try:
        api(f"repos/{TARGET_REPO}/issues/{number}/comments", method="POST",
            body={"body": f"Fermée par renovate-sync : {reason}."})
        api(f"repos/{TARGET_REPO}/pulls/{number}", method="PATCH", body={"state": "closed"})
        api(f"repos/{TARGET_REPO}/git/refs/heads/{urllib.parse.quote(branch)}", method="DELETE")
    except GhError as exc:
        warning(f"#{number}: fermeture incomplète : {exc.stderr[:300]}")


def create_sync_pr(dep: str, current: str, target: str, main_sha: str, src_sha_note: str) -> None:
    cfg = SHARED_CHARTS[dep]
    branch = f"{SYNC_BRANCH_PREFIX}{dep}-{target}"
    found = get_file(TARGET_REPO, cfg["tf"], main_sha)
    if found is None:
        warning(f"{dep}: {cfg['tf']} absent de main")
        return
    content, blob_sha = found
    new_content = tf_set_version(content, dep, target)
    title = f"Update Helm release {dep} to v{target} (sync argocd-apps-homelab)"
    if not mutate(f"{dep}: création de {branch} et de la PR '{title}'"):
        return
    ref_path = f"repos/{TARGET_REPO}/git/refs/heads/{urllib.parse.quote(branch)}"
    try:
        api(ref_path, method="PATCH", body={"sha": main_sha, "force": True})
    except GhError as exc:
        if not (is_not_found(exc) or "422" in exc.stderr):
            raise
        api(f"repos/{TARGET_REPO}/git/refs", method="POST",
            body={"ref": f"refs/heads/{branch}", "sha": main_sha})
    api(f"repos/{TARGET_REPO}/contents/{urllib.parse.quote(cfg['tf'])}", method="PUT", body={
        "message": f"chore(deps): update helm release {dep} to v{target}\n\n"
                   f"Synchronisation avec {SOURCE_REPO} ({src_sha_note}).",
        "content": base64.b64encode(new_content.encode("utf-8")).decode("ascii"),
        "sha": blob_sha,
        "branch": branch,
    })
    body = (
        f"Synchronisation automatique du chart `{dep}` ({current} -> {target}) "
        f"sur la version présente sur `main` dans [{SOURCE_REPO}](https://github.com/{SOURCE_REPO}) "
        f"(`{src_sha_note}`).\n\n"
        f"- Seule la ligne `version` suivant `# renovate: datasource=helm depName={dep}` est modifiée.\n"
        f"- Auto-merge par le workflow `renovate-sync` une fois le check `{GUARD_JOB_NAME}` vert.\n"
        "- Aucun `terraform apply` n'est déclenché : la modification n'atteint le cluster qu'au "
        "prochain apply manuel de la config Talos ou au prochain `talosctl upgrade-k8s`.\n"
    )
    pr = api(f"repos/{TARGET_REPO}/pulls", method="POST",
             body={"title": title, "head": branch, "base": BASE_BRANCH, "body": body})
    notice(f"{dep}: PR #{pr['number']} créée ({pr['html_url']})")


def cmd_reconcile() -> int:
    if not os.environ.get("GH_TOKEN"):
        warning("Secret RENOVATE_SYNC_TOKEN absent : reconcile ignoré (voir la PR de mise en place)")
        return 0
    try:
        bot_login = api("user")["login"]
    except GhError:
        bot_login = None
        warning("Impossible d'identifier l'utilisateur du token : PR renovate-sync non reconnues")

    src = source_versions()
    src_sha = api(f"repos/{SOURCE_REPO}/commits/{SOURCE_REF}")["sha"]
    main_sha = api(f"repos/{TARGET_REPO}/commits/{BASE_BRANCH}")["sha"]
    main_versions: dict[str, str | None] = {}
    for dep, cfg in SHARED_CHARTS.items():
        found = get_file(TARGET_REPO, cfg["tf"], main_sha)
        main_versions[dep] = tf_get_version(found[0], dep) if found else None
        log(f"{dep}: talos={main_versions[dep]} argocd={src[dep]}")

    prs = api(f"repos/{TARGET_REPO}/pulls?state=open&base={BASE_BRANCH}&per_page=100", paginate=True)
    evals: list[tuple[PrEval, dict]] = []
    for pr in prs:
        if pr["head"]["ref"].startswith((RENOVATE_BRANCH_PREFIX, SYNC_BRANCH_PREFIX)):
            try:
                evals.append((evaluate_pr(pr, src), pr))
            except GhError as exc:
                warning(f"#{pr['number']}: analyse impossible : {exc.stderr[:300]}")

    covered: set[str] = set()
    sync_prs: dict[str, list[PrEval]] = {}
    for ev, pr in evals:
        if ev.head_ref.startswith(SYNC_BRANCH_PREFIX) and bot_login and ev.author == bot_login:
            for dep in SHARED_CHARTS:
                if ev.head_ref.startswith(f"{SYNC_BRANCH_PREFIX}{dep}-"):
                    sync_prs.setdefault(dep, []).append(ev)

    # 1. PR Renovate puis renovate-sync éligibles : relance du check, auto-merge.
    ordered = sorted(evals, key=lambda item: 0 if item[0].author in RENOVATE_LOGINS else 1)
    for ev, pr in ordered:
        ok, why = is_sync_candidate(ev, pr, bot_login)
        if not ok:
            log(f"#{ev.number} ({ev.head_ref}): non éligible : {why}")
            continue
        deps = set(ev.changed)
        if deps & covered:
            log(f"#{ev.number}: déjà couvert par une autre PR")
            continue
        if any(norm(src[d]) is None or norm(main_versions[d]) is None
               or norm(src[d]) <= norm(main_versions[d]) for d in deps):
            log(f"#{ev.number}: main déjà à jour pour {sorted(deps)}")
            continue
        covered |= deps
        rerun_guard_if_failed(ev)
        ensure_merge(ev)

    # 2. Charts en retard sans PR éligible : PR renovate-sync dédiée.
    for dep in SHARED_CHARTS:
        target, current = src[dep], main_versions[dep]
        own = sync_prs.get(dep, [])
        if norm(target) is None or norm(current) is None:
            continue
        if norm(target) < norm(current):
            warning(f"{dep}: home-lab-talos ({current}) en avance sur {SOURCE_REPO} ({target}), aucune action")
        expected_branch = f"{SYNC_BRANCH_PREFIX}{dep}-{target}"
        for ev in own:
            if norm(target) <= norm(current):
                close_pr(ev.number, ev.head_ref, f"main déjà en {current}")
            elif ev.head_ref != expected_branch:
                close_pr(ev.number, ev.head_ref, f"{SOURCE_REPO} est passé en {target}")
        if norm(target) <= norm(current):
            continue
        renovate_cover = any(
            e.author in RENOVATE_LOGINS and dep in e.changed and is_sync_candidate(e, p, bot_login)[0]
            for e, p in evals
        )
        if renovate_cover:
            for ev in own:
                if ev.head_ref == expected_branch:
                    close_pr(ev.number, ev.head_ref, "PR Renovate équivalente prise en charge")
            continue
        if any(ev.head_ref == expected_branch for ev in own):
            continue
        create_sync_pr(dep, current, target, main_sha, f"{SOURCE_REF}@{src_sha[:7]}")
    return 0


def cmd_check_renovate_config(path: str) -> int:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    errors: list[str] = []

    def walk(node, where: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "automerge" and value is not False:
                    errors.append(f"{where}.automerge={value!r}")
                if key == "extends":
                    for preset in value if isinstance(value, list) else [value]:
                        if "automerge" in str(preset).lower():
                            errors.append(f"{where}.extends contient {preset!r}")
                walk(value, f"{where}.{key}")
        elif isinstance(node, list):
            for idx, value in enumerate(node):
                walk(value, f"{where}[{idx}]")

    walk(cfg, "$")
    for e in errors:
        error(
            f"renovate.json: {e} — Renovate ne doit rien auto-merger ; les charts partagés "
            "sont mergés par renovate-sync, Talos/Kubernetes/provider talos restent manuels"
        )
    log("check-renovate-config: " + ("OK" if not errors else "ECHEC"))
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("guard")
    g.add_argument("--pr", type=int, required=True)
    sub.add_parser("reconcile")
    c = sub.add_parser("check-renovate-config")
    c.add_argument("--file", default="renovate.json")
    args = parser.parse_args()
    try:
        if args.cmd == "guard":
            return cmd_guard(args.pr)
        if args.cmd == "reconcile":
            return cmd_reconcile()
        return cmd_check_renovate_config(args.file)
    except GhError as exc:
        error(f"{exc}: {exc.stderr[:500]}")
        return 1


if __name__ == "__main__":
    sys.exit(main())

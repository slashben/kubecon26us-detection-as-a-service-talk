# CLAUDE.md

Repo for the KubeCon NA 2026 talk **"Detection as Code"** (Ben + Constanze): demo
scripts, Rule CRDs, GitOps manifests and slide assets.

The talk draws on several upstream Kubescape repos. The expected layout is a workspace
directory with this repo and the upstream clones side by side (`../node-agent`,
`../rulelibrary`, ...). This repo is ours to shape freely; the upstream repos are ones
we read, demo, and possibly patch.

## The talk in one paragraph

Shift-left is solved (scanners, admission control, SBOM + VEX), but when a high-severity
CVE drops with "patch coming soon", production goes quiet for days. Kubescape makes
runtime detection a Kubernetes resource: a Rule CRD (CEL expression evaluated next to
the eBPF tracers) that you review in a PR, version in Git, deploy with Argo/Flux, and
roll back like any manifest. Running example: the **TeamPCP Trivy compromise**. Goal on
stage: "CVE published" → "rule deployed" in under an hour, with a visible clock.

## Talk structure (timeline v2, ~30 min)

One continuous demo of the loop: **notify → author → test → PR → deploy → alert**.

| Section | Min | Who | Content |
|---|---|---|---|
| The uncomfortable corner | 3 | Constanze | Shift-left done; CVE drops; start the clock. You know your apps, your clusters, and that you're vulnerable. |
| Why detection as a resource | 3 | Ben | Everything else went declarative; detection belongs in GitOps. Circle diagram. |
| 1. Notified | 3 | | TeamPCP Trivy advisory; SBOM + VEX answers "am I exposed, and where". Clock checkpoint 1. |
| 2. Author | 6 | Ben | What the eBPF sensor sees (exec/file/network/syscalls). IoCs → CEL rule in a Rule CRD. No-IoC path: node-agent autodiscovery on non-prod → SBOB profiles → mock attack → confusion matrix. |
| 3. PR | 4 | Constanze | PR with the Rule CRD (IoC repo) and signed profiles (app chart repo). Signatures = consciously accepting a detection's blind spots and cost. Rules/SBOB fragments shareable across tools. |
| 4. Deploy | 3 | | Merge, Argo/Flux reconciles, live with no app restart. Clock checkpoint 2. |
| 5. Alert | 4 | | Trigger the compromise, alert fires with context. Best case in real life: it never fires. |
| Stop the clock | 3 | both | Elapsed time; effort is in IoC→rule translation and profile calibration; where it goes wrong; Q&A. |

**Two scenarios:** (1) IoCs published → write a CEL rule; (2) no IoCs → rely on
anomaly detection against application profiles (SBOB).

**Open decisions** (ask the speakers before assuming an answer):
- SBOB profiles: full stage-2 path vs. one-slide aside.
- Live vs. recorded vs. hybrid demo.

**Tech still in flight:** review/cleanup of the CEL rules; the signature feature
(demo-ready, not merge-ready).

## Repositories

| Dir | Upstream | Role in the talk |
|---|---|---|
| `.` (this repo) | `slashben/kubecon26us-detection-as-a-service-talk` (will be **public**) | Our deliverables: demo scripts, Rule CRDs, GitOps manifests, slide assets |
| `../node-agent/` | `kubescape/node-agent` | eBPF sensor + rule manager that evaluates CEL rules (`pkg/rulemanager/cel/`) and builds container profiles; `demo/` has existing attack demos |
| `../rulelibrary/` | `kubescape/rulelibrary` | CEL rule library, one dir per rule under `pkg/rules/`; `rules-crd.yaml` is generated |
| `../storage/` | `kubescape/storage` | Aggregated API server holding profiles (ApplicationProfile / NetworkNeighborhood / ContainerProfile), SBOMs, VEX |
| `../helm-charts/` | `kubescape/helm-charts` | `charts/kubescape-operator`, which installs the demo cluster |
| `../designs-and-proposals/` | `kubescape/designs-and-proposals` | Design proposals (`proposals/`) for background and references |

## Working rules

- **This repo will be published.** Never commit secrets, internal company URLs,
  customer data, private cluster names, or unreleased-product details. Keep demo
  artifacts reproducible by anyone with a kind/minikube cluster and public images.
- **Upstream repos:** read more than you modify. If the demo needs a change in
  node-agent/rulelibrary/storage, do it on a branch as a real upstream PR, not a demo
  hack. Throw-away demo glue belongs in this repo.
- **rulelibrary:** follow `rulelibrary/AGENTS.md`. Every rule dir needs a `README.md`
  updated in the same commit, and CEL should follow `docs/writing-optimized-cel.md`.
- **Check stage claims.** Before slides or speaker notes say what the sensor or rule
  engine can see, check it against the `node-agent` code, not memory.
- Talk copy (slides, abstract-style text) should follow the narrative above.
  Point out where it differs instead of quietly rewriting it.

## Build / test (upstream repos, run from each repo's directory)

```bash
# node-agent
make binary            # build
make docker-build      # includes eBPF gadgets
go test ./pkg/...

# rulelibrary
make generate-rules-crd   # regenerate rules-crd.yaml (also checks rule READMEs)
go test ./pkg/rules/...   # per-rule CEL tests (rule_test.go)

# storage
make build && make test
```

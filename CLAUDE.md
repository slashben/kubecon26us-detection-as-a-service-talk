# CLAUDE.md

Repo for the KubeCon NA 2026 talk **"Detection as Code"**: demo
scripts, Rule CRDs, GitOps manifests and slide assets.

This repo is self-contained. The talk is built on Kubescape, whose code lives in
separate upstream repos (see [Related code](#related-code)). Don't assume they are
cloned locally.

## The talk

Kubescape turns runtime detection into a Kubernetes resource: a Rule CRD that goes
through PR, GitOps deploy and rollback like any other manifest. Running example: the
TeamPCP Trivy compromise, from "CVE published" to "rule deployed" in under an hour.

The full plan (narrative, timeline, speakers, scenarios, open decisions) is in
[docs/talk-plan.md](docs/talk-plan.md). Read it before working on demo or slide content.

## Related code

Upstream Kubescape repos that are useful to read when building the demo or checking
claims. They are not part of this repo and may not be available locally; if a local
clone exists, use it, otherwise refer to GitHub.

| Repo | What's interesting there |
|---|---|
| [kubescape/node-agent](https://github.com/kubescape/node-agent) | eBPF sensor + rule manager that evaluates CEL rules (`pkg/rulemanager/cel/`) and builds container profiles; `demo/` has existing attack demos |
| [kubescape/rulelibrary](https://github.com/kubescape/rulelibrary) | CEL rule library, one dir per rule under `pkg/rules/` (rule YAML + README + `rule_test.go`); good templates for new Rule CRDs |
| [kubescape/storage](https://github.com/kubescape/storage) | Aggregated API server holding profiles (ApplicationProfile / NetworkNeighborhood / ContainerProfile), SBOMs, VEX |
| [kubescape/helm-charts](https://github.com/kubescape/helm-charts) | `charts/kubescape-operator`, which installs Kubescape on the demo cluster |
| [kubescape/designs-and-proposals](https://github.com/kubescape/designs-and-proposals) | Design proposals (`proposals/`) for background and references |

## Working rules

- **This repo will be published.** Never commit secrets, internal company URLs,
  customer data, private cluster names, or unreleased-product details. Keep demo
  artifacts reproducible by anyone with a kind/minikube cluster and public images.
- **Demo code lives here.** Rules, manifests and scripts for the demo belong in this
  repo. If the demo needs a change in Kubescape itself, that's an upstream PR, not
  something to vendor or patch here.
- **New rules** should follow rulelibrary conventions (its `AGENTS.md` and
  `docs/writing-optimized-cel.md`) so they could be upstreamed later.
- **Keep the plan current.** When a decision is made or the timeline changes, update
  `docs/talk-plan.md` in the same change.
- **Check stage claims.** Before slides or speaker notes say what the sensor or rule
  engine can see, verify it against the node-agent source, not memory.
- Talk copy (slides, abstract-style text) should follow `docs/talk-plan.md`.
  Point out where it differs instead of quietly rewriting it.

## Demo status (as of 2026-11-02)

The scenario-1 demo (IoCs → CEL rules) is built, live and verified; details in
[docs/talk-plan.md](docs/talk-plan.md) "Implemented demo" and
[docs/demo-setup.md](docs/demo-setup.md) "Pre-demo sanity check".

- `scan.yaml` (clean) and `scan-compromised.yaml` (harmless TeamPCP emulation via
  `.github/actions/trivy-compromised`) run on the ARC `dac-runners` scale set.
- `gitops/rules/dac-rules.yaml` holds DAC-0001..0004. Clean run = only the upstream
  R1001 drift alert (narrated, not hidden); compromised = drift + all four `dac` rules.
- node-agent is pinned to v0.3.278 in `gitops/values/kubescape.yaml` for `dnsQuery`
  forwarding. Older agents silently lose the NXDOMAIN typosquat detection.
- Both speakers' segments are recorded clips, on separate clusters (this repo's cluster
  for the rule path; the co-speaker's clusters for the SBOB profile path, Flux-managed).
- Before publishing: scrub `docs/superpowers/` of internal references; it still has them.

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
- The demo rules (DAC-0001..0004) are authored on camera from the IoCs and merged via
  PR into `gitops/rules/`; `main` starts without them. The reference set is in
  `docs/reference-rules/`. Clean run = only the upstream R1001 drift alert (narrated,
  not hidden); compromised = drift + all four `dac` rules once they are deployed.
- node-agent is pinned to v0.3.278 in `gitops/values/kubescape.yaml` for `dnsQuery`
  forwarding. Older agents silently lose the NXDOMAIN typosquat detection.
- Both speakers' segments are recorded clips, on separate clusters (this repo's cluster
  for the rule path; the co-speaker's clusters for the SBOB profile path, Flux-managed).
- Before publishing: scrub `docs/superpowers/` of internal references; it still has them.

## Writing rules

Detection rules are `Rules` objects (`apiVersion: kubescape.io/v1`, CRD
`rules.kubescape.io`) in `gitops/rules/`, synced into the `kubescape` namespace by the
`rules` Argo CD Application. One file may hold several rules under `spec.rules`.
`gitops/rules/upstream-rules.yaml` is the vendored upstream library and a good source of
examples; `docs/reference-rules/` has the rules written for this talk.

**Shape of a rule.** Every entry needs `name`, `enabled`, `id`, `description`,
`expressions` (`message`, `uniqueId`, `ruleExpression[]` of `eventType` + CEL
`expression`), `profileDependency`, `severity` (1 to 10), `supportPolicy`,
`isTriggerAlert`, `mitreTactic`, `mitreTechnique` and `tags`. The schema is
`hack/schemas/rules-kubescape.io-v1.json`.

**Demo conventions.**
- `profileDependency: 2`. The CI runner pods are ephemeral and never finish learning a
  profile, so rules must fire on literal event fields without a baseline.
- Tag every rule `dac`. The `RuntimeRuleAlertBinding` in
  `gitops/rules/binding-dac-runners.yaml` binds rules by that tag to the runner pods;
  an untagged rule is never evaluated.
- Use ids `DAC-NNNN`, one rule per indicator type, and a `message` that names the
  indicator so the Slack alert reads on its own.
- Prefer `x in [...]` over `==` OR-chains and `coll.exists(x, x in [...])` over repeated
  `exists`; see rulelibrary's `docs/writing-optimized-cel.md`.

**What the eBPF sensor sees.** Event types the rules can match, with the fields that
matter here:

| `eventType` | Fired on | Useful fields |
|---|---|---|
| `exec` | process execution | `event.comm` (binary name as the kernel sees it, e.g. `sysmon.py`), `event.args` (argv list; compare with `string(a)`), `event.pcomm`, `event.pid`, `event.exepath`, `event.containerName` |
| `open` | file open via `open`/`openat` | `event.path` (full path inside the container), `event.flags` (list), `event.comm` |
| `dns` | an answered DNS response | `event.name`, `event.qtype`, `event.numAnswers` |
| `dnsQuery` | a DNS query, or an error response such as NXDOMAIN | same fields plus `event.qr` (`Q` or `R`) and `event.rcode` on responses |
| `network` | new outbound connection | `event.dstAddr`, `event.dstPort` |

Known gaps and quirks that shape rules:
- `tar` (and other tools using `openat2`) are not seen by the `open` tracer. To catch an
  archive being created, also match the `exec` event whose `args` carry the file name.
- DNS names in events may carry a trailing dot (`example.com.`). Match both forms.
- A lookup that never resolves (NXDOMAIN, typosquats, dead C2) only appears as a
  `dnsQuery` event, and only on node-agent >= v0.3.278 with `dnsRuleForwarding` on
  (both set in `gitops/values/kubescape.yaml`). Gate it with `event.qr == 'Q'` so the
  query and its error response don't alert twice. Keep a plain `dns` expression next to
  it for domains that do resolve.
- An exec rule that matches a file path in `args` also fires on helpers that merely
  touch the file (`chmod`, `cat`). Match the executed `comm` or a distinctive argument
  instead.
- A file written by a shell redirect has no process argv naming it; only the `open`
  event sees the path. Match any open of the path, not only writes: the write can be
  lost in an open storm while the later read (on execution) is reliably seen.

**Validate before opening a PR:**

    ./hack/validate-rules.sh            # kubeconform against the CRD schema

Then open the PR against `main`; Argo CD syncs `gitops/rules/` on merge and node-agent
reloads rules without a restart.

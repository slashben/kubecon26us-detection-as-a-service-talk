# Attack Emulation Design

**Date:** 2026-10-19
**Status:** Draft, for review
**Builds on:** [`2026-10-15-demo-infrastructure-design.md`](2026-10-15-demo-infrastructure-design.md)

## Goal

Give the demo its payload: a simulated compromised CI run that performs harmless
stand-ins for the TeamPCP attack's indicators of compromise, and a set of
Kubescape runtime rules that detect them and raise alerts. Running the clean
workflow produces no alerts; running the compromised workflow fires every demo
rule and lights up Alertmanager.

## What we are emulating

The TeamPCP advisory describes a supply-chain compromise of a Trivy GitHub
Action. Its indicators of compromise:

| Indicator | Role |
|---|---|
| `scan.aquasecurtiy.org` (typosquat) | C2 domain |
| `45.148.10.212` | C2 IP |
| `hackmoltrepeat.com` | Payload host |
| `tdtqy-oyaaa-aaaae-af2dq-cai.raw.icp0.io` | ICP canister C2 (persistence) |
| `plug-tab-protective-relay.trycloudflare.com` | Cloudflare Tunnel C2 |
| `tpcp.tar.gz` | Exfiltration archive |
| `~/.config/systemd/user/sysmon.py` | Persistence backdoor |
| Repositories named `tpcp-docs` | Fallback exfiltration |
| Commit `1885610c` | Poisoned workflow commit |
| GPG Key `E9D0A3616276FA6C` | Compromised signing key |

The last three describe how the compromise was introduced and signed, not a
runtime behavior an eBPF sensor can observe. They stay in the talk narrative and
are not emulated as events. The first seven map to runtime behavior and are
emulated.

## Approach

The emulated malicious action is a **composite GitHub Action**, not a container
image. Its steps run as ordinary processes inside the existing runner pod's one
container. The node's containerd already knows that container, so the node-agent
eBPF sensor sees every exec, file open, and DNS query the steps produce, and the
rules fire.

This was chosen over a custom runner image after weighing both:

- No image to build, push, or make public; no registry auth.
- No second runner scale set; the compromised workflow keeps `runs-on: dac-runners`.
- Faithful to TeamPCP, where the compromise was a poisoned workflow commit
  running malicious code inline during CI, not a daemon baked into an image.
- Deterministic alert order on stage, because the steps run in sequence.

The clean-vs-compromised contrast is purely the two workflows: `scan.yaml` runs
Trivy only; `scan-compromised.yaml` runs the same Trivy scan plus the emulated
action's extra steps.

## Components

| File | Change |
|---|---|
| `.github/actions/trivy-compromised/action.yaml` | Fill the stub: real Trivy scan step, then the IoC emulation step |
| `gitops/rules/dac-rules.yaml` | Replace the placeholder with four enabled rules tagged `dac` |
| `.github/workflows/scan-compromised.yaml` | Unchanged; already calls the action on `dac-runners` |
| `gitops/rules/binding-dac-runners.yaml` | Unchanged; already binds `dac`-tagged rules to `ci-runner` pods |
| `docs/talk-plan.md` | Update the demo section to describe the clean-vs-compromised runs and the four rules |

## Emulated behaviors

One shell step, every line labeled `DAC-SIMULATION`, performs:

| IoC | Emulation | Observable event |
|---|---|---|
| Four C2 / payload domains | A DNS query for each name | `dns`, `event.name` = the domain |
| `~/.config/systemd/user/sysmon.py` | Write that file under `$HOME` | `open`, `event.path` ends in `/systemd/user/sysmon.py` |
| `tpcp.tar.gz` | `tar` a dummy file into `/tmp/tpcp.tar.gz` | `open`, `event.path` ends in `tpcp.tar.gz` |
| `sysmon.py` process + `45.148.10.212` | Exec `sysmon.py` with the C2 domain and IP as argv | `exec`, `event.comm`/`event.args` carry the markers |

The C2 IP appears only as a process argument, never as a connection destination,
so it is detectable without routing to it.

## Detection rules

Four rules in `dac-rules.yaml`, all `enabled: true`, tagged `dac`, with
`profileDependency: 2` (no application profile needed). Profile independence is
essential: runner pods live under two minutes and never finish a learned
baseline, so anomaly rules would stay silent. Literal IoC matching fires on the
first run, every time. The existing binding already selects every `dac`-tagged
rule, so no binding change is needed.

| Rule | Event | Match (intent) | MITRE |
|---|---|---|---|
| C2 beacon | `dns` | `event.name` is one of the four C2 domains (trailing-dot tolerant) | TA0011 / T1071.004 |
| Persistence backdoor | `open` | `event.path` ends in `/systemd/user/sysmon.py` | TA0003 / T1543.002 |
| Exfil archive | `open` | `event.path` ends in `tpcp.tar.gz` | TA0009 / T1560.001 |
| Backdoor process | `exec` | `event.comm` is `sysmon.py`, or argv carries a C2 domain or `45.148.10.212` | TA0002 / T1059.006 |

Each rule sets `isTriggerAlert: true`, a `message` and `uniqueId` expression, and
a severity on the upstream numeric scale (1 low, 5 medium); the C2 beacon and
backdoor process are Critical (10), the two file rules High (8). Exact CEL and
full YAML are deferred to the plan. The rules follow rulelibrary conventions
(its `AGENTS.md` and `docs/writing-optimized-cel.md`) so they could be upstreamed
later.

## Safety invariants

1. No TCP, HTTP, or exfil connection is ever made to any C2 host, IP, or tunnel.
   The IPs and domains appear only as DNS queries and as process-argument
   strings, never as connection destinations.
2. All writes go to the ephemeral runner pod's own filesystem (`$HOME`, `/tmp`),
   destroyed with the pod seconds later. No persistence actually survives.
3. No real malware runs. `sysmon.py` is a stand-in that prints a marker.
4. The DNS query is sent to the in-cluster resolver (CoreDNS), where the sensor
   captures it. CoreDNS may forward the name upstream to resolve it; that is DNS
   name resolution only. No TCP/HTTP connection is ever made to any C2 host or IP
   (invariant 1 holds).

## Demo flow

1. Run `scan.yaml` (clean). A runner pod appears, Trivy scans, pod exits. No alerts.
2. Run `scan-compromised.yaml`. A runner pod appears, Trivy scans, the emulated
   steps run, pod exits. Within the rule cooldown the four `dac` rules fire and
   appear in Alertmanager, routed on `namespace=arc-runners`.
3. On stage: edit a rule, open a PR, merge, Argo CD syncs it, node-agent reloads
   without a restart. This is the "detection as code" beat; the rules above are
   what makes it concrete.

## Testing and validation

- `kubeconform` the `Rules` object against the CRD schema.
- `actionlint` the composite action and workflow.
- Live: run both workflows on the `dac-demo` cluster, confirm clean is silent and
  compromised fires all four rules in Alertmanager.

## Out of scope

- The poisoned commit, GPG key, and `tpcp-docs` repositories: narrative only.
- A `network` rule keyed on the C2 IP: emulating a connection safely would mean
  actually connecting, so the IP is covered by the `exec` rule instead.
- Optional later extension: a `tpcp-docs` directory write detected by an `open`
  rule, if a fifth indicator is wanted.

## Resolved during implementation (live pre-check on dac-demo)

- **`event.comm` for a shebang script is the script name** (`sysmon.py`), with
  the interpreter at `event.exepath` (`/usr/bin/dash`). DAC-0004 matches on
  `event.comm == 'sysmon.py'`.
- **Non-resolving C2 lookups need DNS query forwarding.** node-agent forwards
  only answered DNS responses to rules by default, so a C2/typosquat lookup that
  returns NXDOMAIN (e.g. `scan.aquasecurtiy.org`) is invisible to a `dns` rule.
  DAC-0001 gained a `dnsQuery` expression and the cluster enables
  `dnsRuleForwarding`. This first ships in node-agent **v0.3.278**; chart 1.40.5
  (and 1.41.0) still pin v0.3.219, so the demo pins the newer node-agent image.
- **`tar` writes via `openat2`,** which the open tracer does not hook, so the
  exfil archive never raised an `open` event. DAC-0003 also matches the `tar`
  exec by argv (`tpcp.tar.gz`); the `open` expression still covers a shell
  redirect. The emulation writes the archive under `$HOME`.
- **DAC-0004 was narrowed** to `event.comm`/the C2 IP in argv, not the
  `sysmon.py` path in argv, so `chmod` touching the file no longer raises a
  misleading "backdoor process: chmod" alert.
